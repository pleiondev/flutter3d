/// `fmt-11`'s own acceptance line: zero errors on a real export, an error
/// when an accessor's declared `min`/`max` is wrong.
///
///     dart test test/gltf_validate_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

void main() {
  group('a real export has nothing wrong with its bounds', () {
    // The same eight models gltf_writer_test.dart round-trips byte-for-byte —
    // a writer that gets the geometry right and the bounds wrong would still
    // pass that test, since compareModelDocuments never reads accessors[].min.
    final cases = <String, Future<ModelDocument> Function()>{
      'Box.glb': () => GltfLoader().load(_sample('Box.glb')),
      'BoxTextured.glb': () => GltfLoader().load(_sample('BoxTextured.glb')),
      'BoxVertexColors.glb': () =>
          GltfLoader().load(_sample('BoxVertexColors.glb')),
      'NormalTangentTest.glb': () =>
          GltfLoader().load(_sample('NormalTangentTest.glb')),
      'Triangle.gltf': () => GltfLoader().load(_sample('Triangle.gltf')),
      'teapot.obj (a different decoder, the same writer)': () =>
          ObjLoader().load(_sample('teapot.obj')),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final document = await entry.value();
        final bytes = GltfWriter(document).writeGlb();

        expect(await validateGltfExport(bytes), isEmpty);
      });
    }
  });

  group('a broken min/max is caught', () {
    late Uint8List valid;

    setUp(() async {
      final document = await GltfLoader().load(_sample('Box.glb'));
      valid = GltfWriter(document).writeGlb();
    });

    test('a min moved away from the data it describes', () async {
      final container = GlbContainer.parse(valid);
      final json = jsonDecode(jsonEncode(container.json)) as Map<String, Object?>;
      final accessors = json['accessors']! as List;
      final position = accessors.firstWhere(
        (Object? a) => (a! as Map)['min'] != null,
      ) as Map<String, Object?>;
      final min = (position['min']! as List).cast<Object?>();
      min[0] = (min[0]! as num).toDouble() - 5.0;

      final broken = GlbContainer.encode(json, binary: container.binaryChunk);

      final problems = await validateGltfExport(broken);
      expect(problems, isNotEmpty);
      expect(problems.single, contains('min[0]'));
    });

    test('and an untouched export stays clean, so the check above means '
        'something', () async {
      expect(await validateGltfExport(valid), isEmpty);
    });

    test('a max moved away from the data it describes', () async {
      final container = GlbContainer.parse(valid);
      final json = jsonDecode(jsonEncode(container.json)) as Map<String, Object?>;
      final accessors = json['accessors']! as List;
      final position = accessors.firstWhere(
        (Object? a) => (a! as Map)['max'] != null,
      ) as Map<String, Object?>;
      final max = (position['max']! as List).cast<Object?>();
      max[1] = (max[1]! as num).toDouble() + 5.0;

      final broken = GlbContainer.encode(json, binary: container.binaryChunk);

      final problems = await validateGltfExport(broken);
      expect(problems, isNotEmpty);
      expect(problems.single, contains('max[1]'));
    });
  });

  test(
    'an accessor with no declared min/max is not required to have one',
    () async {
      // NORMAL/TEXCOORD/COLOR_0 never get bounds from this writer — the
      // whole reason the checker only looks at accessors that declared one
      // at all.
      final document = await GltfLoader().load(
        _sample('NormalTangentTest.glb'),
      );
      final bytes = GltfWriter(document).writeGlb();
      final container = GlbContainer.parse(bytes);
      final accessors = container.json['accessors']! as List;
      expect(
        accessors.any((Object? a) => (a! as Map)['min'] == null),
        isTrue,
        reason: 'a mesh with normals writes at least one bounds-free accessor',
      );

      expect(await validateGltfExport(bytes), isEmpty);
    },
  );
}
