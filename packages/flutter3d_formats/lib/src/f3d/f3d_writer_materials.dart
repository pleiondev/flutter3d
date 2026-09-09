/// Writes `.f3d`'s materials and the images their textures bind to.
///
/// **A part of `f3d_writer.dart`, not a file of its own.** Every writer here
/// calls the blob/string helpers (`_blobAppend`, `_string`) declared on
/// `F3dWriter` in `f3d_writer.dart`. A `part` keeps the phase in its own file
/// without making those helpers public.
part of 'f3d_writer.dart';

extension _F3dWriteMaterials on F3dWriter {
  // ---------------------------------------------------------------- materials

  Uint8List _writeMaterials() {
    final table = Uint8List(document.materials.length * F3dRecord.material);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.materials.length; i++) {
      final material = document.materials[i];
      final (nameOffset, nameLength) = _string(material.name);
      var o = i * F3dRecord.material;

      view.setUint32(o, nameOffset, Endian.little);
      view.setUint32(o + 4, nameLength, Endian.little);
      o += 8;

      view.setFloat32(o, material.baseColor.x, Endian.little);
      view.setFloat32(o + 4, material.baseColor.y, Endian.little);
      view.setFloat32(o + 8, material.baseColor.z, Endian.little);
      view.setFloat32(o + 12, material.baseColor.w, Endian.little);
      o += 16;

      view.setFloat32(o, material.metallic, Endian.little);
      view.setFloat32(o + 4, material.roughness, Endian.little);
      view.setFloat32(o + 8, material.normalScale, Endian.little);
      view.setFloat32(o + 12, material.occlusionStrength, Endian.little);
      o += 16;

      view.setFloat32(o, material.emissive.x, Endian.little);
      view.setFloat32(o + 4, material.emissive.y, Endian.little);
      view.setFloat32(o + 8, material.emissive.z, Endian.little);
      view.setFloat32(o + 12, material.emissiveStrength, Endian.little);
      o += 16;

      // The alpha mode's index is written deliberately: the enum is part of the
      // format now, so its order may not be shuffled without a version bump.
      view.setUint32(o, material.alphaMode.index, Endian.little);
      view.setFloat32(o + 4, material.alphaCutoff, Endian.little);
      view.setUint32(o + 8, material.doubleSided ? 1 : 0, Endian.little);
      view.setUint32(o + 12, material.unlit ? 1 : 0, Endian.little);
      o += 16;

      for (final binding in <TextureBinding?>[
        material.baseColorTexture,
        material.metallicRoughnessTexture,
        material.normalTexture,
        material.occlusionTexture,
        material.emissiveTexture,
      ]) {
        _writeBinding(view, o, binding);
        o += F3dRecord.textureBinding;
      }
    }
    return table;
  }

  void _writeBinding(ByteData view, int offset, TextureBinding? binding) {
    if (binding == null) {
      // -1 rather than a separate "present" flag: an index is either a real
      // image or it is not, and one sentinel cannot disagree with itself.
      view.setInt32(offset, -1, Endian.little);
      view.setUint32(offset + 4, 0, Endian.little);
      view.setUint32(offset + 8, 0, Endian.little);
      return;
    }

    final s = binding.sampling;
    var flags = 0;
    if (s.magLinear) flags |= F3dSamplingFlags.magLinear;
    if (s.minLinear) flags |= F3dSamplingFlags.minLinear;
    if (s.useMipmaps) flags |= F3dSamplingFlags.useMipmaps;
    flags |= s.wrapS.index << F3dSamplingFlags.wrapSShift;
    flags |= s.wrapT.index << F3dSamplingFlags.wrapTShift;

    view.setInt32(offset, binding.imageIndex, Endian.little);
    view.setUint32(offset + 4, binding.texCoordSet, Endian.little);
    view.setUint32(offset + 8, flags, Endian.little);
  }

  // ------------------------------------------------------------------- images

  Uint8List _writeImages() {
    final table = Uint8List(document.images.length * F3dRecord.image);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.images.length; i++) {
      final image = document.images[i];
      // Still encoded. Decoding a PNG needs `dart:ui`, which the asset layer
      // deliberately does not have, and a converter that produced raw RGBA
      // would multiply the file size by ten to save a decode the GPU upload
      // path already has to do.
      final dataOffset = _blobAppend(image.bytes);
      final (nameOffset, nameLength) = _string(image.name);
      final (mimeOffset, mimeLength) = _string(image.mimeType);

      final o = i * F3dRecord.image;
      view.setUint32(o, dataOffset, Endian.little);
      view.setUint32(o + 4, image.bytes.length, Endian.little);
      view.setUint32(o + 8, nameOffset, Endian.little);
      view.setUint32(o + 12, nameLength, Endian.little);
      view.setUint32(o + 16, mimeOffset, Endian.little);
      view.setUint32(o + 20, mimeLength, Endian.little);
    }
    return table;
  }
}
