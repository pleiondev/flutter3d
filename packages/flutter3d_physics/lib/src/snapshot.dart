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
void readVector(Object? value, Vector3 out) {
  if (value is! List || value.length < 3) return;
  final x = value[0], y = value[1], z = value[2];
  // All three checked before any is written: a half-read vector is a position
  // that is partly where the body was saved and partly where it happens to be,
  // which is somewhere nobody has ever been.
  if (x is! num || y is! num || z is! num) return;
  out.setValues(x.toDouble(), y.toDouble(), z.toDouble());
}

/// A number from a snapshot, or nought.
///
/// Nought rather than a thrown error for the same reason: what these carry are
/// timers — a coyote window, a buffered jump — and starting one at nought is
/// the state a body is in the moment it lands anyway.
double readNumber(Object? value) => value is num ? value.toDouble() : 0.0;
