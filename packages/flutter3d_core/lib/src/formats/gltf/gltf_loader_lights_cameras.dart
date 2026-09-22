/// Turns glTF's own `cameras` and the `KHR_lights_punctual` extension's
/// `lights` into [ModelCamera]/[ModelLight] — `fmt-28`'s own row.
///
/// **A part of `gltf_loader.dart`**, for the same reason every other phase
/// is: it reads the private JSON helpers (`_mapList`, `_asInt`, ...)
/// declared at the bottom of that file.
part of 'gltf_loader.dart';

extension _GltfLightsAndCameras on GltfLoader {
  /// `extensions.KHR_lights_punctual.lights` — a document-level array, the
  /// extension's own placement, distinct from `node.extensions
  /// .KHR_lights_punctual.light`, which only names which of these a node
  /// points at.
  List<ModelLight> _decodeLights(
    Map<String, Object?> json,
    List<String> warnings,
  ) {
    final extensions = json['extensions'];
    if (extensions is! Map) return const <ModelLight>[];
    final block = extensions['KHR_lights_punctual'];
    if (block is! Map) return const <ModelLight>[];
    final entries = _mapList(block['lights']);

    return <ModelLight>[
      for (var i = 0; i < entries.length; i++)
        _lightFrom(entries[i], i, warnings),
    ];
  }

  ModelLight _lightFrom(
    Map<String, Object?> light,
    int index,
    List<String> warnings,
  ) {
    final typeName = light['type'];
    final type = switch (typeName) {
      'directional' => ModelLightType.directional,
      'point' => ModelLightType.point,
      'spot' => ModelLightType.spot,
      _ => () {
        warnings.add(
          'lights[$index] has ${typeName == null ? 'no' : 'an unknown'} '
          'type${typeName is String ? ' "$typeName"' : ''}; treated as '
          'directional.',
        );
        return ModelLightType.directional;
      }(),
    };

    final spot = light['spot'];
    final spotMap = spot is Map ? spot.cast<String, Object?>() : null;
    final name = light['name'];

    return ModelLight(
      type: type,
      name: name is String ? name : null,
      color: _vec3(light['color']) ?? Vector3(1.0, 1.0, 1.0),
      intensity: _asDouble(light['intensity']) ?? 1.0,
      range: _asDouble(light['range']),
      innerConeAngle: _asDouble(spotMap?['innerConeAngle']) ?? 0.0,
      outerConeAngle: _asDouble(spotMap?['outerConeAngle']),
    );
  }

  /// glTF's own `cameras` array, core rather than an extension.
  ///
  /// **Never drops an entry.** A node's own `camera` is an index into this
  /// list, so a malformed camera dropped here would shift every index past
  /// it onto the wrong camera rather than onto none — the same reason
  /// `_decodeMaterials` never drops a material. A camera this cannot make
  /// sense of becomes a default perspective one instead, named by the
  /// warning that explains why.
  List<ModelCamera> _decodeCameras(
    Map<String, Object?> json,
    List<String> warnings,
  ) {
    final entries = _mapList(json['cameras']);
    return <ModelCamera>[
      for (var i = 0; i < entries.length; i++)
        _cameraFrom(entries[i], i, warnings),
    ];
  }

  static const ModelPerspectiveCamera _fallbackProjection =
      ModelPerspectiveCamera(yfov: 0.8, znear: 0.1);

  ModelCamera _cameraFrom(
    Map<String, Object?> camera,
    int index,
    List<String> warnings,
  ) {
    final name = camera['name'];
    final type = camera['type'];

    if (type == 'perspective') {
      final perspective = camera['perspective'];
      final p = perspective is Map ? perspective.cast<String, Object?>() : null;
      final yfov = _asDouble(p?['yfov']);
      final znear = _asDouble(p?['znear']);
      if (p == null || yfov == null || znear == null) {
        warnings.add(
          'cameras[$index] is a perspective camera missing "perspective", '
          '"yfov" or "znear"; a default 45-degree camera was used instead.',
        );
        return ModelCamera(
          name: name is String ? name : null,
          projection: _fallbackProjection,
        );
      }
      return ModelCamera(
        name: name is String ? name : null,
        projection: ModelPerspectiveCamera(
          yfov: yfov,
          aspectRatio: _asDouble(p['aspectRatio']),
          znear: znear,
          zfar: _asDouble(p['zfar']),
        ),
      );
    }

    if (type == 'orthographic') {
      final orthographic = camera['orthographic'];
      final o = orthographic is Map
          ? orthographic.cast<String, Object?>()
          : null;
      final xmag = _asDouble(o?['xmag']);
      final ymag = _asDouble(o?['ymag']);
      final znear = _asDouble(o?['znear']);
      final zfar = _asDouble(o?['zfar']);
      if (o == null ||
          xmag == null ||
          ymag == null ||
          znear == null ||
          zfar == null) {
        warnings.add(
          'cameras[$index] is an orthographic camera missing '
          '"orthographic", "xmag", "ymag", "znear" or "zfar"; a default '
          '45-degree perspective camera was used instead.',
        );
        return ModelCamera(
          name: name is String ? name : null,
          projection: _fallbackProjection,
        );
      }
      return ModelCamera(
        name: name is String ? name : null,
        projection: ModelOrthographicCamera(
          xmag: xmag,
          ymag: ymag,
          znear: znear,
          zfar: zfar,
        ),
      );
    }

    warnings.add(
      'cameras[$index] has ${type == null ? 'no' : 'an unknown'} '
      'type${type is String ? ' "$type"' : ''}; a default 45-degree '
      'perspective camera was used instead.',
    );
    return ModelCamera(
      name: name is String ? name : null,
      projection: _fallbackProjection,
    );
  }
}
