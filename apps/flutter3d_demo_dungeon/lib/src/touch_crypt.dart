/// The crypt under two thumbs.
///
/// **`TouchControls` does not fit this game any more, and that is a statement
/// about the game rather than about the widget.** It is a stick and a row of
/// buttons — a platformer's hands, and the shape the crypt borrowed when it
/// had two verbs to offer. Two was what it offered: `use` and `fire`. The
/// arsenal is four weapons deep and only the one already in hand could be
/// fired; the automap, which the whole of `Automap` and `AutomapView` exist
/// for, was behind the M key and behind nothing else. Three quarters of the
/// weapons and the entire map were unreachable on the device the touch build
/// is for.
///
/// So this is six controls rather than two, and they are not six of the same
/// kind — which is the whole reason the layout had to be rebuilt rather than
/// having four more circles added to a `Wrap`:
///
/// | control | kind | where |
/// |---|---|---|
/// | walk | analogue, held | bottom left, under the left thumb |
/// | fire | held, constantly | bottom right, nearest the right thumb |
/// | jump | pressed | bottom right, beside it |
/// | use | pressed, aimed | bottom right, furthest in the cluster |
/// | weapon | chosen, occasionally | up the right edge, out of the cluster |
/// | map | set, and stays set | top right corner, on its own |
///
/// The two axes are **how often** and **how bad a mistake is**. Firing happens
/// every second and costs nothing if it happens by accident; choosing a weapon
/// happens twice a room and putting the fists in your hand in front of a tank
/// loses the run. So the rarely-wanted controls are the ones that take a
/// deliberate reach, and nothing that is tapped by accident is next to
/// something that is held.
///
/// The other half of the same rule: the crypt's drag-to-look layer is
/// `Positioned.fill` underneath all of this, so every pixel a control covers
/// is a pixel the player cannot turn the view with. That is why the map and
/// the weapons hug the edges rather than sitting where they would read best.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';

/// Everything the crypt can be played with, on a device with no keyboard.
class TouchCrypt extends StatelessWidget {
  const TouchCrypt({
    super.key,
    required this.state,
    required this.arsenal,
    required this.mapOn,
    required this.onMap,
  });

  final InputState state;

  /// What the player is holding and what they own, so the slot row can say
  /// which button is the one in hand and which are still empty.
  final Arsenal arsenal;

  /// Whether the automap is up. Widget state in the screen above, because the
  /// map is a thing being drawn rather than an action being asked for — see
  /// [TouchToggle], which is stateless for exactly this reason.
  final bool mapOn;

  final VoidCallback onMap;

  /// The four slots, shortened to something legible in a 62-point button.
  ///
  /// The name comes off the weapon rather than being typed here, so a roster
  /// that gains a fifth weapon gains a fifth button and nobody has to
  /// remember. Cut at the first word: "Rocket Launcher" is two words wide and
  /// the row is one thumb wide, and the first word is the one that tells them
  /// apart.
  List<TouchSlot> get _slots => <TouchSlot>[
    for (final weapon in arsenal.slots)
      TouchSlot(
        weapon.name.split(' ').first.toLowerCase(),
        owned: arsenal.owned.contains(weapon),
      ),
  ];

  /// Which slot is in hand, or −1 with nothing in it.
  ///
  /// `Arsenal.current` throws rather than inventing a weapon to answer, which
  /// is right and is also why this cannot simply ask: a player who owns
  /// nothing is a real state, and it is the state a row of empty slot buttons
  /// is most worth drawing in.
  int get _held =>
      arsenal.isEmpty ? -1 : arsenal.slots.indexOf(arsenal.current);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: <Widget>[
        Positioned(left: 28, bottom: 28, child: TouchStick(state: state)),
        // The corner nothing else uses, and the control that is set rather
        // than pressed. The map does not pause the crypt — see the M key — so
        // it is opened and left open, and a button that had to be held would
        // be a hand that cannot fight while it reads.
        Positioned(
          right: 28,
          top: 28,
          child: TouchToggle(label: 'map', on: mapOn, onTap: onMap),
        ),
        // Up the right edge and clear of the cluster: far enough that a thumb
        // coming off the trigger cannot brush it, near enough to be reached
        // without letting go of the stick.
        Positioned(
          right: 28,
          bottom: 116,
          child: TouchSlots(state: state, slots: _slots, current: _held),
        ),
        Positioned(
          right: 28,
          bottom: 28,
          child: Wrap(
            spacing: 14,
            alignment: WrapAlignment.end,
            children: <Widget>[
              // Aimed: it reads whatever is under the crosshair, so it is the
              // one of the three that wants the view pointed first — and the
              // furthest from the thumb's resting place for that reason.
              TouchButton(state: state, action: GameAction.use, label: 'use'),
              TouchButton(state: state, action: GameAction.jump, label: 'jump'),
              // Nearest the thumb, because it is the one held for the whole
              // corridor.
              TouchButton(
                state: state,
                action: ShooterActions.fire,
                label: 'fire',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
