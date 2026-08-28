import 'package:vector_math/vector_math.dart';

import '../math/motion.dart';
import '../math/tolerances.dart';
import 'pose.dart';
import 'tape.dart';

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
    final t = span > Tolerance.divisor ? (time - a.time) / span : 0.0;

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
    if (length > Tolerance.divisor) out.up.scale(1.0 / length);

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
