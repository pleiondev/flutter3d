/// The one place a Flame `Vector2` and a flutter3d `Vector3` are the same
/// point, stated instead of assumed.
///
/// **Why this exists at all.** Every bridged transform — a Flame component's
/// position, a rigid body's, an actor's — has to cross from Flame's flat
/// world into flutter3d's spatial one and back, and there are exactly two
/// honest ways to do that: pick an axis convention once, in one class every
/// bridge shares, or let each bridge invent its own and drift. This is the
/// first. A side-scroller wants Flame's Y to become flutter3d's own Y (depth
/// on Z); a top-down game wants Flame's Y to become flutter3d's Z (a ground
/// plane at a fixed height). Both are [BridgePlane]s; neither is hardcoded
/// into a component.
///
/// **One `Vector2`, not two.** Flame re-exports `package:vector_math`'s own
/// `Vector2` rather than defining its own (`package:flame/src/extensions/
/// vector2.dart`), so a point crossing this bridge is never copied between
/// two unrelated classes — only ever reshaped between two and three
/// components.
///
/// **Named `BridgePlane`, not `Plane`.** `package:vector_math` already
/// exports a geometric `Plane` (a half-space for frustum/collision tests),
/// and this package depends on it transitively through flutter3d itself —
/// the collision would be silent until a caller's own import order broke,
/// which is worse than a name one character longer.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show Portable;
import 'package:vector_math/vector_math.dart';

/// Which flutter3d axis a [BridgePlane] holds constant.
enum PlaneAxis {
  /// A ground plane: Y is constant, Flame's `y` becomes flutter3d's Z.
  y,

  /// A backdrop: Z is constant, Flame's `y` becomes flutter3d's Y.
  z,
}

/// Maps a Flame [Vector2] to and from a flutter3d [Vector3], and a Flame
/// rotation angle to and from a flutter3d [Quaternion].
///
/// A plane is defined by which flutter3d axis stays fixed at [constant] —
/// [PlaneAxis.y] for a ground plane's height, [PlaneAxis.z] for a backdrop's
/// depth — and Flame's `x`/`y` become whichever two flutter3d axes are left.
final class BridgePlane {
  const BridgePlane({
    required this.axis,
    required this.constant,
    this.flipY = false,
  });

  /// A ground plane at [height]: Flame `(x, y)` becomes flutter3d
  /// `(x, height, y)`, and rotation is about the world Y axis — the
  /// convention every existing flutter3d floor/camera demo already assumes
  /// (`OrbitController`, every showcase page with a floor).
  factory BridgePlane.ground({double height = 0.0}) =>
      BridgePlane(axis: PlaneAxis.y, constant: height);

  /// A vertical backdrop at [depth]: Flame `(x, y)` becomes flutter3d
  /// `(x, y, depth)` — a side-scroller's own plane, Z held fixed instead of
  /// Y. Flame's `y` grows downward on screen and flutter3d's grows upward,
  /// so this flips it by default; pass `flipY: false` to keep the two
  /// aligned literally instead of visually.
  factory BridgePlane.backdrop({double depth = 0.0, bool flipY = true}) =>
      BridgePlane(axis: PlaneAxis.z, constant: depth, flipY: flipY);

  /// Which flutter3d axis stays fixed at [constant].
  final PlaneAxis axis;

  /// The flutter3d coordinate held constant across the whole plane.
  final double constant;

  /// Negates Flame's `y` before it becomes a flutter3d coordinate. See
  /// [BridgePlane.backdrop] for why a vertical plane defaults this on.
  final bool flipY;

  /// [flat] as a point in flutter3d space, at this plane's own [constant]
  /// unless [at] names a different one — a jump's own height above a
  /// ground plane, say.
  Vector3 to3d(Vector2 flat, {double? at}) {
    final double y = flipY ? -flat.y : flat.y;
    final double held = at ?? constant;
    return switch (axis) {
      PlaneAxis.y => Vector3(flat.x, held, y),
      PlaneAxis.z => Vector3(flat.x, y, held),
    };
  }

  /// [point]'s coordinates on this plane, dropping the constant axis.
  Vector2 to2d(Vector3 point) {
    final Vector2 flat = switch (axis) {
      PlaneAxis.y => Vector2(point.x, point.z),
      PlaneAxis.z => Vector2(point.x, point.y),
    };
    return flipY ? Vector2(flat.x, -flat.y) : flat;
  }

  /// The axis a rotation around this plane's normal turns about — world Y
  /// for a ground plane, world Z for a backdrop.
  Vector3 get normal => switch (axis) {
    PlaneAxis.y => Vector3(0.0, 1.0, 0.0),
    PlaneAxis.z => Vector3(0.0, 0.0, 1.0),
  };

  /// A flutter3d rotation turning [angle] radians about this plane's normal,
  /// Flame's own sense of positive (clockwise on screen).
  ///
  /// **Negated before it reaches `axisAngle`.** `vector_math`'s
  /// `Quaternion.axisAngle(axis, θ).rotated(v)` measurably turns a vector by
  /// the *standard* right-hand rotation of `-θ`, not `θ` — checked directly
  /// against `Quaternion.axisAngle(Vector3(0,0,1), -1.2).rotated(…)`, which
  /// lands where a right-hand rotation of `+1.2` would. Negating here is
  /// what lets [angleFor] read a rotation back with the ordinary right-hand
  /// formulas, rather than every caller of this class needing to know the
  /// library's own construction convention.
  Quaternion rotationFor(double angle) {
    final double signed = flipY ? angle : -angle;
    return Quaternion.axisAngle(normal, -signed);
  }

  /// The scalar angle [rotation] turns about this plane's normal, inverting
  /// [rotationFor] for the component that carries angle the other way.
  ///
  /// Read off by turning the plane's own zero direction — flutter3d's world
  /// +X — by [rotation] and measuring where it landed, with the ordinary
  /// right-hand rotation formula for whichever axis is [normal]
  /// (`atan2(y, x)` about Z, `atan2(-z, x)` about Y). A rotation with any
  /// component off this plane's normal has no single answer here; this
  /// reports only the turn around the normal, which is the whole of what a
  /// `double angle` can hold.
  double angleFor(Quaternion rotation) {
    final Vector3 turned = rotation.rotated(Vector3(1.0, 0.0, 0.0));
    final double sinComponent = switch (axis) {
      PlaneAxis.y => -turned.z,
      PlaneAxis.z => turned.y,
    };
    // `Portable.atan2`, not `dart:math`'s: this can run inside a bridged
    // game's own deterministic step (a synced actor's rotation read back for
    // gameplay logic), and the platform's own libm disagrees with itself in
    // the last few bits between the Dart VM and a browser — `portable_math`
    // exists in `flutter3d_sim` for exactly this reason.
    final double measured = Portable.atan2(sinComponent, turned.x);
    return flipY ? measured : -measured;
  }
}
