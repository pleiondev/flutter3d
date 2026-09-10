import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'camera_node.dart';
import 'projection.dart';
import 'scene_node.dart';

/// Turntable controls: orbit a node around a target point.
///
/// Drives a [SceneNode] rather than a camera, so the same controller can swing a
/// light or a probe around a model. That separation is why Babylon's
/// ArcRotateCamera behaviour is worth decomposing instead of copying: the orbit
/// is a placement policy, not a property of a lens.
///
/// Holds no Flutter types; the gesture bridge lives in the app layer.
final class OrbitController {
  OrbitController(
    this.node, {
    Vector3? target,
    this.distance = 3.0,
    this.yaw = 0.0,
    this.pitch = 0.35,
    this.minDistance = 0.05,
    this.maxDistance = 1e5,
    this.framingFov = math.pi / 4,
  }) : target = target ?? Vector3.zero(),
       orthoHeight = 2.0 * distance * math.tan(framingFov * 0.5) {
    apply();
  }

  SceneNode node;

  /// Point being orbited, in world space.
  final Vector3 target;

  double distance;

  /// Rotation about the world Y axis.
  double yaw;

  /// Elevation. Clamped just short of the poles, because looking straight down
  /// makes the up vector ambiguous and the view snaps.
  double pitch;

  double minDistance;
  double maxDistance;

  /// The vertical angle the two lenses are kept in step through.
  ///
  /// A perspective camera shows a target-height of `2·distance·tan(fov/2)`, and
  /// [orthoHeight] is held at that same value — so switching a viewport from
  /// one lens to the other leaves the model the size it already was, which is
  /// the whole point of having both.
  final double framingFov;

  /// The world height an orthographic lens shows, in the units the scene is in.
  ///
  /// **Its own number rather than derived from [distance] when it is asked
  /// for.** An orthographic picture does not depend on where along the view
  /// axis the camera stands, and it must not: a caller that walks the camera
  /// back to clear some geometry off the near plane would otherwise find the
  /// model had shrunk. So [zoom] moves both this and [distance] together, and
  /// nothing else does.
  double orthoHeight;

  static const double _kMaxPitch = math.pi / 2 - 0.01;

  /// Radians per pixel of drag.
  double rotateSensitivity = 0.008;

  void rotate(double deltaYaw, double deltaPitch) {
    // A hand on the mouse outranks a turn that is still playing: an animation
    // that kept running would drag the view out from under the drag.
    _turnLength = 0.0;
    yaw -= deltaYaw * rotateSensitivity;
    pitch = (pitch + deltaPitch * rotateSensitivity).clamp(
      -_kMaxPitch,
      _kMaxPitch,
    );
    apply();
  }

  /// Multiplicative zoom: [factor] below 1 moves closer.
  ///
  /// Multiplicative rather than additive so a step feels the same whether the
  /// camera is a centimetre or a kilometre out.
  void zoom(double factor) {
    final before = distance;
    distance = (distance * factor).clamp(minDistance, maxDistance);
    // By what the distance actually moved rather than by [factor], so that a
    // wheel spun into the near clamp stops making the orthographic picture
    // larger — otherwise the two lenses come out of step by exactly the amount
    // the clamp refused, and a viewport switched to orthographic afterwards
    // shows a model of the wrong size.
    orthoHeight *= before == 0.0 ? 1.0 : distance / before;
    apply();
  }

  /// Slides the target across the view plane, in pixels.
  ///
  /// Scaled by distance so a drag moves the same apparent amount regardless of
  /// how far out the camera is.
  void pan(double deltaX, double deltaY, {double viewportHeight = 600.0}) {
    final scale = distance / math.max(viewportHeight, 1.0) * 2.0;
    final right = Vector3(math.cos(yaw), 0.0, -math.sin(yaw));
    final up = _upVector();
    target
      ..addScaled(right, -deltaX * scale)
      ..addScaled(up, deltaY * scale);
    apply();
  }

  /// Places the camera so [bounds] fills the view.
  ///
  /// Uses the bounding sphere rather than the box so the framing holds at any
  /// orbit angle instead of only the one it was computed at.
  void frameBounds(
    Aabb3 bounds, {
    double fovYRadians = math.pi / 4,
    double margin = 1.25,
  }) {
    target
      ..setFrom(bounds.min)
      ..add(bounds.max)
      ..scale(0.5);

    final extent = (bounds.max - bounds.min)..scale(0.5);
    final radius = math.max(extent.length, 1e-4);
    distance = (radius / math.sin(fovYRadians * 0.5) * margin).clamp(
      minDistance,
      maxDistance,
    );
    // What the perspective camera that was just placed shows at the target's
    // own depth, rather than the sphere's diameter — which would be the tighter
    // framing and the wrong one. A sphere fitted tangentially into a frustum
    // leaves the frustum wider than the sphere by the time it reaches the
    // middle, so matching the diameter would frame the model eight per cent
    // larger in one lens than the other, and switching between them would make
    // it jump.
    orthoHeight = 2.0 * distance * math.tan(fovYRadians * 0.5);
    apply();
  }

