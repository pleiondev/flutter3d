/// The demo's morph sliders: what they move, and what they stop.
///
///     flutter test test/morph_controls_test.dart
///
/// **A control panel is the one part of a renderer with no golden**, so the two
/// things this section promises are asserted here instead. It drives every mesh
/// node of the model rather than the one whose slider was dragged — a glTF mesh
/// split across materials arrives as several nodes sharing one set of shapes,
/// and moving one alone tears the model apart along the seam between its
/// primitives. And it pauses the clip on the first drag, because a weights track
/// rewrites these every frame: a slider moved under a running clip snaps back on
/// the next tick and reads as a broken control.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_example/src/spike/control_panel.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// Two mesh nodes over one mesh with two shapes, the way one split glTF mesh
/// arrives.
({List<MeshNode> nodes, AnimationPlayer player}) _model() {
  final device = FakeBackend();
  final base = CuboidShape(size: Vector3.all(1.0)).build();
  Float32List deltas(double x) => Float32List.fromList(<double>[
    for (var v = 0; v < base.vertexCount; v++) ...<double>[x, 0.0, 0.0],
  ]);
  final source = MeshData(
    layout: base.layout,
    vertices: base.vertices,
    indices: base.indices,
    morphTargets: <MorphTarget>[
      MorphTarget(
        vertexCount: base.vertexCount,
        name: 'smile',
        positions: deltas(0.4),
      ),
      MorphTarget(vertexCount: base.vertexCount, positions: deltas(-0.4)),
    ],
  );

  final mesh = DeviceMesh.upload(device, source);
  final packed = MorphTexture.pack(source)!;
  final texture = device.createTextureFromPixels(
    width: packed.width,
    height: packed.height,
    format: TextureFormat.r32g32b32a32Float,
    pixels: packed.bytes,
  )!;

  final nodes = <MeshNode>[
    for (var i = 0; i < 2; i++)
      MeshNode(mesh, engine.Material(name: 'm$i'), name: 'part$i')
        ..morph = MorphState(texture: texture, targetCount: 2),
  ];

  final player = AnimationPlayer(
    clips: <AnimationClip>[
      AnimationClip(
        name: 'idle',
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.linear,
            componentCount: 3,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
          ),
        ],
      ),
    ],
    targets: <AnimationTarget?>[null],
  );

  return (nodes: nodes, player: player);
}

Widget _panel(({List<MeshNode> nodes, AnimationPlayer player}) model) =>
    MaterialApp(
      home: Scaffold(
        body: MorphControls(
          nodes: model.nodes,
          player: model.player,
          onChanged: () {},
        ),
      ),
    );

void main() {
  testWidgets('one slider per target, named where the file named it', (
    tester,
  ) async {
    final model = _model();
    await tester.pumpWidget(_panel(model));

    // Two shapes on two nodes: the node label appears because there is more
    // than one, and each node gets both sliders.
    expect(find.textContaining('smile'), findsNWidgets(2));
    expect(find.textContaining('Target 1'), findsNWidgets(2));
    expect(find.byType(Slider), findsNWidgets(4));
  });

  testWidgets('dragging one moves every node of the model', (tester) async {
    // Mutation: write the weight to `node` instead of looping over `nodes` —
    // the second node stays at nought and a split mesh comes apart.
    final model = _model();
    await tester.pumpWidget(_panel(model));

    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(200, 0));
    await tester.pump();

    expect(model.nodes[0].morphWeights[0], greaterThan(0.0));
    expect(
      model.nodes[1].morphWeights[0],
      model.nodes[0].morphWeights[0],
      reason: 'the second node did not follow the first',
    );
    expect(
      model.nodes[0].morphWeights[1],
      0.0,
      reason: 'the other target moved as well',
    );
  });

  testWidgets('and pauses the clip, so the track does not fight it', (
    tester,
  ) async {
    // Mutation: drop the `player?.pause()` — the assertion below fails, and in
    // the running demo the slider springs back under the ticker.
    final model = _model();
    model.player.play();
    expect(model.player.isPlaying, isTrue);

    await tester.pumpWidget(_panel(model));
    await tester.drag(find.byType(Slider).first, const Offset(200, 0));
    await tester.pump();

    expect(model.player.isPlaying, isFalse);
  });

  testWidgets('a model with one morphing node shows no node label', (
    tester,
  ) async {
    final model = _model();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MorphControls(
            nodes: <MeshNode>[model.nodes.first],
            player: null,
            onChanged: () {},
          ),
        ),
      ),
    );

    expect(find.text('part0'), findsNothing);
    expect(find.byType(Slider), findsNWidgets(2));
  });
}
