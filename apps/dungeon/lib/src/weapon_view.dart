import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

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
final class WeaponView {
  WeaponView() {
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

    _buildWeapons();
    // The pistol, not the fists: the game starts with both, and a shooter
    // that opens on empty hands looks unfinished.
    _show(1);
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

  ViewModelPass get pass => ViewModelPass(scene: _scene, camera: _camera);

  void _buildWeapons() {
    _scene.add(_holder);

    // Procedural blocks, because there is no weapon art yet. Deliberately not
    // a placeholder cube each: distinguishable silhouettes are what make the
    // switch readable, which is the only thing this view has to do before the
    // models arrive.
    // Two of them, because one block in the corner of the screen reads as a
    // stray object rather than as a pair of hands.
    _byWeapon[Weapons.fists.name] = _assemble(<_Part>[
      _Part(Vector3(0.03, 0.0, 0.0), Vector3(0.13, 0.11, 0.16), _skin),
      _Part(Vector3(-0.26, -0.05, 0.05), Vector3(0.13, 0.11, 0.16), _skin),
    ]);
    _byWeapon[Weapons.pistol.name] = _assemble(<_Part>[
      _Part(Vector3(0.0, 0.0, -0.08), Vector3(0.052, 0.070, 0.25), _metal),
      _Part(Vector3(0.0, -0.09, 0.04), Vector3(0.048, 0.115, 0.085), _grip),
    ]);
    _byWeapon[Weapons.shotgun.name] = _assemble(<_Part>[
      _Part(Vector3(0.0, 0.01, -0.20), Vector3(0.065, 0.065, 0.46), _metal),
      _Part(Vector3(0.0, -0.06, 0.10), Vector3(0.055, 0.098, 0.19), _grip),
      _Part(Vector3(0.0, -0.06, -0.16), Vector3(0.062, 0.055, 0.14), _grip),
    ]);
    _byWeapon[Weapons.rocketLauncher.name] = _assemble(<_Part>[
      _Part(Vector3(0.0, 0.03, -0.24), Vector3(0.110, 0.110, 0.54), _metal),
      _Part(Vector3(0.0, -0.08, 0.06), Vector3(0.055, 0.110, 0.13), _grip),
      _Part(Vector3(0.0, 0.13, -0.10), Vector3(0.039, 0.047, 0.18), _grip),
    ]);
  }

  // Not actually metallic, despite the name and despite being a gun barrel.
  // A metallic surface reflects its surroundings and has almost no diffuse
  // response, so with no environment map to reflect it renders very nearly
  // black — which is exactly how the first version looked. Image-based lighting
  // would fix it properly and is out of reach on this channel, since it needs
  // mip levels. A dark dielectric reads as gunmetal and costs nothing.
  static final engine.Material _metal = engine.Material(
    baseColor: Vector4(0.30, 0.31, 0.34, 1.0),
    roughness: 0.45,
  );
  static final engine.Material _grip = engine.Material(
    baseColor: Vector4(0.29, 0.21, 0.16, 1.0),
    roughness: 0.75,
  );
  static final engine.Material _skin = engine.Material(
    baseColor: Vector4(0.52, 0.36, 0.28, 1.0),
    roughness: 0.7,
  );

  SceneNode _assemble(List<_Part> parts) {
    final root = SceneNode()..visible = false;
    _holder.add(root);
    for (final part in parts) {
      root.add(
        MeshNode(
          GpuMesh.upload(CuboidShape(size: part.size).build()),
          part.material,
        )..setPositionFrom(part.offset),
      );
    }
    return root;
  }

  /// Shows the weapon in [slot] and hides the rest.
  void _show(int slot) {
    final wanted = Weapons.all[slot.clamp(0, Weapons.all.length - 1)].name;
    for (final entry in _byWeapon.entries) {
      entry.value.visible = entry.key == wanted;
    }
  }

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
      _bobOffset += (0.0 - _bobOffset) * (1.0 - math.exp(-8.0 * dt));
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

final class _Part {
  _Part(this.offset, this.size, this.material);

  final Vector3 offset;
  final Vector3 size;
  final engine.Material material;
}
