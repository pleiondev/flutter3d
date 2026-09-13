/// `ModelNode.lods` through a glTF round trip — `pro-eng-06`'s own row, the
/// half `model_lod_test.dart` leaves to this file: `.f3d` round-trips
/// [ModelLod] directly, but glTF's own `MSFT_lod` extension names alternate
/// *nodes*, not an alternate surface list on one node, so this is a real
/// conversion rather than the same struct written twice — see
/// `gltf_writer_scene.dart`'s and `gltf_loader_scene.dart`'s own doc
/// comments on the shape and its limits.
///
///     dart test test/gltf_lod_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelSurface _surface({double x = 0}) => ModelSurface(
  mesh: MeshData(
    layout: VertexLayout.positionOnly,
    vertices: Float32List.fromList(<double>[x, 0, 0, x, 1, 0, x, 0, 1]),
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  ),
  transform: Matrix4.identity(),
);

void main() {
  group('MSFT_lod', () {
    test('a node\'s own lods survive a glTF round trip', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface(), _surface(x: 1), _surface(x: 2)],
        nodes: <ModelNode>[
          ModelNode(
            surfaces: <int>[0],
            lods: <ModelLod>[
              const ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.5),
              const ModelLod(surfaceIndices: <int>[2], maxScreenFraction: 0.1),
            ],
          ),
        ],
      );

      final bytes = GltfWriter(document).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      // Every original node plus one real glTF node per lod level — MSFT_lod
      // names *sibling nodes*, so the two levels are two real, extra entries
      // in `nodes`, not something folded back invisibly. Only the base node
      // (index 0, this document's only root) is ever drawn on its own.
      expect(readBack.nodes, hasLength(3));
      expect(readBack.roots, <int>[0]);

      final node = readBack.nodes.first;
      expect(node.surfaces, hasLength(1));
      expect(node.lods, hasLength(2));
      expect(node.lods[0].surfaceIndices, hasLength(1));
      expect(node.lods[0].maxScreenFraction, closeTo(0.5, 1e-6));
      expect(node.lods[1].surfaceIndices, hasLength(1));
      expect(node.lods[1].maxScreenFraction, closeTo(0.1, 1e-6));
    });

    test('a lod sibling with two surfaces keeps both', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface(), _surface(x: 1), _surface(x: 2)],
        nodes: <ModelNode>[
          ModelNode(
            surfaces: <int>[0],
            lods: <ModelLod>[
              const ModelLod(
                surfaceIndices: <int>[1, 2],
                maxScreenFraction: 0.3,
              ),
            ],
          ),
        ],
      );

      final bytes = GltfWriter(document).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      expect(readBack.nodes.first.lods.single.surfaceIndices, hasLength(2));
    });

    test('a node with no lods at all round-trips with lods empty', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface()],
        nodes: <ModelNode>[
          ModelNode(surfaces: <int>[0]),
        ],
      );

      final bytes = GltfWriter(document).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      expect(readBack.nodes.single.lods, isEmpty);
    });
  });
}
