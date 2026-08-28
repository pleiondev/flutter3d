import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/gltf_resolvers.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

/// A minimal but valid glTF with one animated node, assembled by hand.
///
/// Hand-built rather than sampled: the cases worth pinning down are malformed
/// ones, and a well-formed Khronos file cannot exercise them.
Uint8List buildAnimatedGltf({
  required Map<String, Object?> animation,
  List<Map<String, Object?>>? extraAccessors,
  Uint8List? binary,
}) {
  final bin =
      binary ??
      Uint8List.view(
        Float32List.fromList(<double>[
          // Two keyframe times.
          0.0, 1.0,
          // Two vec3 translations.
          0.0, 0.0, 0.0,
          10.0, 0.0, 0.0,
        ]).buffer,
      );

  final json = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <int>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'mover'},
    ],
    'buffers': <Object?>[
      <String, Object?>{'byteLength': bin.lengthInBytes},
    ],
    'bufferViews': <Object?>[
      <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 8},
      <String, Object?>{'buffer': 0, 'byteOffset': 8, 'byteLength': 24},
    ],
    'accessors': <Object?>[
      <String, Object?>{
        'bufferView': 0,
        'componentType': 5126,
        'count': 2,
        'type': 'SCALAR',
      },
      <String, Object?>{
        'bufferView': 1,
        'componentType': 5126,
        'count': 2,
        'type': 'VEC3',
      },
      ...?extraAccessors,
    ],
    'animations': <Object?>[animation],
  };

  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadding = (4 - (jsonBytes.length % 4)) % 4;
  final binPadding = (4 - (bin.lengthInBytes % 4)) % 4;

  final total =
      12 +
      8 +
      jsonBytes.length +
      jsonPadding +
      8 +
      bin.lengthInBytes +
      binPadding;
  final out = ByteData(total);
  var offset = 0;

  out.setUint32(offset, 0x46546C67, Endian.little); // 'glTF'
  out.setUint32(offset + 4, 2, Endian.little);
  out.setUint32(offset + 8, total, Endian.little);
  offset += 12;

  out.setUint32(offset, jsonBytes.length + jsonPadding, Endian.little);
  out.setUint32(offset + 4, 0x4E4F534A, Endian.little); // 'JSON'
  offset += 8;
  for (var i = 0; i < jsonBytes.length; i++) {
    out.setUint8(offset + i, jsonBytes[i]);
  }
  for (var i = 0; i < jsonPadding; i++) {
    out.setUint8(offset + jsonBytes.length + i, 0x20);
  }
  offset += jsonBytes.length + jsonPadding;

  out.setUint32(offset, bin.lengthInBytes + binPadding, Endian.little);
  out.setUint32(offset + 4, 0x004E4942, Endian.little); // 'BIN'
  offset += 8;
  for (var i = 0; i < bin.lengthInBytes; i++) {
    out.setUint8(offset + i, bin[i]);
  }

  return out.buffer.asUint8List();
}

Map<String, Object?> translationAnimation({
  String? interpolation,
  String path = 'translation',
  int? node = 0,
  int outputAccessor = 1,
}) => <String, Object?>{
  'name': 'move',
  'samplers': <Object?>[
    <String, Object?>{
      'input': 0,
      'output': outputAccessor,
      'interpolation': ?interpolation,
    },
  ],
  'channels': <Object?>[
    <String, Object?>{
      'sampler': 0,
      'target': <String, Object?>{'node': ?node, 'path': path},
    },
  ],
};

