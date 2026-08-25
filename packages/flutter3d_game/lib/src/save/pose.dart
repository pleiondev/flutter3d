import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'snapshot.dart';

/// Where something was at one moment.
///
/// A place, a facing and an up. Enough to draw a body again and no more.
final class Pose {
  Pose({this.time = 0.0, this.yaw = 0.0});

  /// Seconds since the recording started.
  double time;

  final Vector3 position = Vector3.zero();

  /// Which way it was facing, about the vertical.
  double yaw;

  /// Which way was up.
  ///
  /// **Not always the world's up**, which is why it is recorded: a car on a
  /// banked corner leans with the road, and a replay that assumed vertical
  /// would stand it upright through a turn it was clearly leaning into.
  final Vector3 up = Vector3(0.0, 1.0, 0.0);

  void setFrom(Pose other) {
    time = other.time;
    yaw = other.yaw;
    position.setFrom(other.position);
    up.setFrom(other.up);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        't': _round(time),
        'p': <double>[
          _round(position.x),
          _round(position.y),
          _round(position.z),
        ],
        'y': _round(yaw),
        'u': <double>[_round(up.x), _round(up.y), _round(up.z)],
      };

  /// **Read leniently, because this is a file from somebody's disk.** Every
  /// field used to be a `!` and an `as num`, so a tape truncated by a machine
  /// that lost power threw a `TypeError` out of a load — and what is on that
  /// disk is a best run somebody spent an evening on, whose worst possible
  /// failure is being forgotten, not taking the game down with it.
  ///
  /// A pose it cannot read is a pose at the origin at time nought, which a
  /// playback either interpolates through or drops off the end of.
  factory Pose.fromJson(Map<String, Object?> json) {
    final pose = Pose(
      time: json.number('t'),
      yaw: json.number('y'),
    );
    readVector(json['p'], pose.position);
    // The up is optional: tapes written before there was one still read, which
    // matters in the direction that counts — what is on disk was written by an
    // older build.
    readVector(json['u'], pose.up);
    return pose;
  }

  /// Three decimal places: a millimetre and a thousandth of a radian, which is
  /// far below anything a replay is looked at closely enough to show. Written
  /// out in full, a minute of it is several times the size it needs to be.
  static double _round(double value) => (value * 1000).roundToDouble() / 1000;
}
