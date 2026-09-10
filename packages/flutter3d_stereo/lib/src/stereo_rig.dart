import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'head_pose.dart';

/// Which eye.
///
/// **A value class rather than an enum, and the rule it follows says why**: an
/// enum in a published package is a closed list, and adding to it breaks every
/// switch anybody wrote. Two eyes look like a list that can never grow, right
/// up until a runtime with a third view configuration — quad views for
/// foveation are exactly that — arrives and it does.
final class Eye {
  const Eye._(this.index, this.label);

  static const Eye left = Eye._(0, 'left');
  static const Eye right = Eye._(1, 'right');

  /// In the order a projection layer lists them, which is also the order the
  /// halves of a target run in.
  static const List<Eye> both = <Eye>[left, right];

  /// Where this eye sits in a runtime's view list.
  final int index;

  final String label;

  @override
  String toString() => 'Eye.$label';
}

/// Two cameras under a head, under wherever the player is standing.
///
/// **Three nodes rather than two, and the third is the one that matters.**
/// A headset reports where the head is inside a room, so the head's pose is
/// *given* rather than chosen — which leaves an application nowhere to put
/// walking, riding a car, or a level that starts somewhere other than the
/// origin. [stage] is that somewhere: move it, parent it to a vehicle, and the
/// head keeps reporting what it reports.
///
/// The eyes are children of the head so that an interpupillary distance is
/// stated once, in metres, in the space where metres mean something.
final class StereoRig {
  StereoRig({
    this.interpupillaryDistance = 0.064,
    this.near = 0.05,
    this.far = 500.0,
    String? name,
  }) : stage = SceneNode(name: name ?? 'stage') {
    stage.add(head);
    head.add(_left);
    head.add(_right);
    _placeEyes();
  }

  /// Where the player is standing, and the only node an application moves.
  final SceneNode stage;

  /// Where the tracker says the head is, relative to [stage].
  final SceneNode head = SceneNode(name: 'head');

  /// The distance between the eyes, in metres. The average adult is around
  /// 63 mm; a headset states its own and should overwrite this.
  final double interpupillaryDistance;

  final double near;
  final double far;

  final CameraNode _left = CameraNode(name: 'eye.left');
  final CameraNode _right = CameraNode(name: 'eye.right');

  /// Set once a runtime has stated the eyes' frusta, so that a viewport's
  /// aspect ratio stops overwriting them. A headset's field of view is the
  /// headset's business; a phone's is the screen's.
  bool _projectionsAreGiven = false;

  CameraNode camera(Eye eye) => identical(eye, Eye.left) ? _left : _right;

  /// The pair, side by side in one target.
  ///
  /// Left in the left half, right in the right, which is the arrangement a
  /// projection layer expects and the one a phone in a holder needs.
  late final List<RenderView> views = <RenderView>[
    RenderView(
      camera: _left,
      viewportFraction: const ViewportRect(0.0, 0.0, 0.5, 1.0),
    ),
    RenderView(
      camera: _right,
      viewportFraction: const ViewportRect(0.5, 0.0, 0.5, 1.0),
    ),
  ];

  void _placeEyes() {
    final half = interpupillaryDistance / 2.0;
    _left.setPosition(-half, 0.0, 0.0);
    _right.setPosition(half, 0.0, 0.0);
  }

  /// Points the head where the tracker says it is.
  void applyHead(HeadPose pose) {
    head
      ..setRotation(pose.rotation)
      ..setPosition(pose.position.x, pose.position.y, pose.position.z);
  }

  /// What a runtime states for one eye: the frustum, and where the eye is
  /// relative to the head.
  ///
  /// Once either eye has been given a frustum, [fitToViewport] stops touching
  /// them — a runtime's angles are not something a widget's aspect ratio gets
  /// to correct.
  void applyEye(
    Eye eye, {
    required OffAxisProjection projection,
    Vector3? offset,
    Quaternion? rotation,
  }) {
    final node = camera(eye)..projection = projection;
    if (offset != null) node.setPosition(offset.x, offset.y, offset.z);
    if (rotation != null) node.setRotation(rotation);
    _projectionsAreGiven = true;
  }

  /// Frusta for a screen rather than a headset: symmetric, and as wide as half
  /// the surface is.
  ///
  /// [width] and [height] are the whole surface in pixels, both halves
  /// together, because that is what the renderer is handed and what the caller
  /// has. Called every frame and cheap: it does nothing once a runtime has
  /// spoken, and the two projections it builds are values.
  void fitToViewport({
    required int width,
    required int height,
    double verticalFieldOfView = 1.0,
  }) {
    if (_projectionsAreGiven) return;
    final aspect = height <= 0 ? 1.0 : (width / 2) / height;
    final projection = OffAxisProjection.symmetric(
      fovYRadians: verticalFieldOfView,
      aspect: aspect,
      near: near,
      far: far,
    );
    // The same frustum for both eyes: on a flat screen the only difference
    // between them is where they are, and a phone has no lenses to be
    // off-centre against.
    _left.projection = projection;
    _right.projection = projection;
  }

  /// Turns the rig to face [yawRadians] about the world's up axis.
  ///
  /// On [stage] rather than on [head]: the head is what the tracker says it is,
  /// and a rig that answered a stick by rotating the head would be arguing with
  /// the sensor sixty times a second.
  void faceYaw(double yawRadians) => stage.setRotation(
    Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yawRadians),
  );

  /// Where the head is looking, in world space — for a game that wants to know.
  Vector3 gaze([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = head.worldMatrix.storage;
    result.setValues(-m[8], -m[9], -m[10]);
    if (result.length2 > 0.0) result.normalize();
    return result;
  }

  /// The angle each eye sees vertically, for anything sizing against the frame.
  double get verticalFieldOfView =>
      _left.projection.verticalFieldOfView ?? math.pi / 4;
}
