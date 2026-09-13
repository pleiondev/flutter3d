/// `pro-eng-06`'s own row: a `ModelNode.lods`-carrying node builds a real,
/// working `LodGroup` when its asset is instantiated, rather than drawing
/// every level at once.
///
///     flutter test test/model_lod_instantiate_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/model_asset.dart';
import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ModelSurface _triangle({required double size}) => ModelSurface(
  mesh: MeshData(
    layout: VertexLayout.positionOnly,
    vertices: Float32List.fromList(<double>[
      -size, 0, 0,
      size, 0, 0,
      0, size, 0,
    ]),
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  ),
  transform: Matrix4.identity(),
);

void main() {
  test('a single-surface lod node instantiates as a working LodGroup', () async {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        _triangle(size: 1.0),
        _triangle(size: 0.9),
        _triangle(size: 0.8),
      ],
      nodes: <ModelNode>[
        ModelNode(
          name: 'lodded',
          surfaces: <int>[0],
          lods: <ModelLod>[
            const ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.5),
            const ModelLod(surfaceIndices: <int>[2], maxScreenFraction: 0.1),
          ],
        ),
      ],
    );

    final asset = await ModelAsset.fromDocument(document, device: FakeBackend());
    final scene = Scene();
    final instance = asset.instantiate(scene);

    final wrapper = instance.nodes.single;
    // Mutation: add the level meshes straight to `wrapper` instead of
    // wrapping them in an `LodGroup` — this still finds three mesh nodes
    // among the children, just not gathered under one `LodGroup`, so the
    // type check below is what actually distinguishes the two.
    final group = wrapper.children.whereType<LodGroup>().single;
    expect(group.levels, hasLength(3));
    // Finest (the base surface, `maxScreenFraction: 2.0`) sorts first.
    expect(group.levels.first.maxScreenFraction, 2.0);
    expect(group.levels[1].maxScreenFraction, 0.5);
    expect(group.levels[2].maxScreenFraction, 0.1);

    // The group actually ran its own constructor logic (`_apply(0)`) rather
    // than being a stand-in — the finest level is active until something
    // calls `select`.
    expect(group.activeLevel, 0);
    expect(group.levels[0].node.visible, isTrue);
    expect(group.levels[1].node.visible, isFalse);
  });

  test('a node with several surfaces at one level falls back to drawing '
      'them directly, not silently dropping any', () async {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_triangle(size: 1.0), _triangle(size: 0.9)],
      nodes: <ModelNode>[
        ModelNode(
          surfaces: <int>[0, 1],
          lods: <ModelLod>[
            const ModelLod(surfaceIndices: <int>[0, 1], maxScreenFraction: 0.5),
          ],
        ),
      ],
    );

    final asset = await ModelAsset.fromDocument(document, device: FakeBackend());
    final scene = Scene();
    final instance = asset.instantiate(scene);

    // Mutation: silently draw only the first surface when the multi-surface
    // case cannot become an LodGroup — this catches losing the second one.
    expect(instance.nodes.single.children.whereType<LodGroup>(), isEmpty);
    expect(instance.meshes, hasLength(2));
  });
}
