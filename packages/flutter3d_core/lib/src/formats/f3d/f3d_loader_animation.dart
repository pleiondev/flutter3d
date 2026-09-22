/// Reads `.f3d`'s animation clips and skins.
///
/// **A part of `f3d_loader.dart`, not a file of its own.** Every reader here
/// calls the private byte-view helpers (`_section`, `_recordOffset`, `_string`,
/// `_floats`, `_int32s`, ...) declared on `F3dDocument` in `f3d_loader.dart`.
/// A `part` keeps the phase in its own file without making those helpers
/// public.
part of 'f3d_loader.dart';

extension _F3dAnimation on F3dDocument {
  // --------------------------------------------------------------- animations

  List<AnimationClip> _readAnimations() {
    final table = _section(F3dSection.animations);
    return <AnimationClip>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(
            F3dSection.animations,
            i,
            F3dRecord.animation,
          );
          final firstTrack = _view.getUint32(o + 8, Endian.little);
          final trackCount = _view.getUint32(o + 12, Endian.little);

          return AnimationClip(
            name: _string(
              _view.getUint32(o, Endian.little),
              _view.getUint32(o + 4, Endian.little),
            ),
            tracks: <AnimationTrack>[
              for (var t = 0; t < trackCount; t++) _readTrack(firstTrack + t),
            ],
          );
        }(),
    ];
  }

  AnimationTrack _readTrack(int index) {
    final o = _recordOffset(F3dSection.tracks, index, F3dRecord.track);
    final pathIndex = _view.getUint32(o + 4, Endian.little);
    final interpolationIndex = _view.getUint32(o + 8, Endian.little);

    if (pathIndex >= AnimationPath.values.length ||
        interpolationIndex >= AnimationInterpolation.values.length) {
      throw F3dFormatException(
        'tracks[$index] names path $pathIndex and interpolation '
        '$interpolationIndex, which this build does not have.',
      );
    }

    return AnimationTrack(
      nodeIndex: _view.getUint32(o, Endian.little),
      path: AnimationPath.values[pathIndex],
      interpolation: AnimationInterpolation.values[interpolationIndex],
      componentCount: _view.getUint32(o + 12, Endian.little),
      times: _floats(
        _view.getUint32(o + 16, Endian.little),
        _view.getUint32(o + 20, Endian.little),
      ),
      values: _floats(
        _view.getUint32(o + 24, Endian.little),
        _view.getUint32(o + 28, Endian.little),
      ),
    );
  }

  // -------------------------------------------------------------------- skins

  List<ModelSkin> _readSkins() {
    final table = _section(F3dSection.skins);
    return <ModelSkin>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.skins, i, F3dRecord.skin);
          final jointCount = _view.getUint32(o + 12, Endian.little);
          final matrices = _floats(
            _view.getUint32(o + 16, Endian.little),
            jointCount * 16,
          );
          final root = _view.getInt32(o + 20, Endian.little);

          return ModelSkin(
            name: _string(
              _view.getUint32(o, Endian.little),
              _view.getUint32(o + 4, Endian.little),
            ),
            joints: _int32s(
              _view.getUint32(o + 8, Endian.little),
              jointCount,
            ).toList(),
            inverseBindMatrices: <Matrix4>[
              for (var j = 0; j < jointCount; j++)
                Matrix4.fromFloat32List(
                  Float32List.sublistView(matrices, j * 16, j * 16 + 16),
                ),
            ],
            skeletonRoot: root < 0 ? null : root,
          );
        }(),
    ];
  }
}
