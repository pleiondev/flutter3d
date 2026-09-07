/// A camera over a map: it pans, it zooms, and it follows nothing.
///
/// **The fourth camera, and the first that is not chasing anybody.** A shooter
/// looks out of a head, a platformer looks at a runner and a racer looks at a
/// car; all three are the same arrangement with different numbers. This one
/// watches a *place*, and the place moves because a player pushed the view
/// rather than because anything in the world did.
///
/// **It still turns [CameraRig].** That is not obedience to the structure rule
/// that asks for it — it is the reason the rule exists. The rig owns the
/// smoothing that stops a view from oscillating, the kick and shake that an
/// explosion asks for, and the first-frame cut that keeps a game from opening
/// with the camera flying across the level. A map camera wants all three, and
/// what it does *not* want — being pulled out of walls — costs nothing to carry:
/// the world it hands the rig is empty, because open ground has no walls, and
/// the day a map grows something a view should not pass through, that world is
/// where it will be said.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// How a map camera behaves.
final class MapCameraTuning {
  /// Builds the numbers.
  const MapCameraTuning({
    this.pitch = 0.95,
    this.minDistance = 12.0,
    this.maxDistance = 90.0,
    this.lag = 12.0,
  });

  /// How far the view tilts down from the horizon, in radians. About
  /// fifty-four degrees by default: steep enough to read the ground, shallow
  /// enough that units have a silhouette rather than a footprint.
  final double pitch;

  /// The closest and furthest the eye may be from what it watches.
  final double minDistance;
  final double maxDistance;

  /// How much of the gap the rig closes in a second. Higher is tighter.
  final double lag;
}

/// The view over a strategy's map.
final class MapCamera {
  /// Builds a camera watching the middle of [ground].
  MapCamera({
    required this.ground,
    this.tuning = const MapCameraTuning(),
    CollisionWorld? world,
  }) : rig = CameraRig(world: world ?? CollisionWorld()),
       _distance = (tuning.minDistance + tuning.maxDistance) / 2.0 {
    _focus.setValues(
      ground.origin.x + ground.width / 2.0,
      0.0,
      ground.origin.z + ground.depth / 2.0,
    );
  }

  /// The ground the view is over, which is also what bounds it.
  final Heightfield ground;

  /// The numbers.
  final MapCameraTuning tuning;

  /// The smoothing, the impulses and the first-frame cut.
  final CameraRig rig;

  final Vector3 _focus = Vector3.zero();
  final Vector3 _desiredEye = Vector3.zero();
  final Vector3 _desiredTarget = Vector3.zero();
  double _distance;

  /// Where the view is pointed, on the ground.
  Vector3 get focus => _focus;

  /// How far the eye is from [focus].
  double get distance => _distance;

  /// Where the camera is. Valid after the first [place].
  Vector3 get eye => rig.eye;

  /// What it is looking at.
  Vector3 get target => rig.target;

  /// Pushes the view across the map, in metres.
  ///
  /// **Clamped to the ground.** A view that can be pushed off the map shows a
  /// player the void beyond it and gives them nothing to steer back by; the
  /// edge of the ground is the edge of the game.
  void pan(double x, double z) {
    _focus
      ..x = (_focus.x + x).clamp(
        ground.origin.x,
        ground.origin.x + ground.width,
      )
      ..z = (_focus.z + z).clamp(
        ground.origin.z,
        ground.origin.z + ground.depth,
      );
  }

  /// Moves the eye closer to or further from the ground.
  void zoom(double by) {
    _distance = (_distance + by).clamp(tuning.minDistance, tuning.maxDistance);
  }

  /// Puts the camera where it belongs this frame.
  ///
  /// The focus rides the ground: a view over a hill is as far above the hill as
  /// a view over a valley is above the valley, which is what stops a camera
  /// from burying itself in a slope the player panned onto.
  void place(double dt) {
    _focus.y = ground.heightAt(_focus.x, _focus.z);
    _desiredTarget.setFrom(_focus);

    // Behind along -Z and above by the pitch. The yaw is fixed: a map that
    // turns is a map a player has to re-read, and nothing here has asked for
    // one.
    final double back = Portable.cos(tuning.pitch) * _distance;
    final double up = Portable.sin(tuning.pitch) * _distance;
    _desiredEye.setValues(_focus.x, _focus.y + up, _focus.z + back);

    rig.place(
      desiredEye: _desiredEye,
      desiredTarget: _desiredTarget,
      lag: tuning.lag,
      dt: dt,
    );
  }
}
