import 'package:flutter3d_game/flutter3d_game.dart';

import 'vehicle/vehicle_controller.dart';

/// Where a car was at one moment of a recorded lap.
///
/// The engine's [Pose]. Named here because a racing game says "ghost frame"
/// and nothing is gained by making it say something else — but a place, a
/// facing and an up have nothing to do with racing, and a platformer wanting
/// to draw a speedrun beside the player wants exactly the same four numbers.
typedef GhostFrame = Pose;

/// A recorded lap.
typedef GhostTape = Tape;

/// Reads a recorded lap back, smoothly — Catmull-Rom between samples, angles
/// the short way round, and no place in the collision world. See [Playback].
typedef GhostPlayer = Playback;

/// Writes down where a car was, a few times a second.
///
/// A wrapper on [Recorder] and not a copy of one: what is here is the single
/// line that knows what a car is — where a vehicle keeps its heading, its
/// position and its own idea of up.
final class GhostRecorder {
  GhostRecorder({double hz = 15.0}) : _recorder = Recorder(hz: hz);

  final Recorder _recorder;

  int get frameCount => _recorder.length;

  /// Records the car's place at [time], if enough time has passed.
  void tick(double time, VehicleController vehicle) => _recorder.tick(
        time,
        position: vehicle.position,
        yaw: vehicle.headingYaw,
        // The middle column of the car's basis is its own up, which is what
        // makes a ghost on a banked corner lean with the road.
        up: vehicle.visualBasis.getColumn(1),
      );

  /// Ends the recording and hands over the lap.
  GhostTape finish(double lapTime) => _recorder.finish(lapTime);

  /// Throws the recording away and starts again. For the next lap.
  void reset() => _recorder.reset();
}

/// The lap a tape is, and the document it is kept as.
///
/// **The document's shape lives here rather than in the engine**, and the
/// engine's own genre test is what put it here: `lapTime` and `frames` are the
/// keys already written on players' disks, and `lap` is a word a package with
/// no idea what a race is may not say. A format is a contract with a file, and
/// the file is this game's.
extension GhostDocument on GhostTape {
  /// What the lap took. The reason anybody keeps the tape.
  double get lapTime => seconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'lapTime': seconds,
        'frames': <Map<String, Object?>>[
          for (final frame in poses) frame.toJson(),
        ],
      };
}

/// Reads a lap back from what was written.
///
/// Forwards compatibility in the one direction that matters: a player's best
/// lap is the thing they would most mind losing to a format change.
GhostTape ghostTapeFromJson(Map<String, Object?> json) => GhostTape(
      seconds: (json['lapTime']! as num).toDouble(),
      poses: <GhostFrame>[
        for (final frame in json['frames']! as List<Object?>)
          GhostFrame.fromJson(frame! as Map<String, Object?>),
      ],
    );
