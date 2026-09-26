/// `pro-eng-06`'s own row: a `ModelNode.lods`-carrying node builds a real,
/// working `LodGroup` when its asset is instantiated, rather than drawing
/// every level at once.
///
///     flutter test test/model_lod_instantiate_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/model_asset.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show ImpostorNode;
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ModelSurface _triangle({required double size}) => ModelSurface(
  mesh: MeshData(
    layout: VertexLayout.positionOnly,
    vertices: Float32List.fromList(<double>[
      -size,
      0,
      0,
      size,
      0,
      0,
      0,
      size,
      0,
    ]),
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  ),
  transform: Matrix4.identity(),
);

void main() {
  test(
    'a single-surface lod node instantiates as a working LodGroup',
    () async {
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
              const ModelLod(
                surfaceIndices: <int>[1],
                maxScreenFraction: 0.5,
                error: 0.02,
              ),
              const ModelLod(surfaceIndices: <int>[2], maxScreenFraction: 0.1),
            ],
          ),
        ],
      );

      final asset = await ModelAsset.fromDocument(
        document,
        device: FakeBackend(),
      );
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
      // A measured level brings its error, and an unmeasured one does not
      // invent one.
      expect(group.levels[1].error, 0.02);
      expect(group.levels[2].error, isNull);

      // The group actually ran its own constructor logic (`_apply(0)`) rather
      // than being a stand-in — the finest level is active until something
      // calls `select`.
      expect(group.activeLevel, 0);
      expect(group.levels[0].node.visible, isTrue);
      expect(group.levels[1].node.visible, isFalse);
    },
  );

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

    final asset = await ModelAsset.fromDocument(
      document,
      device: FakeBackend(),
    );
    final scene = Scene();
    final instance = asset.instantiate(scene);

    // Mutation: silently draw only the first surface when the multi-surface
    // case cannot become an LodGroup — this catches losing the second one.
    expect(instance.nodes.single.children.whereType<LodGroup>(), isEmpty);
    expect(instance.meshes, hasLength(2));
  });

  test('a chain that ends in an impostor ends in an ImpostorNode', () async {
    // `C4`. The atlases' bytes stand for PNGs; the decoder handed in answers
    // for them, so the test is about the wiring and not about decoding.
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_triangle(size: 1.0), _triangle(size: 0.5)],
      images: <EncodedImage>[
        EncodedImage(bytes: Uint8List.fromList(<int>[1]), name: 'albedo'),
        EncodedImage(bytes: Uint8List.fromList(<int>[2]), name: 'normals'),
      ],
      nodes: <ModelNode>[
        ModelNode(
          name: 'tree',
          surfaces: <int>[0],
          lods: <ModelLod>[
            const ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.3),
            ModelLod.impostor(
              maxScreenFraction: 0.05,
              impostor: ModelImpostor(
                albedoImage: 0,
                normalDepthImage: 1,
                grid: 8,
                centre: Vector3(0, 0.5, 0),
                radius: 1.2,
              ),
            ),
          ],
        ),
      ],
    );

    final asset = await ModelAsset.fromDocument(
      document,
      device: FakeBackend(),
      decodeImage: (_) async =>
          Rgba8Image(width: 8, height: 8, pixels: Uint8List(8 * 8 * 4)),
    );
    expect(asset.impostors, hasLength(1));

    final group = asset
        .instantiate(Scene())
        .nodes
        .single
        .children
        .whereType<LodGroup>()
        .single;
    // Mutation: leave the impostor level out of the chain, as before `C4` —
    // the group then ends at the simplified mesh.
    expect(group.levels, hasLength(3));
    final card = group.levels.last.node;
    expect(card, isA<ImpostorNode>());
    expect(group.levels.last.maxScreenFraction, 0.05);
    expect((card as ImpostorNode).radius, closeTo(1.2, 1e-6));
    // A second instance shares the card rather than uploading its own.
    final again = asset
        .instantiate(Scene())
        .nodes
        .single
        .children
        .whereType<LodGroup>()
        .single;
    expect(again.levels.last.node.mesh, same(card.mesh));
  });

  test('an impostor whose atlases will not decode leaves the mesh chain '
      'switching', () async {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[_triangle(size: 1.0), _triangle(size: 0.5)],
      images: <EncodedImage>[
        EncodedImage(bytes: Uint8List.fromList(<int>[1]), name: 'albedo'),
        EncodedImage(bytes: Uint8List.fromList(<int>[2]), name: 'normals'),
      ],
      nodes: <ModelNode>[
        ModelNode(
          name: 'tree',
          surfaces: <int>[0],
          lods: <ModelLod>[
            const ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.3),
            ModelLod.impostor(
              maxScreenFraction: 0.05,
              impostor: ModelImpostor(
                albedoImage: 0,
                normalDepthImage: 1,
                grid: 8,
                centre: Vector3(0, 0.5, 0),
                radius: 1.2,
              ),
            ),
          ],
        ),
      ],
    );

    final asset = await ModelAsset.fromDocument(
      document,
      device: FakeBackend(),
      decodeImage: (_) async => null,
    );
    expect(asset.impostors, isEmpty);

    // Mutation: require every level to be uploaded before building the
    // group — the node then draws its base alone and never switches.
    final group = asset
        .instantiate(Scene())
        .nodes
        .single
        .children
        .whereType<LodGroup>()
        .single;
    expect(group.levels, hasLength(2));
    expect(group.levels.last.maxScreenFraction, 0.3);
  });
}
