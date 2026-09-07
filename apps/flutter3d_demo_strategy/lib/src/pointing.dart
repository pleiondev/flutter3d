/// Where a pointer lands on the map.
///
/// **Out of `main.dart` because a widget cannot be asked a question.** Turning
/// a click into a place on the hillside is three lines of arithmetic and two
/// ways to get it wrong — the sign of the denominator, and the ray that never
/// meets the plane at all — and while it lived inside a pointer callback the
/// only way to exercise either was to open a window. Here it is a function of
/// two vectors and a height, so a test can ask it about a ray aimed upwards
/// without a device, a camera or a frame.
///
/// **The height is the camera's focus plane, not the ground under the click.**
/// The hillside is samples and the honest answer would be a walk along the ray
/// asking the heightfield at each step. This does not do that, and for the
/// order it exists to serve — *go and stand over there* — the difference does
/// not matter: the step puts everybody on the real surface the moment they
/// arrive, so an aim that is a metre out along the slope ends up in the same
/// place. Where it does matter is a rectangle drawn across a hill. Both corners
/// are projected onto one flat plane, so a rectangle whose far edge lies up a
/// slope covers less ground than it looks like it does, and the error grows
/// with the height between the plane and the slope. Nothing here compensates
/// for that, deliberately: a rectangle that guessed at heights would select a
/// different crowd depending on where the camera happened to be, which is worse
/// than one that is simply flat and says so.
library;

import 'package:vector_math/vector_math.dart';

/// Where the ray from [origin] along [direction] crosses the level plane at
/// [planeY], or null for a ray that never does.
///
/// Null rather than a far-away point for a ray aimed level or upwards: a click
/// on the sky above the horizon is a click on nothing, and answering it with
/// the place a nearly-parallel ray eventually reaches would send a crowd off
/// the edge of the map at a click nobody meant.
///
/// The answer's own height is nought rather than [planeY]. What comes back is
/// used as a goal on the map, and every reader of it — the flow field, the
/// arrangement, the fog — is asking about a place in plan, not about a height;
/// carrying the plane's height along would make two clicks at the same spot
/// from two camera distances into two different goals.
Vector3? groundUnder(
  Vector3 origin,
  Vector3 direction, {
  required double planeY,
}) {
  // Anything shallower than this is level as far as a map camera is concerned,
  // and dividing by it gives a point a kilometre away.
  if (direction.y >= -1e-4) return null;
  final double t = (planeY - origin.y) / direction.y;
  if (t < 0.0) return null;
  return Vector3(origin.x + direction.x * t, 0.0, origin.z + direction.z * t);
}
