
import 'package:vector_math/vector_math.dart';

import '../math/motion.dart';

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

  factory Pose.fromJson(Map<String, Object?> json) {
    final pose = Pose(
      time: (json['t']! as num).toDouble(),
      yaw: (json['y']! as num).toDouble(),
    );
    final position = json['p']! as List<Object?>;
    pose.position.setValues(
      (position[0]! as num).toDouble(),
      (position[1]! as num).toDouble(),
      (position[2]! as num).toDouble(),
    );
    final up = json['u'] as List<Object?>?;
    if (up != null) {
      pose.up.setValues(
        (up[0]! as num).toDouble(),
        (up[1]! as num).toDouble(),
        (up[2]! as num).toDouble(),
      );
    }
    return pose;
  }

  /// Three decimal places: a millimetre and a thousandth of a radian, which is
  /// far below anything a replay is looked at closely enough to show. Written
  /// out in full, a minute of it is several times the size it needs to be.
  static double _round(double value) => (value * 1000).roundToDouble() / 1000;
}

/// A recording: where something was, over and over.
///
/// **Not a replay of the simulation, and that distinction is the whole design.**
/// Playing a run back by feeding recorded input through the physics would be
/// exact, and would break the moment anything about the body was tuned — which
/// is exactly when somebody most wants to compare against their old time.
/// Positions survive tuning, survive a changed surface, and cost nothing to
/// draw.
///
/// [seconds] is what the recorded thing took, and is the reason anybody keeps
/// the tape: a lap time, a run's clock, a personal best.
final class Tape {
  const Tape({required this.poses, required this.seconds});

  final List<Pose> poses;

  final double seconds;

  bool get isEmpty => poses.isEmpty;

  /// How long the recording runs for, which is not always [seconds]: the last
  /// sample lands before the finish rather than on it.
  double get duration => poses.isEmpty ? 0.0 : poses.last.time;

  /// **A tape does not write itself down, and that is not an omission.**
  ///
  /// The obvious `toJson` here would have to choose key names, and the names
  /// that matter are already on players' disks — written by the game that had
  /// this class first, under words this package is not allowed to say. The
  /// engine's own `no_genre_test.dart` caught the attempt, and it was right to:
  /// `lapTime` is a racing word, and a document's shape belongs to whoever
  /// keeps the document.
  ///
  /// [Pose] does serialise, because a place, a facing and a time are nobody's
  /// vocabulary in particular.
}

/// Writes down where something was, a few times a second.
///
/// Fifteen a second rather than every step, and the reason is the file: what a
/// replay is looked at is a shape moving in the distance, and the difference
/// between a sample every sixtieth of a second and every fifteenth is invisible
/// once the gaps are interpolated — while the file is a quarter of the size.
final class Recorder {
  Recorder({this.hz = 15.0});

  final double hz;

  final List<Pose> _poses = <Pose>[];
  double _nextAt = 0.0;

  int get length => _poses.length;

  /// Records a place at [time], if enough time has passed since the last one.
  ///
  /// Called every step and mostly does nothing, which is the point: the caller
  /// does not have to know the rate, so changing it changes one number here
  /// rather than a condition at every call site.
  void tick(
    double time, {
    required Vector3 position,
    required double yaw,
    Vector3? up,
  }) {
    if (_poses.isNotEmpty && time < _nextAt) return;

    final pose = Pose(time: time, yaw: yaw)..position.setFrom(position);
    if (up != null) pose.up.setFrom(up);

    _poses.add(pose);
    _nextAt = time + 1.0 / hz;
  }

  /// Ends the recording and hands over what was recorded.
  Tape finish(double seconds) =>
      Tape(poses: List<Pose>.of(_poses), seconds: seconds);

  /// Throws the recording away and starts again.
  void reset() {
    _poses.clear();
    _nextAt = 0.0;
  }
}

/// Reads a recording back, smoothly.
///
/// What is played back **is not in the world**: it is not in the collision
/// world, is not stepped, and cannot be hit. A replay that could be collided
/// with would be a body from a previous run blocking the one being made, which
/// is the one thing it must never do.
final class Playback {
  Playback(this.tape);

  final Tape tape;

  /// Fills [out] with where the body was at [time].
  ///
  /// Returns false before the lap started and after it ended, which is how the
  /// caller knows not to draw anything.
  bool sampleAt(double time, Pose out) {
    final frames = tape.poses;
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
    out.yaw = a.yaw + shortestAngle(a.yaw, b.yaw) * t;
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
    final frames = tape.poses;
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


  final Vector3 _p0 = Vector3.zero();
  final Vector3 _p3 = Vector3.zero();
}
