import 'package:flutter3d_camera/flutter3d_camera.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'player.dart';

/// The view out of the player's head.
///
/// **The shooter's preset of the virtual cameras**: `FirstPersonFraming` in
/// `flutter3d_camera`, with the eye at [Player.eyeFrom] and the view
/// along [Player.aim] — the recoil included, because the sight climbing is
/// what the screen is meant to show. No smoothing and no pulling out of
/// walls, the two things a first-person view must not have, so the picture
/// is the one an application placing its camera by hand from the same two
/// calls would draw.
///
/// What the virtual camera adds is the head: [rig] carries a kick, a shake
/// and a widening that fade, under the player's motion setting, and
/// [virtualCamera] can go into a `CameraDirector` beside a camera standing
/// back from the body, so a death blends out of the eyes rather than cutting.
final class FirstPersonCamera {
  /// A view [fovY] radians wide, known to a director as [name].
  FirstPersonCamera({
    double fovY = 1.0,
    String name = 'eyes',
    CameraFraming Function(FirstPersonFraming preset)? reframe,
  }) : framing = FirstPersonFraming(fovY: fovY),
       // Open air: the eye is inside a body the physics already keeps out of
       // the walls, and a ray from a point in front of the face back to the
       // eye finds the wall the player is pressed against.
       rig = CameraRig(world: CollisionWorld()) {
    virtualCamera = VirtualCamera(
      name,
      reframe?.call(framing) ?? framing,
      rig: rig,
    );
  }

  /// Where the eye wants to be and which way it looks.
  final FirstPersonFraming framing;

  /// The knocks, the shake and the widening.
  final CameraRig rig;

  /// This camera as one of a director's.
  ///
  /// **Its framing can be replaced.** Pass `reframe` to the constructor and
  /// the camera takes its shots from what that returns, given the eye
  /// preset in [framing]: a framing of the game's own that wraps the preset
  /// and changes what it asks for, or one that ignores it. The preset is
  /// still the one the calls here feed, so a replacement that wraps it
  /// keeps the subject and the look it is given.
  late final VirtualCamera virtualCamera;

  /// Where the eye is, after the last [follow].
  Vector3 get eye => rig.eye;

  /// What it looks at: a metre along the aim.
  Vector3 get target => rig.target;

  /// The field of view to draw with, in radians, widened by anything that
  /// asked for it.
  double get fovY => virtualCamera.shot.fovY;

  /// Places the view for a frame, from [player] standing at [position].
  ///
  /// [position] is the *interpolated* body position, not the simulated one:
  /// on a display faster than the step rate, several frames in a row would
  /// otherwise show the same place and then jump.
  ///
  /// With the camera in a `CameraDirector`, call [aim] instead and let the
  /// director place it.
  void follow(Player player, Vector3 position, double dt) {
    aim(player, position);
    virtualCamera.update(dt);
  }

  /// Hands the player's eye and aim to the framing without placing the view.
  void aim(Player player, Vector3 position) {
    player
      ..eyeFrom(position, framing.eye)
      ..aim(framing.direction);
  }

  /// Puts the view in the head at once and drops what was shaking it: a
  /// respawn, a loaded save.
  void cut() => virtualCamera.cut();
}
