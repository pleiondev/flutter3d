import 'combat/weapon.dart';
import 'inventory.dart';

/// Something a pickup gives.
///
/// A hierarchy rather than an enum with a switch, for the same reason
/// `EntityKind` is one: every job that treats gifts differently — granting
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

  /// What to tell the player, as a message a game words in its own
  /// language; null says nothing. See [GiftAnnouncement].
  GiftAnnouncement? announce(double amount, String? detail) => null;

  /// What a level should give when it does not say.
  /// In the gift's own unit: hit points, armour points or rounds.
  double get defaultAmount => 1.0;
}

final class HealthGift extends Gift {
  const HealthGift() : super('health');

  /// In hit points (unitless).
  @override
  double get defaultAmount => 25.0;

  @override
  bool grantTo(Inventory to, double amount, String? detail) =>
      to.health.heal(amount) > 0.0;

  @override
  GiftAnnouncement? announce(double amount, String? detail) =>
      GiftAnnouncement(GiftAnnouncement.pickedUp, gift: name, amount: amount);
}

final class ArmorGift extends Gift {
  const ArmorGift() : super('armour');

  /// In armour points (unitless).
  @override
  double get defaultAmount => 50.0;

  @override
  bool grantTo(Inventory to, double amount, String? detail) =>
      to.addArmor(amount) > 0.0;

  @override
  GiftAnnouncement? announce(double amount, String? detail) =>
      GiftAnnouncement(GiftAnnouncement.pickedUp, gift: name, amount: amount);
}

/// One class for all three ammunition types, because they differ only in which
/// pouch they fill.
final class AmmoGift extends Gift {
  const AmmoGift(super.name, this.type, {required this.defaultAmount});

  final AmmoType type;

  /// In rounds: a count.
  @override
  final double defaultAmount;

  @override
  bool grantTo(Inventory to, double amount, String? detail) =>
      to.arsenal.addAmmo(type, amount.round()) > 0;

  @override
  GiftAnnouncement? announce(double amount, String? detail) =>
      GiftAnnouncement(GiftAnnouncement.pickedUp, gift: name, amount: amount);
}

/// A key, whose colour is the pickup's own `color` rather than the gift's.
final class KeyGift extends Gift {
  const KeyGift() : super('key');

  @override
  bool grantTo(Inventory to, double amount, String? detail) {
    if (detail == null) return false;
    return to.keyRing.add(detail);
  }

  @override
  GiftAnnouncement? announce(double amount, String? detail) => detail == null
      ? null
      : GiftAnnouncement(GiftAnnouncement.key, gift: name, detail: detail);
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
  GiftAnnouncement? announce(double amount, String? detail) =>
      GiftAnnouncement(GiftAnnouncement.poweredUp, gift: name, amount: amount);
}

/// What a [Gift] tells the player it gave: a message id and what fills it in,
/// worded by the game.
///
/// **Not a sentence.** `announce` returned English until 1.0, and a game in
/// any other language had to parse it back apart or say nothing. The words
/// belong where the language is known — the screen that shows the message —
/// and this carries what that screen needs: which message ([id]), which gift
/// ([gift], the document's word), how much ([amount]) and which one
/// ([detail], a key's colour). [english] is the wording the shooter always
/// had, for a log, a test and a game with no translations.
///
/// **An open set of ids**, so a game's own gift can say something the three
/// here do not: a [Gift] subclass returns its own id, and the game that wrote
/// it words it.
final class GiftAnnouncement {
  const GiftAnnouncement(
    this.id, {
    required this.gift,
    this.amount,
    this.detail,
  });

  /// "Picked up 25 health." — a pool filled by [amount] of [gift].
  static const String pickedUp = 'shooter.gift.pickedUp';

  /// "Picked up the red key." — the key of colour [detail].
  static const String key = 'shooter.gift.key';

  /// "berserk for 30 seconds." — [gift] running for [amount] seconds.
  static const String poweredUp = 'shooter.gift.poweredUp';

  /// Which message this is.
  final String id;

  /// The gift's word in a level document: `health`, `shells`, `berserk`.
  final String gift;

  /// How much was given: points, rounds or seconds, by [id].
  final double? amount;

  /// Which one, where a gift has kinds: a key's colour.
  final String? detail;

  /// The message in English, as the shooter has always worded it; for an id
  /// it does not know, the gift's word.
  String get english {
    final count = amount?.round();
    return switch (id) {
      pickedUp => 'Picked up $count $gift.',
      key => 'Picked up the $detail key.',
      poweredUp => '$gift for $count seconds.',
      _ => gift,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is GiftAnnouncement &&
      other.id == id &&
      other.gift == gift &&
      other.amount == amount &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(id, gift, amount, detail);

  @override
  String toString() => 'GiftAnnouncement($id, $gift, $amount, $detail)';
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
