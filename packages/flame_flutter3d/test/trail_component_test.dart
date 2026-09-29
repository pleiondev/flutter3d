/// A line drawn behind a bridged missile, gone with it.
library;

import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final class _World extends FlameGame with HasFlutter3d {}

void main() {
  test(
    'a missile lays its trail as it flies, and takes it when it goes',
    () async {
      final device = FakeBackend();
      final game = _World()..open3d(device);
      await initializeGame(() => game);
      final trail = TrailComponent(spacing: 1.0, length: 4);
      final missile = Object3dComponent(
        node: SceneNode(),
        scene: game.scene,
        plane: BridgePlane.ground(),
        direction: SyncDirection.flameToScene,
      )..add(trail);
      await game.add(missile);
      await game.ready();

      for (var i = 0; i < 10; i++) {
        missile.position.y -= 1.5;
        game.update(1 / 60);
      }
      final line = trail.line!;
      expect(line.count, 4, reason: 'a fixed length behind it');
      expect(line.points.last.z, closeTo(missile.position.y, 1.6));
      expect(game.scene.root.childrenView, contains(line));

      missile.removeFromParent();
      await game.ready();
      expect(game.scene.root.childrenView, isNot(contains(line)));
      expect(device.releasedGeometry, isNotEmpty);
    },
  );
}
