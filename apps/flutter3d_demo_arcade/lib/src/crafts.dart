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
/// **A body is bridged through a holder, never through its model.** The
/// ship's and every drone's bridged node is an empty [SceneNode]; what it
/// draws is a child. Until [dressWithCrafts] has loaded the models, and
/// always in the tests, which never load them, that child is the primitive
/// the game was first written with. When a model arrives it replaces the
/// child, and the bridges, which only ever touched the holder, carry on
/// unchanged. A model that fails to load leaves the primitive, so the game
/// still plays.
///
/// Between holder and model sits a pivot that [_turnCrafts] turns to face
/// the way the craft is flying. The holder cannot be turned: the physics
/// bridge writes the body's own rotation into it every frame.
extension ArcadeGameCrafts on ArcadeGame {
  /// Loads the three craft and dresses the ship and every drone in play.
  /// Drones spawned later are dressed as they are made.
  Future<void> dressWithCrafts() async {
    for (final role in CraftRole.values) {
      final look = _looks[role]!;
      try {
        final document = await decodeModelInIsolate(
          ModelLoadRequest(source: BundleAssetSource(look.file)),
        );
        _crafts[role] = await ModelAsset.fromDocument(
          document,
          device: _device,
          name: look.file,
        );
      } catch (error) {
        debugPrint('arcade: ${look.file} did not load ($error)');
      }
    }
    _dress(ship.node, CraftRole.ship);
    for (final drone in drones) {
      final role = _holderRoles[drone.node];
      if (role != null) _dress(drone.node, role);
    }
  }

  /// Puts [role]'s model in [holder] in place of whatever it drew before.
  /// Nothing happens while that model has not loaded.
  void _dress(SceneNode holder, CraftRole role) {
    final asset = _crafts[role];
    if (asset == null) return;
    final look = _looks[role]!;

    for (final child in holder.children) {
      child.removeFromParent();
    }
    final pivot = SceneNode(name: '${holder.name} pivot');
    holder.add(pivot);
    final instance = asset.instantiate(
      _scene,
      parent: pivot,
      name: '${holder.name} model',
    );

    // Centred on the holder and scaled to [_CraftLook.length]: the kit's
    // craft sit on the ground at an origin of their own, nose along -Z.
    final bounds = asset.localBounds;
    final length = bounds.max.z - bounds.min.z;
    final scale = length > 1e-6 ? look.length / length : 1.0;
    final centre = (bounds.min + bounds.max)..scale(0.5 * scale);
    instance.root
      ..setUniformScale(scale)
      ..setPosition(-centre.x, -centre.y, -centre.z);

    final (r, g, b) = look.accent;
    pivot.traverse((SceneNode node) {
      if (node is MeshNode && node.material.name == 'metalRed') {
        node.material.baseColor.setValues(r, g, b, 1.0);
      }
    });
    _pivots[holder] = pivot;
  }

  /// Turns every dressed craft to face the way it is flying: the ship by
  /// [ArcadeGame.shipHeading], a drone by its body's velocity. A craft
  /// barely moving keeps the way it last faced rather than spinning to
  /// whatever the noise in its velocity says.
  void _turnCrafts() {
    _turnTowards(ship.node, shipHeading);
    for (final drone in drones) {
      final body = drone.actor.body;
      if (body != null) _turnTowards(drone.node, body.velocity);
    }
  }

  void _turnTowards(SceneNode holder, Vector3 course) {
    final pivot = _pivots[holder];
    if (pivot == null) return;
    if (course.x * course.x + course.z * course.z < 0.04) return;
    // The model's nose is along -Z; this turns -Z onto the course.
    final yaw = math.atan2(-course.x, -course.z);
    pivot.setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw));
  }
}
