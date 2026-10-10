import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'pose.dart';
import 'tape.dart';

/// Where one body was at one recorded step: what [PoseRecorder.record] is
/// handed. The vectors are copied, so a caller may pass the body's own.
final class BodyPose {
  const BodyPose(this.name, this.position, this.rotation);

  /// The body's name, stable for the run: `'runner'`, `'crate#3'`.
  final String name;
  final Vector3 position;
  final Quaternion rotation;
}

/// One recorded step: the step it was taken after, and each body's place and
/// rotation, in [PoseRecord.bodies] order — null for a body that was not
/// there at that step.
final class PoseRecordFrame {
  const PoseRecordFrame(this.step, this.bodies);

  final int step;

  /// Seven numbers a body — `x, y, z, qx, qy, qz, qw` — or null. Shorter
  /// than [PoseRecord.bodies] when bodies appeared after this frame.
  final List<Float64List?> bodies;
}

/// Where the run's bodies were, every few steps: the half of a `.f3drun` that
/// plays on any build.
///
/// **The tape replays the run; this shows it.** A tape of intents is exact
/// and small, and it means something only in the simulation that recorded it
/// (`SimulationVersion`). Positions mean the same thing on every build, so a
/// viewer — an editor, a ghost, a run page — draws these whatever the
/// simulation has become since. Nothing here is stepped or collided with;
/// the record is a picture of a run, never a run.
///
/// **Compact on purpose.** Every [every]th step rather than every step,
/// millimetres and four decimals of a quaternion rather than full doubles,
/// and a body that is not there written as one null rather than seven
/// numbers. The racing ghost's [Pose] would carry one body with a facing and
/// an up; a crate tumbling end over end has a rotation no yaw can say, so a
/// body here is a place and a quaternion, and [track] turns one of them back
/// into the ghost's [Tape] for anything already drawing ghosts.
final class PoseRecord {
  PoseRecord({
    required this.every,
    required this.stepSeconds,
    required List<String> bodies,
    required List<PoseRecordFrame> frames,
  }) : bodies = List<String>.unmodifiable(bodies),
       frames = List<PoseRecordFrame>.unmodifiable(frames);

  /// Steps between frames.
  final int every;

  /// How long a step was, so a viewer plays the record at the run's pace.
  final double stepSeconds;

  /// Every body the record names, in the order it first appeared.
  final List<String> bodies;

  /// In step order, one per recorded step.
  final List<PoseRecordFrame> frames;

  bool get isEmpty => frames.isEmpty;

  /// The step of the last frame, which is where a viewer's scrubber ends.
  int get lastStep => frames.isEmpty ? 0 : frames.last.step;

  Map<String, Object?> toJson() => <String, Object?>{
    'every': every,
    'dt': stepSeconds,
    'bodies': bodies,
    'frames': <Map<String, Object?>>[
      for (final frame in frames)
        <String, Object?>{
          's': frame.step,
          'b': <Object?>[
            for (final body in frame.bodies)
              if (body == null)
                null
              else ...<double>[
                for (var i = 0; i < 7; i++) _round(body[i], i < 3 ? 1e3 : 1e4),
              ],
          ],
        },
    ],
  };

  /// Reads what [toJson] wrote, or throws a [PoseRecordFormatException] saying where
  /// it stopped making sense.
  factory PoseRecord.fromJson(Map<String, Object?> json) {
    final every = json['every'];
    final dt = json['dt'];
    final names = json['bodies'];
    final rawFrames = json['frames'];
    if (every is! int || every < 1) {
      throw PoseRecordFormatException('the pose record is every $every steps');
    }
    if (dt is! num || dt <= 0) {
      throw PoseRecordFormatException('the pose record\'s step is $dt seconds');
    }
    if (names is! List || names.any((name) => name is! String)) {
      throw const PoseRecordFormatException('the pose record names no bodies');
    }
    if (rawFrames is! List) {
      throw const PoseRecordFormatException('the pose record has no frames');
    }
    final frames = <PoseRecordFrame>[];
    for (final raw in rawFrames) {
      if (raw is! Map<String, Object?>) {
        throw const PoseRecordFormatException('a pose frame is not a document');
      }
      final step = raw['s'];
      final values = raw['b'];
      if (step is! int || values is! List) {
        throw const PoseRecordFormatException(
          'a pose frame has no step or no bodies',
        );
      }
      if (frames.isNotEmpty && step <= frames.last.step) {
        throw PoseRecordFormatException(
          'the pose frame at step $step comes after the one at step '
          '${frames.last.step}; frames are written in step order',
        );
      }
      final bodies = <Float64List?>[];
      var at = 0;
      while (at < values.length) {
        if (values[at] == null) {
          bodies.add(null);
          at++;
          continue;
        }
        if (at + 7 > values.length) {
          throw PoseRecordFormatException(
            'the pose frame at step $step is cut short',
          );
        }
        final body = Float64List(7);
        for (var i = 0; i < 7; i++) {
          final value = values[at + i];
          if (value is! num) {
            throw PoseRecordFormatException(
              'the pose frame at step $step has $value where a number goes',
            );
          }
          body[i] = value.toDouble();
        }
        bodies.add(body);
        at += 7;
      }
      if (bodies.length > names.length) {
        throw PoseRecordFormatException(
          'the pose frame at step $step has ${bodies.length} bodies and the '
          'record names ${names.length}',
        );
      }
      frames.add(PoseRecordFrame(step, bodies));
    }
    return PoseRecord(
      every: every,
      stepSeconds: dt.toDouble(),
      bodies: names.cast<String>(),
      frames: frames,
    );
  }

