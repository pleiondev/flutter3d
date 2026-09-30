@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'package:flame/components.dart' show Vector2;
import 'package:flame/game.dart' show FlameGame;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyUpEvent,
        LogicalKeyboardKey,
        PhysicalKeyboardKey;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_showcase/pages/flame/flame_camera_bridge.dart';
import 'package:flutter3d_showcase/pages/flame/flame_ecs_bridge.dart';
import 'package:flutter3d_showcase/pages/flame/flame_horde.dart';
import 'package:flutter3d_showcase/pages/flame/flame_level_scene.dart';
import 'package:flutter3d_showcase/pages/flame/flame_overview.dart';
import 'package:flutter3d_showcase/pages/flame/flame_physics_bridge.dart';
import 'package:flutter3d_showcase/pages/flame/flame_seats.dart';
import 'package:flutter3d_showcase/pages/flame/flame_transform_bridge.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../support/page_harness.dart';

/// Mounts [game] at 800 by 600 and steps it [frames] times, with no window:
/// what a `GameWidget` does, minus the widget.
Future<void> _run(FlameGame game, int frames) async {
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

/// A key going down or up on the keyboard itself, where `listenToKeyboard`
/// hears it, with nothing holding the focus.
void _key(
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical,
  bool down,
) => HardwareKeyboard.instance.handleKeyEvent(
  down
      ? KeyDownEvent(
          physicalKey: physical,
          logicalKey: logical,
          timeStamp: Duration.zero,
        )
      : KeyUpEvent(
          physicalKey: physical,
          logicalKey: logical,
          timeStamp: Duration.zero,
        ),
);

/// Steps [game] one frame at a time: a key pressed between two of them is
/// read in the next.
void _frames(FlameGame game, int frames) {
  for (var i = 0; i < frames; i++) {
    game.update(1 / 60);
  }
}

void main() {
  // `HardwareKeyboard` and the input step's lifecycle listener both need a
  // binding, and a plain `test()` never makes one.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('flame pages', () {
    test('a layout joins on its own key, in the order it pressed', () async {
      // Mutation: seat the free layouts in the order they are listed rather
      // than on their own key, and WASD is player one with no press at all.
      final FlameSeatsDemo demo = FlameSeatsDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        await _run(demo.game, 5);
        final FlameInputBridge wasd = demo.seats.candidates[0];
        final FlameInputBridge arrows = demo.seats.candidates[1];
        expect(demo.seats.seated, isEmpty);
        expect(demo.markers.every((MeshNode m) => !m.visible), isTrue);

        // The second layout presses first, through the keyboard alone.
        _key(LogicalKeyboardKey.slash, PhysicalKeyboardKey.slash, true);
        _frames(demo.game, 1);
        _key(LogicalKeyboardKey.slash, PhysicalKeyboardKey.slash, false);
        expect(demo.seats.seated, <FlameInputBridge>[arrows]);
        expect(demo.markers[1].visible, isTrue);
        expect(demo.markers[0].visible, isFalse);

        // Held, the join key seats nobody else on later frames.
        _frames(demo.game, 5);
        expect(demo.seats.seated, hasLength(1));

        _key(LogicalKeyboardKey.space, PhysicalKeyboardKey.space, true);
        _frames(demo.game, 1);
        _key(LogicalKeyboardKey.space, PhysicalKeyboardKey.space, false);
        expect(demo.seats.seated, <FlameInputBridge>[arrows, wasd]);
        // Player one wears the first seat's colour, whichever layout it is.
        expect(demo.markers[1].material.baseColor.x, greaterThan(0.9));
        expect(demo.markers[0].material.baseColor.z, greaterThan(0.9));

        // A seated player walks with its own keys, and only its marker goes.
        final double arrowsX = demo.markers[1].readPosition().x;
        final double wasdX = demo.markers[0].readPosition().x;
        _key(
          LogicalKeyboardKey.arrowRight,
          PhysicalKeyboardKey.arrowRight,
          true,
        );
        _frames(demo.game, 30);
        _key(
          LogicalKeyboardKey.arrowRight,
          PhysicalKeyboardKey.arrowRight,
          false,
        );
        expect(demo.markers[1].readPosition().x, greaterThan(arrowsX + 1.0));
        expect(demo.markers[0].readPosition().x, wasdX);
      } finally {
        run.dispose();
      }
    });

    test('the horde is one batch, split between the two players', () async {
      // Mutation: step the system towards the first player alone, and no
      // monster ever goes for the second.
      final FlameHordeDemo demo = FlameHordeDemo();
      final DemoRun run = await DemoRun.start(cpuDevice(), demo);
      try {
        double nearest() {
          final List<Vector3> players = demo.players;
          return demo.monsters
                  .map(
                    (m) => players
                        .map((Vector3 p) => (p..y = m.at.y).distanceTo(m.at))
                        .reduce((double a, double b) => a < b ? a : b),
                  )
                  .reduce((double a, double b) => a + b) /
              demo.monsters.length;
        }

        await _run(demo.game, 1);
        final double before = nearest();
        _frames(demo.game, 90);

        // Every monster is a slot of the one batch.
        expect(demo.batch.count, demo.monsters.length);
        expect(demo.monsters, hasLength(96));
        // Both players are chased, each by some of the horde.
        final Iterable<int> attended = demo.monsters.map((m) => m.attended);
        expect(attended.where((int i) => i == 0), isNotEmpty);
        expect(attended.where((int i) => i == 1), isNotEmpty);
        // And the horde closed in on whichever was nearer.
        expect(nearest(), lessThan(before - 2.0));
        // The slot draws the body, not somewhere of its own.
        final Matrix4 placed = Matrix4.zero();
        demo.batch.readTransform(0, placed);
        final Vector3 drawn = placed.getTranslation();
        final Iterable<double> gaps = demo.monsters.map(
          (m) => Vector3(m.at.x - drawn.x, 0.0, m.at.z - drawn.z).length,
        );
        expect(
          gaps.reduce((double a, double b) => a < b ? a : b),
          lessThan(0.2),
        );
      } finally {
        run.dispose();
      }
    });

    test(
      'the level moves to its next scene and the camera finds the party',
      () async {
        // Mutation: leave out `replaceScene3d`, and the second level is never
        // the one drawn.
        final FlameLevelSceneDemo demo = FlameLevelSceneDemo();
        final DemoRun run = await DemoRun.start(cpuDevice(), demo);
        try {
          await _run(demo.game, 90);
          expect(demo.level, same(demo.levels[0]));
          // The camera keeps up with the party as it walks the first level.
          expect(
            demo.camera.readPosition().distanceTo(demo.wantedEye),
            lessThan(2.0),
          );

          // Past six seconds: the second level, with the camera and the party.
          _frames(demo.game, 6 * 60 - 90 + 2);
          expect(demo.level, same(demo.levels[1]));
          expect(demo.levels[1].cameras, contains(demo.camera));
          expect(demo.levels[0].cameras, isNot(contains(demo.camera)));
          expect(
            demo.party.every((MeshNode m) => demo.levels[1].meshes.contains(m)),
            isTrue,
          );
          // The party starts the new level elsewhere; the camera eases after.
          final double moved = demo.camera.readPosition().distanceTo(
            demo.wantedEye,
          );
          expect(moved, greaterThan(5.0));
          _frames(demo.game, 90);
          expect(
            demo.camera.readPosition().distanceTo(demo.wantedEye),
            lessThan(moved / 2.0),
          );
        } finally {
          run.dispose();
        }
      },
    );

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
