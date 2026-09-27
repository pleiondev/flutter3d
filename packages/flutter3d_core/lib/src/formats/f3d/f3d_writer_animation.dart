/// Writes `.f3d`'s animation clips and skins.
///
/// **A part of `f3d_writer.dart`, not a file of its own.** Every writer here
/// calls the blob/string helpers (`_blobAppend`, `_string`) declared on
/// `F3dWriter` in `f3d_writer.dart`. A `part` keeps the phase in its own file
/// without making those helpers public.
part of 'f3d_writer.dart';

extension _F3dWriteAnimation on F3dWriter {
  // --------------------------------------------------------------- animations

  (Uint8List, Uint8List, int, int) _writeAnimations() {
    final clips = document.animations;
    final animationTable = Uint8List(clips.length * F3dRecord.animation);
    final animationView = ByteData.view(animationTable.buffer);

    final trackRecords = BytesBuilder();
    var trackCount = 0;

    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final (nameOffset, nameLength) = _string(clip.name);
      final firstTrack = trackCount;
      final nodeTracks = clip.tracks.where((t) => t.pointer == null).length;

      for (final track in clip.tracks) {
        // A pointer track goes to its own section — see
        // [F3dSection.pointerTracks] for why an old reader must not meet it.
        if (track.pointer != null) continue;
        final timesOffset = _blobAppend(track.times);
        final valuesOffset = _blobAppend(track.values);

        final record = ByteData(F3dRecord.track);
        record.setUint32(0, track.nodeIndex, Endian.little);
        record.setUint32(4, track.path.index, Endian.little);
        record.setUint32(8, track.interpolation.index, Endian.little);
        record.setUint32(12, track.componentCount, Endian.little);
        record.setUint32(16, timesOffset, Endian.little);
        record.setUint32(20, track.times.length, Endian.little);
        record.setUint32(24, valuesOffset, Endian.little);
        record.setUint32(28, track.values.length, Endian.little);
        trackRecords.add(record.buffer.asUint8List());
        trackCount++;
      }

      final o = i * F3dRecord.animation;
      animationView.setUint32(o, nameOffset, Endian.little);
      animationView.setUint32(o + 4, nameLength, Endian.little);
      animationView.setUint32(o + 8, firstTrack, Endian.little);
      animationView.setUint32(o + 12, nodeTracks, Endian.little);
    }

    return (animationTable, trackRecords.toBytes(), clips.length, trackCount);
  }

  /// The pointer tracks of every clip, with the clip and the position in it
  /// each came from.
  (Uint8List, int) _writePointerTracks() {
    final records = BytesBuilder();
    var count = 0;
    final clips = document.animations;
    for (var clip = 0; clip < clips.length; clip++) {
      final tracks = clips[clip].tracks;
      for (var position = 0; position < tracks.length; position++) {
        final track = tracks[position];
        final pointer = track.pointer;
        if (pointer == null) continue;
        final (pointerOffset, pointerLength) = _string(pointer.pointer);

        final record = ByteData(F3dRecord.pointerTrack);
        record.setUint32(0, clip, Endian.little);
        record.setUint32(4, position, Endian.little);
        record.setUint32(8, track.interpolation.index, Endian.little);
        record.setUint32(12, track.componentCount, Endian.little);
        record.setUint32(16, _blobAppend(track.times), Endian.little);
        record.setUint32(20, track.times.length, Endian.little);
        record.setUint32(24, _blobAppend(track.values), Endian.little);
        record.setUint32(28, track.values.length, Endian.little);
        record.setUint32(32, pointerOffset, Endian.little);
        record.setUint32(36, pointerLength, Endian.little);
        records.add(record.buffer.asUint8List());
        count++;
      }
    }
    return (records.toBytes(), count);
  }

  /// One record per variant: its name, and the surfaces that choose a
  /// material in it.
  Uint8List _writeVariants() {
    final variants = document.variants;
    final table = Uint8List(variants.length * F3dRecord.variant);
    final view = ByteData.view(table.buffer);
    final surfaces = document.surfaces;

    for (var v = 0; v < variants.length; v++) {
      final pairs = Int32List.fromList(<int>[
        for (var s = 0; s < surfaces.length; s++)
          if (surfaces[s].variantMaterials[v] case final material?) ...<int>[
            s,
            material,
          ],
      ]);
      final (nameOffset, nameLength) = _string(variants[v]);
      final o = v * F3dRecord.variant;
      view.setUint32(o, nameOffset, Endian.little);
      view.setUint32(o + 4, nameLength, Endian.little);
      view.setUint32(o + 8, _blobAppend(pairs), Endian.little);
      view.setUint32(o + 12, pairs.length ~/ 2, Endian.little);
    }
    return table;
  }

  // -------------------------------------------------------------------- skins

  Uint8List _writeSkins() {
    final table = Uint8List(document.skins.length * F3dRecord.skin);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.skins.length; i++) {
      final skin = document.skins[i];
      final (nameOffset, nameLength) = _string(skin.name);
      final jointOffset = _blobAppend(Int32List.fromList(skin.joints));

      // Flattened into one array rather than written matrix by matrix, so the
      // reader can view the lot and slice it, the way it does vertex data.
      final matrices = Float32List(skin.inverseBindMatrices.length * 16);
      for (var j = 0; j < skin.inverseBindMatrices.length; j++) {
        final storage = skin.inverseBindMatrices[j].storage;
        for (var e = 0; e < 16; e++) {
          matrices[j * 16 + e] = storage[e];
        }
      }
      final matrixOffset = _blobAppend(matrices);

      final o = i * F3dRecord.skin;
      view.setUint32(o, nameOffset, Endian.little);
      view.setUint32(o + 4, nameLength, Endian.little);
      view.setUint32(o + 8, jointOffset, Endian.little);
      view.setUint32(o + 12, skin.joints.length, Endian.little);
      view.setUint32(o + 16, matrixOffset, Endian.little);
      view.setInt32(o + 20, skin.skeletonRoot ?? -1, Endian.little);
    }
    return table;
  }
}
