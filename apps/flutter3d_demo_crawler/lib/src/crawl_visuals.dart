/// The heroes, the horde and the shots, drawn.
///
/// **One instanced batch per kind of monster**, which is the whole reason the
/// horde is affordable: two hundred monsters of two kinds are two draws, not
/// two hundred. Each frame writes the living ones' transforms and sets the
/// count; a monster that died this step simply is not written, so nothing has
/// to be told to go away.
///
/// The heroes are four nodes of their own, each a capsule in its class's
/// colour with a nose that points the way they face — the way they shoot.
///
/// Nothing here decides anything: it reads the simulation after a step and
/// moves pictures to match.
library;

import 'dart:math' as math;

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

vm.Vector4 _monsterColour(MonsterKind kind) => switch (kind.name) {
  'grunt' => vm.Vector4(0.45, 0.35, 0.30, 1.0),
  'ghost' => vm.Vector4(0.80, 0.85, 0.95, 1.0),
  'death' => vm.Vector4(0.08, 0.06, 0.10, 1.0),
  'thief' => vm.Vector4(0.55, 0.30, 0.65, 1.0),
  _ => vm.Vector4(0.6, 0.2, 0.2, 1.0),
};

Material _flat(vm.Vector4 colour, String name, {double glow = 0.0}) =>
    LevelLoader.materialFrom(
      LevelMaterial(baseColor: colour, roughness: 0.7, emissive: glow),
      const <String, TextureHandle?>{},
      name: name,
    );

final class CrawlVisuals {
  CrawlVisuals({
    required GraphicsDevice device,
    required List<Hero> heroes,
    List<MonsterKind> kinds = MonsterKind.all,
    this.capacity = 256,
  }) {
    for (final kind in kinds) {
      final batch = InstancedMeshNode(
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
        capacity: capacity,
        name: kind.name,
      );
      for (var i = 0; i < capacity; i++) {
        batch.addInstance(vm.Matrix4.identity());
      }
      batch.count = 0;
      _batches[kind] = batch;
    }

    final body = DeviceMesh.upload(
      device,
      const CapsuleShape(radius: 0.35, height: 1.1).build(),
    );
    final nose = DeviceMesh.upload(
      device,
      CuboidShape(size: vm.Vector3(0.18, 0.18, 0.45)).build(),
    );
    for (final hero in heroes) {
      final colour = colourOf(hero.kind);
      final node = MeshNode(body, _flat(colour, hero.kind.name), name: 'hero')
        ..add(
          MeshNode(nose, _flat(colour, 'nose', glow: 0.6), name: 'nose')
            ..setPosition(0.0, 0.3, -0.4),
        );
      _heroes[hero] = node;
    }

    _bolts = InstancedMeshNode(
      DeviceMesh.upload(device, const SphereShape(radius: 0.14).build()),
      _flat(vm.Vector4(1.0, 0.9, 0.6, 1.0), 'bolt', glow: 1.2),
      capacity: capacity,
      name: 'bolts',
    );
    for (var i = 0; i < capacity; i++) {
      _bolts.addInstance(vm.Matrix4.identity());
    }
    _bolts.count = 0;
  }

  /// How many of one kind, and how many shots, can be drawn at once.
  final int capacity;

  final Map<MonsterKind, InstancedMeshNode> _batches =
      <MonsterKind, InstancedMeshNode>{};
  final Map<Hero, MeshNode> _heroes = <Hero, MeshNode>{};
  late final InstancedMeshNode _bolts;

  final vm.Matrix4 _transform = vm.Matrix4.identity();
  final Map<MonsterKind, int> _drawn = <MonsterKind, int>{};

  /// Puts everything into [scene].
  void addTo(Scene scene) {
    _batches.values.forEach(scene.add);
    _heroes.values.forEach(scene.add);
    scene.add(_bolts);
  }

  /// Brings the picture up to date with [sim] and its [horde].
  void sync(CrawlerSimulation sim, Horde horde) {
    _drawn.clear();
    for (final monster in horde.monsters) {
      final kind = horde.kindOf(monster);
      final at = monster.position;
      final batch = _batches[kind];
      if (kind == null || at == null || batch == null) continue;
      final index = _drawn[kind] ?? 0;
      if (index >= batch.capacity) continue;
      _transform
        ..setIdentity()
        ..setTranslationRaw(at.x, at.y, at.z)
        ..rotateY(monster.yaw);
      batch.setTransform(index, _transform);
      _drawn[kind] = index + 1;
    }
    for (final MapEntry(key: kind, value: batch) in _batches.entries) {
      batch.count = _drawn[kind] ?? 0;
    }

    for (final MapEntry(key: hero, value: node) in _heroes.entries) {
      node.visible = hero.isAlive;
      if (!hero.isAlive) continue;
      node
        ..setPositionFrom(hero.position)
        ..setRotationYawPitchRoll(
          math.atan2(-hero.facing.x, -hero.facing.z),
          0.0,
          0.0,
        );
    }

    var shots = 0;
    for (final bolt in sim.volley.bolts) {
      if (shots >= _bolts.capacity) break;
      _transform
        ..setIdentity()
        ..setTranslationRaw(bolt.at.x, bolt.at.y, bolt.at.z);
      _bolts.setTransform(shots++, _transform);
    }
    _bolts.count = shots;
  }
}
