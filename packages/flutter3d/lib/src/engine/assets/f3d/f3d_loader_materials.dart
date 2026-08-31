/// Reads `.f3d`'s materials and the images their textures bind to.
///
/// **A part of `f3d_loader.dart`, not a file of its own.** Every reader here
/// calls the private byte-view helpers (`_section`, `_recordOffset`, `_string`,
/// `_blobOffset`, ...) declared on `F3dDocument` in `f3d_loader.dart`. A
/// `part` keeps the phase in its own file without making those helpers public.
part of 'f3d_loader.dart';

extension _F3dMaterials on F3dDocument {
  // ---------------------------------------------------------------- materials

  List<SurfaceMaterial> _readMaterials() {
    final table = _section(F3dSection.materials);
    return <SurfaceMaterial>[
      for (var i = 0; i < table.count; i++) _readMaterial(i),
    ];
  }

  SurfaceMaterial _readMaterial(int index) {
    var o = _recordOffset(F3dSection.materials, index, F3dRecord.material);

    final name = _string(
      _view.getUint32(o, Endian.little),
      _view.getUint32(o + 4, Endian.little),
    );
    o += 8;

    final baseColor = Vector4(
      _view.getFloat32(o, Endian.little),
      _view.getFloat32(o + 4, Endian.little),
      _view.getFloat32(o + 8, Endian.little),
      _view.getFloat32(o + 12, Endian.little),
    );
    o += 16;

    final metallic = _view.getFloat32(o, Endian.little);
    final roughness = _view.getFloat32(o + 4, Endian.little);
    final normalScale = _view.getFloat32(o + 8, Endian.little);
    final occlusionStrength = _view.getFloat32(o + 12, Endian.little);
    o += 16;

    final emissive = Vector3(
      _view.getFloat32(o, Endian.little),
      _view.getFloat32(o + 4, Endian.little),
      _view.getFloat32(o + 8, Endian.little),
    );
    final emissiveStrength = _view.getFloat32(o + 12, Endian.little);
    o += 16;

    final alphaModeIndex = _view.getUint32(o, Endian.little);
    final alphaCutoff = _view.getFloat32(o + 4, Endian.little);
    final doubleSided = _view.getUint32(o + 8, Endian.little) != 0;
    final unlit = _view.getUint32(o + 12, Endian.little) != 0;
    o += 16;

    final bindings = <TextureBinding?>[];
    for (var b = 0; b < 5; b++) {
      bindings.add(_readBinding(o));
      o += F3dRecord.textureBinding;
    }

    return SurfaceMaterial(
      name: name,
      baseColor: baseColor,
      metallic: metallic,
      roughness: roughness,
      baseColorTexture: bindings[0],
      metallicRoughnessTexture: bindings[1],
      normalTexture: bindings[2],
      normalScale: normalScale,
      occlusionTexture: bindings[3],
      occlusionStrength: occlusionStrength,
      emissiveTexture: bindings[4],
      emissive: emissive,
      emissiveStrength: emissiveStrength,
      alphaMode: alphaModeIndex < SurfaceAlphaMode.values.length
          ? SurfaceAlphaMode.values[alphaModeIndex]
          : SurfaceAlphaMode.opaque,
      alphaCutoff: alphaCutoff,
      doubleSided: doubleSided,
      unlit: unlit,
    );
  }

  TextureBinding? _readBinding(int offset) {
    final imageIndex = _view.getInt32(offset, Endian.little);
    if (imageIndex < 0) return null;

    final flags = _view.getUint32(offset + 8, Endian.little);
    TextureWrap wrap(int shift) {
      final value = (flags >> shift) & F3dSamplingFlags.wrapMask;
      return value < TextureWrap.values.length
          ? TextureWrap.values[value]
          : TextureWrap.repeat;
    }

    return TextureBinding(
      imageIndex: imageIndex,
      texCoordSet: _view.getUint32(offset + 4, Endian.little),
      sampling: TextureSampling(
        magLinear: flags & F3dSamplingFlags.magLinear != 0,
        minLinear: flags & F3dSamplingFlags.minLinear != 0,
        useMipmaps: flags & F3dSamplingFlags.useMipmaps != 0,
        wrapS: wrap(F3dSamplingFlags.wrapSShift),
        wrapT: wrap(F3dSamplingFlags.wrapTShift),
      ),
    );
  }

  // ------------------------------------------------------------------- images

  List<EncodedImage> _readImages() {
    final table = _section(F3dSection.images);
    return <EncodedImage>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.images, i, F3dRecord.image);
          final dataOffset = _view.getUint32(o, Endian.little);
          final dataLength = _view.getUint32(o + 4, Endian.little);

          return EncodedImage(
            // A view, not a copy: image bytes are the largest thing in the file
            // and the decoder downstream only reads them.
            bytes: _bytes.buffer.asUint8List(
              _blobOffset(dataOffset),
              dataLength,
            ),
            name: _string(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ),
            mimeType: _string(
              _view.getUint32(o + 16, Endian.little),
              _view.getUint32(o + 20, Endian.little),
            ),
          );
        }(),
    ];
  }
}
