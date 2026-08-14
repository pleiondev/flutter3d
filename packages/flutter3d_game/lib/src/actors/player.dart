/// Who the player's collider is.
///
/// ## The field this untangles
///
/// `Collider.userData` answers "who is this?" — a monster, a door, a pickup,
/// a brush. The player's collider answered something else: it carried the
/// player's `Inventory`, which is not who the collider is but what the body is
/// holding. One untyped field with two different relations in it, and the
/// consequences were two: every place that dealt damage had to test the
/// collider's *layer* for the player while testing `userData` for a monster,
/// and a locked door asking what keys the body holds worked only because
/// `Inventory` happened to be a `KeyHolder`.
///
/// A player is a body, and the body carries an inventory. Saying that directly
/// costs one class and removes both special cases: `userData` is the player,
/// the player is `Damageable`, and the player is a `KeyHolder` because the
/// person holding the keys is the person, not their pockets.
///
/// ## What is deliberately not here yet
///
/// Where the player is *looking*. Yaw, pitch, eye height and the aim vector
/// still belong to the application, which is the next thing to fix and a larger
/// one: the aim vector is written out three times there. This class is the
/// place they will land, and it is useful before they do.
library;

import '../physics/layers.dart';
import '../world/inventory.dart';
import '../world/key_ring.dart';
import 'damageable.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';

final class Player with KeyHolder implements Damageable {
  Player({required this.body, Inventory? inventory})
      : inventory = inventory ?? Inventory() {
    // The one line that makes this worth having: from here on, "who is this
    // collider" has one answer for every collider in the world.
    body.collider.userData = this;
    body.collider.layer = CollisionLayers.player;
  }

  /// The capsule that walks, jumps and rides lifts.
  final CharacterController body;

  /// What is being carried: health, armour, weapons, keys, power-ups.
  final Inventory inventory;

  /// The keys the *person* holds.
  ///
  /// Forwarded rather than inherited from the inventory so that
  /// `MechanismWorld.activationBy` — which asks whether a collider's owner is a
  /// [KeyHolder] — keeps working unchanged. It used to find the inventory
  /// itself there, which was right by accident.
  @override
  Set<String> get keys => inventory.keys;

  @override
  bool applyDamage(double amount) => inventory.damage(amount);

  bool get isAlive => inventory.health.isAlive;
}
