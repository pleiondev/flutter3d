import 'package:flutter3d/flutter3d.dart'
    show Material, MeshNode, SphereShape, TextureHandle;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:vector_math/vector_math.dart';

/// What this game's furniture looks like.
///
/// The bridge places every fixture, keeps its node on its collider and drives
/// the lights; what a coin looks like, whether it spins and whether a collected
/// one is still there are decided here, because they are decisions about a
/// platformer rather than about drawing.
final class PlatformerLooks implements FixtureAppearance {
  const PlatformerLooks();

  /// A lamp: a glowing globe on a post, with a flame the game feeds.
  ///
  /// It used to return null for everything, on the grounds that a level lit by
  /// its own lights needs no fixtures — true, and it left `LightFixture`,
  /// `FlameFlicker` and the whole particle path unused. A maze with five
  /// hundred metres of corridor in it is exactly where a light you can see the
  /// source of earns its place.
  @override
  TorchFire? buildLightFixture(LightFixtureBuild build) {
    final size = build.fixture.size;
    build.holder
      ..add(
        MeshNode(
          build.meshes.shape(
            'globe${size.x}',
            () => SphereShape(radius: size.x * 0.5),
          ),
          build.glow,
          name: 'globe',
        ),
      )
      ..add(
        MeshNode(
          build.meshes.box(Vector3(size.x * 0.28, size.y, size.z * 0.28)),
          LevelLoader.materialFrom(
            LevelMaterial(
              baseColor: Vector4(0.22, 0.20, 0.18, 1.0),
              roughness: 0.6,
              metallic: 0.7,
            ),
            const <String, TextureHandle?>{},
            name: 'lamp post',
          ),
          name: 'post',
        )..setPosition(0.0, -size.y * 0.5, 0.0),
      );
    // Just clear of the globe, so the flame is not inside its own glass.
    return TorchFire(build.holder, rise: size.y * 0.25);
  }

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

  /// How long a collected coin takes to shrink away.
  ///
  /// Three hundred milliseconds. A second read as the coin dawdling: by the
  /// time it had gone the player was two coins further on, and a trail of
  /// half-sized coins behind them looked like the pickup had not registered.
  static const double _vanish = 0.3;

  /// A collected coin is gone **once it has finished shrinking**, not the
  /// instant it was taken — see [scaleOf].
  ///
  /// The `isTaken` half is not redundant, whatever it looks like: a coin that
  /// has never been picked up has `sinceTaken` of infinity, which is how it
  /// says *never*. Testing the clock alone made every uncollected coin in the
  /// level spent on the first frame, and a level with two hundred coins in it
  /// drew none of them.
  @override
  bool isSpent(Fixture fixture) {
    // A dead guard leaves the screen. `ActorSystem` turns a corpse's collider
    // into a trigger so it stops being an obstacle, and nothing was watching
    // that from the drawing side — so an enemy killed by a stomp stayed
    // standing there, and the player kept trying to jump on it.
    final who = fixture.collider?.userData;
    if (who is Actor) return !who.isAlive;

    final mechanism = fixture.mechanism;

    // **Geometry that has given way stops being drawn.** Five crumbling
    // shelves and three breakable caps in the big level kept their meshes after
    // their colliders left, so a player falls through a shelf that still looks
    // solid — the same shape of defect as the guard who stayed standing, and
    // the third time this question has been answered one type at a time.
    //
    // `isSpent` is the right question for both even though a crumbling shelf
    // comes *back*: the bridge answers it every frame and only sets `visible`,
    // so a shelf that returns is drawn again on the frame it returns.
    if (mechanism is Crumbling) return mechanism.hasFallen;
    if (mechanism is Breakable) return mechanism.isBroken;

    return mechanism is Collectible &&
        mechanism.isTaken &&
        mechanism.sinceTaken >= _vanish;
  }

  /// A taken coin shrinks to nothing over [_vanish] and then leaves.
  ///
  /// Eased rather than linear: a coin that shrinks at a constant rate looks
  /// like it is being deleted, and one that starts slowly and finishes fast
  /// looks like it went somewhere.
  @override
  double scaleOf(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is! Collectible || !mechanism.isTaken) return 1.0;
    final t = (mechanism.sinceTaken / _vanish).clamp(0.0, 1.0);
    return (1.0 - t) * (1.0 - t);
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
    //
    // **The strength, not the factor**, since a level material's `emissive`
    // began arriving as a strength over the base colour rather than being
    // dropped on the floor. Setting the factor here and leaving the 0.3 that
    // `fallbackFor` asks for standing multiplies the two, and the post got
    // dimmer the brighter it was told to be. The factor follows the colour
    // that was just written, so a green checkpoint glows green.
    material.emissive.setValues(
      material.baseColor.x,
      material.baseColor.y,
      material.baseColor.z,
    );
    material.emissiveStrength = reached ? 0.85 : 0.30;
  }
}
