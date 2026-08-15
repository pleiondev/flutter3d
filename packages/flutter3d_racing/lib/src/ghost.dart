import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'vehicle/vehicle_controller.dart';

/// Where a car was at one moment of a recorded lap.
final class GhostFrame {
  GhostFrame({this.time = 0.0, this.yaw = 0.0});

  /// Seconds since the lap started.
  double time;

  final Vector3 position = Vector3.zero();

  /// Which way the nose pointed.
  double yaw;

  /// Which way was up, so that a ghost on a banked corner leans with the road
  /// rather than standing upright through it.
  final Vector3 up = Vector3(0.0, 1.0, 0.0);

  void setFrom(GhostFrame other) {
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

  factory GhostFrame.fromJson(Map<String, Object?> json) {
    final frame = GhostFrame(
      time: (json['t']! as num).toDouble(),
      yaw: (json['y']! as num).toDouble(),
    );
    final position = json['p']! as List<Object?>;
    frame.position.setValues(
      (position[0]! as num).toDouble(),
      (position[1]! as num).toDouble(),
      (position[2]! as num).toDouble(),
    );
    final up = json['u'] as List<Object?>?;
    if (up != null) {
      frame.up.setValues(
        (up[0]! as num).toDouble(),
        (up[1]! as num).toDouble(),
        (up[2]! as num).toDouble(),
      );
    }
    return frame;
  }

  /// Three decimal places: a millimetre and a thousandth of a radian, which is
  /// far below anything a ghost is looked at closely enough to show. Written
  /// out in full, a lap is several times the size it needs to be.
  static double _round(double value) => (value * 1000).roundToDouble() / 1000;
}

/// A recorded lap.
///
/// Not a replay of the simulation — a list of where a car was. That distinction
/// is the whole design: replaying a lap by feeding recorded input back through
/// the physics would be exact, and would break the moment anything about the
/// car was tuned, which is exactly when a player most wants to compare against
/// their old time. Positions survive tuning, survive a changed track surface,
/// and cost nothing to draw.
final class GhostTape {
  const GhostTape({required this.frames, required this.lapTime});

  final List<GhostFrame> frames;

  /// What the lap took. The reason anybody keeps the tape.
  final double lapTime;

  bool get isEmpty => frames.isEmpty;

  /// How long the recording runs for.
  double get duration => frames.isEmpty ? 0.0 : frames.last.time;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'lapTime': lapTime,
        'frames': <Map<String, Object?>>[
          for (final frame in frames) frame.toJson(),
        ],
      };

  factory GhostTape.fromJson(Map<String, Object?> json) => GhostTape(
        lapTime: (json['lapTime']! as num).toDouble(),
        frames: <GhostFrame>[
          for (final frame in json['frames']! as List<Object?>)
            GhostFrame.fromJson(frame! as Map<String, Object?>),
        ],
      );
}

/// Writes down where a car was, a few times a second.
///
/// Fifteen a second rather than sixty. A ghost is a shape moving smoothly in
/// the distance, and the difference between a sample every sixty-sixth of a
/// second and every fifteenth is invisible once the gaps are interpolated —
/// while the file is a quarter of the size, which matters when a game keeps one
/// per track.
final class GhostRecorder {
  GhostRecorder({this.hz = 15.0});

  final double hz;

  final List<GhostFrame> _frames = <GhostFrame>[];
  double _nextAt = 0.0;

  int get frameCount => _frames.length;

  /// Records the car's place at [time], if enough time has passed since the
  /// last one.
  ///
  /// Called every step and mostly does nothing, which is the point: the caller
  /// does not have to know the rate, so changing it changes one number here
  /// rather than a condition at every call site.
  void tick(double time, VehicleController vehicle) {
    if (_frames.isNotEmpty && time < _nextAt) return;

    final frame = GhostFrame(time: time, yaw: vehicle.headingYaw)
      ..position.setFrom(vehicle.position);
    // The middle column of the car's basis is its own up.
    frame.up.setFrom(vehicle.visualBasis.getColumn(1));

    _frames.add(frame);
    _nextAt = time + 1.0 / hz;
  }

