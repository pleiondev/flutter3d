/// `KHR_gaussian_splatting` primitives turned into [SplatCloud]s — `C1`.
///
/// **Which text this follows.** The extension's own README in
/// KhronosGroup/glTF, whose status line reads "Complete, Ratified by the
/// Khronos Group", as it stood at commit `81762cc` (2026-09-03) — the text
/// has no version number of its own, so the commit is the version. Checked on
/// 2026-09-24, when this reader was written; open question 1 of the 0.8 plan.
///
/// **What the ratified text changed against the PLY this engine already
/// reads**, and so what this reader does differently from `parseSplatPly`:
/// scales are linear rather than logarithms, opacity is linear rather than a
/// logit, and the quaternion is in glTF's `xyzw` rather than `w` first. The
/// colour is the same zeroth spherical-harmonic band plus a half, but in a
/// declared colour space — `srgb_rec709_display` or `lin_rec709_display` —
/// and this engine blends in linear light, so an sRGB cloud is decoded here,
/// per splat, after the clamp to `[0, 1]` the extension's own `COLOR_0`
/// fallback note describes. That is an approximation the text itself
/// allows for a renderer that is not blending in the splat's colour space:
/// decoding before the blend rather than after it darkens where translucent
/// splats overlap, slightly, and only there.
///
/// **Bands above zero are kept, not used.** `SplatCloud.shRest` carries every
/// complete band the file holds; the draw reads band 0 alone, which the
/// extension permits ("Implementations MAY ignore higher-degree
/// coefficients").
///
/// A part of `gltf_loader.dart` for the reason its siblings are: the private
/// JSON helpers at the bottom of that file.
part of 'gltf_loader.dart';

/// The attribute prefix every semantic of the extension carries.
const String _kSplat = 'KHR_gaussian_splatting';

extension _GltfSplats on GltfLoader {
  /// Every splat primitive of [mesh], as clouds, in primitive order.
  ///
  /// A primitive that does not carry the extension is not this function's —
  /// `_decodeMesh` reads it — and one that carries it and cannot be read is
  /// skipped with the reason in [warnings], the way a broken triangle
  /// primitive is.
  List<(SplatCloud, SplatColourSpace)> _decodeMeshSplats(
    Map<String, Object?> mesh,
    int meshIndex,
    GltfAccessorReader reader,
    List<String> warnings,
  ) {
    final primitives = _mapList(mesh['primitives']);
    return <(SplatCloud, SplatColourSpace)>[
      for (var i = 0; i < primitives.length; i++)
        if (_splatExtensionOf(primitives[i]) case final extension?)
          ?_decodeSplatPrimitive(
            primitives[i],
            extension,
            'meshes[$meshIndex].primitives[$i]',
            reader,
            warnings,
          ),
    ];
  }

