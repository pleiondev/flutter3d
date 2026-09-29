/// Flame's own hit test and conversions, through a perspective 3D camera.
library;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';

final class _Crate extends PositionComponent with TapCallbacks {
  _Crate(Vector2 at)
    : super(position: at, size: Vector2.all(1.0), anchor: Anchor.center);
}

void main() {
  final eye = CameraNode()
    ..setPosition(0.0, 6.0, 6.0)
    ..lookAt(Vector3(0.0, 0.0, -6.0));
  final plane = BridgePlane.ground();

  FlameGame projected() {
    late final FlameGame game;
    final world = World();
    game = FlameGame(
      world: world,
      camera: CameraComponent(
        world: world,
        viewfinder: ProjectedViewfinder(
          projector: BridgeProjector(camera: eye, viewSize: () => game.size),
          plane: plane,
        ),
      ),
    );
    return game;
  }

  testWithGame<FlameGame>(
    'a point on the screen is the point of the plane drawn there',
    projected,
    (game) async {
      // Mutation: map the screen through the viewfinder's affine transform.
      final crate = _Crate(Vector2(2.0, -8.0));
      await game.world.add(crate);
      await game.ready();

      final projector = BridgeProjector(camera: eye, viewSize: () => game.size);
      final screen = projector.toScreen(plane.to3d(crate.position))!;
      final back = game.camera.globalToLocal(screen);
      expect(back.x, closeTo(2.0, 1e-3));
      expect(back.y, closeTo(-8.0, 1e-3));

      expect(game.componentsAtPoint(screen), contains(crate));
      expect(
        game.camera.localToGlobal(crate.position).distanceTo(screen),
        lessThan(1e-3),
      );
    },
  );

  testWithGame<FlameGame>(
    'the sky meets no plane and hits nothing',
    () {
      late final FlameGame game;
      final world = World();
      final level = CameraNode()
        ..setPosition(0.0, 2.0, 0.0)
        ..lookAt(Vector3(0.0, 2.0, -10.0));
      game = FlameGame(
        world: world,
        camera: CameraComponent(
          world: world,
          viewfinder: ProjectedViewfinder(
            projector: BridgeProjector(
              camera: level,
              viewSize: () => game.size,
            ),
            plane: plane,
          ),
        ),
      );
      return game;
    },
    (game) async {
      final crate = _Crate(Vector2.zero());
      await game.world.add(crate);
      await game.ready();
      final sky = Vector2(game.size.x / 2, 2.0);
      expect(game.camera.globalToLocal(sky).x.isNaN, isTrue);
      expect(game.componentsAtPoint(sky), isNot(contains(crate)));
    },
  );
}
