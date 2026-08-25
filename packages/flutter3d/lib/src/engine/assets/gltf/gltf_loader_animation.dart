/// Decodes `animations` into engine clips.
///
/// **A part of `gltf_loader.dart`, not a file of its own**, for the same
/// reason as the rest of this pipeline's phases: it reads the private JSON
/// helpers (`_mapList`, `_intList`, `_asInt`, ...) declared at the bottom of
/// `gltf_loader.dart`, and those stay unexported by staying in the same
/// library.
part of 'gltf_loader.dart';

extension _GltfAnimation on GltfLoader {
  // ---------------------------------------------------------------- animation

  /// Channels are grouped per clip and addressed by node index, which is why the
  /// node array is kept index-aligned with glTF's rather than compacted to the
  /// nodes that happen to draw something.
  List<AnimationClip> _decodeAnimations(
    Map<String, Object?> json,
    GltfAccessorReader reader,
    List<ModelNode> nodes,
    List<String> warnings,
  ) {
    final animations = _mapList(json['animations']);
    if (animations.isEmpty) return const <AnimationClip>[];

    final clips = <AnimationClip>[];
    for (var a = 0; a < animations.length; a++) {
      final animation = animations[a];
      final label = 'animations[$a]';
      final samplers = _mapList(animation['samplers']);
      final channels = _mapList(animation['channels']);
      final tracks = <AnimationTrack>[];

      for (var c = 0; c < channels.length; c++) {
        final channel = channels[c];
        final channelLabel = '$label.channels[$c]';

        final target = channel['target'];
        if (target is! Map) {
          warnings.add('$channelLabel has no target; skipped.');
          continue;
        }
        final nodeIndex = _asInt(target['node']);
        if (nodeIndex == null) {
          // A channel with no node is legal and means "do nothing", which the
          // spec allows so that a clip can be authored before its target is.
          continue;
        }
        if (nodeIndex < 0 || nodeIndex >= nodes.length) {
          warnings.add('$channelLabel targets node $nodeIndex, which does not '
              'exist; skipped.');
          continue;
        }

        final pathName = target['path'];
        final path =
            AnimationPath.fromGltf(pathName is String ? pathName : null);
        if (path == null) {
          warnings.add('$channelLabel targets unknown path "$pathName"; '
              'skipped.');
          continue;
        }

        final samplerIndex = _asInt(channel['sampler']);
        if (samplerIndex == null ||
            samplerIndex < 0 ||
            samplerIndex >= samplers.length) {
          warnings.add('$channelLabel references sampler $samplerIndex, which '
              'does not exist; skipped.');
          continue;
        }
        final sampler = samplers[samplerIndex];

        final inputAccessor = _asInt(sampler['input']);
        final outputAccessor = _asInt(sampler['output']);
        if (inputAccessor == null || outputAccessor == null) {
          warnings.add('$label.samplers[$samplerIndex] is missing input or '
              'output; skipped.');
          continue;
        }

        final interpolationName = sampler['interpolation'];
        final interpolation = AnimationInterpolation.fromGltf(
          interpolationName is String ? interpolationName : null,
        );

        final Float32List times;
        final Float32List values;
        try {
          times = reader.readAsFloats(inputAccessor);
          values = reader.readAsFloats(outputAccessor);
        } on FormatException catch (error) {
          warnings.add('$channelLabel could not be read: ${error.message}');
          continue;
        }

        if (times.isEmpty) {
          warnings.add('$channelLabel has no keyframes; skipped.');
          continue;
        }

        // Weight tracks carry one value per morph target, and only the value
        // count knows how many that is.
        final perKey = interpolation.valuesPerKey;
        final componentCount = path == AnimationPath.weights
            ? values.length ~/ (times.length * perKey)
            : path.componentCount;

        if (componentCount <= 0 ||
            values.length != times.length * componentCount * perKey) {
          warnings.add(
            '$channelLabel has ${times.length} keys but ${values.length} '
            'values, which does not divide into ${interpolation.name} '
            '${path.name} keyframes; skipped.',
          );
          continue;
        }

        if (path == AnimationPath.weights) {
          warnings.add('$channelLabel animates morph target weights, which are '
              'decoded but not applied.');
        }

        tracks.add(
          AnimationTrack(
            nodeIndex: nodeIndex,
            path: path,
            interpolation: interpolation,
            times: times,
            values: values,
            componentCount: componentCount,
          ),
        );
      }

      if (tracks.isEmpty) {
        warnings.add('$label has no usable channels; skipped.');
        continue;
      }

      final name = animation['name'];
      clips.add(
        AnimationClip(
          name: name is String ? name : 'animation $a',
          tracks: tracks,
        ),
      );
    }

    return clips;
  }
}