  (SplatCloud, SplatColourSpace)? _decodeSplatPrimitive(
    Map<String, Object?> primitive,
    Map<String, Object?> extension,
    String label,
    GltfAccessorReader reader,
    List<String> warnings,
  ) {
    final kernel = extension['kernel'];
    if (kernel != 'ellipse') {
      // The extension's own rule for a kernel a renderer does not know: fall
      // back to the ellipse, which is the only one there is.
      warnings.add(
        '$label: $_kSplat kernel "$kernel" is not implemented; drawn as '
        '"ellipse".',
      );
    }
    final colourSpace = switch (extension['colorSpace']) {
      'srgb_rec709_display' => SplatColourSpace.srgb,
      'lin_rec709_display' => SplatColourSpace.linear,
      final other => () {
        warnings.add(
          '$label: $_kSplat colorSpace "$other" is not one this reader '
          'knows; read as srgb_rec709_display.',
        );
        return SplatColourSpace.srgb;
      }(),
    };
    for (final (key, expected) in const <(String, String)>[
      ('projection', 'perspective'),
      ('sortingMethod', 'cameraDistance'),
    ]) {
      final value = extension[key];
      if (value != null && value != expected) {
        warnings.add(
          '$label: $_kSplat $key "$value" is not implemented; '
          '"$expected" used.',
        );
      }
    }
    final mode = _asInt(primitive['mode']) ?? 4;
    if (mode != GltfPrimitiveMode.points.code) {
      warnings.add(
        '$label: a $_kSplat primitive must be POINTS and this one is mode '
        '$mode; read as splats anyway.',
      );
    }

    final attributes = primitive['attributes'];
    if (attributes is! Map) {
      warnings.add('$label: a $_kSplat primitive with no attributes; skipped.');
      return null;
    }

    final position = _asInt(attributes['POSITION']);
    if (position == null || reader.typeOf(position) != GltfAccessorType.vec3) {
      warnings.add(
        '$label: a $_kSplat primitive needs a VEC3 POSITION; '
        'skipped.',
      );
      return null;
    }
    final count = reader.countOf(position);

    // A compression extension nested in this one keeps its data in its own
    // buffer, and leaves the ordinary accessors without views; reading those
    // as zeros would load a cloud pinched to the origin.
    final nested = extension['extensions'];
    if (nested is Map && nested.isNotEmpty && !reader.hasData(position)) {
      warnings.add(
        '$label: $_kSplat data is compressed with '
        '${nested.keys.join(', ')}, which is not implemented; skipped.',
      );
      return null;
    }

    int? required(String name, GltfAccessorType type) {
      final accessor = _asInt(attributes[name]);
      if (accessor == null) {
        warnings.add('$label: a $_kSplat primitive has no $name; skipped.');
        return null;
      }
      final actualType = reader.typeOf(accessor);
      final actualCount = reader.countOf(accessor);
      if (actualType != type || actualCount != count) {
        warnings.add(
          '$label: $name is $actualCount ${actualType.name} elements for '
          '$count splats; skipped.',
        );
        return null;
      }
      return accessor;
    }

    final rotation = required('$_kSplat:ROTATION', GltfAccessorType.vec4);
    final scale = required('$_kSplat:SCALE', GltfAccessorType.vec3);
    final opacity = required('$_kSplat:OPACITY', GltfAccessorType.scalar);
    final dc = required('$_kSplat:SH_DEGREE_0_COEF_0', GltfAccessorType.vec3);
    if (rotation == null || scale == null || opacity == null || dc == null) {
      return null;
    }

    final centres = reader.readAsFloats(position);
    final scales = reader.readAsFloats(scale);
    final rotations = reader.readAsFloats(rotation);
    final opacities = reader.readAsFloats(opacity);
    final coefficients = reader.readAsFloats(dc);

    final colours = Float32List(count * 4);
    for (var i = 0; i < count; i++) {
      for (var c = 0; c < 3; c++) {
        // Negative colours clamp to nought, as the extension requires; an
        // sRGB one also clamps at one, since the curve is only defined there.
        final linear = math.max(0.0, splatChannel(coefficients[i * 3 + c]));
        colours[i * 4 + c] = colourSpace == SplatColourSpace.srgb
            ? srgbToLinear(math.min(linear, 1.0))
            : linear;
      }
      colours[i * 4 + 3] = opacities[i].clamp(0.0, 1.0);

      // Unit by the text, and not quite unit once quantised to bytes or
      // shorts, which is most of what a compressed file writes. The
      // covariance is `R S Sᵀ Rᵀ` and a quaternion of length 0.99 scales
      // every splat by nearly 2 % twice over.
      final q = i * 4;
      final length = math.sqrt(
        rotations[q] * rotations[q] +
            rotations[q + 1] * rotations[q + 1] +
            rotations[q + 2] * rotations[q + 2] +
            rotations[q + 3] * rotations[q + 3],
      );
      if (length > 0.0) {
        for (var k = 0; k < 4; k++) {
          rotations[q + k] /= length;
        }
      } else {
        rotations.fillRange(q, q + 4, 0.0);
        rotations[q + 3] = 1.0;
      }
    }

    final (degree, rest) = _higherBands(
      attributes,
      count,
      label,
      reader,
      warnings,
    );
    return (
      SplatCloud(
        centres: centres,
        colours: colours,
        scales: scales,
        rotations: rotations,
        shDegree: degree,
        shRest: rest,
      ),
      colourSpace,
    );
  }

  /// The complete bands above zero, packed as `SplatCloud.shRest` wants.
  ///
  /// A band is complete when every one of its `2l + 1` coefficients is there
  /// at the right shape; the first band that is not ends the list, since the
  /// text forbids a band without the ones below it.
  (int, Float32List) _higherBands(
    Map<Object?, Object?> attributes,
    int count,
    String label,
    GltfAccessorReader reader,
    List<String> warnings,
  ) {
    final bands = <List<Float32List>>[];
    for (var degree = 1; degree <= 3; degree++) {
      final names = <String>[
        for (var n = 0; n < 2 * degree + 1; n++)
          '$_kSplat:SH_DEGREE_${degree}_COEF_$n',
      ];
      final accessors = <int?>[
        for (final name in names) _asInt(attributes[name]),
      ];
      if (accessors.every((a) => a == null)) break;
      final complete = accessors.every(
        (a) =>
            a != null &&
            reader.typeOf(a) == GltfAccessorType.vec3 &&
            reader.countOf(a) == count,
      );
      if (!complete) {
        warnings.add(
          '$label: spherical-harmonic degree $degree is partly defined; '
          'kept up to degree ${degree - 1}.',
        );
        break;
      }
      bands.add(<Float32List>[
        for (final a in accessors) reader.readAsFloats(a!),
      ]);
    }

    final degree = bands.length;
    final coefficientsPerSplat = (degree + 1) * (degree + 1) - 1;
    final rest = Float32List(count * coefficientsPerSplat * 3);
    final all = <Float32List>[for (final band in bands) ...band];
    for (var i = 0; i < count; i++) {
      for (var k = 0; k < all.length; k++) {
        final at = (i * coefficientsPerSplat + k) * 3;
        rest[at] = all[k][i * 3];
        rest[at + 1] = all[k][i * 3 + 1];
        rest[at + 2] = all[k][i * 3 + 2];
      }
    }
    return (degree, rest);
  }
}

/// [primitive]'s `KHR_gaussian_splatting` object, or null when it carries
/// none. A value that is there and not an object counts as none: the
/// primitive is then only a point cloud, which `_decodeMesh` skips as one.
Map<String, Object?>? _splatExtensionOf(Map<String, Object?> primitive) {
  final extensions = primitive['extensions'];
  if (extensions is! Map) return null;
  final extension = extensions[_kSplat];
  return extension is Map ? extension.cast<String, Object?>() : null;
}
