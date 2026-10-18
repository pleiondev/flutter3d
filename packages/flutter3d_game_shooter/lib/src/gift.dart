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
  /// A gift a document names as [name].
  const Gift(this.name);

  /// The word a level document uses in a pickup's `gives`.
  final String name;

  /// Grants this to the grant's inventory. False when it would do nothing,
  /// and the pickup then stays where it is.
  bool grantTo(GiftGrant context);

  /// What to tell the player, as a message a game words in its own
  /// language; null says nothing. See [GiftAnnouncement].
  GiftAnnouncement? announce(GiftAnnounce context) => null;

  /// What a level should give when it does not say.
  /// In the gift's own unit: hit points, armour points or rounds.
  double get defaultAmount => 1.0;
}

/// Heals the taker by the amount, in hit points; refused at full health, so
/// the medkit stays on the floor.
final class HealthGift extends Gift {
  /// The gift, named `health` in a document.
  const HealthGift() : super('health');

  /// In hit points (unitless).
  @override
  double get defaultAmount => 25.0;

  @override
  bool grantTo(GiftGrant context) {
    final to = context.to;
    final amount = context.amount;
    return to.health.heal(amount) > 0.0;
  }

  @override
  GiftAnnouncement? announce(GiftAnnounce context) {
    final amount = context.amount;
    return GiftAnnouncement(
      GiftAnnouncement.pickedUp,
      gift: name,
      amount: amount,
    );
  }
}

/// Adds the amount to the taker's armour; refused when the armour is
/// already full.
final class ArmorGift extends Gift {
  /// The gift, named `armour` in a document.
  const ArmorGift() : super('armour');

  /// In armour points (unitless).
  @override
  double get defaultAmount => 50.0;

  @override
  bool grantTo(GiftGrant context) {
    final to = context.to;
    final amount = context.amount;
    return to.addArmor(amount) > 0.0;
  }

  @override
  GiftAnnouncement? announce(GiftAnnounce context) {
    final amount = context.amount;
    return GiftAnnouncement(
      GiftAnnouncement.pickedUp,
      gift: name,
      amount: amount,
    );
  }
}

/// One class for all three ammunition types, because they differ only in which
/// pouch they fill.
final class AmmoGift extends Gift {
  /// A gift named `name` in a document, filling [type]'s pouch by
  /// [defaultAmount] rounds unless the level says otherwise.
  const AmmoGift(super.name, this.type, {required this.defaultAmount});

  /// Which pouch it fills; the amount is rounded to whole rounds, and the
  /// gift is refused when none fit.
  final AmmoType type;

  /// In rounds: a count.
  @override
  final double defaultAmount;

  @override
  bool grantTo(GiftGrant context) {
    final to = context.to;
    final amount = context.amount;
    return to.arsenal.addAmmo(type, amount.round()) > 0;
  }

  @override
  GiftAnnouncement? announce(GiftAnnounce context) {
    final amount = context.amount;
    return GiftAnnouncement(
      GiftAnnouncement.pickedUp,
      gift: name,
      amount: amount,
    );
  }
}

/// A key, whose colour is the pickup's own `color` rather than the gift's.
final class KeyGift extends Gift {
  /// The gift, named `key`; refused without a colour or for a key already
  /// held.
  const KeyGift() : super('key');

  @override
  bool grantTo(GiftGrant context) {
    final to = context.to;
    final detail = context.detail;
    if (detail == null) return false;
    return to.keyRing.add(detail);
  }

  @override
  GiftAnnouncement? announce(GiftAnnounce context) {
    final detail = context.detail;
    return detail == null
        ? null
        : GiftAnnouncement(GiftAnnouncement.key, gift: name, detail: detail);
  }
}

/// Runs out, rather than filling a pool.
final class PowerUpGift extends Gift {
  /// The power `name`, running for [defaultAmount] seconds unless the level
  /// says otherwise; never refused, and a second one restarts the clock.
  const PowerUpGift(super.name, {required this.defaultAmount});

  /// Seconds.
  @override
  final double defaultAmount;

  @override
  bool grantTo(GiftGrant context) {
    final to = context.to;
    final amount = context.amount;
    // Refreshing rather than stacking: two medkits are twice the health, two
    // invulnerabilities are not two minutes of it.
    to.empower(name, amount);
    return true;
  }

  @override
  GiftAnnouncement? announce(GiftAnnounce context) {
    final amount = context.amount;
    return GiftAnnouncement(
      GiftAnnouncement.poweredUp,
      gift: name,
      amount: amount,
    );
  }
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
  /// The message [id] about [gift], filled in with [amount] and [detail]
  /// where it has them.
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
  /// A registry of [gifts] by name; of two with one name, the later wins.
  GiftRegistry(Iterable<Gift> gifts)
    : _byName = <String, Gift>{for (final gift in gifts) gift.name: gift};

  final Map<String, Gift> _byName;

  /// The gift a document names as [name], or null for one nobody knows.
  Gift? operator [](String name) => _byName[name];

  /// Every name a pickup's `gives` may use, in the order they were given.
  Iterable<String> get names => _byName.keys;

  /// Whether a pickup may name [name] in its `gives`.
  bool knows(String name) => _byName.containsKey(name);
}

/// What [Gift.grantTo] is handed: who takes the gift, and how much of it.
///
/// **One object, so a minor can hand a gift more** — the pickup it lay in,
/// the step it was taken at — without breaking a gift written against 1.0.
final class GiftGrant {
  /// [amount] of a gift for [to], with the level's [detail] if it wrote one.
  const GiftGrant({required this.to, required this.amount, this.detail});

  /// What the taker carries.
  final Inventory to;

  /// How much, in the gift's own unit: hit points, armor points or rounds.
  final double amount;

  /// What the level wrote beside the amount: a key's color, a power-up's
  /// name; null when it wrote nothing.
  final String? detail;
}

/// What [Gift.announce] is handed, once the gift was granted, for the
/// reason [GiftGrant] gives.
final class GiftAnnounce {
  /// The [amount] given, with the level's [detail] if it wrote one.
  const GiftAnnounce({required this.amount, this.detail});

  /// How much was given, in the gift's own unit.
  final double amount;

  /// What the level wrote beside the amount, or null.
  final String? detail;
}
