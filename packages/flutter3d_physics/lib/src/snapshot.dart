import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Reading a saved body back.
///
/// **Two identical eight-line copies**, one in `RigidBody` and one in
/// `CharacterController`, both reading the same two keys written by the same
/// two `save()` methods. Restoring a snapshot is one job however many kinds of
/// body have one.
///
/// What arrives here is a file from a player's disk: a save written by an older
/// build, a level document somebody edited by hand, a truncated write from a
/// machine that lost power. So it never throws. A vector it cannot read leaves
/// [out] as it was, which is the position the body already had — a body that
/// stays where it is is a bug a player can walk out of, and a `TypeError` from
/// a `as num` on a half-written array is a game that will not start.
/// Returns whether it read one, for a caller that treats "the field was there"
/// differently from "the field says where the body already is".
bool readVector(Object? value, Vector3 out) {
  if (value is! List || value.length < 3) return false;
  final x = value[0], y = value[1], z = value[2];
  // All three checked before any is written: a half-read vector is a position
  // that is partly where the body was saved and partly where it happens to be,
  // which is somewhere nobody has ever been.
  if (x is! num || y is! num || z is! num) return false;
  out.setValues(x.toDouble(), y.toDouble(), z.toDouble());
  return true;
}

/// Reading a saved orientation back, by the same rules as [readVector].
///
/// **Written as it was saved, not renormalised**, unless it is plainly not a
/// rotation. What `save()` wrote is already unit length to the precision it is
/// stored in, and normalising it again moves its last bits — which is a
/// restored run that is not the run that was saved. A hand-edited document
/// that says `[0, 0, 1, 1]` is a different matter, and is scaled to unit
/// length rather than left to stretch the body it turns. Zero length and
/// non-finite values are refused, leaving [out] as it was.
bool readQuaternion(Object? value, Quaternion out) {
  if (value is! List || value.length < 4) return false;
  final x = value[0], y = value[1], z = value[2], w = value[3];
  if (x is! num || y is! num || z is! num || w is! num) return false;
  final (qx, qy, qz, qw) = (
    x.toDouble(),
    y.toDouble(),
    z.toDouble(),
    w.toDouble(),
  );
  final length2 = qx * qx + qy * qy + qz * qz + qw * qw;
  if (!(length2 > 0.0) || !length2.isFinite) return false;
  // A single-precision unit quaternion is within a few millionths of length
  // one; anything further out was not written by `save()`.
  if ((length2 - 1.0).abs() <= 1e-5) {
    out.setValues(qx, qy, qz, qw);
  } else {
    final length = math.sqrt(length2);
    out.setValues(qx / length, qy / length, qz / length, qw / length);
  }
  return true;
}

/// A number from a snapshot, or nought.
///
/// Nought rather than a thrown error for the same reason: what these carry are
/// timers — a coyote window, a buffered jump — and starting one at nought is
/// the state a body is in the moment it lands anyway.
double readNumber(Object? value) => value is num ? value.toDouble() : 0.0;