void main() {
  group('the node hierarchy survives decoding', () {
    test('a file with no animation still exposes its nodes', () async {
      final asset = await GltfLoader().load(readSample('Box.glb'));
      expect(asset.nodes, isNotEmpty);
      expect(asset.roots, isNotEmpty);
      expect(asset.animations, isEmpty);

      // Every surface is claimed by exactly one node, which is what makes the
      // instantiated hierarchy match the file.
      final claimed = <int>[];
      for (final node in asset.nodes) {
        claimed.addAll(node.surfaces);
      }
      claimed.sort();
      expect(claimed, <int>[for (var i = 0; i < asset.surfaces.length; i++) i]);
    });

    test(
      'nodes are index-aligned with the file, transform-only ones included',
      () async {
        // BoxAnimated has a node that only carries a transform, and that is the
        // node its clip drives; compacting the list to drawing nodes would leave
        // every channel pointing at the wrong thing.
        final asset = await GltfLoader().load(readSample('BoxAnimated.glb'));
        expect(asset.nodes.length, greaterThan(asset.surfaces.length));

        final animatedIndices = asset.animations
            .expand((c) => c.tracks)
            .map((t) => t.nodeIndex);
        for (final index in animatedIndices) {
          expect(index, lessThan(asset.nodes.length));
        }
      },
    );

    test('children reference nodes rather than surfaces', () async {
      final asset = await GltfLoader().load(readSample('BoxAnimated.glb'));
      var withChildren = 0;
      for (final node in asset.nodes) {
        for (final child in node.children) {
          expect(child, inInclusiveRange(0, asset.nodes.length - 1));
        }
        if (node.children.isNotEmpty) withChildren++;
      }
      expect(withChildren, greaterThan(0));
    });
  });

  group('Khronos animated samples', () {
    test('AnimatedCube decodes one looping rotation', () async {
      final asset = await GltfLoader().load(
        readSample('animated_cube/AnimatedCube.gltf'),
        resolveUri: fileUriResolver('$kSamples/animated_cube'),
      );

      expect(asset.animations, hasLength(1));
      final clip = asset.animations.single;
      expect(clip.tracks, hasLength(1));
      expect(clip.tracks.single.path, AnimationPath.rotation);
      expect(clip.tracks.single.componentCount, 4);
      expect(clip.duration, greaterThan(0.0));
    });

    test('BoxAnimated drives a hierarchy', () async {
      final asset = await GltfLoader().load(readSample('BoxAnimated.glb'));
      expect(asset.animations, isNotEmpty);

      final paths = asset.animations
          .expand((c) => c.tracks)
          .map((t) => t.path)
          .toSet();
      expect(paths, contains(AnimationPath.translation));
      expect(asset.animations.first.duration, greaterThan(0.0));
    });

    test('InterpolationTest covers all three interpolations', () async {
      // The whole point of this sample: if a decoder silently treats
      // CUBICSPLINE as LINEAR it reads tangents as values, and nothing else in
      // the suite would notice.
      final asset = await GltfLoader().load(
        readSample('InterpolationTest.glb'),
      );
      expect(asset.animations, isNotEmpty);

      final kinds = asset.animations
          .expand((c) => c.tracks)
          .map((t) => t.interpolation)
          .toSet();
      expect(
        kinds,
        containsAll(<AnimationInterpolation>[
          AnimationInterpolation.step,
          AnimationInterpolation.linear,
          AnimationInterpolation.cubicSpline,
        ]),
      );
    });

    test('a cubic track from the sample samples to a finite pose', () async {
      final asset = await GltfLoader().load(
        readSample('InterpolationTest.glb'),
      );
      final cubic = asset.animations
          .expand((c) => c.tracks)
          .firstWhere(
            (t) => t.interpolation == AnimationInterpolation.cubicSpline,
          );

      final out = Float32List(cubic.componentCount);
      for (var i = 0; i <= 10; i++) {
        cubic.sample(cubic.endTime * i / 10.0, out);
        for (final value in out) {
          expect(value.isFinite, isTrue);
        }
      }
    });
  });

  group('malformed animations are reported, not fatal', () {
    test(
      'a channel with no node is skipped silently, as the spec allows',
      () async {
        final asset = await GltfLoader().load(
          buildAnimatedGltf(animation: translationAnimation(node: null)),
        );
        expect(asset.animations, isEmpty);
        expect(
          asset.warnings.any((w) => w.contains('no usable channels')),
          isTrue,
        );
      },
    );

    test('a channel targeting a node that does not exist warns', () async {
      final asset = await GltfLoader().load(
        buildAnimatedGltf(animation: translationAnimation(node: 99)),
      );
      expect(asset.animations, isEmpty);
      expect(asset.warnings.any((w) => w.contains('node 99')), isTrue);
    });

    test('an unknown target path warns', () async {
      final asset = await GltfLoader().load(
        buildAnimatedGltf(animation: translationAnimation(path: 'colour')),
      );
      expect(asset.animations, isEmpty);
      expect(asset.warnings.any((w) => w.contains('colour')), isTrue);
    });

    test('a sampler index out of range warns', () async {
      final animation = translationAnimation();
      (animation['channels']! as List).first as Map<String, Object?>;
      ((animation['channels']! as List).first
              as Map<String, Object?>)['sampler'] =
          7;

      final asset = await GltfLoader().load(
        buildAnimatedGltf(animation: animation),
      );
      expect(asset.animations, isEmpty);
      expect(asset.warnings.any((w) => w.contains('sampler 7')), isTrue);
    });

    test('a value count that does not divide into keyframes warns', () async {
      // Declares CUBICSPLINE, which needs three values per key, over data that
      // only has one. Without the check this would throw out of the decoder.
      final asset = await GltfLoader().load(
        buildAnimatedGltf(
          animation: translationAnimation(interpolation: 'CUBICSPLINE'),
        ),
      );
      expect(asset.animations, isEmpty);
      expect(asset.warnings.any((w) => w.contains('does not divide')), isTrue);
    });

    test('a well-formed hand-built clip decodes', () async {
      final asset = await GltfLoader().load(
        buildAnimatedGltf(animation: translationAnimation()),
      );
      expect(asset.animations, hasLength(1));

      final track = asset.animations.single.tracks.single;
      expect(track.nodeIndex, 0);
      expect(track.path, AnimationPath.translation);
      expect(track.interpolation, AnimationInterpolation.linear);
      expect(track.keyCount, 2);

      final out = Float32List(3);
      track.sample(0.5, out);
      expect(out[0], closeTo(5.0, 1e-5));
    });

    test('an omitted interpolation defaults to LINEAR', () async {
      final asset = await GltfLoader().load(
        buildAnimatedGltf(animation: translationAnimation()),
      );
      expect(
        asset.animations.single.tracks.single.interpolation,
        AnimationInterpolation.linear,
      );
    });

    test('STEP is honoured rather than smoothed', () async {
      final asset = await GltfLoader().load(
        buildAnimatedGltf(
          animation: translationAnimation(interpolation: 'STEP'),
        ),
      );
      final track = asset.animations.single.tracks.single;
      expect(track.interpolation, AnimationInterpolation.step);

      final out = Float32List(3);
      track.sample(0.99, out);
      expect(out[0], 0.0);
    });
  });
}
