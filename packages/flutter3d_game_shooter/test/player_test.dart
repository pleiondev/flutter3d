/// Where the player is looking, now that it is one place instead of three.
///
/// The spherical-to-cartesian aim used to be written out three times in the
/// application — for the use ray, for firing, and for the camera's look-at
/// target. None of the three had a test, and the interesting thing about that
/// is not that they were wrong: they agreed. It is that nothing would have
/// noticed if one of them had stopped agreeing.
///
/// Each test below was written by breaking the thing it covers. The mutation is
/// named in the test.
///
/// Tolerances are `1e-6` wherever a `Vector3` is involved and `1e-9` where the
/// value is a plain `double`. That is not fussiness: `vector_math` stores
/// vectors in a `Float32List`, so a component carries about seven decimal
/// digits and the first draft of this file failed five times over asking for
/// nine.
library;

import 'dart:math' as math;

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Player _pawn({double yaw = 0.0, double pitch = 0.0, double eyeOffset = 0.7}) {
  final world = CollisionWorld();
  return Player(
      body: CharacterController(world: world, position: Vector3.zero()),
      eyeOffset: eyeOffset,
    )
    ..yaw = yaw
    ..pitch = pitch;
}

void main() {
  group('pitch', () {
    test('never reaches the angle at which a camera stops having one', () {
      // The invariant the limit exists for. At exactly a right angle the
      // forward vector is parallel to world up, the cross product that builds
      // the view basis is zero, and the orientation is undefined — the picture
      // does not tilt, it stops existing.
      //
      // Mutation: drop the clamp in the setter. This fails.
      final player = _pawn();
      for (var i = 0; i < 200; i++) {
        player.look(Vector2(0.0, -1000.0)); // hard up, over and over
      }

      expect(player.pitch, lessThan(math.pi / 2.0));

      final aim = Vector3.zero();
      player.aim(aim);
      final up = Vector3(0.0, 1.0, 0.0);
      expect(
        aim.cross(up).length,
        greaterThan(1e-3),
        reason: 'the view basis is degenerate at this pitch',
      );
    });

    test('is limited downwards by the same amount', () {
      final player = _pawn();
      for (var i = 0; i < 200; i++) {
        player.look(Vector2(0.0, 1000.0));
      }
      expect(player.pitch, greaterThan(-math.pi / 2.0));
      expect(player.pitch, closeTo(-Player.pitchLimit, 1e-9));
    });

    test('is clamped when set directly, not only through look', () {
      // A caller placing the pawn from a saved game goes through the setter.
      final player = _pawn()..pitch = 40.0;
      expect(player.pitch, Player.pitchLimit);
    });
  });

  group('look', () {
    test('turns by the delta times the sensitivity', () {
      final player = _pawn()..lookSensitivity = 0.01;
      player.look(Vector2(10.0, 0.0));
      expect(player.yaw, closeTo(-0.1, 1e-9));
    });

    test('moving the pointer right turns the view right', () {
      // Sign conventions are the kind of thing that is obviously right until
      // it is inverted and everyone argues about which way is correct.
      // Forward at yaw zero is −Z; turning right must swing it towards +X.
      final player = _pawn();
      final before = Vector3.zero();
      player.forward(before);
      expect(before.x, closeTo(0.0, 1e-6));
      expect(before.z, closeTo(-1.0, 1e-6));

      player.look(Vector2(100.0, 0.0));
      final after = Vector3.zero();
      player.forward(after);
      expect(after.x, greaterThan(0.0));
    });
  });

  group('aim', () {
    test('is a unit vector at any yaw and pitch', () {
      // Mutation: forget `cosPitch` on x or z — the usual slip, and the one
      // that makes a shot travel further when you look up. The length stops
      // being one and this fails.
      final aim = Vector3.zero();
      for (final yaw in <double>[0.0, 0.7, 2.5, -1.9, 6.0]) {
        for (final pitch in <double>[0.0, 0.5, -0.5, Player.pitchLimit]) {
          _pawn(yaw: yaw, pitch: pitch).aim(aim);
          expect(
            aim.length,
            closeTo(1.0, 1e-6),
            reason: 'yaw $yaw pitch $pitch',
          );
        }
      }
    });

    test('is the ground forward when the pitch is level', () {
      final player = _pawn(yaw: 1.3);
      final aim = Vector3.zero();
      final ahead = Vector3.zero();
      player
        ..aim(aim)
        ..forward(ahead);
      expect(aim.x, closeTo(ahead.x, 1e-6));
      expect(aim.y, closeTo(0.0, 1e-6));
      expect(aim.z, closeTo(ahead.z, 1e-6));
    });

    test('looking up aims up', () {
      final aim = Vector3.zero();
      _pawn(pitch: 0.5).aim(aim);
      expect(aim.y, closeTo(math.sin(0.5), 1e-6));
    });
  });

  group('the ground basis', () {
    test('right is perpendicular to forward, and both are horizontal', () {
      final ahead = Vector3.zero();
      final side = Vector3.zero();
      for (final yaw in <double>[0.0, 0.9, -2.2, 4.4]) {
        _pawn(yaw: yaw)
          ..forward(ahead)
          ..right(side);
        expect(ahead.y, 0.0);
        expect(side.y, 0.0);
        expect(ahead.dot(side), closeTo(0.0, 1e-6), reason: 'yaw $yaw');
        expect(ahead.length, closeTo(1.0, 1e-6));
        expect(side.length, closeTo(1.0, 1e-6));
      }
    });

    test('right really is right and not left', () {
      // Both of these pass with the sign flipped, individually. Together with
      // the pointer test above they pin the handedness down.
      final side = Vector3.zero();
      _pawn().right(side);
      expect(
        side.x,
        closeTo(1.0, 1e-6),
        reason: 'facing −Z, the right hand points at +X',
      );
    });
  });

  group('moveWish', () {
    test('ignores the pitch entirely', () {
      // The claim the application made in a comment and never checked:
      // "walking forward while looking at the floor must not drive the player
      // into it — that is what a fly camera does".
      //
      // Mutation: build the wish from `aim` instead of the yaw. The y stops
      // being zero and the horizontal part shrinks by cos(pitch); this fails
      // on both counts.
      final level = Vector3.zero();
      final steep = Vector3.zero();
      _pawn(yaw: 0.8).moveWish(Vector2(0.0, 1.0), level);
      _pawn(
        yaw: 0.8,
        pitch: -Player.pitchLimit,
      ).moveWish(Vector2(0.0, 1.0), steep);

      expect(steep.y, 0.0, reason: 'looking down is not walking down');
      expect(steep.x, closeTo(level.x, 1e-6));
      expect(steep.z, closeTo(level.z, 1e-6));
    });

    test('forward is forward and strafing is sideways', () {
      final player = _pawn(yaw: 1.1);
      final ahead = Vector3.zero();
      final side = Vector3.zero();
      final wish = Vector3.zero();
      player
        ..forward(ahead)
        ..right(side);

      player.moveWish(Vector2(0.0, 1.0), wish);
      expect(wish.x, closeTo(ahead.x, 1e-6));
      expect(wish.z, closeTo(ahead.z, 1e-6));

      player.moveWish(Vector2(1.0, 0.0), wish);
      expect(wish.x, closeTo(side.x, 1e-6));
      expect(wish.z, closeTo(side.z, 1e-6));
    });

    test('half a deflection is half a wish', () {
      // Not normalised, and that is the point: an analogue stick pushed
      // halfway is a request to walk, not to run. Normalising here would make
      // every gamepad a digital one, which is the whole reason the axis is a
      // vector rather than four booleans.
      //
      // Mutation: normalise before returning. This fails.
      final wish = Vector3.zero();
      _pawn(yaw: 0.4).moveWish(Vector2(0.0, 0.5), wish);
      expect(wish.length, closeTo(0.5, 1e-6));
    });

    test('standing still wishes for nothing', () {
      final wish = Vector3.zero();
      _pawn(yaw: 2.0).moveWish(Vector2.zero(), wish);
      expect(wish.length, 0.0);
    });
  });

  group('the eye', () {
    test('sits above the body', () {
      final player = _pawn(eyeOffset: 0.7);
      final eye = Vector3.zero();
      player.eye(eye);
      expect(eye.y, closeTo(player.body.position.y + 0.7, 1e-6));
    });

    test('can be taken from a position the body is not at', () {
      // The camera reads the *interpolated* position, not the simulated one:
      // on a display faster than the step rate, several frames in a row would
      // otherwise show the same place and then jump.
      //
      // Mutation: have `eyeFrom` ignore its argument and use `body.position`.
      // This fails.
      final player = _pawn(eyeOffset: 0.7);
      final eye = Vector3.zero();
      player.eyeFrom(Vector3(3.0, 5.0, -2.0), eye);
      expect(eye.x, 3.0);
      expect(eye.y, closeTo(5.7, 1e-6));
      expect(eye.z, -2.0);
    });

    test('survives being handed its own output vector', () {
      // Which is exactly how the camera calls it: read the interpolated
      // position into a scratch vector, then raise that same vector to the eye.
      final player = _pawn(eyeOffset: 0.7);
      final both = Vector3(1.0, 2.0, 3.0);
      player.eyeFrom(both, both);
      expect(both.x, 1.0);
      expect(both.y, closeTo(2.7, 1e-6));
      expect(both.z, 3.0);
    });
  });

  group('what the pointer settings do', () {
    test('inverting the vertical axis reverses it and nothing else', () {
      // A preference and not a taste: a sizeable minority cannot play a
      // first-person game without it, and there was nowhere to ask for it —
      // the panel offered a slider for the right stick and nothing at all for
      // the mouse.
      //
      // Mutation: apply the sign to `yaw` as well. Turning left starts turning
      // right, which is not what anybody means by "invert look".
      final upright = _pawn()..look(Vector2(10.0, 10.0));
      final inverted = _pawn()
        ..invertLook = true
        ..look(Vector2(10.0, 10.0));

      expect(inverted.pitch, closeTo(-upright.pitch, 1e-9));
      expect(inverted.yaw, closeTo(upright.yaw, 1e-9));
    });

    test('and sensitivity scales both axes together', () {
      // The scale the settings panel offers is a factor either side of the
      // default, because radians per pixel is not a number anybody can set by
      // feel.
      final slow = _pawn()
        ..lookSensitivity = 0.001
        ..look(Vector2(10.0, 10.0));
      final fast = _pawn()
        ..lookSensitivity = 0.002
        ..look(Vector2(10.0, 10.0));

      expect(fast.yaw, closeTo(slow.yaw * 2.0, 1e-9));
      expect(fast.pitch, closeTo(slow.pitch * 2.0, 1e-9));
    });
  });
}
