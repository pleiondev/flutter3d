/// What the crawl's furniture looks like from above.
///
/// Colour does all the work: from twenty metres up a key is a speck, and a
/// speck is told apart by being gold. Loot turns on the spot, because a thing
/// that moves in a still room is a thing a player walks to.
library;

import 'package:flutter3d/flutter3d.dart' show Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class CrawlerLooks implements FixtureAppearance {
  const CrawlerLooks();

  @override
  TorchFire? buildLightFixture(LightFixtureBuild build) => null;

  @override
  LevelMaterial fallbackFor(Fixture fixture) => switch (fixture.mechanism) {
    Food() => LevelMaterial(
      baseColor: Vector4(0.55, 0.78, 0.30, 1.0),
      roughness: 0.6,
      emissive: 0.25,
    ),
    DoorKey() => LevelMaterial(
      baseColor: Vector4(0.98, 0.78, 0.22, 1.0),
      roughness: 0.25,
      metallic: 0.8,
      emissive: 0.45,
    ),
    Potion() => LevelMaterial(
      baseColor: Vector4(0.30, 0.55, 1.0, 1.0),
      roughness: 0.2,
      emissive: 0.6,
    ),
    Treasure() => LevelMaterial(
      baseColor: Vector4(0.95, 0.85, 0.45, 1.0),
      roughness: 0.3,
      metallic: 0.9,
      emissive: 0.3,
    ),
    Generator() => LevelMaterial(
      baseColor: Vector4(0.45, 0.10, 0.12, 1.0),
      roughness: 0.7,
      emissive: 0.35,
    ),
    Exit() => LevelMaterial(
      baseColor: Vector4(0.95, 0.95, 0.85, 1.0),
      roughness: 0.3,
      emissive: 0.8,
    ),
    _ => LevelMaterial(baseColor: Vector4(0.55, 0.52, 0.48, 1.0)),
  };

  @override
  bool isSpent(Fixture fixture) => switch (fixture.mechanism) {
    final Loot loot => loot.isTaken,
    final Generator generator => generator.isDestroyed,
    _ => false,
  };

  @override
  double scaleOf(Fixture fixture) => 1.0;

  @override
  bool spins(Fixture fixture) => fixture.mechanism is Loot;

  /// A generator glows less the closer it is to breaking, so a player can see
  /// their shots doing something to it.
  @override
  void refresh(Fixture fixture, Material material) {
    final mechanism = fixture.mechanism;
    if (mechanism is! Generator) return;
    final left = mechanism.health.current / mechanism.health.maximum;
    material.emissive.setValues(0.5 * left, 0.08 * left, 0.08 * left);
  }
}
