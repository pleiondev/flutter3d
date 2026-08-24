/// Writes `.f3d`'s surfaces and the node hierarchy they hang off.
///
/// **A part of `f3d_writer.dart`, not a file of its own.** `_writeSurfaces`
/// calls `_meshIndex` (in `f3d_writer_geometry.dart`), and every writer here
/// calls the blob/string helpers (`_blobAppend`, `_string`) declared on
/// `F3dWriter` in `f3d_writer.dart`. A `part` keeps the phase in its own file
/// without making any of that public.
part of 'f3d_writer.dart';

extension _F3dWriteScene on F3dWriter {
  // ----------------------------------------------------------------- surfaces

  Uint8List _writeSurfaces() {
    final table = Uint8List(document.surfaces.length * F3dRecord.surface);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.surfaces.length; i++) {
      final surface = document.surfaces[i];
      final (nameOffset, nameLength) = _string(surface.name);

      final o = i * F3dRecord.surface;
      view.setUint32(o, _meshIndex(surface.mesh), Endian.little);
      view.setInt32(o + 4, surface.materialIndex ?? -1, Endian.little);
      view.setUint32(o + 8, nameOffset, Endian.little);
      view.setUint32(o + 12, nameLength, Endian.little);
      // The skin index rides in the flip-winding slot's upper bits: a surface
      // is at most one of skinned or mirrored in practice, but packing rather
      // than widening the record keeps every existing offset where it was, so
      // a reader of the previous version still finds the transform.
      view.setUint32(
        o + 16,
        (surface.flipWinding ? 1 : 0) | ((surface.skinIndex ?? -1) + 1) << 1,
        Endian.little,
      );

      // Column-major, matching vector_math's storage, so the reader can copy
      // straight into a Matrix4 without transposing.
      for (var e = 0; e < 16; e++) {
        view.setFloat32(
          o + 20 + e * 4,
          surface.transform.storage[e],
          Endian.little,
        );
      }
    }
    return table;
  }

  // -------------------------------------------------------------------- nodes

  Uint8List _writeNodes() {
    final nodes = document.nodes;
    final table = Uint8List(nodes.length * F3dRecord.node);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final (nameOffset, nameLength) = _string(node.name);
      final childOffset = _blobAppend(Int32List.fromList(node.children));
      final surfaceOffset = _blobAppend(Int32List.fromList(node.surfaces));

      var o = i * F3dRecord.node;
      view.setUint32(o, nameOffset, Endian.little);
      view.setUint32(o + 4, nameLength, Endian.little);
      o += 8;

      view.setFloat32(o, node.translation.x, Endian.little);
      view.setFloat32(o + 4, node.translation.y, Endian.little);
      view.setFloat32(o + 8, node.translation.z, Endian.little);
      o += 12;

      view.setFloat32(o, node.rotation.x, Endian.little);
      view.setFloat32(o + 4, node.rotation.y, Endian.little);
      view.setFloat32(o + 8, node.rotation.z, Endian.little);
      view.setFloat32(o + 12, node.rotation.w, Endian.little);
      o += 16;

      view.setFloat32(o, node.scale.x, Endian.little);
      view.setFloat32(o + 4, node.scale.y, Endian.little);
      view.setFloat32(o + 8, node.scale.z, Endian.little);
      o += 12;

      view.setUint32(o, childOffset, Endian.little);
      view.setUint32(o + 4, node.children.length, Endian.little);
      view.setUint32(o + 8, surfaceOffset, Endian.little);
      view.setUint32(o + 12, node.surfaces.length, Endian.little);
    }
    return table;
  }

  Uint8List _writeRoots() {
    final roots = Int32List.fromList(document.roots);
    return Uint8List.view(
      roots.buffer,
      roots.offsetInBytes,
      roots.lengthInBytes,
    );
  }
}
