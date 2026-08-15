import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A car that goes exactly where it is told, so that a test about recording is
/// not also a test about driving.
final class ScriptedCar implements VehicleController {
  ScriptedCar()
      : collider = Collider(
          shape: CollisionSphere(0.7),
          position: Vector3.zero(),
        );

  @override
  final Collider collider;

  @override
  Vector3 get position => collider.position;

  @override
  final Vector3 velocity = Vector3.zero();

  @override
  double headingYaw = 0.0;

  @override
  Matrix3 get visualBasis => _basis;
  final Matrix3 _basis = Matrix3.identity();

  set up(Vector3 value) => _basis.setColumn(1, value);

  @override
  double get speed => velocity.length;

  @override
  double slipAngle = 0.0;

  @override
  double slipRatio = 0.0;

  @override
  bool grounded = true;

  @override
  double rpm = 0.0;

  @override
  double trackDistance = 0.0;

  @override
  void step(double dt, VehicleInput input) {}

  @override
  void placeAt(Vector3 at, double yaw, {double? trackDistance}) {
    collider.position.setFrom(at);
    headingYaw = yaw;
  }
}

void main() {
  group('recording', () {
    test('a lap is sampled at the rate asked for, not at the step rate', () {
      // Mutation: record on every call. A lap at sixty a second is four times
      // the file for a difference nobody can see on a shape in the distance.
      final car = ScriptedCar();
      final recorder = GhostRecorder(hz: 10.0);

      for (var step = 0; step < 600; step++) {
        final time = step / 60.0;
        car.position.setValues(time * 20.0, 0.0, 0.0);
        recorder.tick(time, car);
      }

      // Ten seconds at ten a second, plus the one at the start.
      expect(recorder.frameCount, closeTo(100, 2));
    });

    test('the first moment is recorded, not skipped', () {
      // Otherwise a ghost appears a fifteenth of a second after the lights,
      // which on a grid start is the whole of the interesting part.
      final car = ScriptedCar();
      final recorder = GhostRecorder();

      recorder.tick(0.0, car);

      expect(recorder.frameCount, 1);
    });

    test('a tape remembers what the lap took', () {
      final car = ScriptedCar();
      final recorder = GhostRecorder();
      recorder.tick(0.0, car);

      final tape = recorder.finish(84.5);

      expect(tape.lapTime, 84.5);
    });

    test('resetting throws the lap away', () {
      final car = ScriptedCar();
      final recorder = GhostRecorder()..tick(0.0, car);

      recorder.reset();

      expect(recorder.frameCount, 0);
    });
  });

  group('playing back', () {
    GhostTape straightLine({double hz = 10.0, double speed = 20.0}) {
      final car = ScriptedCar();
      final recorder = GhostRecorder(hz: hz);
      for (var step = 0; step <= 600; step++) {
        final time = step / 60.0;
        car.position.setValues(time * speed, 0.0, 0.0);
        recorder.tick(time, car);
      }
      return recorder.finish(10.0);
    }

    test('a recorded moment plays back as it was recorded', () {
      final player = GhostPlayer(straightLine());
      final out = GhostFrame();

      for (final frame in player.tape.frames) {
        expect(player.sampleAt(frame.time, out), isTrue);
        expect(out.position.x, closeTo(frame.position.x, 1e-6));
      }
    });

    test('between two moments the ghost is where the car was', () {
      // Mutation: return the nearest recorded frame instead of interpolating.
      // At ten a second and twenty metres a second the frames are two metres
      // apart, so the ghost would jump two metres at a time — a shape that
      // teleports rather than drives.
      final player = GhostPlayer(straightLine());
      final out = GhostFrame();

      for (var time = 0.0; time < 9.9; time += 0.017) {
        expect(player.sampleAt(time, out), isTrue);
        expect(out.position.x, closeTo(time * 20.0, 0.05));
      }
    });

    test('a corner is played back curved, not in facets', () {
      // The reason the interpolation is cubic. On a circle, straight lines
      // between samples cut inside the arc by a measurable amount; the whole
      // point of a ghost is a shape moving smoothly.
      final car = ScriptedCar();
      final recorder = GhostRecorder(hz: 6.0);
      const radius = 40.0;
      for (var step = 0; step <= 360; step++) {
        final time = step / 60.0;
        final angle = time * 0.9;
        car.position.setValues(
          radius * math.cos(angle),
          0.0,
          radius * math.sin(angle),
        );
        recorder.tick(time, car);
      }

      final player = GhostPlayer(recorder.finish(6.0));
      final out = GhostFrame();

      var worst = 0.0;
      for (var time = 0.2; time < 5.8; time += 0.01) {
        player.sampleAt(time, out);
        worst = math.max(worst, (out.position.length - radius).abs());
      }

      // Six samples a second on a forty-metre arc puts them a sixth of a radian
      // apart. Joined with straight lines the ghost would cut eleven centimetres
      // inside the arc — `R(1 - cos(theta/2))`, and visible at any distance a
      // ghost is watched from. Joined with a cubic it stays within two.
      expect(worst, lessThan(0.03));
    });

    test('the nose takes the short way round the wrap point', () {
      // Mutation: blend the angles directly. A ghost passing the point where
      // the track happens to face south would spin almost all the way round the
      // wrong way, once a lap, and only there.
      final car = ScriptedCar();
      final recorder = GhostRecorder(hz: 10.0);

      car
        ..headingYaw = 3.1
        ..position.setValues(0.0, 0.0, 0.0);
      recorder.tick(0.0, car);
      car.headingYaw = -3.1;
      recorder.tick(0.1, car);

      final player = GhostPlayer(recorder.finish(1.0));
      final out = GhostFrame();
      player.sampleAt(0.05, out);

      // The short way passes through pi, not through zero.
      expect((out.yaw.abs() - math.pi).abs(), lessThan(0.05));
    });

    test('the ghost is not there before it started or after it ended', () {
      final player = GhostPlayer(straightLine());
      final out = GhostFrame();

      expect(player.sampleAt(-0.5, out), isFalse);
      expect(player.sampleAt(player.tape.duration + 0.5, out), isFalse);
    });

    test('an empty tape draws nothing rather than throwing', () {
      final player = GhostPlayer(const GhostTape(frames: [], lapTime: 0.0));

      expect(player.sampleAt(0.0, GhostFrame()), isFalse);
    });

    test('the ghost leans with the road it was recorded on', () {
      final car = ScriptedCar()..up = Vector3(0.2, 0.98, 0.0).normalized();
      final recorder = GhostRecorder()..tick(0.0, car);
      car.position.setValues(10.0, 0.0, 0.0);
      recorder.tick(1.0, car);

      final out = GhostFrame();
      GhostPlayer(recorder.finish(1.0)).sampleAt(0.5, out);

      expect(out.up.y, lessThan(1.0));
      expect(out.up.length, closeTo(1.0, 1e-6));
    });
  });

  group('keeping a lap', () {
    test('a tape survives being written out and read back', () {
      final car = ScriptedCar();
      final recorder = GhostRecorder(hz: 10.0);
      for (var step = 0; step <= 300; step++) {
        final time = step / 60.0;
        car
          ..headingYaw = time * 0.3
          ..position.setValues(time * 20.0, time * 0.5, time * 3.0);
        recorder.tick(time, car);
      }
      final tape = recorder.finish(5.0);

      final copy = GhostTape.fromJson(
        jsonDecode(jsonEncode(tape.toJson())) as Map<String, Object?>,
      );

      expect(copy.lapTime, tape.lapTime);
      expect(copy.frames.length, tape.frames.length);
      for (var i = 0; i < copy.frames.length; i++) {
        // Written to the millimetre, which is far below what a shape in the
        // distance shows and several times smaller a file.
        expect(copy.frames[i].position.x,
            closeTo(tape.frames[i].position.x, 0.001));
        expect(copy.frames[i].yaw, closeTo(tape.frames[i].yaw, 0.001));
        expect(copy.frames[i].time, closeTo(tape.frames[i].time, 0.001));
      }
    });

    test('a tape written by an older build without camber still reads', () {
      // Forwards compatibility in the one direction that matters: a player's
      // best lap is the thing they would most mind losing to a format change.
      final copy = GhostTape.fromJson(<String, Object?>{
        'version': 1,
        'lapTime': 40.0,
        'frames': <Map<String, Object?>>[
          <String, Object?>{
            't': 0.0,
            'p': <double>[1.0, 2.0, 3.0],
            'y': 0.5,
          },
        ],
      });

      expect(copy.frames.single.up.y, 1.0);
    });
  });
}
