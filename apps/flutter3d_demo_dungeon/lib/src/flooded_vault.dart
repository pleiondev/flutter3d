/// The first crypt's vault, flooded: a hand's depth of black water held in
/// by a stone sill at its door, fed by a culvert that spills down the far
/// wall and drained under the sill, so it is never quite still.
///
/// The water itself is the run's — see `CryptVault` in
/// `package:flutter3d_demo_content/crypt.dart`, which floods the room, and
/// the wading it slows. What is here draws it:
/// the surface and its falling sheet, the sill and the ledge as stone, the
/// culvert's mouth, and the torch the water mirrors. It reads the water and
/// writes nothing to it.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_content/crypt.dart' show CryptVault, FloodPlan;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

import 'wooden_props.dart';

/// The run's flooded vault, drawn into a level's scene.
final class FloodedVault {
  FloodedVault({
    required this.world,
    required this.vault,
    required ByteData liquidBundle,
    required this._device,
    required this._scene,
    required RenderMaterial stone,
    required bool light,
  }) {
    look = LiquidLook.of(liquidBundle)
      ..optics = murky
      // The crypt's air is still.
      ..wind = 0.0
      // A crypt has no sky: the water mirrors a dark vault, and its one sun
      // is a torch, which [update] turns to whichever flame the eye sees
      // mirrored in it. What it mirrors low down, at the grazing angles most
      // of the room is seen at, is torchlit stone, warm and many times
      // brighter than the vault's black ceiling, so the ripples, tipping the
      // mirrored ray between the two, show as a moving sheen.
      ..sun(along: Vector3(0.0, -0.5, 0.85), light: flameLight)
      ..sky(
        zenith: Vector3(0.012, 0.01, 0.008),
        horizon: Vector3(0.12, 0.08, 0.042),
      );
    view = LiquidView(
      world: world,
      liquid: vault.liquid,
      ground: vault.ground,
      device: _device,
      scene: _scene,
      look: look.material,
      detail: light ? _phoneDetail : _detail,
    );
    _build(stone);
  }

  /// The world the water is in: the run's.
  final NativeWorld world;

  /// The water, as the run has it.
  final CryptVault vault;
  FloodPlan get plan => vault.plan;

  final GraphicsDevice _device;
  final Scene _scene;

  /// The surface's look, and what draws it.
  late final LiquidLook look;
  late final LiquidView view;

  /// **Murky, not clear.** Standing water in a crypt is silt and leaf
  /// mould: nearly seven in a thousand of the light through a metre of it,
  /// so the flags show dimly through a hand's depth at the walker's feet
  /// and hardly at all across the room.
  static final LiquidOptics murky = LiquidOptics(
    absorb: Vector3.all(6.908),
    backscatter: Vector3(0.0417, 0.06273, 0.05571),
  );

  /// A torch's flame as the water's sun: its colour times its brightness,
  /// enough for its image in the water to burn as the flame does while the
  /// light it throws into the water's body stays a glimmer.
  static Vector3 get flameLight => Vector3(1.3, 0.62, 0.22);

  /// How much of the culvert's spill is drawn.
  ///
  /// **A hundred drops, not hundreds.** Where the spill lands it throws its
  /// drops along the same few arcs step after step, and with three hundred
  /// and sixty drawn they hung about the culvert's foot as strings of white
  /// beads a metre long; a hundred is the splash, and what is past them is
  /// still simulated. No mist: thirty litres a second falling a metre
  /// throws spray, not a cloud.
  static const LiquidDetail _detail = LiquidDetail(
    sheet: 1500,
    drops: 100,
    bubbles: 1200,
  );

  /// The same on a phone.
  static const LiquidDetail _phoneDetail = LiquidDetail(
    sheet: 800,
    drops: 50,
    bubbles: 400,
  );

  /// What this vault put into the scene beside its water, to be taken out
  /// with it.
  final List<MeshNode> _drawn = <MeshNode>[];

  void _build(RenderMaterial stone) {
    for (final (at, half) in vault.blocks) {
      final node = MeshNode(
        DeviceMesh.upload(_device, blockMesh(at, half, every: 1.2)),
        stone,
        name: 'vault stone',
      );
      _scene.add(node);
      _drawn.add(node);
    }
    // The culvert's mouth: a dark opening in the wall over the ledge.
    final mouth = MeshNode(
      DeviceMesh.upload(
        _device,
        blockMesh(
          Vector3(plan.x1 - 0.01, CryptVault.ledgeTop + 0.22, plan.culvertZ),
          Vector3(0.02, 0.2, 0.32),
        ),
      ),
      RenderMaterial(
        name: 'culvert',
        baseColor: LinearColor.fromSrgb(0.015, 0.014, 0.013, 1.0),
        roughness: 1.0,
      ),
      name: 'culvert mouth',
    );
    _scene.add(mouth);
    _drawn.add(mouth);
  }

  /// [dt] seconds on, [seconds] into the level, seen from [eye], with the
  /// water's sun turned to the torch [flames] about the level.
  void update(
    double dt, {
    required double seconds,
    required Vector3 eye,
    required Iterable<Vector3> flames,
  }) {
    look.update(seconds: seconds, eye: eye);
    view.update(dt);
    _mirror(eye, flames);
  }

  /// The look's one sun shone from the flame whose image the water shows
  /// [eye], onto the point of the surface the image is at.
  ///
  /// The material mirrors a sky and a sun, not the room; a sun fixed in
  /// one direction put its glint wherever that direction happened to fall,
  /// mostly nowhere the eye was looking. Aimed from the flame at its own
  /// image, the glint is drawn where the flame's reflection is, and the
  /// ripples break it into the trembling streak a torch makes on water.
  /// Of the flames in the vault itself, the nearest whose image lies on the
  /// water: the guard room's torch, behind the vault's west wall, is nearer
  /// the doorway than the vault's own, and the glint it was aimed from lay
  /// off to the side of the room where no torch could be mirrored.
  void _mirror(Vector3 eye, Iterable<Vector3> flames) {
    final over = eye.y - plan.level;
    if (over <= 0.0) return;
    final image = Vector3.zero();
    Vector3? shone;
    var nearest = double.infinity;
    for (final flame in flames) {
      final under = flame.y - plan.level;
      if (under <= 0.0 || !vault.covers(flame.x, flame.z)) continue;
      // Where the line from the eye to the flame mirrored under the
      // surface crosses it: as far along as the eye's height is of the
      // two heights together.
      final t = over / (over + under);
      final x = eye.x + (flame.x - eye.x) * t;
      final z = eye.z + (flame.z - eye.z) * t;
      final far = flame.distanceToSquared(eye);
      if (!vault.covers(x, z) || far >= nearest) continue;
      nearest = far;
      shone = flame;
      image.setValues(x, plan.level, z);
    }
    if (shone == null) return;
    look.sun(along: image - shone, light: flameLight);
  }

  /// Out of the scene, its meshes given back.
  void dispose() {
    view.dispose();
    for (final node in _drawn) {
      node.removeFromParent();
      final mesh = node.mesh;
      if (mesh is DeviceMesh) {
        _device
          ..releaseGeometry(mesh.vertices)
          ..releaseGeometry(mesh.indices);
      }
    }
    _drawn.clear();
  }
}
