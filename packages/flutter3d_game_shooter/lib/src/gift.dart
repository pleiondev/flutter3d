import 'combat/weapon.dart';
import 'inventory.dart';

/// Something a pickup gives.
///
/// A hierarchy rather than an enum with a switch, for the same reason
/// [EntityKind] is one: every job that treats gifts differently — granting
/// them, wording the message, drawing the editor's dropdown — would otherwise
/// grow its own switch over the same eight names in a different file, and the
/// switches drift.
///
/// Refusal is the interesting part of the interface. A medkit walked over at
/// full health must stay on the floor, because a player who is about to be hurt
/// wants to come back for it; a pickup that vanished into a full pool is a
/// pickup the level lied about.
abstract base class Gift {
  const Gift(this.name);

  /// The word a level document uses in a pickup's `gives`.
  final String name;

  /// Grants this to [to]. False when it would do nothing, and the pickup then
  /// stays where it is.
  bool grantTo(Inventory to, double amount, String? detail);

  /// What to tell the player. Null says nothing.
  String? announce(double amount, String? detail) => null;

  /// What a level should give when it does not say.
  double get defaultAmount => 1.0;
}

final class HealthGift extends Gift {
  const HealthGift() : super('health');

  @override
  double get defaultAmount => 25.0;

  @override
  bool grantTo(Inventory to, double amount, String? detail) =>
      to.health.heal(amount) > 0.0;

  @override
  String? announce(double amount, String? detail) =>
      'Picked up ${amount.round()} health.';
}

final class ArmourGift extends Gift {
  const ArmourGift() : super('armour');

  @override
  double get defaultAmount => 50.0;

  @override
  bool grantTo(Inventory to, double amount, String? detail) =>
      to.addArmour(amount) > 0.0;

  @override
  String? announce(double amount, String? detail) =>
      'Picked up ${amount.round()} armour.';
}

/// One class for all three ammunition types, because they differ only in which
/// pouch they fill.
final class AmmoGift extends Gift {
  const AmmoGift(super.name, this.type, {required this.defaultAmount});

  final AmmoType type;

  @override
  final double defaultAmount;

  @override
  bool grantTo(Inventory to, double amount, String? detail) =>
      to.arsenal.addAmmo(type, amount.round()) > 0;

  @override
  String? announce(double amount, String? detail) =>
      'Picked up ${amount.round()} $name.';
}

/// A key, whose colour is the pickup's own `color` rather than the gift's.
final class KeyGift extends Gift {
  const KeyGift() : super('key');

  @override
  bool grantTo(Inventory to, double amount, String? detail) {
    if (detail == null) return false;
    return to.keyRing.take(detail);
  }

  @override
  String? announce(double amount, String? detail) =>
      detail == null ? null : 'Picked up the $detail key.';
}

/// Runs out, rather than filling a pool.
final class PowerUpGift extends Gift {
  const PowerUpGift(super.name, {required this.defaultAmount});

  /// Seconds.
  @override
  final double defaultAmount;

  @override
  bool grantTo(Inventory to, double amount, String? detail) {
    // Refreshing rather than stacking: two medkits are twice the health, two
    // invulnerabilities are not two minutes of it.
    to.empower(name, amount);
    return true;
  }

  @override
  String? announce(double amount, String? detail) =>
      '$name for ${amount.round()} seconds.';
}

/// The gifts a build knows about, by the name a document uses.
final class GiftRegistry {
  GiftRegistry(Iterable<Gift> gifts)
      : _byName = <String, Gift>{for (final gift in gifts) gift.name: gift};

  final Map<String, Gift> _byName;

  Gift? operator [](String name) => _byName[name];

  Iterable<String> get names => _byName.keys;

  bool knows(String name) => _byName.containsKey(name);
}
