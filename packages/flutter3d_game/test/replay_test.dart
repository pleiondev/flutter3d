/// Where something was, played back smoothly.
///
///     flutter test test/replay_test.dart
///
/// This was the racing game's ghost, and nothing in it is about racing: a
/// place, a facing, an up and a time. A platformer wanting to draw a speedrun
/// beside the player wants the same four numbers.
///
/// What the racing package keeps is the vehicle it reads them off and the shape
/// of the file they are written to — the latter because the engine's own
/// `no_genre_test.dart` will not let this package say "lap", and because a
/// document belongs to whoever keeps it.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A recording of something driving in a circle, sampled at [hz].
Tape _circle({double hz = 15.0, double seconds = 4.0, double radius = 20.0}) {
  final recorder = Recorder(hz: hz);
  for (var t = 0.0; t <= seconds; t += 1.0 / 120.0) {
    final angle = t / seconds * 2 * math.pi;
    recorder.tick(
      t,
      position: Vector3(math.cos(angle) * radius, 0.0, math.sin(angle) * radius),
      yaw: angle,
    );
  }
  return recorder.finish(seconds);
}

void main() {
  group('recording', () {
    test('samples at its own rate rather than at the caller\'s', () {
      // Called every step and mostly does nothing, which is the point: the
      // caller does not have to know the rate, so changing it changes one
      // number rather than a condition at every call site.
      // Ticked 481 times, at 120 a second. What comes out is the recorder's
      // rate, not the caller's — and the exact count is a few short of
      // `seconds × hz` because a sample lands on the first tick at or after
      // each deadline rather than exactly on it.
      final tape = _circle(hz: 15.0, seconds: 4.0);

      expect(tape.poses.length, closeTo(60, 8));
      expect(tape.poses.length, lessThan(100),
          reason: 'it recorded at the rate it was called at');
    });

    test('and a finer rate makes a bigger tape', () {
      expect(_circle(hz: 30.0).poses.length,
          greaterThan(_circle(hz: 15.0).poses.length));
    });

    test('and starting again forgets what came before', () {
      final recorder = Recorder()
        ..tick(0.0, position: Vector3.zero(), yaw: 0.0)
        ..tick(1.0, position: Vector3.zero(), yaw: 0.0);
      expect(recorder.length, 2);

      recorder.reset();
      recorder.tick(0.0, position: Vector3.zero(), yaw: 0.0);

      expect(recorder.length, 1);
    });
  });

  group('playing back', () {
    test('says nothing before it started and after it ended', () {
      // Which is how a caller knows not to draw anything.
      final playback = Playback(_circle(seconds: 4.0));
      final out = Pose();

      expect(playback.sampleAt(-1.0, out), isFalse);
      expect(playback.sampleAt(99.0, out), isFalse);
      expect(playback.sampleAt(2.0, out), isTrue);
    });

    test('and follows the curve rather than cutting the corner', () {
      // **The reason this interpolates rather than joining the dots.** At
      // fifteen samples a second and forty metres a second the samples are
      // nearly three metres apart, and straight lines between them give
      // something that visibly corners in facets.
      //
      // Measured against the circle it was recorded from: a straight-line blend
      // sits inside the arc, and by a distance that is easy to state.
      const radius = 20.0;
      final playback = Playback(_circle(hz: 8.0, seconds: 4.0, radius: radius));
      final out = Pose();

      var worst = 0.0;
      for (var t = 0.5; t < 3.5; t += 0.017) {
        playback.sampleAt(t, out);
        worst = math.max(worst, (out.position.length - radius).abs());
      }

      // A chord between samples 45° apart cuts nearly 1.5 m off a 20 m circle.
      // The curve keeps it inside a couple of centimetres.
      expect(worst, lessThan(0.1),
          reason: 'the playback is cutting corners by ${worst}m');
    });

    test('and does not crawl away from the start', () {
      // **The end case, and the obvious answer is wrong in a way that shows.**
      // A curve needs a neighbour on each side; at the ends there is none, and
      // using the end sample twice halves the slope there — so a recording that
      // began at speed plays back easing away from the line, which is not what
      // happened.
      final playback = Playback(_circle(hz: 8.0, seconds: 4.0));
      final out = Pose();
      final start = Pose();

      playback.sampleAt(0.0, start);
      playback.sampleAt(0.05, out);
      final early = out.position.distanceTo(start.position);

      playback.sampleAt(2.0, start);
      playback.sampleAt(2.05, out);
      final middle = out.position.distanceTo(start.position);

      // **Twelve per cent, and the number is measured rather than chosen.**
      // Mirroring gives 1.02 of the middle's speed; doubling the end sample
      // gives 0.82, and a looser bound let that through — which is how this
      // test came to be tightened rather than trusted.
      expect(early, closeTo(middle, middle * 0.12),
          reason: 'it crawls away from the start rather than arriving at speed');
    });

    test('and turns the short way round the wrap point', () {
      // A plain blend between 3.1 and −3.1 radians turns almost the whole way
      // round the wrong way — once a lap, wherever the track happens to point
      // south, and exactly where somebody is watching.
      final tape = Tape(seconds: 1.0, poses: <Pose>[
        Pose(time: 0.0, yaw: math.pi - 0.1),
        Pose(time: 1.0, yaw: -math.pi + 0.1),
      ]);
      final out = Pose();

      Playback(tape).sampleAt(0.5, out);

      // Halfway between them the short way is the wrap point itself.
      final fromWrap = (out.yaw.abs() - math.pi).abs();
      expect(fromWrap, lessThan(0.05),
          reason: 'it went the long way round: yaw ${out.yaw}');
    });

    test('and leans with whatever was leaning', () {
      // Not always the world's up: a body on a banked corner leans with the
      // surface, and a playback that assumed vertical would stand it upright
      // through a turn it was clearly leaning into.
      final tape = Tape(seconds: 1.0, poses: <Pose>[
        Pose(time: 0.0)..up.setValues(0.0, 1.0, 0.0),
        Pose(time: 1.0)..up.setValues(1.0, 0.0, 0.0),
      ]);
      final out = Pose();

      Playback(tape).sampleAt(0.5, out);

      expect(out.up.length, closeTo(1.0, 1e-6), reason: 'the up is not a unit');
      expect(out.up.x, closeTo(out.up.y, 1e-6), reason: 'halfway is halfway');
    });
  });

  test('a pose survives being written down and read back', () {
    final pose = Pose(time: 1.25, yaw: 0.5)
      ..position.setValues(1.0, 2.0, 3.0)
      ..up.setValues(0.0, 0.7071, 0.7071);

    final copy = Pose.fromJson(pose.toJson());

    expect(copy.time, closeTo(1.25, 1e-3));
    expect(copy.position.x, closeTo(1.0, 1e-3));
    expect(copy.up.z, closeTo(0.7071, 1e-3));
  });

  test('and one written before there was an up still reads', () {
    // Forwards compatibility in the direction that matters: what is on disk was
    // written by an older build, and losing it is losing somebody's best run.
    final copy = Pose.fromJson(<String, Object?>{
      't': 0.0,
      'p': <double>[1.0, 2.0, 3.0],
      'y': 0.5,
    });

    expect(copy.up.y, 1.0);
  });

  test('and a tape truncated mid-write still reads', () {
    // **Every field here was a `!` and an `as num`.** What is on the disk is a
    // best run somebody spent an evening on, and a machine that lost power
    // halfway through writing it turned loading into a `TypeError` — the game
    // taken down by the file that was meant to be the reward.
    for (final broken in <Map<String, Object?>>[
      <String, Object?>{},
      <String, Object?>{'t': null, 'p': null, 'y': null},
      <String, Object?>{'t': 'soon', 'p': <Object?>[1.0], 'y': 0.0},
      <String, Object?>{'t': 1.0, 'p': <Object?>[1.0, null, 3.0], 'y': 0.0},
    ]) {
      final pose = Pose.fromJson(broken);

      expect(pose.time, isNotNull);
      expect(pose.position.x.isFinite, isTrue);
      expect(pose.up.y, 1.0, reason: 'the up was left broken rather than up');
    }
  });
}
