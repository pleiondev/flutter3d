/// The readouts this genre has, as widgets a game lays out itself.
///
/// **Not a HUD.** The crypt's heads-up display is four hundred lines of
/// `Container` holding a frame-rate counter, a particle count, a message line
/// that fades and a screen flash — none of which is a shooter, all of which is
/// that game. What is a shooter is the handful of numbers below: how much
/// health is left, how many rounds are in hand, which keys are carried. Those
/// were written once per game and got the same three details wrong each time —
/// the fists reading `0` instead of `∞`, armour drawn as a second health bar,
/// a key ring that showed a key the player had used.
///
/// So the genre ships the readouts and the game ships the layout. Each widget
/// takes the genre's own type — an [Arsenal], an [Inventory] — rather than the
/// numbers pulled out of it, because pulling them out is where the three
/// mistakes were. Each takes a [ReadoutStyle], because where it sits and what
/// colour it is are the game's business and not this package's.
///
/// **This is the one file in this package that draws**, and the structure rule
/// `a genre package draws only where it says` is about reaching the renderer
/// rather than about Flutter: a widget is fine here, a `package:flutter3d/`
/// import is not.
library;

import 'package:flutter/widgets.dart';

import 'combat/weapon.dart';
import 'inventory.dart';

/// How a game wants its readouts drawn.
///
/// **One object rather than a dozen parameters**, so a game states its look
/// once and passes the same object to every readout — and so a readout that
/// grows a fourth thing to colour does not change the shape of six call sites.
final class ReadoutStyle {
  const ReadoutStyle({
    this.text = const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18.0),
    this.dim = const Color(0x66FFFFFF),
    this.warning = const Color(0xFFE5533D),
    this.barHeight = 6.0,
    this.barWidth = 120.0,
  });

  /// What numbers and names are drawn in.
  final TextStyle text;

  /// The empty part of a bar, and anything the player is not being asked to
  /// look at.
  final Color dim;

  /// What a bar turns when it is nearly empty. See [HealthBar.lowAt].
  final Color warning;

  final double barHeight;
  final double barWidth;
}

/// How much of the player is left, and what is in front of it.
///
/// **Armour is drawn over the health rather than beside it**, because that is
/// what it does: it is the share of the next hit somebody else takes, not a
/// second life. Two bars side by side was the drawing every game reached for
/// first and it reads as twice the health, which is exactly wrong at the
/// moment it matters.
final class HealthBar extends StatelessWidget {
  const HealthBar({
    super.key,
    required this.health,
    required this.armour,
    this.maxHealth = 100.0,
    this.maxArmour = 100.0,
    this.lowAt = 0.25,
    this.style = const ReadoutStyle(),
  });

  final double health;
  final double armour;
  final double maxHealth;
  final double maxArmour;

  /// The share of health below which the bar turns [ReadoutStyle.warning].
  final double lowAt;

  final ReadoutStyle style;

  @override
  Widget build(BuildContext context) {
    final left = (health / maxHealth).clamp(0.0, 1.0);
    final shield = (armour / maxArmour).clamp(0.0, 1.0);
    final colour = left <= lowAt ? style.warning : style.text.color!;
    return SizedBox(
      width: style.barWidth,
      height: style.barHeight * 2.0 + 2.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Bar(fraction: left, colour: colour, style: style),
          const SizedBox(height: 2.0),
          // Absent rather than empty: a shield bar at nought is a bar the
          // player learns to ignore, and then does not notice arriving.
          if (shield > 0.0)
            _Bar(fraction: shield, colour: style.dim, style: style),
        ],
      ),
    );
  }
}

/// What is in the weapon, or infinity when the weapon does not spend anything.
///
/// **The fists read `∞` and not `0`.** Every game that drew this from
/// `arsenal.currentAmmo` printed nought for the starting weapon, which reads as
/// a weapon that cannot fire — and it is the one weapon that always can.
/// [Arsenal.ammoOf] answers `-1` for [AmmoType.none] precisely so this can tell
/// the two apart, and doing it here is what stops the next game from getting it
/// wrong again.
final class AmmoReadout extends StatelessWidget {
  const AmmoReadout({
    super.key,
    required this.arsenal,
    this.style = const ReadoutStyle(),
    this.endless = '∞',
  });

  final Arsenal arsenal;
  final ReadoutStyle style;

  /// What to draw for a weapon that spends nothing.
  final String endless;

  @override
  Widget build(BuildContext context) {
    if (arsenal.isEmpty) return const SizedBox.shrink();
    final held = arsenal.ammoOf(arsenal.current.ammo);
    return Text(held < 0 ? endless : '$held', style: style.text);
  }
}

/// The keys the player is carrying, as a pip each.
///
/// Named for the drawing rather than for the thing: [KeyRing] is already the
/// engine type that holds them, and two of that name a package apart is a
/// prefix at every use.
///
/// Takes the [Inventory] rather than the set of names, because a key that has
/// been used is removed from it and a game holding its own copy showed one that
/// was gone. Unknown names are drawn in [ReadoutStyle.dim]: a level may name a
/// key colour this table has never heard of, and a pip in grey is a better
/// answer than a crash or a missing pip a player cannot account for.
final class KeyPips extends StatelessWidget {
  const KeyPips({
    super.key,
    required this.inventory,
    this.colours = const <String, Color>{},
    this.style = const ReadoutStyle(),
    this.pipSize = 10.0,
  });

  final Inventory inventory;

  /// What colour each key name is drawn in. A name not here gets
  /// [ReadoutStyle.dim].
  final Map<String, Color> colours;

  final ReadoutStyle style;
  final double pipSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (final String key in inventory.keys)
        Padding(
          padding: EdgeInsets.only(right: pipSize * 0.4),
          child: SizedBox(
            width: pipSize,
            height: pipSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colours[key] ?? style.dim,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
    ],
  );
}

/// One bar, filled to [fraction].
final class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.colour,
    required this.style,
  });

  final double fraction;
  final Color colour;
  final ReadoutStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: style.barWidth,
    height: style.barHeight,
    child: Stack(
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(color: style.dim),
          child: const SizedBox.expand(),
        ),
        FractionallySizedBox(
          widthFactor: fraction,
          child: DecoratedBox(
            decoration: BoxDecoration(color: colour),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    ),
  );
}
