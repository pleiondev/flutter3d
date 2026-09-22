/// `ModelNode.lods` through a `.f3d` round trip — `pro-eng-06`'s own row.
///
///     dart test test/model_lod_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelSurface _surface() => ModelSurface(
  mesh: MeshData(
    layout: VertexLayout.positionOnly,
    vertices: Float32List(3 * 3),
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  ),
  transform: Matrix4.identity(),
);

void main() {
  test('a node\'s own lods survive a round trip, surface indices and all', () {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_surface(), _surface(), _surface()],
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

    final bytes = F3dWriter(document).write();
    final reread = F3dDocument.parse(bytes);

    final lods = reread.nodes.single.lods;
    expect(lods, hasLength(2));
    expect(lods[0].surfaceIndices, <int>[1]);
    expect(lods[0].maxScreenFraction, 0.5);
    expect(lods[1].surfaceIndices, <int>[2]);
    expect(lods[1].maxScreenFraction, closeTo(0.1, 1e-6));
  });

  test('a lod naming several surfaces keeps every one, in order', () {
    // Mutation: read only the first surface index back, or drop the count.
    // A single-surface lod (the test above) cannot tell that apart from the
    // right answer.
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_surface(), _surface(), _surface()],
      nodes: <ModelNode>[
        ModelNode(
          surfaces: <int>[0],
          lods: <ModelLod>[
            const ModelLod(
              surfaceIndices: <int>[2, 1, 0],
              maxScreenFraction: 0.4,
            ),
          ],
        ),
      ],
    );

    final bytes = F3dWriter(document).write();
    final reread = F3dDocument.parse(bytes);

    expect(reread.nodes.single.lods.single.surfaceIndices, <int>[2, 1, 0]);
  });

  test('sparse: only the node that has lods reads any back', () {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_surface(), _surface()],
      nodes: <ModelNode>[
        ModelNode(surfaces: <int>[0]),
        ModelNode(
          surfaces: <int>[1],
          lods: <ModelLod>[
            const ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.2),
          ],
        ),
      ],
    );

    final bytes = F3dWriter(document).write();
    final reread = F3dDocument.parse(bytes);

    expect(reread.nodes[0].lods, isEmpty);
    expect(reread.nodes[1].lods, hasLength(1));
  });

  test('a document with no lods at all round-trips with every node empty '
      '— an old file reads exactly like one', () {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_surface()],
      nodes: <ModelNode>[
        ModelNode(surfaces: <int>[0]),
      ],
    );

    final bytes = F3dWriter(document).write();
    final reread = F3dDocument.parse(bytes);

    expect(reread.nodes.single.lods, isEmpty);
  });
}