  /// Ends the recording and hands over what was recorded.
  GhostTape finish(double lapTime) =>
      GhostTape(frames: List<GhostFrame>.of(_frames), lapTime: lapTime);

  /// Throws the recording away and starts again. For the next lap.
  void reset() {
    _frames.clear();
    _nextAt = 0.0;
  }
}

/// Reads a recorded lap back, smoothly.
///
/// The ghost is not in the collision world, is not stepped, and cannot be hit —
/// it is drawn and nothing else. A ghost that could be collided with would be a
/// car from a previous lap blocking the one being driven, which is the one
/// thing a ghost must never do.
final class GhostPlayer {
  GhostPlayer(this.tape);

  final GhostTape tape;

  /// Fills [out] with where the car was at [time].
  ///
  /// Returns false before the lap started and after it ended, which is how the
  /// caller knows not to draw anything.
  bool sampleAt(double time, GhostFrame out) {
    final frames = tape.frames;
    if (frames.isEmpty) return false;
    if (time < frames.first.time || time > frames.last.time) return false;
    if (frames.length == 1) {
      out.setFrom(frames.first);
      return true;
    }

    final index = _segmentAt(time);
    final a = frames[index];
    final b = frames[index + 1];
    final span = b.time - a.time;
    final t = span > 1e-9 ? (time - a.time) / span : 0.0;

    // The two beyond the segment. Curved rather than straight between samples:
    // at fifteen a second and forty metres a second the samples are nearly
    // three metres apart, and joining them with straight lines gives a ghost
    // that visibly corners in facets.
    //
    // At the ends there is no neighbour, and the obvious answer — use the end
    // frame twice — is wrong in a way that shows: a doubled point halves the
    // curve's slope there, so a ghost crawls away from the start line and eases
    // to a halt at the finish, neither of which the car did. Mirroring the
    // segment instead keeps the slope, so a lap that began at speed plays back
    // beginning at speed.
    if (index > 0) {
      _p0.setFrom(frames[index - 1].position);
    } else {
      _p0
        ..setFrom(a.position)
        ..scale(2.0)
        ..sub(b.position);
    }
    if (index + 2 < frames.length) {
      _p3.setFrom(frames[index + 2].position);
    } else {
      _p3
        ..setFrom(b.position)
        ..scale(2.0)
        ..sub(a.position);
    }

    _catmullRom(_p0, a.position, b.position, _p3, t, out.position);

    // Angles take the short way round. A ghost crossing the wrap point with a
    // plain blend spins almost all the way round the wrong way, once a lap,
    // wherever the track happens to point south.
    out.yaw = a.yaw + _shortestDelta(a.yaw, b.yaw) * t;
    out.time = time;

    out.up
      ..setFrom(a.up)
      ..scale(1.0 - t)
      ..addScaled(b.up, t);
    final length = out.up.length;
    if (length > 1e-9) out.up.scale(1.0 / length);

    return true;
  }

  /// The last frame at or before [time].
  int _segmentAt(double time) {
    final frames = tape.frames;
    var low = 0;
    var high = frames.length - 2;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (frames[middle].time <= time) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  static void _catmullRom(
    Vector3 p0,
    Vector3 p1,
    Vector3 p2,
    Vector3 p3,
    double t,
    Vector3 out,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    out.setValues(
      _axis(p0.x, p1.x, p2.x, p3.x, t, t2, t3),
      _axis(p0.y, p1.y, p2.y, p3.y, t, t2, t3),
      _axis(p0.z, p1.z, p2.z, p3.z, t, t2, t3),
    );
  }

  static double _axis(
    double a,
    double b,
    double c,
    double d,
    double t,
    double t2,
    double t3,
  ) =>
      0.5 *
      ((2 * b) +
          (-a + c) * t +
          (2 * a - 5 * b + 4 * c - d) * t2 +
          (-a + 3 * b - 3 * c + d) * t3);

  static double _shortestDelta(double from, double to) {
    const twoPi = 2.0 * math.pi;
    var delta = (to - from) % twoPi;
    if (delta > math.pi) {
      delta -= twoPi;
    } else if (delta < -math.pi) {
      delta += twoPi;
    }
    return delta;
  }

  final Vector3 _p0 = Vector3.zero();
  final Vector3 _p3 = Vector3.zero();
}
