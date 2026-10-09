part of 'arcade_game.dart';

/// Which Kenney craft plays which part.
enum CraftRole { ship, patrol, hunter }

/// A Space Kit craft as this game fits it.
final class _CraftLook {
  const _CraftLook(this.file, this.length, this.accent);

  /// The asset, under `assets/models`.
  final String file;

  /// Nose to tail once fitted, in metres: about the depth of the collider
  /// it stands for, so what is drawn is what can be hit.
  final double length;

  /// The colour the kit's orange accent material (`metalRed`) is given, so
  /// the three roles read apart: the kit draws every craft in one palette.
  final (double, double, double) accent;
}

const Map<CraftRole, _CraftLook> _looks = <CraftRole, _CraftLook>{
  CraftRole.ship: _CraftLook('assets/models/craft_speederD.glb', 1.0, (
    0.25,
    0.75,
    1.0,
  )),
  CraftRole.patrol: _CraftLook('assets/models/craft_miner.glb', 0.95, (
    1.0,
    0.55,
    0.15,
  )),
  CraftRole.hunter: _CraftLook('assets/models/craft_racer.glb', 0.95, (
    0.9,
    0.25,
    0.8,
  )),
};

/// The craft models, dressed onto the bodies the bridges already move.
///
/// **What a craft draws hangs from its component's `visual` node.** Until
/// [dressWithCrafts] has loaded the models, and always in the tests, which
/// never load them, that is the primitive the game was first written with;
/// the game's `ModelWardrobe` replaces it as each model arrives, including
/// on bots made while it was loading. A model that fails to load leaves the
/// primitive, so the game still plays.
///
/// [_turnCrafts] turns the visual node to face the way the craft is flying.
/// The bridged node is left unturned: a bridge leads it and reads its
/// rotation back into the Flame component's `angle` every frame, and a body
/// has no rotation of its own to give it. The visual node is below anything
/// a bridge looks at, so it can turn freely.
extension ArcadeGameCrafts on ArcadeGame {
  /// Loads the three craft and dresses the ship and every bot in play.
  /// Bots spawned later are dressed as they are made.
  Future<void> dressWithCrafts() => wardrobe.load(
    onError: (role, error) =>
        debugPrint('arcade: ${_looks[role]!.file} did not load ($error)'),
  );

  /// Gives a craft that has just been dressed its role's accent colour: the
  /// kit draws every craft in one palette, and its orange accent material
  /// (`metalRed`) is what tells the three roles apart.
  void _paintAccent(ModelInstance instance, CraftRole role) {
    final (r, g, b) = _looks[role]!.accent;
    instance.root.traverse((SceneNode node) {
      if (node is MeshNode && node.material.name == 'metalRed') {
        node.material.baseColor = LinearColor.fromSrgb(r, g, b, 1.0);
      }
    });
  }

  /// Turns every dressed craft to face the way it is flying: the ship by
  /// [ArcadeGame.shipHeading], a bot by its body's velocity. A craft
  /// barely moving keeps the way it last faced rather than spinning to
  /// whatever the noise in its velocity says.
  void _turnCrafts() {
    _turnTowards(ship, shipHeading);
    for (final bot in bots) {
      final body = bot.actor.body;
      if (body != null) _turnTowards(bot, body.velocity);
    }
  }

  void _turnTowards(Object3dComponent craft, Vector3 course) {
    if (course.x * course.x + course.z * course.z < 0.04) return;
    // The model's nose is along -Z; this turns -Z onto the course.
    final yaw = math.atan2(-course.x, -course.z);
    craft.visual.setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw));
  }
}
