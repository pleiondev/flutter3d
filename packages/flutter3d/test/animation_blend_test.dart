import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Records what the player wrote, so a test can read the blended pose.
final class _Recorder implements AnimationTarget {
  final Vector3 position = Vector3.zero();
  final Quaternion rotation = Quaternion.identity();
  final Vector3 scale = Vector3.all(1.0);

  @override
  void setPosition(double x, double y, double z) => position.setValues(x, y, z);

  @override
  void setRotation(Quaternion value) => rotation.setFrom(value);

  @override
  void setScale(double x, double y, double z) => scale.setValues(x, y, z);
}

/// A clip holding one joint at a constant translation.
AnimationClip _still(String name, double x) => AnimationClip(
  name: name,
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      componentCount: 3,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(<double>[x, 0, 0, x, 0, 0]),
    ),
  ],
);

/// A clip holding one joint at a constant rotation about Y.
AnimationClip _turned(String name, double radians) {
  final q = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), radians);
  return AnimationClip(
    name: name,
    tracks: <AnimationTrack>[
      AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        componentCount: 4,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[
          q.x,
          q.y,
          q.z,
          q.w,
          q.x,
          q.y,
          q.z,
          q.w,
        ]),
      ),
    ],
  );
}

void main() {
  group('crossfading', () {
    test('the pose lands between the two clips halfway through', () {
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('a', 0.0), _still('b', 10.0)],
        targets: <AnimationTarget?>[target],
      )..play(0);
      player.apply();
      expect(target.position.x, closeTo(0.0, 1e-6));

      player.crossFadeTo(1, duration: 0.2);
      for (var i = 0; i < 6; i++) {
        player.update(1.0 / 60.0);
      }
      player.apply();

      expect(target.position.x, closeTo(5.0, 0.6));
    });

    test('and arrives fully on the new clip when it finishes', () {
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('a', 0.0), _still('b', 10.0)],
        targets: <AnimationTarget?>[target],
      )..play(0);

      player.crossFadeTo(1, duration: 0.2);
      for (var i = 0; i < 20; i++) {
        player.update(1.0 / 60.0);
      }
      player.apply();

      expect(player.isCrossFading, isFalse);
      expect(target.position.x, closeTo(10.0, 1e-6));
    });

    test('a zero duration is a cut', () {
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('a', 0.0), _still('b', 10.0)],
        targets: <AnimationTarget?>[target],
      )..play(0);

      player.crossFadeTo(1, duration: 0.0);
      player.apply();

      expect(player.isCrossFading, isFalse);
      expect(target.position.x, closeTo(10.0, 1e-6));
    });

    test('fading to the clip already playing is ignored', () {
      // A state machine asks for its current animation every step; restarting
      // it each time would freeze the pose on frame zero for ever.
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('a', 0.0), _still('b', 10.0)],
        targets: <AnimationTarget?>[_Recorder()],
      )..play(1);

      player.update(0.3);
      final before = player.time;
      player.crossFadeTo(1);

      expect(player.time, before);
      expect(player.isCrossFading, isFalse);
    });

    test('the weight runs from zero to one', () {
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('a', 0.0), _still('b', 10.0)],
        targets: <AnimationTarget?>[_Recorder()],
      )..play(0);

      player.crossFadeTo(1, duration: 0.2);
      expect(player.fadeWeight, closeTo(0.0, 1e-9));

      player.update(0.1);
      expect(player.fadeWeight, closeTo(0.5, 0.05));

      player.update(0.2);
      expect(player.fadeWeight, 1.0);
    });

    test('a second fade replaces the first rather than stacking', () {
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          _still('a', 0.0),
          _still('b', 10.0),
          _still('c', 20.0),
        ],
        targets: <AnimationTarget?>[target],
      )..play(0);

      player.crossFadeTo(1, duration: 0.2);
      player.update(0.05);
      player.crossFadeTo(2, duration: 0.2);
      for (var i = 0; i < 20; i++) {
        player.update(1.0 / 60.0);
      }
      player.apply();

      expect(target.position.x, closeTo(20.0, 1e-6));
    });

    test('a joint the old clip never touched simply takes its new value', () {
      final moved = _Recorder();
      final untouched = _Recorder();
      final wide = AnimationClip(
        name: 'wide',
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: 1,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.linear,
            componentCount: 3,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[7, 0, 0, 7, 0, 0]),
          ),
        ],
      );

      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('narrow', 0.0), wide],
        targets: <AnimationTarget?>[moved, untouched],
      )..play(0);

      player.crossFadeTo(1, duration: 0.2);
      player.update(1.0 / 60.0);
      player.apply();

      // Nothing to blend from, so it arrives at once rather than at a
      // meaningless average with zero.
      expect(untouched.position.x, closeTo(7.0, 1e-6));
    });
  });

  group('blending rotations', () {
    test('halfway between two turns is the turn between them', () {
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[_turned('a', 0.0), _turned('b', math.pi / 2)],
        targets: <AnimationTarget?>[target],
      )..play(0);

      player.crossFadeTo(1, duration: 0.2);
      player.update(0.1);
      player.apply();

      final forward = target.rotation.rotate(Vector3(0.0, 0.0, -1.0));
      final angle = math.atan2(-forward.x, -forward.z);

      expect(angle.abs(), closeTo(math.pi / 4, 0.15));
    });

    test('a wide turn takes the short way round', () {
      // The failure this exists for: a quaternion and its negation are the same
      // rotation, and blending without picking the closer of the two spins the
      // long way — which on a monster reacting to a shot is a full pirouette.
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[_turned('a', 3.0), _turned('b', -3.0)],
        targets: <AnimationTarget?>[target],
      )..play(0);

      player.crossFadeTo(1, duration: 0.2);
      player.update(0.1);
      player.apply();

      final forward = target.rotation.rotate(Vector3(0.0, 0.0, -1.0));
      final angle = math.atan2(-forward.x, -forward.z);

      // Going the short way passes through pi; the long way passes through
      // zero, which is what a naive blend produces.
      expect(angle.abs(), greaterThan(2.8));
    });

    test('blending a rotation with itself leaves it alone', () {
      final target = _Recorder();
      final player = AnimationPlayer(
        clips: <AnimationClip>[_turned('a', 1.0), _turned('b', 1.0)],
        targets: <AnimationTarget?>[target],
      )..play(0);

      // Compared against the same clip applied without a blend, so the test
      // says nothing about which way round the angle convention runs.
      player.apply();
      final unblended = target.rotation.rotate(Vector3(0.0, 0.0, -1.0));

      player.crossFadeTo(1, duration: 0.2);
      player.update(0.1);
      player.apply();
      final blended = target.rotation.rotate(Vector3(0.0, 0.0, -1.0));

      expect(blended.x, closeTo(unblended.x, 1e-5));
      expect(blended.y, closeTo(unblended.y, 1e-5));
      expect(blended.z, closeTo(unblended.z, 1e-5));
    });
  });

  group('by name', () {
    test('fades to a clip that exists', () {
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('idle', 0.0), _still('walk', 5.0)],
        targets: <AnimationTarget?>[_Recorder()],
      )..play(0);

      expect(player.crossFadeToNamed('walk'), isTrue);
      expect(player.clipIndex, 1);
    });

    test('and says so when there is none', () {
      final player = AnimationPlayer(
        clips: <AnimationClip>[_still('idle', 0.0)],
        targets: <AnimationTarget?>[_Recorder()],
      )..play(0);

      expect(player.crossFadeToNamed('somersault'), isFalse);
      expect(player.clipIndex, 0);
    });
  });
}
