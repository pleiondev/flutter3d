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

  /// One bitmask per surface, [F3dSection.surfaceAttributes] order matching
  /// [F3dSection.surfaces]. See [F3dAttributeFlags].
  Uint8List _writeSurfaceAttributes() {
    final table = Uint8List(
      document.surfaces.length * F3dRecord.surfaceAttributes,
    );
    final view = ByteData.view(table.buffer);
    const named = <(String, int)>[
      ('position', F3dAttributeFlags.position),
      ('normal', F3dAttributeFlags.normal),
      ('texcoord', F3dAttributeFlags.texcoord),
      ('tangent', F3dAttributeFlags.tangent),
      ('color', F3dAttributeFlags.color),
      ('joints', F3dAttributeFlags.joints),
      ('weights', F3dAttributeFlags.weights),
    ];

    for (var i = 0; i < document.surfaces.length; i++) {
      final authored = document.surfaces[i].authoredAttributes;
      var flags = 0;
      for (final (name, bit) in named) {
        if (authored.contains(name)) flags |= bit;
      }
      view.setUint32(i * F3dRecord.surfaceAttributes, flags, Endian.little);
    }
    return table;
  }

  /// One `(offset, length)` string per surface, [F3dSection.surfaces] order.
  /// See `ModelSurface.meshName`.
  Uint8List _writeMeshNames() {
    final table = Uint8List(document.surfaces.length * F3dRecord.meshName);
    final view = ByteData.view(table.buffer);
    for (var i = 0; i < document.surfaces.length; i++) {
      final (offset, length) = _string(document.surfaces[i].meshName);
      view.setUint32(i * F3dRecord.meshName, offset, Endian.little);
      view.setUint32(i * F3dRecord.meshName + 4, length, Endian.little);
    }
    return table;
  }

  /// Zero or one record — see `ModelDocument.asset`.
  (Uint8List, int) _writeAsset() {
    final generator = document.asset?.generator;
    if (generator == null) return (Uint8List(0), 0);
    final (offset, length) = _string(generator);
    final table = Uint8List(F3dRecord.asset);
    final view = ByteData.view(table.buffer);
    view.setUint32(0, offset, Endian.little);
    view.setUint32(4, length, Endian.little);
    return (table, 1);
  }

  /// One `(offset, length)` string per image, [F3dSection.images] order. See
  /// `EncodedImage.sourceUri`.
  Uint8List _writeImageUris() {
    final table = Uint8List(document.images.length * F3dRecord.imageUri);
    final view = ByteData.view(table.buffer);
    for (var i = 0; i < document.images.length; i++) {
      final (offset, length) = _string(document.images[i].sourceUri);
      view.setUint32(i * F3dRecord.imageUri, offset, Endian.little);
      view.setUint32(i * F3dRecord.imageUri + 4, length, Endian.little);
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

  /// One record per `ModelLod`, across every node that has any — sparse,
  /// the same shape [_writeMorphTargets] already writes for surfaces.
  (Uint8List, int) _writeLods() {
    final records = BytesBuilder();
    var count = 0;

    for (var i = 0; i < document.nodes.length; i++) {
      for (final lod in document.nodes[i].lods) {
        // Its own section: see [_writeImpostors].
        if (lod.impostor != null) continue;
        final surfaceOffset = _blobAppend(
          Int32List.fromList(lod.surfaceIndices),
        );

        final record = ByteData(F3dRecord.lod);
        record.setUint32(0, i, Endian.little);
        record.setFloat32(4, lod.maxScreenFraction, Endian.little);
        record.setUint32(8, surfaceOffset, Endian.little);
        record.setUint32(12, lod.surfaceIndices.length, Endian.little);

        records.add(record.buffer.asUint8List());
        count++;
      }
    }
    return (records.toBytes(), count);
  }

  /// One record per impostor level — `C4`. Kept out of [_writeLods] so a
  /// reader that predates it finds an ordinary chain of surface levels rather
  /// than a level naming no surfaces at all.
  (Uint8List, int) _writeImpostors() {
    final records = BytesBuilder();
    var count = 0;

    for (var i = 0; i < document.nodes.length; i++) {
      for (final lod in document.nodes[i].lods) {
        final impostor = lod.impostor;
        if (impostor == null) continue;
        final record = ByteData(F3dRecord.impostor)
          ..setUint32(0, i, Endian.little)
          ..setFloat32(4, lod.maxScreenFraction, Endian.little)
          ..setUint32(8, impostor.albedoImage, Endian.little)
          ..setUint32(12, impostor.normalDepthImage, Endian.little)
          ..setUint32(16, impostor.grid, Endian.little)
          ..setFloat32(20, impostor.centre.x, Endian.little)
          ..setFloat32(24, impostor.centre.y, Endian.little)
          ..setFloat32(28, impostor.centre.z, Endian.little)
          ..setFloat32(32, impostor.radius, Endian.little);
        records.add(record.buffer.asUint8List());
        count++;
      }
    }
    return (records.toBytes(), count);
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
