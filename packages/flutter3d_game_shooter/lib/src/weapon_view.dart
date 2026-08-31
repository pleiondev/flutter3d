import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'combat/weapon.dart';

/// The weapon in the player's hands, and everything that makes it feel held.
///
/// Its own scene and its own camera, drawn by the renderer's view-model pass
/// after the world and with the depth buffer cleared. A weapon is a few
/// centimetres from the eye, and in the world's depth buffer it would be buried
/// by the first wall the player walked up to.
///
/// The narrow field of view is not a detail either. The world camera is wide
/// enough to take in a room; a model rendered at that angle this close has its
/// edges stretched into something that reads as a bug.
///
/// What the weapons look like is not here. The game hands in one node per
/// weapon name; this owns the rig around them — the scene, the camera, the
/// lighting, the holder, the bob and the recoil.
final class WeaponView {
  /// [models] is one root node per [WeaponDef.name]. Each is parented to the
  /// holder and hidden; [initial] is the one shown first.
  ///
  /// A map rather than a builder callback because the nodes are built once and
  /// the bridge has nothing to add to their construction — it only needs to own
  /// where they hang.
  /// [environment] is what the held weapon reflects, and [environmentLevels] is
  /// its roughness scale — see `EnvironmentMap`.
  ///
  /// **Its own, not the world's.** A weapon is held in front of the eye and lit
  /// by this scene's two lights rather than by the room's, so the room's sky
  /// would be the wrong thing to reflect even where there is one — and in a
  /// crypt there is none at all. What a game hands in here is a studio: a small
  /// environment that makes a barrel read as metal.
  ///
  /// Without one a metal barrel is very nearly black, because a metal has no
  /// diffuse response. That is why the games' own weapon models were built from
  /// dark dielectrics pretending to be gunmetal.
  WeaponView({
    required Map<String, SceneNode> models,
    WeaponDef? initial,
    TextureHandle? environment,
    int environmentLevels = 0,
  }) {
    _scene
      ..environment = environment
      ..environmentLevels = environmentLevels;
    _scene.add(
      LightNode(
        color: Vector3(1.0, 0.92, 0.82),
        intensity: 4.5,
        name: 'key',
      )
        ..setPosition(1.0, 1.4, 0.8)
        ..lookAt(Vector3(0.0, -0.2, -1.0)),
    );
    _scene.add(
      LightNode(
        type: LightType.point,
        color: Vector3(1.0, 0.7, 0.4),
        intensity: 3.0,
        range: 5.0,
        name: 'fill',
      )..setPosition(-0.8, -0.4, 0.6),
    );

    _camera.setPosition(0.0, 0.0, 0.0);
    _camera.lookAt(Vector3(0.0, 0.0, -1.0));
    _camera.projection = PerspectiveProjection(
      // 55 degrees against the world's 90.
      fovYRadians: 55.0 * math.pi / 180.0,
      near: 0.01,
      far: 10.0,
    );

    _scene.add(_holder);
    for (final entry in models.entries) {
      _byWeapon[entry.key] = entry.value..visible = false;
      _holder.add(entry.value);
    }

    if (initial != null) selectWeapon(initial);
  }

  static const double _bobSpeed = 9.5;
  static const double _bobAmount = 0.018;

  /// How far the weapon kicks back, and how fast it returns.
  static const double _recoilKick = 0.085;
  static const double _recoilRecovery = 7.0;

  final Scene _scene = Scene();
  final CameraNode _camera = CameraNode(name: 'view model');

  /// One node per weapon, all parented to a holder so the bob and recoil are
  /// applied once rather than per weapon.
  final SceneNode _holder = SceneNode(name: 'holder');
  final Map<String, SceneNode> _byWeapon = <String, SceneNode>{};

  final Vector3 _restPosition = Vector3(0.20, -0.19, -0.78);

  double _bobPhase = 0.0;
  double _bobOffset = 0.0;
  double _recoil = 0.0;

  /// The plugin that draws the weapon over the finished scene.
  ///
  /// Built once and registered with the renderer, rather than handed in with
  /// every frame: what draws is now a property of the renderer, not an
  /// argument to a call.
  late final ViewModelNode plugin =
      ViewModelNode(scene: _scene, camera: _camera);

  /// Shows [weapon]'s model and hides the rest.
  void selectWeapon(WeaponDef weapon) {
    for (final entry in _byWeapon.entries) {
      entry.value.visible = entry.key == weapon.name;
    }
  }

  /// Kicks the weapon back. Called when a shot actually happened, not when the
  /// trigger was pulled — a dry click should not recoil.
  void recoil() => _recoil = 1.0;

  /// Advances the bob and the recoil by one simulation step.
  ///
  /// [speed] is the player's horizontal speed, and [grounded] whether their
  /// feet are down: a weapon that keeps swaying while the player is in mid-air
  /// is the detail that makes a jump feel weightless.
  void step(double dt, {required double speed, required bool grounded}) {
    if (grounded && speed > 0.2) {
      _bobPhase += dt * _bobSpeed * (speed / 6.0).clamp(0.3, 1.8);
      _bobOffset = math.sin(_bobPhase) * _bobAmount;
    } else {
      // Eased back to centre rather than snapped: stopping dead mid-swing is
      // more noticeable than the sway itself.
      _bobOffset += (0.0 - _bobOffset) * easeFactor(8.0, dt);
    }

    if (_recoil > 0.0) {
      _recoil -= _recoilRecovery * dt;
      if (_recoil < 0.0) _recoil = 0.0;
    }

    _holder.setPosition(
      _restPosition.x,
      _restPosition.y + _bobOffset,
      // Back towards the eye, and slightly up: a straight backwards kick reads
      // as the weapon shrinking.
      _restPosition.z + _recoil * _recoilKick,
    );
    _holder.setRotation(
      Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), _recoil * 0.22),
    );
  }
}
