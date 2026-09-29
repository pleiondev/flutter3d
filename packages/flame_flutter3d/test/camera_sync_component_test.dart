/// A [CameraSyncComponent] advances its [CameraSyncController] once per
/// Flame update.
library;

import 'package:flame/camera.dart' show Viewfinder;
import 'package:flame/components.dart' show PositionComponent;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an update carries the authoritative side across', () {
    final camera = CameraNode()..setPosition(3.0, 0.0, 4.0);
    final viewfinder = Viewfinder();
    final component = CameraSyncComponent(
      controller: CameraSyncController(
        camera: camera,
        viewfinder: viewfinder,
        plane: BridgePlane.ground(),
      ),
      priority: 10,
    );

    component.update(1 / 60);

    expect(viewfinder.position, Vector2(3.0, 4.0));
    expect(component.priority, 10);
  });

  testWithGame<FlameGame>(
    'synced from a viewfinder that follows the player, the 3D camera is '
    'where the player is this frame',
    FlameGame.new,
    (game) async {
      // Flame's camera follows its target after everything else, and a sync
      // run before it read last frame's viewfinder.
      //
      // Mutation: give the flowing-to-the-scene sync the camera priority.
      final camera = CameraNode();
      final player = _Runner();
      await game.world.add(player);
      await game.add(
        CameraSyncComponent(
          controller: CameraSyncController(
            camera: camera,
            viewfinder: game.camera.viewfinder,
            plane: BridgePlane.ground(),
            direction: SyncDirection.flameToScene,
          ),
        ),
      );
      game.camera.follow(player);
      await game.ready();

      for (var i = 0; i < 3; i++) {
        game.update(1 / 60);
      }
      expect(camera.readPosition().x, closeTo(player.position.x, 1e-6));
    },
  );
}

final class _Runner extends PositionComponent {
  @override
  void update(double dt) {
    super.update(dt);
    position.x += 10.0;
  }
}
