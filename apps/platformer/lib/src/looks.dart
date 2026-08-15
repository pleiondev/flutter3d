import 'package:flutter3d/flutter3d.dart' show Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:vector_math/vector_math.dart';

/// What this game's furniture looks like.
///
/// The bridge places every fixture, keeps its node on its collider and drives
/// the lights; what a coin looks like, whether it spins and whether a collected
/// one is still there are decided here, because they are decisions about a
/// platformer rather than about drawing.
final class PlatformerLooks implements FixtureAppearance {
  const PlatformerLooks();

  /// This game has no torches. Returning null is a fixture that glows without
  /// burning, which is the whole of the answer for a level lit by its lights.
  @override
  TorchFire? buildLightFixture(LightFixtureBuild build) => null;

  @override
  LevelMaterial fallbackFor(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is Collectible) {
      return LevelMaterial(
        baseColor: Vector4(0.98, 0.80, 0.22, 1.0),
        roughness: 0.25,
        metallic: 0.8,
        emissive: 0.35,
      );
    }
    if (mechanism is Hazard) {
      // Red, and lit from inside: a hazard the player cannot see coming is a
      // hazard that reads as the game cheating.
      return LevelMaterial(
        baseColor: Vector4(0.75, 0.13, 0.10, 1.0),
        roughness: 0.6,
        emissive: 0.5,
      );
    }
    if (mechanism is Checkpoint) {
      return LevelMaterial(
        baseColor: mechanism.isReached
            ? Vector4(0.35, 0.85, 0.45, 1.0)
            : Vector4(0.35, 0.45, 0.85, 1.0),
        roughness: 0.4,
        emissive: 0.3,
      );
    }
    if (mechanism is Exit) {
      return LevelMaterial(
        baseColor: Vector4(0.95, 0.95, 0.85, 1.0),
        roughness: 0.3,
        emissive: 0.7,
      );
    }
    return LevelMaterial(baseColor: Vector4(0.55, 0.52, 0.48, 1.0));
  }

  /// A collected coin is gone, and the node with it.
  @override
  bool isSpent(Fixture fixture) {
    final mechanism = fixture.mechanism;
    return mechanism is Collectible && mechanism.isTaken;
  }

  /// Coins turn. Nothing else does.
  @override
  bool spins(Fixture fixture) => fixture.mechanism is Collectible;

  /// A checkpoint is blue until it is yours, and green after.
  ///
  /// Asked every frame rather than once at spawn, because the whole job of the
  /// thing is to answer a question that changes. Built once, it stayed blue for
  /// ever and a player reasonably asked what the purple post was for.
  @override
  void refresh(Fixture fixture, Material material) {
    final mechanism = fixture.mechanism;
    if (mechanism is! Checkpoint) return;
    final reached = mechanism.isReached;
    material.baseColor.setValues(
      reached ? 0.30 : 0.45,
      reached ? 0.85 : 0.35,
      reached ? 0.45 : 0.95,
      1.0,
    );
    // Brighter once it is yours, so it reads across a room and not only up
    // close, where a colour change is easy to miss mid-jump.
    final glow = reached ? 0.85 : 0.30;
    material.emissive.setValues(glow, glow, glow);
  }
}
