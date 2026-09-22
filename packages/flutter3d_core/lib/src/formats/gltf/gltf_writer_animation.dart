/// Encodes `document.skins` and `document.animations`, the exact inverse of
/// `gltf_loader_skins.dart` and `gltf_loader_animation.dart`.
///
/// **A part of `gltf_writer.dart`**, for the same reason as every other
/// phase: it appends to the single binary blob and the flat `accessors`
/// array kept there.
part of 'gltf_writer.dart';

extension _GltfWriterAnimation on GltfWriter {
  List<Map<String, Object?>> _writeSkins() => <Map<String, Object?>>[
    for (final skin in document.skins)
      <String, Object?>{
        if (skin.name != null) 'name': skin.name,
        'joints': skin.joints,
        'skeleton': ?skin.skeletonRoot,
        if (skin.extras != null) 'extras': skin.extras,
        'inverseBindMatrices': _addAccessor(<String, Object?>{
          'bufferView': _appendBufferView(_flattenMatrices(skin)),
          'componentType': GltfComponentType.float.code,
          'type': GltfAccessorType.mat4.name,
          'count': skin.joints.length,
        }),
      },
  ];

  /// [skin.inverseBindMatrices] as one contiguous, column-major float array —
  /// `Matrix4.storage` is already column-major, matching the file's own
  /// convention, so this is a concatenation and not a transform.
  Float32List _flattenMatrices(ModelSkin skin) {
    final floats = Float32List(skin.joints.length * 16);
    for (var j = 0; j < skin.inverseBindMatrices.length; j++) {
      floats.setRange(j * 16, j * 16 + 16, skin.inverseBindMatrices[j].storage);
    }
    return floats;
  }

  List<Map<String, Object?>> _writeAnimations() => <Map<String, Object?>>[
    for (final clip in document.animations)
      () {
        final channels = <Map<String, Object?>>[];
        final samplers = <Map<String, Object?>>[];
        for (final track in clip.tracks) {
          final inputAccessor = _addAccessor(<String, Object?>{
            'bufferView': _appendBufferView(track.times),
            'componentType': GltfComponentType.float.code,
            'type': GltfAccessorType.scalar.name,
            'count': track.times.length,
            // Required on the input accessor by the spec — a reader is
            // allowed to trust it rather than scan the buffer, and one that
            // does gets a wrong clip duration from a wrong bound here.
            'min': <double>[track.times.first],
            'max': <double>[track.times.last],
          });

          // The accessor's own component count, which decides both its
          // `type` and how many elements `count` describes — not
          // `track.componentCount`, which for a `weights` track is the
          // number of morph targets rather than a glTF vector width.
          final accessorComponents = switch (track.path) {
            AnimationPath.rotation => 4,
            AnimationPath.weights => 1,
            AnimationPath.translation || AnimationPath.scale => 3,
          };
          final outputAccessor = _addAccessor(<String, Object?>{
            'bufferView': _appendBufferView(track.values),
            'componentType': GltfComponentType.float.code,
            'type': switch (accessorComponents) {
              4 => GltfAccessorType.vec4.name,
              3 => GltfAccessorType.vec3.name,
              _ => GltfAccessorType.scalar.name,
            },
            'count': track.values.length ~/ accessorComponents,
          });

          final samplerIndex = samplers.length;
          samplers.add(<String, Object?>{
            'input': inputAccessor,
            'output': outputAccessor,
            'interpolation': track.interpolation.toGltf(),
          });
          channels.add(<String, Object?>{
            'sampler': samplerIndex,
            'target': <String, Object?>{
              'node': track.nodeIndex,
              'path': track.path.toGltf(),
            },
          });
        }
        return <String, Object?>{
          if (clip.name != null) 'name': clip.name,
          'channels': channels,
          'samplers': samplers,
          if (clip.extras != null) 'extras': clip.extras,
        };
      }(),
  ];
}