  /// [body]'s path as the ghost's [Tape]: its place and, from its rotation,
  /// a facing about the vertical and an up — what [Playback] draws. Frames
  /// the body was absent from are left out. [Tape.seconds] is the record's
  /// length.
  Tape track(String body) {
    final index = bodies.indexOf(body);
    final rotation = Quaternion.identity();
    final poses = <Pose>[];
    if (index >= 0) {
      for (final frame in frames) {
        if (index >= frame.bodies.length) continue;
        final values = frame.bodies[index];
        if (values == null) continue;
        rotation.setValues(values[3], values[4], values[5], values[6]);
        // Through the matrix, not `Quaternion.rotated`: vector_math 2.4
        // turns a vector the other way round there, so a body yawed by
        // `axisAngle(up, a)` came back facing -a and its ghost ran mirrored.
        final turn = rotation.asRotationMatrix();
        final forward = turn.transformed(Vector3(0.0, 0.0, 1.0));
        final pose = Pose(
          time: frame.step * stepSeconds,
          yaw: Portable.atan2(forward.x, forward.z),
        )..position.setValues(values[0], values[1], values[2]);
        pose.up.setFrom(turn.transformed(Vector3(0.0, 1.0, 0.0)));
        poses.add(pose);
      }
    }
    return Tape(poses: poses, seconds: lastStep * stepSeconds);
  }

  static double _round(double value, double scale) =>
      (value * scale).roundToDouble() / scale;
}

/// Writes a [PoseRecord] down as a run is played: every [every]th step,
/// whichever bodies the caller hands it.
final class PoseRecorder {
  PoseRecorder({this.every = 4, this.stepSeconds = 1.0 / 60.0})
    : assert(every > 0, 'a frame every no steps is no record');

  final int every;

  /// The simulation's fixed step, in seconds.
  final double stepSeconds;

  final List<String> _bodies = <String>[];
  final Map<String, int> _index = <String, int>{};
  final List<PoseRecordFrame> _frames = <PoseRecordFrame>[];

  /// Whether [step] is one a frame is taken at, so a caller gathers its
  /// bodies only then.
  bool due(int step) =>
      step % every == 0 && (_frames.isEmpty || _frames.last.step < step);

  /// Records [bodies] as they were after [step], if [step] is [due].
  ///
  /// A body is named by [BodyPose.name]; one never seen before joins the
  /// record's list, and one missing from a later frame is written absent.
  void record(int step, Iterable<BodyPose> bodies) {
    if (!due(step)) return;
    final values = List<Float64List?>.filled(
      _bodies.length,
      null,
      growable: true,
    );
    for (final body in bodies) {
      final index = _index.putIfAbsent(body.name, () {
        _bodies.add(body.name);
        values.add(null);
        return _bodies.length - 1;
      });
      final rotation = body.rotation;
      values[index] = Float64List.fromList(<double>[
        body.position.x,
        body.position.y,
        body.position.z,
        rotation.x,
        rotation.y,
        rotation.z,
        rotation.w,
      ]);
    }
    _frames.add(PoseRecordFrame(step, values));
  }

  /// Forgets frames after [step]: a run rewound and lived again from there.
  void forgetAfter(int step) => _frames.removeWhere((f) => f.step > step);

  int get length => _frames.length;

  /// The record so far.
  PoseRecord get recorded => PoseRecord(
    every: every,
    stepSeconds: stepSeconds,
    bodies: _bodies,
    frames: _frames,
  );
}

/// Thrown when a pose record cannot be read.
final class PoseRecordFormatException extends Flutter3dFormatException {
  const PoseRecordFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'PoseRecordFormatException: $message';
}
