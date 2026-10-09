import 'package:flame/components.dart' show Component;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_camera/flutter3d_camera.dart'
    show CameraFraming, CameraRig, CameraShot, VirtualCamera;
import 'package:flutter3d_physics/flutter3d_physics.dart';

import '../host/bridge_priority.dart';
import 'chase_camera.dart' show FlameChaseCamera;

/// A camera eased towards wherever a function says it should be.
///
/// **For what one component cannot say.** [FlameChaseCamera] follows a bridged
/// component; a camera over a co-op party follows all of it, and where it
/// should be is worked out from every hero at once — by the game's own
/// framing, which may also be a rule of the simulation. [view] is that
/// answer, asked once a frame: it writes the eye and the point looked at
/// into the two vectors it is handed, or answers false while there is
/// nothing to look at yet.
///
/// A [VirtualCamera] with a [ViewFraming], as [FlameChaseCamera] is: the
/// easing, the shake and the pull out of walls are its [CameraRig]'s.
final class ViewCamera {
  ViewCamera({
    required this.camera,
    required bool Function(Vector3 eye, Vector3 target) view,
    double stiffness = 4.0,
    CollisionWorld? world,
  }) : framing = ViewFraming(view: view, stiffness: stiffness) {
    virtualCamera = VirtualCamera('view', framing, world: world);
  }

  /// The scene camera the shot is written to.
  final CameraNode camera;

  /// Where the camera wants to be.
  final ViewFraming framing;

  /// The framing with its rig: what a director would hold.
  late final VirtualCamera virtualCamera;

  /// Where the camera wants to be this frame, written into `eye` and
  /// `target`; false leaves the camera where it is.
  bool Function(Vector3 eye, Vector3 target) get view => framing.view;

  /// How many times its distance the camera closes per second, a rate per
  /// second; zero puts it there outright.
  double get stiffness => framing.stiffness;

  /// What eases the camera, and what shakes it.
  CameraRig get rig => virtualCamera.rig;

  /// Moves the camera for this frame; a frame [view] answers false for
  /// leaves it where it is.
  void advance(double dt) {
    if (!framing.ask()) return;
    virtualCamera.update(dt);
    camera
      ..setPositionFrom(virtualCamera.shot.eye)
      ..lookAt(virtualCamera.shot.target);
  }
}

/// Where a function says a camera should be, asked once a frame.
final class ViewFraming extends CameraFraming {
  ViewFraming({required this.view, this.stiffness = 4.0});

  /// Writes the eye and the point looked at into the two vectors it is
  /// handed, or answers false while there is nothing to look at.
  final bool Function(Vector3 eye, Vector3 target) view;

  /// How many times its distance the camera closes per second; zero puts it
  /// there outright.
  final double stiffness;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();

  /// Asks [view] for this frame's place; false when it has none, and the
  /// camera should not move.
  bool ask() => view(_eye, _target);

  /// The rate the virtual camera eases at, per second: [stiffness], or a
  /// rate no frame outlasts when that is zero.
  @override
  double get lag => stiffness > 0.0 ? stiffness : 1e4;

  @override
  void frame(CameraShot wanted, double dt) {
    wanted.eye.setFrom(_eye);
    wanted.target.setFrom(_target);
  }
}

/// A [ViewCamera] run as a Flame component, after whatever moves what it
/// frames.
final class ViewCameraComponent extends Component {
  ViewCameraComponent(
    this.viewCamera, {
    super.priority = BridgePriority.camera,
  });

  final ViewCamera viewCamera;

  @override
  void update(double dt) => viewCamera.advance(dt);
}
