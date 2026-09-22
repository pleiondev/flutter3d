/// The walk a level starts with, in numbers.
///
///     flutter test test/level_walk_test.dart
///
/// Each of these was a line of arithmetic in the game example's `main.dart`,
/// checked by walking around; they are checked here instead.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test(
    'a spawn is lifted off the floor it was authored on, facing its way',
    () {
      final level = Level.fromJson(
        jsonDecode(File('example/assets/levels/first.json').readAsStringSync())
            as Map<String, Object?>,
      );
      final authored = level.entities.firstWhere(
        (EntityDef it) => it.type.contains('spawn'),
      );

      final spawn = LevelWalk.spawnIn(level);

      expect(spawn.at.y, closeTo(authored.position.y + 0.9, 1e-5));
      expect(spawn.at.x, closeTo(authored.position.x, 1e-5));
      expect(spawn.yaw, authored.yaw);
    },
  );

  test('forwards at yaw nought is -Z, and a quarter turn makes it -X', () {
    final walk = LevelWalk(world: CollisionWorld(), at: Vector3.zero());
    final ahead = walk.wishFor(Vector2(0.0, 1.0));
    expect(ahead.z, closeTo(-1.0, 1e-6));
    expect(ahead.x, closeTo(0.0, 1e-6));

    walk.yaw = -math.pi / 2;
    final turned = walk.wishFor(Vector2(0.0, 1.0));
    expect(turned.x, closeTo(-1.0, 1e-6));
    expect(turned.y, 0.0, reason: 'a wish stays on the ground');
  });

  test('looking up stops short of straight up', () {
    final walk = LevelWalk(world: CollisionWorld(), at: Vector3.zero())
      ..look(0.0, -1e6);
    expect(walk.pitch, LevelWalk.pitchLimit);

    walk.look(0.0, 1e6);
    expect(walk.pitch, -LevelWalk.pitchLimit);
  });

  test('the camera stands at eye height above the body', () {
    final walk = LevelWalk(
      world: CollisionWorld(),
      at: Vector3(1.0, 2.0, 3.0),
      eyeHeight: 0.5,
    );
    final camera = CameraNode();

    walk.placeCamera(camera);

    final eye = Vector3.zero();
    camera.readWorldPosition(eye);
    expect(eye.x, closeTo(1.0, 1e-5));
    expect(eye.y, closeTo(2.5, 1e-5));
    expect(eye.z, closeTo(3.0, 1e-5));
  });
}
