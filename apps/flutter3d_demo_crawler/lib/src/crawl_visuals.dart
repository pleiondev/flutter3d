/// What the heroes, the horde and the shots are drawn with.
///
/// Only the meshes and the colours: placing them each frame is the bridge's —
/// `CharacterBodyComponent` for a hero, `InstancedActorComponent` for a
/// monster, `InstancedPoseComponent` for a shot — so nothing here reads the
/// simulation.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// How a crawl is drawn: one shadow map over the whole level.
///
/// **One cascade, not three.** Cascades are for a view that runs from the
/// player's feet to the horizon; this one looks down on a floor that is all
/// about the same distance away, so the near cascades buy no sharpness — and
/// on Metal they drew a black disc on the floor around the foot of the camera
/// once the party walked south. The CPU backend draws the same frames clean,
/// so the fault is in the GPU path of the near cascades and is the engine's to
/// find; a level forty metres across in a 2048 map is two centimetres a texel
/// either way.
const RenderSettings crawlRenderSettings = RenderSettings(
  shadows: ShadowSettings(cascades: 1, resolution: 2048),
);

/// The colour a class is drawn in, on the floor and on the HUD.
vm.Vector4 colourOf(HeroClass kind) => switch (kind.name) {
  'warrior' => vm.Vector4(0.85, 0.25, 0.20, 1.0),
  'valkyrie' => vm.Vector4(0.30, 0.55, 0.95, 1.0),
  'wizard' => vm.Vector4(0.95, 0.85, 0.30, 1.0),
  'elf' => vm.Vector4(0.35, 0.85, 0.40, 1.0),
  _ => vm.Vector4(0.8, 0.8, 0.8, 1.0),
};

/// Colours that stand off a brown floor, the grunts most of all: drawn brown
/// they were the colour of the pillars.
vm.Vector4 _monsterColour(MonsterKind kind) => switch (kind.name) {
  'grunt' => vm.Vector4(0.62, 0.18, 0.55, 1.0),
  'ghost' => vm.Vector4(0.85, 0.90, 1.0, 1.0),
  'death' => vm.Vector4(0.06, 0.05, 0.08, 1.0),
  'thief' => vm.Vector4(0.15, 0.75, 0.80, 1.0),
  _ => vm.Vector4(0.6, 0.2, 0.2, 1.0),
};

Material _flat(vm.Vector4 colour, String name, {double glow = 0.0}) =>
    LevelLoader.materialFrom(
      LevelMaterial(baseColor: colour, roughness: 0.7, emissive: glow),
      const <String, TextureHandle?>{},
      name: name,
    );

/// One batch per kind of monster: two hundred of them are as many draws as
/// there are kinds.
InstancedMeshNode monsterBatch(GraphicsDevice device, MonsterKind kind) =>
    InstancedMeshNode(
      DeviceMesh.upload(
        device,
        CapsuleShape(
          radius: kind.radius,
          height: kind.height - 2.0 * kind.radius,
        ).build(),
      ),
      _flat(
        _monsterColour(kind),
        kind.name,
        glow: kind.name == 'ghost' ? 0.4 : 0.0,
      ),
      capacity: 64,
      name: kind.name,
    );

/// A hero: a capsule in its class's colour with a nose that points the way
/// they face, which is the way they shoot.
MeshNode heroFigure(GraphicsDevice device, HeroClass kind) {
  final colour = colourOf(kind);
  return MeshNode(
    DeviceMesh.upload(
      device,
      const CapsuleShape(radius: 0.35, height: 1.1).build(),
    ),
    _flat(colour, kind.name),
    name: kind.name,
  )..add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: vm.Vector3(0.18, 0.18, 0.45)).build(),
      ),
      _flat(colour, 'nose', glow: 0.6),
      name: 'nose',
    )..setPosition(0.0, 0.3, -0.4),
  );
}

/// The shots in the air, one batch.
InstancedMeshNode boltBatch(GraphicsDevice device) => InstancedMeshNode(
  DeviceMesh.upload(device, const SphereShape(radius: 0.14).build()),
  _flat(vm.Vector4(1.0, 0.9, 0.6, 1.0), 'bolt', glow: 1.2),
  capacity: 64,
  name: 'bolts',
);
