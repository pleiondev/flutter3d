import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'camera_node.dart';
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
  }) : target = target ?? Vector3.zero() {
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

  static const double _kMaxPitch = math.pi / 2 - 0.01;

  /// Radians per pixel of drag.
  double rotateSensitivity = 0.008;

  void rotate(double deltaYaw, double deltaPitch) {
    yaw -= deltaYaw * rotateSensitivity;
    pitch = (pitch + deltaPitch * rotateSensitivity)
        .clamp(-_kMaxPitch, _kMaxPitch);
    apply();
  }

  /// Multiplicative zoom: [factor] below 1 moves closer.
  ///
  /// Multiplicative rather than additive so a step feels the same whether the
  /// camera is a centimetre or a kilometre out.
  void zoom(double factor) {
    distance = (distance * factor).clamp(minDistance, maxDistance);
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
    distance = (radius / math.sin(fovYRadians * 0.5) * margin)
        .clamp(minDistance, maxDistance);
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
    return Vector3(
      -sinYaw * sinPitch,
      cosPitch,
      -cosYaw * sinPitch,
    )..normalize();
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

  /// Applies the suggested depth range to a perspective camera, if the node is one.
  void syncProjectionDepth(CameraNode camera) {
    final projection = camera.projection;
    if (projection is! PerspectiveProjection) return;
    final range = suggestedDepthRange();
    camera.projection = projection.copyWith(near: range.near, far: range.far);
  }
}
