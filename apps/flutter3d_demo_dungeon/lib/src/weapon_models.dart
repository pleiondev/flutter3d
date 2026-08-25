import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:vector_math/vector_math.dart';

/// A small room for the weapon in the player's hands to reflect.
///
/// **Not the crypt.** The crypt has no sky to build an environment from, and a
/// weapon is held in front of the eye and lit by `WeaponView`'s own two lights
/// rather than by the room — so what it should reflect is a studio, not the
/// corridor behind it.
///
/// Built rather than shipped: six faces of a vertical gradient, bright above
/// and dark below, which is what a room does to a barrel. Sixteen pixels a side
/// because it is only ever sampled through a roughness lobe, and a sharper one
/// would cost the convolution sixteen times as much to no visible end.
///
/// Null on a device with no cube textures, which leaves the weapons lit by the
/// flat ambient exactly as they were.
({TextureHandle texture, int levels})? studioEnvironment(
    GraphicsDevice device) {
  if (!device.supportsCubeTextures) return null;
  const size = 16;

  final faces = <ByteData>[];
  for (var face = 0; face < 6; face++) {
    final data = ByteData(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        // +Y is the ceiling and −Y the floor; the four sides ramp between them.
        final double up;
        if (face == 2) {
          up = 1.0;
        } else if (face == 3) {
          up = 0.0;
        } else {
          up = 1.0 - (y + 0.5) / size;
        }
        final value = (0.10 + 0.70 * up * up) * 255.0;
        final at = (y * size + x) * 4;
        final level = value.round().clamp(0, 255);
        data.setUint8(at, level);
        data.setUint8(at + 1, level);
        // A touch cooler than neutral, so a barrel does not read as a mirror of
        // nothing in particular.
        data.setUint8(at + 2, (value * 1.06).round().clamp(0, 255));
        data.setUint8(at + 3, 255);
      }
    }
    faces.add(data);
  }

  const levels = 4;
  final chain = EnvironmentMap.prefilter(faces, size: size, levels: levels);
  if (chain == null) return null;
  final texture = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces,
    mipLevels: chain,
  );
  return texture == null ? null : (texture: texture, levels: levels);
}

/// The models fetched by `tool/fetch_weapons.py`, by weapon name.
///
/// Only two: a weapon without art is a missing key here rather than a missing
/// file discovered at load.
///
/// **Keyed off the definitions rather than typed out.** The first version wrote
/// `'pistol'`, and the weapons are called `Pistol` and `Shotgun` — so every
/// lookup missed, every weapon silently stayed a block, and nothing said so.
/// That costs the `const`, which is a fair price for a key that cannot drift
/// from the thing it names.
final Map<String, String> kWeaponModels = <String, String>{
  Weapons.pistol.name: 'assets/models/weapon_pistol.glb',
  Weapons.shotgun.name: 'assets/models/weapon_shotgun.glb',
};

/// One node per weapon, for [WeaponView].
///
/// **Two of the four are models now.** The pistol and the shotgun are
/// Quaternius', fetched and oriented by `tool/fetch_weapons.py`; the fists and
/// the rocket launcher are still procedural blocks, the fists because a pair of
/// hands is not a weapon model and the rocket launcher because no CC0 pack
/// searched had one. Deliberately not a placeholder cube each: distinguishable
/// silhouettes are what make the switch readable, which is the only thing this
/// view has to do for a weapon whose art has not arrived.
///
/// The rig around them — the scene, the camera at 55 degrees, the bob and the
/// recoil — is the bridge's. Only the shapes are here.
///
/// **Asynchronous because a model is.** The blocks alone needed nothing but a
/// device, and this used to be a plain function; a weapon that appeared a
/// second into the level would be a pistol that arrives after the first shot.
Future<Map<String, SceneNode>> dungeonWeaponModels(GraphicsDevice device) async {
  final models = <String, SceneNode>{
    // Two blocks for the fists, because one block in the corner of the screen
    // reads as a stray object rather than as a pair of hands.
    Weapons.fists.name: _assemble(device, <_Part>[
      _Part(Vector3(0.03, 0.0, 0.0), Vector3(0.13, 0.11, 0.16), _skin),
      _Part(Vector3(-0.26, -0.05, 0.05), Vector3(0.13, 0.11, 0.16), _skin),
    ]),
    Weapons.pistol.name: _assemble(device, <_Part>[
      _Part(Vector3(0.0, 0.0, -0.08), Vector3(0.052, 0.070, 0.25), _metal),
      _Part(Vector3(0.0, -0.09, 0.04), Vector3(0.048, 0.115, 0.085), _grip),
    ]),
    Weapons.shotgun.name: _assemble(device, <_Part>[
      _Part(Vector3(0.0, 0.01, -0.20), Vector3(0.065, 0.065, 0.46), _metal),
      _Part(Vector3(0.0, -0.06, 0.10), Vector3(0.055, 0.098, 0.19), _grip),
      _Part(Vector3(0.0, -0.06, -0.16), Vector3(0.062, 0.055, 0.14), _grip),
    ]),
    Weapons.rocketLauncher.name: _assemble(device, <_Part>[
      _Part(Vector3(0.0, 0.03, -0.24), Vector3(0.110, 0.110, 0.54), _metal),
      _Part(Vector3(0.0, -0.08, 0.06), Vector3(0.055, 0.110, 0.13), _grip),
      _Part(Vector3(0.0, 0.13, -0.10), Vector3(0.039, 0.047, 0.18), _grip),
    ]),
  };

  for (final entry in kWeaponModels.entries) {
    // **The blocks stay if a model will not load.** A weapon the player cannot
    // see is a weapon they cannot tell they are holding, and the block that was
    // good enough yesterday is a better answer than an empty hand.
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(entry.value)),
      );
      final asset = await ModelAsset.fromDocument(
        document,
        device: device,
        name: entry.value,
      );
      // Instantiated into a scene of its own, which is thrown away: the node is
      // what is wanted, and `WeaponView` parents it under its own holder.
      models[entry.key] = asset.instantiate(Scene(), name: entry.key).root
        ..removeFromParent();
    } catch (error) {
      debugPrint('weapon: ${entry.key} staying blocks ($error)');
    }
  }
  return models;
}

// Metallic at last, and the comment it replaces is worth keeping in mind: this
// used to be a dark dielectric *pretending* to be gunmetal, because a metal
// with nothing to reflect renders very nearly black and image-based lighting
// was out of reach. It is not out of reach now — see [studioEnvironment], which
// is what this reflects.
//
// Lighter than the dielectric it replaces: a metal's colour is its reflectance,
// not its diffuse albedo, and gunmetal reflects a good deal more than 0.30.
final Material _metal = Material(
  baseColor: Vector4(0.56, 0.57, 0.60, 1.0),
  metallic: 1.0,
  roughness: 0.35,
  lighting: LightingModel.pbr,
);
final Material _grip = Material(
  baseColor: Vector4(0.29, 0.21, 0.16, 1.0),
  roughness: 0.75,
);
final Material _skin = Material(
  baseColor: Vector4(0.52, 0.36, 0.28, 1.0),
  roughness: 0.7,
);

SceneNode _assemble(GraphicsDevice device, List<_Part> parts) {
  final root = SceneNode();
  for (final part in parts) {
    root.add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: part.size).build()),
        part.material,
      )..setPositionFrom(part.offset),
    );
  }
  return root;
}

final class _Part {
  _Part(this.offset, this.size, this.material);

  final Vector3 offset;
  final Vector3 size;
  final Material material;
}
