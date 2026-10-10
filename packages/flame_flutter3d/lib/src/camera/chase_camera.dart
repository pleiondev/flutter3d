import 'package:flame/components.dart' show Component;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_camera/flutter3d_camera.dart'
    show CameraFraming, CameraRig, CameraShot, VirtualCamera;
import 'package:flutter3d_physics/flutter3d_physics.dart';

import '../host/bridge_priority.dart';
import '../transform/object3d_component.dart';

/// A camera that follows a bridged component from where [offset] puts it,
/// looking at where [lookOffset] points: behind and above a jet, looking up
/// the river ahead of it.
///
/// **For a perspective camera, where [CameraSyncController] cannot help.**
/// That reconciles a Flame viewfinder's zoom with an orthographic height;
/// a perspective chase has nothing of Flame's to reconcile, only a target
/// to keep in frame, and every game that had one wrote it by hand.
///
/// **Part way across.** Along the plane's own x axis the camera follows
/// the target by [followAcross] and aims by [lookAcross], fractions of the
/// target's x: a camera locked to a craft's every dodge turns the whole
/// world with it, and one that does not follow at all loses a craft off a
/// narrow screen. Everything else follows the target in full.
///
/// **Stiff or springy.** With [stiffness] at zero the camera is exactly
/// where the offsets say every frame. Above zero it closes on that place
/// exponentially, [stiffness] being how many times its distance it closes
/// per second, and the first [advance] still puts it there outright.
///
/// **A [VirtualCamera] with a [FlameChaseFraming].** The framing says where
/// the camera wants to be; the virtual camera's [CameraRig] eases it there,
/// knocks and shakes it, and pulls it out of walls, written once for every
/// camera in the engine: [rig] is there to shake when the craft is hit, and a
/// [world] with walls in it keeps the camera out of them. Without one the
/// camera has nothing to be kept out of. A `CameraDirector` can take
/// [virtualCamera] like any other.
final class FlameChaseCamera {
  FlameChaseCamera({
    required this.camera,
    required Object3dComponent target,
    required Vector3 offset,
    required Vector3 lookOffset,
    double followAcross = 1.0,
    double lookAcross = 1.0,
    double stiffness = 0.0,
    CollisionWorld? world,
  }) : framing = FlameChaseFraming(
         target: target,
         offset: offset,
         lookOffset: lookOffset,
         followAcross: followAcross,
         lookAcross: lookAcross,
         stiffness: stiffness,
       ) {
    virtualCamera = VirtualCamera('chase', framing, world: world);
  }

  /// The scene camera the shot is written to.
  final CameraNode camera;

  /// Where the camera wants to be.
  final FlameChaseFraming framing;

  /// The framing with its rig: what a director would hold.
  late final VirtualCamera virtualCamera;

  /// What eases the camera, and what shakes it: `rig.shake(0.4)` when the
  /// craft goes down.
  CameraRig get rig => virtualCamera.rig;

  Object3dComponent get target => framing.target;
  Vector3 get offset => framing.offset;
  Vector3 get lookOffset => framing.lookOffset;

  /// How much of the target's x the camera follows: a fraction.
  double get followAcross => framing.followAcross;

  /// How much of the target's x the camera aims at: a fraction.
  double get lookAcross => framing.lookAcross;

  /// How many times its distance the camera closes per second, a rate per
  /// second; zero puts it there outright.
  double get stiffness => framing.stiffness;

  /// Moves the camera for this frame. Call it once the target has moved,
  /// from `Flutter3dFlameWidget.onTick` or through [FlameChaseCameraComponent].
  void advance(double dt) {
    virtualCamera.update(dt);
    camera
      ..setPositionFrom(virtualCamera.shot.eye)
      ..lookAt(virtualCamera.shot.target);
  }
}

/// Where a chase camera wants to be: [offset] from a bridged component, part
/// way across, looking at [lookOffset] from it.
final class FlameChaseFraming extends CameraFraming {
  FlameChaseFraming({
    required this.target,
    required this.offset,
    required this.lookOffset,
    this.followAcross = 1.0,
    this.lookAcross = 1.0,
    this.stiffness = 0.0,
  });

  /// What is followed.
  final Object3dComponent target;

  /// From the target's scene position to the camera, in metres.
  final Vector3 offset;

  /// From the target's scene position to the point the camera looks at, in
  /// metres.
  final Vector3 lookOffset;

  /// How much of the target's x the camera follows: a fraction.
  final double followAcross;

  /// How much of the target's x the camera aims at: a fraction.
  final double lookAcross;

  /// How many times its distance the camera closes per second; zero puts it
  /// there outright.
  final double stiffness;

  /// A closing rate high enough that a stiff camera is where it should be
  /// after any frame, through the same easing a springy one goes through.
  static const double _rigid = 1e4;

  /// The rate the virtual camera eases at, per second: [stiffness], or a
  /// rate no frame outlasts when that is zero.
  @override
  double get lag => stiffness > 0.0 ? stiffness : _rigid;

  @override
  void frame(CameraShot wanted, double dt) {
    final at = target.scenePosition;
    wanted.eye
      ..setFrom(at)
      ..add(offset)
      ..x = at.x * followAcross + offset.x;
    wanted.target
      ..setFrom(at)
      ..add(lookOffset)
      ..x = at.x * lookAcross + lookOffset.x;
  }
}

/// A [FlameChaseCamera] run as a Flame component, for a game that would rather
/// order it by priority than call it from a tick. Give it a priority above
/// whatever moves the target, so it follows this frame's move.
final class FlameChaseCameraComponent extends Component {
  FlameChaseCameraComponent(
    this.chase, {
    super.priority = BridgePriority.camera,
  });

  final FlameChaseCamera chase;

  @override
  void update(double dt) => chase.advance(dt);
}