  /// Sensible near and far planes for the current framing.
  ///
  /// A fixed 0.1..1000 range wastes most of the depth buffer on empty space and
  /// z-fights on small models; tying the range to the orbit distance keeps
  /// precision where the geometry actually is.
  ({double near, double far}) suggestedDepthRange() {
    final near = math.max(distance * 0.01, 1e-4);
    // 10x the orbit distance covers the far side of anything frameBounds framed,
    // with room to zoom in. A larger multiplier only spends depth precision on
    // empty space, which is the very thing this method exists to avoid.
    final far = distance * 10.0 + 10.0;
    return (near: near, far: far);
  }

  Vector3 _upVector() {
    // The up direction of the orbit frame, tilted by pitch.
    final sinYaw = math.sin(yaw);
    final cosYaw = math.cos(yaw);
    final sinPitch = math.sin(pitch);
    final cosPitch = math.cos(pitch);
    return Vector3(-sinYaw * sinPitch, cosPitch, -cosYaw * sinPitch)
      ..normalize();
  }

  /// Writes the orbit state into the node's transform.
  void apply() {
    final cosPitch = math.cos(pitch);
    final offset = Vector3(
      math.sin(yaw) * cosPitch,
      math.sin(pitch),
      math.cos(yaw) * cosPitch,
    )..scale(distance);

    node.setPosition(
      target.x + offset.x,
      target.y + offset.y,
      target.z + offset.z,
    );
    node.lookAt(target);
  }

  /// Applies the framing to whichever lens [camera] is carrying.
  ///
  /// A perspective camera gets the depth range and nothing else — its size on
  /// screen is already the orbit distance's doing. An orthographic one gets
  /// [orthoHeight] as well, because for that lens the framing *is* the height
  /// and no amount of moving the camera will produce it.
  void syncProjectionDepth(CameraNode camera) {
    final projection = camera.projection;
    final range = suggestedDepthRange();
    camera.projection = switch (projection) {
      PerspectiveProjection() => projection.copyWith(
        near: range.near,
        far: range.far,
      ),
      OrthographicProjection() => projection.copyWith(
        height: orthoHeight,
        near: range.near,
        far: range.far,
      ),
      // An off-axis projection is a stereo eye or a portal, and its frustum is
      // the thing on the other side of the window rather than anything an
      // orbit has an opinion about.
      _ => projection,
    };
  }

  /// Where a turn in progress began and where it is going.
  ///
  /// A length of zero is the resting state, which is why nothing here is
  /// nullable: [advance] on a controller nobody asked to turn has one number to
  /// look at.
  double _fromYaw = 0.0;
  double _fromPitch = 0.0;
  double _turnYaw = 0.0;
  double _turnPitch = 0.0;
  double _turnAt = 0.0;
  double _turnLength = 0.0;

  /// Whether a turn asked for by [animateTo] is still playing.
  bool get isTurning => _turnLength > 0.0;

  /// Swings the view round to [yaw] and [pitch] over [seconds].
  ///
  /// **What the orientation gizmo clicks into.** A view that jumps to −X leaves
  /// the person to work out which way the model just turned; a quarter of a
  /// second of travel shows them, and it is short enough that nobody waits for
  /// it. Driving it from the caller's clock rather than a timer of its own is
  /// what keeps this file free of `dart:async` and lets a test step it by hand.
  ///
  /// The yaw takes the short way round: asked to go from just under a half turn
  /// to just over one, it crosses the seam rather than unwinding the long way,
  /// which is the difference between a nudge and a full spin of the model.
  void animateTo({double? yaw, double? pitch, double seconds = 0.25}) {
    final double wantYaw = yaw ?? this.yaw;
    final double wantPitch = (pitch ?? this.pitch).clamp(
      -_kMaxPitch,
      _kMaxPitch,
    );
    if (seconds <= 0.0) {
      _turnLength = 0.0;
      this.yaw = wantYaw;
      this.pitch = wantPitch;
      apply();
      return;
    }
    _fromYaw = this.yaw;
    _fromPitch = this.pitch;
    final turn = wantYaw - this.yaw;
    _turnYaw = math.atan2(math.sin(turn), math.cos(turn));
    _turnPitch = wantPitch - this.pitch;
    _turnAt = 0.0;
    _turnLength = seconds;
  }

  /// Advances a turn by [seconds] of wall clock. Does nothing when none is
  /// playing, so a viewport can call it every frame without asking first.
  void advance(double seconds) {
    if (_turnLength <= 0.0) return;
    _turnAt += seconds;
    final double t = (_turnAt / _turnLength).clamp(0.0, 1.0);
    // Smoothstep, so the view leaves and arrives at rest. A linear turn stops
    // dead at the end, and the eye reads that as the picture having been
    // yanked rather than moved.
    final double eased = t * t * (3.0 - 2.0 * t);
    yaw = _fromYaw + _turnYaw * eased;
    pitch = (_fromPitch + _turnPitch * eased).clamp(-_kMaxPitch, _kMaxPitch);
    if (t >= 1.0) _turnLength = 0.0;
    apply();
  }
}
