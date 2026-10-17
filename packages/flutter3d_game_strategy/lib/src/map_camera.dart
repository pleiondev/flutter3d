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

import 'package:flutter3d_camera/flutter3d_camera.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// How a map camera behaves.
final class MapCameraSettings {
  /// Builds the numbers.
  const MapCameraSettings({
    this.pitch = 0.95,
    this.minDistance = 12.0,
    this.maxDistance = 90.0,
    this.lag = 12.0,
  });

  /// A copy with the given fields replaced.
  MapCameraSettings copyWith({
    double? pitch,
    double? minDistance,
    double? maxDistance,
    double? lag,
  }) => MapCameraSettings(
    pitch: pitch ?? this.pitch,
    minDistance: minDistance ?? this.minDistance,
    maxDistance: maxDistance ?? this.maxDistance,
    lag: lag ?? this.lag,
  );

  /// How far the view tilts down from the horizon, in radians. About
  /// fifty-four degrees by default: steep enough to read the ground, shallow
  /// enough that units have a silhouette rather than a footprint.
  final double pitch;

  /// The closest and furthest the eye may be from what it watches.
  /// Both in metres.
  final double minDistance;

  /// The furthest, in metres.
  final double maxDistance;

  /// How much of the gap the rig closes in a second. Higher is tighter.
  final double lag;
}

/// The view over a strategy's map.
///
/// **The strategy preset of the virtual cameras**: `OverheadFraming` in
/// `flutter3d_camera`, bounded by [ground] and riding its heights, with
/// [rig] under it. Hand [virtualCamera] to a `CameraDirector` to cut to a
/// battle and blend back.
final class MapCamera {
  /// Builds a camera watching the middle of [ground].
  MapCamera({
    required this.ground,
    this.tuning = const MapCameraSettings(),
    CollisionWorld? world,
    String name = 'map',
    CameraFraming Function(OverheadFraming preset)? reframe,
  }) : rig = CameraRig(world: world ?? CollisionWorld()),
       framing = OverheadFraming(
         minX: ground.origin.x,
         minZ: ground.origin.z,
         maxX: ground.origin.x + ground.width,
         maxZ: ground.origin.z + ground.depth,
         startX: ground.origin.x + ground.width / 2.0,
         startZ: ground.origin.z + ground.depth / 2.0,
         groundHeight: ground.heightAt,
         pitch: tuning.pitch,
         minDistance: tuning.minDistance,
         maxDistance: tuning.maxDistance,
         lag: tuning.lag,
       ) {
    virtualCamera = VirtualCamera(
      name,
      reframe?.call(framing) ?? framing,
      rig: rig,
    );
  }

  /// The ground the view is over, which is also what bounds it.
  final Heightfield ground;

  /// The numbers.
  final MapCameraSettings tuning;

  /// The smoothing, the impulses and the first-frame cut.
  final CameraRig rig;

  /// Where the camera wants to be: the focus, the zoom and the tilt.
  final OverheadFraming framing;

  /// This camera as one of a director's: the [framing] carried out by [rig].
  ///
  /// **Its framing can be replaced.** Pass `reframe` to the constructor and
  /// the camera takes its shots from what that returns, given the overhead view
  /// preset in [framing]: a framing of the game's own that wraps the preset
  /// and changes what it asks for, or one that ignores it. The preset is
  /// still the one the calls here feed, so a replacement that wraps it
  /// keeps the subject and the look it is given.
  late final VirtualCamera virtualCamera;

  /// Where the view is pointed, on the ground.
  Vector3 get focus => framing.focus;

  /// How far the eye is from [focus].
  /// In metres.
  double get distance => framing.distance;

  /// Where the camera is. Valid after the first [place].
  Vector3 get eye => rig.eye;

  /// What it is looking at.
  Vector3 get target => rig.target;

  /// Pushes the view across the map, in metres.
  ///
  /// **Clamped to the ground.** A view that can be pushed off the map shows a
  /// player the void beyond it and gives them nothing to steer back by; the
  /// edge of the ground is the edge of the game.
  void pan(double x, double z) => framing.pan(x, z);

  /// Moves the eye closer to or further from the ground.
  void zoom(double by) => framing.zoom(by);

  /// Puts the camera where it belongs this frame.
  ///
  /// The focus rides the ground: a view over a hill is as far above the hill as
  /// a view over a valley is above the valley, which is what stops a camera
  /// from burying itself in a slope the player panned onto.
  void place(double dt) => virtualCamera.update(dt);
}
