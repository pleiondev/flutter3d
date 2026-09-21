@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/pages/flame/flame_camera_bridge.dart';
import 'package:flutter3d_showcase/pages/flame/flame_ecs_bridge.dart';
import 'package:flutter3d_showcase/pages/flame/flame_overview.dart';
import 'package:flutter3d_showcase/pages/flame/flame_physics_bridge.dart';
import 'package:flutter3d_showcase/pages/flame/flame_transform_bridge.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/page_harness.dart';

/// Mounts [game] at 800 by 600 and steps it [frames] times, with no window:
/// what a `GameWidget` does, minus the widget.
Future<void> _run(TransparentFlameGame game, int frames) async {
  game.onGameResize(Vector2(800.0, 600.0));
  // ignore: invalid_use_of_internal_member
  await game.load();
  // ignore: invalid_use_of_internal_member
  game.mount();
  // Components load asynchronously; wait for every one, children included.
  game.update(0.0);
  await game.ready();
  game.update(0.0);
  await game.ready();
  for (var i = 0; i < frames; i++) {
    game.update(1 / 60);
  }
}

void main() {
  group('flame pages', () {
    test('the transform bridge carries each side across, live', () async {
      // Mutation: give both components the same direction and one of the
      // two cubes stays where it started.
      final FlameTransformBridgeDemo demo = FlameTransformBridgeDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        for (var i = 0; i < 60; i++) {
          run.update(1 / 60);
        }
        await _run(demo.game, 60);
        final Scene scene = run.scene;
        final SceneNode orange = scene.root.childrenView.firstWhere(
          (SceneNode n) => n.name == 'flame leads',
        );
        // The Flame side slid it: it has left the origin.
        expect(
          orange.readPosition().x.abs() + orange.readPosition().z.abs(),
          greaterThan(0.1),
        );
      } finally {
        run.dispose();
      }
    });

    test('the physics bridge lands the crate and Flame hears it', () async {
      final FlamePhysicsBridgeDemo demo = FlamePhysicsBridgeDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        await _run(demo.game, 80);
        final SceneNode crate = run.scene.root.childrenView.firstWhere(
          (SceneNode n) => n.name == 'crate',
        );
        expect(crate.readPosition().y, closeTo(0.3, 0.05));
        final SceneNode pad = run.scene.root.childrenView.firstWhere(
          (SceneNode n) => n.name == 'landing pad',
        );
        // Flame heard the landing and the pad answered by turning green.
        expect((pad as MeshNode).material.baseColor.y, greaterThan(0.5));
      } finally {
        run.dispose();
      }
    });

    test('the actors walk under the system and the bridge follows', () async {
      final FlameEcsBridgeDemo demo = FlameEcsBridgeDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        await _run(demo.game, 90);
        final SceneNode goblin = run.scene.root.childrenView.firstWhere(
          (SceneNode n) => n.name == 'goblin 0',
        );
        // Started at x = -4.5 and walked on.
        expect(goblin.readPosition().x, greaterThan(-4.4));
        expect(goblin.readPosition().y, greaterThan(0.0));
      } finally {
        run.dispose();
      }
    });

    test('the camera bridge keeps the two lenses in step', () async {
      final FlameCameraBridgeDemo demo = FlameCameraBridgeDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        await _run(demo.game, 120);
        // The lens moved and the viewfinder went with it.
        expect(demo.game.camera.viewfinder.zoom, greaterThan(1.0));
      } finally {
        run.dispose();
      }
    });

    test('the overview game steps its own square', () async {
      final FlameOverviewDemo demo = FlameOverviewDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        await _run(demo.game, 30);
      } finally {
        run.dispose();
      }
    });
  });
}
