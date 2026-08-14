import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter3d_game/sample.dart';

/// One node per weapon, for [WeaponView].
///
/// Procedural blocks, because there is no weapon art yet. Deliberately not a
/// placeholder cube each: distinguishable silhouettes are what make the switch
/// readable, which is the only thing this view has to do before the models
/// arrive.
///
/// The rig around them — the scene, the camera at 55 degrees, the bob and the
/// recoil — is the bridge's. Only the shapes are here.
Map<String, SceneNode> dungeonWeaponModels(GraphicsDevice device) {
  return <String, SceneNode>{
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
}

// Not actually metallic, despite the name and despite being a gun barrel.
// A metallic surface reflects its surroundings and has almost no diffuse
// response, so with no environment map to reflect it renders very nearly
// black — which is exactly how the first version looked. Image-based lighting
// would fix it properly and is out of reach on this channel, since it needs
// mip levels. A dark dielectric reads as gunmetal and costs nothing.
final Material _metal = Material(
  baseColor: Vector4(0.30, 0.31, 0.34, 1.0),
  roughness: 0.45,
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
