/// The dungeon's heads-up display.
///
/// Three hundred lines of `Text` and `Container` that were the largest single
/// thing in `main.dart` and had nothing to do with anything else in it. It
/// takes values and draws them; it holds no state and reads no simulation.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// The colours the HUD draws a carried key in.
const Map<String, Color> _keyPips = <String, Color>{
  'blue': Color(0xFF3A6BF2),
  'red': Color(0xFFE52E29),
  'yellow': Color(0xFFF2D133),
};

class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.captured,
    required this.fps,
    required this.steps,
    required this.dropped,
    this.behind = false,
    required this.voices,
    required this.particles,
    required this.position,
    required this.grounded,
    required this.weapon,
    required this.ammo,
    required this.hitFlash,
    required this.painFlash,
    required this.health,
    required this.kills,
    required this.monstersLeft,
    required this.message,
    required this.messageOpacity,
    required this.keys,
    required this.armour,
    required this.pouches,
    required this.powers,
  });

  final bool captured;
  final double fps;
  final int steps;
  final int dropped;

  /// Whether the machine is not keeping up.
  ///
  /// **A count of dropped steps is a number nobody reads**, and this game has
  /// had one in its debug line for as long as it has existed. What it means is
  /// that the game is running in slow motion and saying nothing about it, which
  /// is worth a sentence rather than an integer.
  final bool behind;

  /// Sounds actually playing. Zero with no audio device, and the only thing on
  /// screen that says whether the mixer is doing anything at all.
  final int voices;

  /// Particles alive. The same job the voice count does for sound: the only
  /// number that separates "never emitted" from "emitted and not drawn".
  final int particles;
  final Vector3 position;
  final bool grounded;
  final WeaponDef weapon;

  /// Negative when the weapon needs none.
  final int ammo;

  /// Fades from one to zero after a shot connected.
  final double hitFlash;

  final double painFlash;
  final Health health;
  final int kills;
  final int monstersLeft;

  /// The last thing the level said — a locked door, a key collected.
  final String message;

  /// Fades over the last part of the message's life rather than vanishing.
  final double messageOpacity;

  /// What the player is carrying, drawn as coloured pips.
  final Set<String> keys;

  final double armour;

  /// Every pouch, not only the one in use: a player deciding whether to switch
  /// needs to see what switching would cost.
  final Map<AmmoType, int> pouches;

  /// Seconds left on whatever is running.
  final Map<String, double> powers;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The crosshair, which turns red the moment a shot connects. A hit
        // marker is the cheapest feedback in a shooter and the one players
        // notice the absence of.
        Center(
          child: SizedBox(
            width: 5.0 + hitFlash * 4.0,
            height: 5.0 + hitFlash * 4.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.white70,
                  const Color(0xFFFF5B4A),
                  hitFlash,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Positioned(
          left: 12.0,
          top: 12.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'fps ${fps.toStringAsFixed(0)}   '
                  'steps this frame $steps   dropped $dropped   '
                  'voices $voices   particles $particles',
                ),
                Text(
                  'x ${position.x.toStringAsFixed(1)}  '
                  'y ${position.y.toStringAsFixed(1)}  '
                  'z ${position.z.toStringAsFixed(1)}  '
                  '${grounded ? 'grounded' : 'airborne'}',
                ),
              ],
            ),
          ),
        ),
        // A red wash on being hurt. Drawn under everything else so the numbers
        // stay legible exactly when they matter most.
        if (painFlash > 0.0)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: <Color>[
                    const Color(0x00FF2A18),
                    Color.lerp(
                      const Color(0x00FF2A18),
                      const Color(0xAAFF2A18),
                      painFlash,
                    )!,
                  ],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          left: 20.0,
          bottom: 18.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'HEALTH',
                  style: TextStyle(color: Colors.white54, fontSize: 12.0),
                ),
                Text(
                  health.isAlive ? '${health.current.round()}' : 'DEAD',
                  style: TextStyle(
                    color: health.current > 30.0
                        ? Colors.white
                        : const Color(0xFFFF6B5A),
                    fontSize: 22.0,
                  ),
                ),
                Text(
                  'kills $kills   left $monstersLeft',
                  style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 20.0,
          bottom: 18.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  weapon.name.toUpperCase(),
                  style: const TextStyle(color: Colors.white54, fontSize: 12.0),
                ),
                Text(ammo < 0 ? '∞' : '$ammo'),
              ],
            ),
          ),
        ),
        // Above the crosshair rather than at the bottom of the screen: it
        // answers something the player just did, and their eyes are here.
        if (messageOpacity > 0.0 && message.isNotEmpty)
          Align(
            alignment: const Alignment(0.0, -0.35),
            child: Opacity(
              opacity: messageOpacity,
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFF2E4C8),
                  fontSize: 17.0,
                  shadows: <Shadow>[Shadow(blurRadius: 6.0)],
                ),
              ),
            ),
          ),

        // Armour beside health, in the corner the eye already goes to.
        if (armour > 0.0)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 132.0, bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'ARMOUR',
                    style: TextStyle(color: Colors.white38, fontSize: 12.0),
                  ),
                  Text(
                    '${armour.round()}',
                    style: const TextStyle(
                      color: Color(0xFF8FC6E8),
                      fontSize: 34.0,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Every pouch, the one in use picked out. A row of small numbers
        // rather than four labelled lines: it is glanced at, not read.
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 24.0, bottom: 84.0),
            // `Wrap` rather than `Row`: this one is bounded by the screen, so
            // at a large text size a row of four pouches overflows and Flutter
            // paints the yellow bars over the game. Wrapping puts the fourth on
            // a second line, which is what a glance wants anyway.
            child: Wrap(
              alignment: WrapAlignment.end,
              children: <Widget>[
                for (final entry in pouches.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 14.0),
                    child: Text(
                      '${entry.key.name.substring(0, 3).toUpperCase()} '
                      '${entry.value}',
                      style: TextStyle(
                        color: entry.key == weapon.ammo
                            ? Colors.white
                            : Colors.white30,
                        fontSize: 13.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        if (powers.isNotEmpty)
          Align(
            alignment: const Alignment(0.0, -0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final power in powers.entries)
                  Text(
                    '${power.key.toUpperCase()}  ${power.value.ceil()}',
                    style: const TextStyle(
                      color: Color(0xFFE8D48F),
                      fontSize: 15.0,
                      letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),
          ),

        if (keys.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 84.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final key in keys)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: SizedBox(
                        width: 14.0,
                        height: 22.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _keyPips[key] ?? Colors.white70,
                            borderRadius: BorderRadius.circular(3.0),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        if (!captured)
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Click to look around  ·  WASD to move  ·  Space to jump  ·  '
                'E to use  ·  Esc to release the pointer',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        if (behind)
          Positioned(
            right: 24,
            top: 24,
            child: Text(
              'This machine is behind — the game is running slowly.',
              style: TextStyle(
                color: Colors.amber.withValues(alpha: 0.9),
                fontSize: 13,
                shadows: const <Shadow>[
                  Shadow(blurRadius: 8, color: Colors.black87),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
