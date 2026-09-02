import 'package:flutter/widgets.dart';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'touch_action.dart';
import 'touch_button.dart';
import 'touch_stick.dart';

export 'touch_action.dart';
export 'touch_button.dart';
export 'touch_stick.dart';

/// A thumb stick and some buttons, drawn over a game that has no keyboard.
///
/// The third translator, beside `DesktopInput` and `PadInput`, and the one the
/// device-independent input was written for in the first place —
/// [InputState.setStickAxis] has said "for a stick or a d-pad" since before
/// either existed, and its class doc has always promised that the touch build
/// and the desktop build run the same game code. This is that promise being
/// collected.
///
/// ## Widgets, and why that is not a layering mistake
///
/// Everything else in this package is free of Flutter's widget tree. This is
/// not, because a touch control **is** its own picture: there is no operating
/// system offering one, no plugin to ask, and nothing to translate from. A
/// package that held only the arithmetic would leave every game drawing its own
/// stick, and the first one to get the dead centre wrong would be the only one
/// to find out.
///
/// What is *not* here is what the buttons say, which is the game's: a platformer
/// wants jump and dash, a shooter wants fire and a slot. [TouchControls] takes
/// them as a list.
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
    this.stickRadius = 64.0,
    this.buttonRadius = 34.0,
    this.margin = 28.0,
  });

  final InputState state;

  /// What the buttons on the right do, in the order they are drawn: the last is
  /// nearest the thumb.
  ///
  /// A list rather than a fixed set, because "jump, dash, drop through" is a
  /// platformer's answer and "fire" is a shooter's.
  final List<TouchAction> buttons;

  final double stickRadius;
  final double buttonRadius;

  /// How far the controls sit from the edges. Generous, because the edges of a
  /// phone are where the system's own gestures live.
  final double margin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: margin,
            bottom: margin,
            child: TouchStick(state: state, radius: stickRadius),
          ),
          Positioned(
            right: margin,
            bottom: margin,
            child: Wrap(
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
          ),
        ],
      ),
    );
  }
}
