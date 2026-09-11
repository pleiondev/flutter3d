/// `GltfWriter`: the geometry half of a real glTF export, checked the way
/// every writer in this package is — decode, write, decode again, and ask
/// `compareModelDocuments` whether anything moved.
///
///     dart test test/gltf_writer_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The Khronos sample assets live in `flutter3d_samples`, a sibling package —
/// read straight off disk by relative path rather than declared as a
/// dependency, since that package pulls the Flutter SDK in for its
/// `flutter.assets` block and this one is not allowed to.
Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

void main() {
  group('9 models round-trip through writeGlb with nothing lost', () {
    final cases = <String, Future<ModelDocument> Function()>{
      'Box.glb': () => GltfLoader().load(_sample('Box.glb')),
      'BoxTextured.glb': () => GltfLoader().load(_sample('BoxTextured.glb')),
      'BoxVertexColors.glb': () =>
          GltfLoader().load(_sample('BoxVertexColors.glb')),
      'NormalTangentTest.glb': () =>
          GltfLoader().load(_sample('NormalTangentTest.glb')),
      'NormalTangentMirrorTest.glb': () =>
          GltfLoader().load(_sample('NormalTangentMirrorTest.glb')),
      'Triangle.gltf': () => GltfLoader().load(_sample('Triangle.gltf')),
      'cube/Cube.gltf': () => GltfLoader().load(
        _sample('cube/Cube.gltf'),
        resolveUri: (request) async => _sample('cube/${request.uri}'),
      ),
      'teapot.obj (a different decoder, the same writer)': () =>
          ObjLoader().load(_sample('teapot.obj')),
      'teapot.stl (a third decoder, real curvature rather than only '
              'synthetic edge cases)':
          () => StlLoader().load(_sample('teapot.stl')),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final source = await entry.value();
        final bytes = GltfWriter(source).writeGlb();
        final readBack = await GltfLoader().load(bytes);
        final problems = compareModelDocuments(source, readBack);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  });

  group('alignment', () {
    test('every bufferView starts on a 4-byte boundary', () async {
      // BoxTextured mixes an odd-length image (whatever the PNG happens to
      // compress to) with float vertex data, which is exactly the case an
      // unaligned writer gets wrong: the accessor after an odd-sized image
      // starts reading from the wrong byte.
      final source = await GltfLoader().load(_sample('BoxTextured.glb'));
      final bytes = GltfWriter(source).writeGlb();
      final container = GlbContainer.parse(bytes);
      final bufferViews = (container.json['bufferViews']! as List)
          .cast<Map<String, Object?>>();
      for (var i = 0; i < bufferViews.length; i++) {
        // Mutation: drop the padding loop in `_appendBufferView`. An image
        // whose length is not a multiple of four then leaves the next
        // bufferView's byteOffset odd, and this is what catches it.
        expect(
          bufferViews[i]['byteOffset'],
          isA<int>().having((o) => o % 4, 'byteOffset % 4', 0),
          reason: 'bufferViews[$i]',
        );
      }
    });
  });

  group('accessor min/max', () {
    test(
      'POSITION carries the mesh\'s real bounds, not swapped or omitted',
      () {
        final mesh = MeshData(
          layout: VertexLayout.positionOnly,
          vertices: Float32List.fromList(<double>[
            -1, -2, -3, // a corner
            4, 5, 6, // the opposite corner
            0, 0, 0,
          ]),
          indices: Uint32List.fromList(<int>[0, 1, 2]),
        );
        final document = PlainModelDocument(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: mesh, transform: Matrix4.identity()),
          ],
        );
        final bytes = GltfWriter(document).writeGlb();
        final container = GlbContainer.parse(bytes);
        final accessors = (container.json['accessors']! as List)
            .cast<Map<String, Object?>>();
        // accessors[0] is POSITION; accessors[1] is the index accessor.
        final position = accessors.first;
        // Mutation: write `bounds.max` under the `min` key and vice versa.
        // Every component here is distinct, so a swap changes every entry.
        expect(position['min'], <double>[-1.0, -2.0, -3.0]);
        expect(position['max'], <double>[4.0, 5.0, 6.0]);
      },
    );
  });

  group('a node\'s rotation keeps glTF\'s xyzw component order', () {
    test('a quaternion with four distinct components round-trips in order', () {
      final rotation = Quaternion(0.1, 0.2, 0.3, 0.9)..normalize();
      final node = ModelNode(rotation: rotation, surfaces: const <int>[]);
      final document = PlainModelDocument(nodes: <ModelNode>[node]);
      final bytes = GltfWriter(document).writeGlb();
      final container = GlbContainer.parse(bytes);
      final written = (container.json['nodes']! as List).cast<Map>().single;
      // Mutation: write `[w, x, y, z]` instead of `[x, y, z, w]`. All four
      // components are distinct, so a reordering changes every position.
      expect(written['rotation'], <double>[
        rotation.x,
        rotation.y,
        rotation.z,
        rotation.w,
      ]);
    });
  });

  group('indices narrow to 16 bit only when the mesh actually fits', () {
    MeshData meshOf(int vertexCount) => MeshData(
      layout: VertexLayout.positionOnly,
      vertices: Float32List(vertexCount * 3),
      indices: Uint32List.fromList(<int>[0, 0, 0]),
    );

    int indicesComponentType(MeshData mesh) {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: mesh, transform: Matrix4.identity()),
        ],
      );
      final bytes = GltfWriter(document).writeGlb();
      final container = GlbContainer.parse(bytes);
      final accessors = (container.json['accessors']! as List)
          .cast<Map<String, Object?>>();
      // POSITION is accessors[0], the index accessor is whatever came after
      // it — there are no other attributes on a position-only mesh.
      return accessors[1]['componentType']! as int;
    }

    test('a small mesh writes UNSIGNED_SHORT (5123)', () {
      expect(indicesComponentType(meshOf(3)), 5123);
    });

    test('a mesh over 65536 vertices writes UNSIGNED_INT (5125)', () {
      // Mutation: always take the 16-bit branch in `_accessorsFor`. A vertex
      // index past 65535 then truncates, and this is the boundary where that
      // starts happening — `fitsIn16BitIndices` itself is `<= 0x10000`.
      expect(indicesComponentType(meshOf(0x10000 + 1)), 5125);
    });
  });

  group('a GLB the writer produces is self-contained', () {
    test(
      'no buffer names a uri; everything embeds in the binary chunk',
      () async {
        final source = await GltfLoader().load(_sample('BoxTextured.glb'));
        final bytes = GltfWriter(source).writeGlb();
        final container = GlbContainer.parse(bytes);
        expect(container.binaryChunk, isNotNull);
        final buffers = (container.json['buffers']! as List).cast<Map>();
        for (final buffer in buffers) {
          expect(buffer.containsKey('uri'), isFalse);
        }
      },
    );
  });

  group('geometry shared by several nodes is written once', () {
    test('two surfaces over one MeshData share one set of accessors', () {
      final mesh = MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]),
        indices: Uint32List.fromList(<int>[0, 1, 2]),
      );
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: mesh, transform: Matrix4.identity()),
          ModelSurface(mesh: mesh, transform: Matrix4.identity()),
        ],
        nodes: <ModelNode>[
          ModelNode(surfaces: const <int>[0]),
          ModelNode(surfaces: const <int>[1]),
        ],
      );
      final bytes = GltfWriter(document).writeGlb();
      final container = GlbContainer.parse(bytes);
      // One POSITION accessor and one index accessor, not two of each.
      expect((container.json['accessors']! as List).length, 2);
      expect((container.json['meshes']! as List).length, 2);
    });
  });
}
