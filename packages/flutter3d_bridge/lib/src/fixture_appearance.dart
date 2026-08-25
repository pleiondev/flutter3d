import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

import 'shared_meshes.dart';

/// One torch's fire.
///
/// A [LightEmitter], so the particle system measures it — and the object the
/// emission is keyed on, which means the thing that burns and the thing that
/// is measured are the same thing rather than two that have to be kept in
/// step.
final class TorchFire with LightEmitter {
  TorchFire(this.origin, {this.rise = 0.0});

  /// The node the flame rises from, read every frame so the fire is wherever
  /// the mesh ended up.
  final SceneNode origin;

  /// How far above that node's own position the flame actually starts.
  ///
  /// A number rather than a second transform: the offset is "just clear of the
  /// rim", and the rim belongs to whoever modelled the fixture.
  final double rise;

  /// Where the fire is, in world space.
  ///
  /// From the node's own transform, so the flame is wherever the level's yaw
  /// put the thing holding it. Recomputing it from the yaw instead is a second
  /// copy of the placement and a second chance to put the fire inside the wall,
  /// which is what the first version did.
  Vector3 originInto(Vector3 out) {
    final world = origin.worldMatrix;
    out.setValues(world.entry(0, 3), world.entry(1, 3), world.entry(2, 3));
    return out..y += rise;
  }
}

/// Everything the bridge has already decided by the time a silhouette is built.
///
/// Handed to [FixtureAppearance.buildLightFixture] so the game can hang meshes
/// off a node that is already positioned, turned and in the scene, and use a
/// glow material that is already wired to the simulation's brightness.
final class LightFixtureBuild {
  LightFixtureBuild({
    required this.fixture,
    required this.mechanism,
    required this.holder,
    required this.glow,
    required this.meshes,
  });

  final Fixture fixture;
  final LightFixture mechanism;

  /// Already placed, already turned by the entity's yaw, already in the scene.
  /// Parent every part to this and think in local space.
  final SceneNode holder;

  /// Emissive, tinted by the entity's colour, and driven every frame by
  /// [LightFixture.brightness]. Use it for the parts that are supposed to look
  /// hot; anything else needs a material of the game's own.
  final Material glow;

  /// Shared with every other fixture in the level. Ask it for boxes and
  /// cylinders rather than uploading a mesh per torch.
  final SharedMeshes meshes;
}

/// The half of a fixture's look that only the game can know.
///
/// [FixtureVisuals] owns the mechanism — placement, caches, the model loader,
/// the material override, and driving the glow and the light off one brightness
/// number. What a torch actually looks like is not mechanism: it is the
/// difference between a torch and a lamp and a window, and it is decided here.
abstract interface class FixtureAppearance {
  /// Builds the visible parts of a light fixture under [LightFixtureBuild.holder].
  ///
  /// Returns the fire it produced, or null for a fixture that glows without
  /// burning — a window, a lamp behind glass.
  TorchFire? buildLightFixture(LightFixtureBuild build);

  /// Something visible for a fixture whose material the level did not name.
  ///
  /// A game that would rather see nothing can return a flat colour; a game with
  /// keys and buttons will want to tell them apart at a distance.
  LevelMaterial fallbackFor(Fixture fixture);

  /// Whether the fixture is used up and should not be drawn at all.
  ///
  /// This and [spins] used to be one line each of `mechanism is Pickup` in
  /// [FixtureVisuals.sync], which is how the bridge came to know what a pickup
  /// was. Both questions are about *this game's* furniture: a collected medkit
  /// disappears, a racing game's checkpoint does not, and neither fact is the
  /// renderer's or the simulation's to hold.
  bool isSpent(Fixture fixture);

  /// How big to draw a fixture right now, as a fraction of its size.
  ///
  /// One for almost everything. It exists because a collected coin that simply
  /// stops being drawn reads as a rendering glitch — the eye needs a moment to
  /// connect the sound to the thing that made it — and a shrink is the cheapest
  /// honest way to give it one.
  ///
  /// [isSpent] stays the question "is it gone", and a game that shrinks
  /// something answers *that* only once the shrink has finished. The two are
  /// separate so a fixture can be invisible without being over, and over
  /// without ever having shrunk.
  double scaleOf(Fixture fixture);

  /// Whether it turns on the spot.
  ///
  /// The oldest trick in the genre, and it works for the same reason it always
  /// did: a thing that moves in a still room is a thing the player walks over
  /// to. Still a decision about furniture rather than about drawing.
  bool spins(Fixture fixture);

  /// A chance to change how a fixture looks, once a frame.
  ///
  /// [fallbackFor] is asked once, when the node is built, which is right for
  /// "what colour is a key" and wrong for anything whose look depends on what
  /// has happened. A checkpoint is the case that forced this: it was built
  /// blue, turned green in the code and stayed blue on the screen, so the one
  /// thing it exists to tell the player — *you have got this far* — it never
  /// said.
  ///
  /// The material handed over belongs to this fixture alone, so changing it
  /// changes nothing else. Fixtures drawn from a loaded model are not offered,
  /// because their materials belong to the model and are shared with every
  /// other copy of it.
  void refresh(Fixture fixture, Material material);
}
