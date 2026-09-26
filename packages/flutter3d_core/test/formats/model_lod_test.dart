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

  group('a level\'s measured error', () {
    /// The section kinds a file's directory lists.
    List<int> sectionKinds(Uint8List bytes) {
      final view = ByteData.sublistView(bytes);
      final count = view.getUint32(8, Endian.little);
      return <int>[
        for (var i = 0; i < count; i++)
          view.getUint32(
            kF3dHeaderBytes + i * kF3dSectionEntryBytes,
            Endian.little,
          ),
      ];
    }

    test('survives a round trip across nodes, a missing one staying '
        'missing', () {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[for (var i = 0; i < 5; i++) _surface()],
        nodes: <ModelNode>[
          ModelNode(
            surfaces: <int>[0],
            lods: <ModelLod>[
              const ModelLod(
                surfaceIndices: <int>[1],
                maxScreenFraction: 0.5,
                error: 0.0125,
              ),
              const ModelLod(surfaceIndices: <int>[2], maxScreenFraction: 0.1),
            ],
          ),
          ModelNode(
            surfaces: <int>[3],
            lods: <ModelLod>[
              const ModelLod(
                surfaceIndices: <int>[4],
                maxScreenFraction: 0.3,
                error: 0.0,
              ),
            ],
          ),
        ],
      );

      final bytes = F3dWriter(document).write();
      expect(sectionKinds(bytes), contains(F3dSection.lodErrors));
      final reread = F3dDocument.parse(bytes);

      expect(reread.nodes[0].lods[0].error, closeTo(0.0125, 1e-7));
      expect(reread.nodes[0].lods[1].error, isNull);
      // Zero is a measurement — a level that did not move — not an absence.
      expect(reread.nodes[1].lods.single.error, 0.0);
    });

    test('a file with no measured level has no section for it, and reads '
        'every level as unmeasured — the file every earlier writer made', () {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface(), _surface()],
        nodes: <ModelNode>[
          ModelNode(
            surfaces: <int>[0],
            lods: <ModelLod>[
              const ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.5),
            ],
          ),
        ],
      );

      final bytes = F3dWriter(document).write();
      expect(sectionKinds(bytes), isNot(contains(F3dSection.lodErrors)));
      final lod = F3dDocument.parse(bytes).nodes.single.lods.single;
      expect(lod.error, isNull);
      expect(lod.maxScreenFraction, 0.5);
    });

    test('a reader that does not know the section still reads the levels', () {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface(), _surface()],
        nodes: <ModelNode>[
          ModelNode(
            surfaces: <int>[0],
            lods: <ModelLod>[
              const ModelLod(
                surfaceIndices: <int>[1],
                maxScreenFraction: 0.5,
                error: 0.25,
              ),
            ],
          ),
        ],
      );
      final bytes = F3dWriter(document).write();
      // Renumber the section to a kind nobody knows, which is what it looks
      // like to a build from before it existed.
      final view = ByteData.sublistView(bytes);
      final kinds = sectionKinds(bytes);
      view.setUint32(
        kF3dHeaderBytes +
            kinds.indexOf(F3dSection.lodErrors) * kF3dSectionEntryBytes,
        0xFFFF,
        Endian.little,
      );

      final lod = F3dDocument.parse(bytes).nodes.single.lods.single;
      expect(lod.surfaceIndices, <int>[1]);
      expect(lod.maxScreenFraction, 0.5);
      expect(lod.error, isNull);
    });
  });
}
