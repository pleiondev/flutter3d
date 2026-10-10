import 'package:flutter3d_physics/flutter3d_physics.dart';

import 'blend.dart';
import 'camera_rig.dart';
import 'framing.dart';
import 'shot.dart';

/// One camera a game could be looking through: a framing, the rig that
/// carries it out, and how much it wants to be the one shown.
///
/// **A virtual camera draws nothing and owns no projection.** It answers with
/// a [shot]; a `CameraDirector` decides which of its cameras is live, blends
/// between them, and hands the result to whatever draws. A game with one
/// camera can skip the director and read [shot] itself.
///
/// **The rig is the engine's `CameraRig`**, which already owns easing without
/// overshoot, the knocks and shakes that fade, the player's motion setting and
/// keeping the camera out of the walls, in an order a property test settled.
/// A virtual camera is that rig with a framing deciding where it should be —
/// which is why every camera that moved onto this kept its feel: it is the
/// same rig, handed the same numbers.
///
/// ## Determinism
///
/// Cameras are the view's: nothing here is read by a step, and nothing in a
/// replay depends on where a camera was. The walls are read through the
/// world's rays, which is a read of the simulation, never a write; a camera
/// that moved anything would be a step and would have to live in one.
final class VirtualCamera {
  /// A camera called [name], taking the shots [framing] wants.
  ///
  /// [rig] is the one to carry them out; without one, a rig is made over
  /// [world], with the engine's defaults. Without a [world] either, the camera
  /// keeps out of no walls, which is right for a first-person view and an
  /// overhead one.
  VirtualCamera(
    this.name,
    this.framing, {
    CameraRig? rig,
    CollisionWorld? world,
    this.priority = 0,
    this.blendIn,
    this.updateOnStandby = false,
  }) : rig = rig ?? CameraRig(world: world ?? CollisionWorld());

  /// How the camera is known to a director, a blend table and a log.
  final String name;

  /// Where it wants to be.
  final CameraFraming framing;

  /// How it gets there.
  final CameraRig rig;

  /// How much it wants to be live. The highest enabled one is.
  int priority;

  /// Whether a director may make it live. Switched off, it stays where it was
  /// and a director goes to the next.
  bool enabled = true;

  /// The blend into this camera, when a director has no blend for the pair.
  CameraBlend? blendIn;

  /// Whether a director keeps placing it while another camera is live.
  ///
  /// Off by default, because a placed camera costs a framing and a ray, and
  /// a game with ten cameras round a level needs one. A camera that was not
  /// kept up is cut into place the moment it goes live, so its rig does not
  /// ease in from wherever it was left; the blend into it is what is smooth.
  bool updateOnStandby;

  /// What the camera shows, after the last [update].
  final CameraShot shot = CameraShot();

  final CameraShot _wanted = CameraShot();

  /// The shot the framing asked for on the last update, before the rig eased
  /// it, knocked it or pulled it out of a wall. For a test, or a debug line
  /// drawn from where the camera wanted to be.
  CameraShot get wanted => _wanted;

  /// Whether it has been placed yet.
  bool get isPlaced => rig.isPlaced;

  /// Places the camera for a frame [dt] seconds after the last.
  void update(double dt) {
    framing.frame(_wanted, dt);
    rig.place(
      desiredEye: _wanted.eye,
      desiredTarget: _wanted.target,
      lag: framing.lag,
      dt: dt,
    );
    shot.eye.setFrom(rig.eye);
    shot.target.setFrom(rig.target);
    shot.fovY = _wanted.fovY + rig.extraFovY;
    shot.roll = _wanted.roll;
  }

  /// Puts the camera where its framing wants it on the next [update], without
  /// a chase, and drops what was shaking it.
  void cut() {
    rig.cut();
    framing.cut();
  }

  @override
  String toString() =>
      'VirtualCamera($name, priority $priority'
      '${enabled ? '' : ', off'})';
}
