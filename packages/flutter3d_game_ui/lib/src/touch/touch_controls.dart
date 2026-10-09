import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'touch_action.dart';
import 'touch_button.dart';
import 'touch_slots.dart';
import 'touch_stick.dart';
import 'touch_toggle.dart';

/// A thumb stick and some buttons, drawn over a game that has no keyboard,
/// with numbered slots and switches where a game has them.
///
/// The third translator, beside `DesktopInput` and `PadInput`, and the one the
/// device-independent input was written for in the first place —
/// [InputState.setStickAxis] has said "for a stick or a d-pad" since before
/// either existed, and its class doc has always promised that the touch build
/// and the desktop build run the same game code. This is that promise being
/// collected.
///
/// ## Where each control goes
///
/// A game with two or three verbs is a stick and a row of buttons. A game
/// with six is not served by adding circles to the row, because its verbs are
/// not six of the same kind:
///
/// | control | kind | where |
/// |---|---|---|
/// | the [TouchStick] | analogue, held | bottom left, under the left thumb |
/// | [buttons] | held | bottom right, the last nearest the thumb |
/// | [toggles] | set, and stays set | a row just above [buttons] |
/// | [slots] | chosen, occasionally | up the right edge, out of the cluster |
/// | [corner] | set, and rarely wanted | top right corner, on its own |
///
/// The two axes are **how often** and **how bad a mistake is**. What is pressed
/// every second and costs nothing by accident sits where the thumb rests;
/// what is wanted twice a minute and loses the game when pressed by mistake
/// takes a deliberate reach. Nothing that is tapped by accident is next to
/// something that is held.
///
/// A drag-to-look layer under this is the other half of the same rule: every
/// pixel a control covers is a pixel the player cannot turn the view with, so
/// the slots and the corner hug the edges.
///
/// Until 1.0.0-rc.1 the stick-and-row and the layout with slots and a corner
/// were two widgets, `TouchControls` and `TouchCluster`, doing one job. This
/// is both: a game that hands no [slots] and no [corner] gets the row it
/// always had.
///
/// ## Labelled, even though a blind player is not playing this
///
/// Each button says what it does to a screen reader. That is not the
/// contradiction it looks like: a player with low vision, or one whose reader is
/// on for something else entirely, meets these controls and gets "jump" rather
/// than an unnamed circle. The stick is not labelled, because a thumb stick
/// under a reader is a gesture nobody can perform.
///
/// ## One finger per control
///
/// Every control tracks the pointer id that claimed it, which is the whole of
/// multi-touch and is not optional: a player walking and jumping is holding two
/// fingers down at once, and a control that took the most recent pointer would
/// snap the stick to the jump button.
class TouchControls extends StatelessWidget {
  const TouchControls({
    super.key,
    required this.state,
    required this.buttons,
    this.toggles = const <TouchToggle>[],
    this.slots = const <TouchSlot>[],
    this.current = -1,
    this.corner,
    this.stickRadius = 64.0,
    this.buttonRadius = 34.0,
    this.margin = 28.0,
    this.stickAction = DualAxisAction.move,
  });

  final InputState state;

  /// What the stick asks for — walking unless the game says otherwise. See
  /// [TouchStick.action].
  final DualAxisAction stickAction;

  /// Controls that are set rather than held — see [TouchToggle] — and wanted
  /// often enough to sit by the thumb.
  ///
  /// Drawn in a row *above* [buttons] rather than among them, and the split is
  /// the point: a control that stays on after the finger has gone is a
  /// different kind of thing from a trigger, and a thumb reaching back for the
  /// jump button should not be able to land on the sprint by a centimetre.
  final List<TouchToggle> toggles;

  /// What the buttons on the right do, in the order they are drawn: the last is
  /// nearest the thumb.
  ///
  /// A list rather than a fixed set, because "jump, dash, drop through" is a
  /// platformer's answer and "fire" is a shooter's.
  final List<TouchAction> buttons;

  /// The numbered slots, or none for a game without them. See [TouchSlots].
  final List<TouchSlot> slots;

  /// Which of [slots] is in use, or −1 for none.
  final int current;

  /// The one switch that is wanted rarely and costs something when pressed
  /// by mistake — a map, say — in the corner nothing else uses, or null.
  final TouchToggle? corner;

  /// The stick's radius, in logical pixels.
  final double stickRadius;

  /// Each button's radius, in logical pixels.
  final double buttonRadius;

  /// How far the controls sit from the edges, in logical pixels. Generous,
  /// because the edges of a phone are where the system's own gestures live.
  final double margin;

  /// How tall the row of [toggles] stands over the buttons, with the gap
  /// under it; nought for none.
  double get _toggleRow => toggles.isEmpty
      ? 0.0
      : toggles.fold(0.0, (double tallest, TouchToggle t) {
              return math.max(tallest, t.radius * 2);
            }) +
            22.0;

  @override
  Widget build(BuildContext context) {
    final top = corner;
    return SafeArea(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: margin,
            bottom: margin,
            child: TouchStick(
              state: state,
              radius: stickRadius,
              action: stickAction,
            ),
          ),
          if (top != null) Positioned(right: margin, top: margin, child: top),
          // Up the right edge and clear of the cluster: far enough that a
          // thumb coming off a held button cannot brush it, near enough to be
          // reached without letting go of the stick. Over the row of
          // toggles, when there is one, rather than on it.
          if (slots.isNotEmpty)
            Positioned(
              right: margin,
              bottom: margin + 88.0 + _toggleRow,
              child: TouchSlots(state: state, slots: slots, current: current),
            ),
          Positioned(
            right: margin,
            bottom: margin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (toggles.isNotEmpty) ...<Widget>[
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    alignment: WrapAlignment.end,
                    children: toggles,
                  ),
                  // A gap the width of a thumb, not a margin: this is the
                  // distance between a control that latches and one that fires.
                  const SizedBox(height: 22),
                ],
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    for (final button in buttons)
                      TouchButton(
                        state: state,
                        action: button.action,
                        label: button.label,
                        radius: buttonRadius,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
