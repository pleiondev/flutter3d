import 'package:flutter/widgets.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../l10n/game_localizations.dart';
import 'steering_band.dart';
import 'touch_action.dart';
import 'touch_button.dart';

/// A wheel and pedals, drawn over a game nobody can reach a keyboard for.
///
/// **`TouchControls` does not fit and should not be made to.** It is a thumb
/// stick and a cluster of buttons; a vehicle has no stick, its steering is one
/// axis rather than two, and its two most important controls are held for
/// whole corners at a time rather than tapped. Bending the shared widget into
/// this shape would make it worse at the games that already use it.
///
/// The layout:
///
/// | control | where |
/// |---|---|
/// | [SteeringBand] on [steerLeft] and [steerRight] | bottom left |
/// | pedals ([TouchButton.pedal]): [handbrake], [brake], [throttle] | bottom right, the throttle nearest the thumb |
/// | [corner] | top right, on its own |
///
/// What the controls are named and which actions they press are the game's.
class TouchDrive extends StatelessWidget {
  const TouchDrive({
    super.key,
    required this.state,
    required this.steerLeft,
    required this.steerRight,
    required this.throttle,
    required this.brake,
    this.handbrake,
    this.corner,
    this.throttleLabel,
    this.brakeLabel,
    this.handbrakeLabel,
    this.steer,
  });

  final InputState state;

  /// The wheel as one [AxisAction] as well — see [SteeringBand.axis].
  final AxisAction? steer;

  final GameAction steerLeft;
  final GameAction steerRight;
  final GameAction throttle;
  final GameAction brake;

  /// Optional, because a game may not have one and a control for nothing is
  /// worse than a gap.
  final GameAction? handbrake;

  /// A button pressed once, standing still — fresh tyres, a reset, a horn —
  /// or null for none.
  ///
  /// **Over the pedals rather than among them, because it is not one.** A
  /// pedal-sized target beside the throttle is a press entered at full speed;
  /// this is the one control never wanted mid-corner, so it takes a
  /// deliberate reach, at the far side of the screen from everything held.
  final TouchAction? corner;

  /// What the pedals say, on them and to a screen reader; null for
  /// [Flutter3dGameLocalizations.throttle], `brake` and `handbrake` in the
  /// player's language.
  final String? throttleLabel;
  final String? brakeLabel;
  final String? handbrakeLabel;

  @override
  Widget build(BuildContext context) {
    final words = Flutter3dGameLocalizations.of(context);
    final hand = handbrake;
    final top = corner;
    return SafeArea(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 24,
            bottom: 24,
            child: SteeringBand(
              state: state,
              left: steerLeft,
              right: steerRight,
              axis: steer,
            ),
          ),
          if (top != null)
            Positioned(
              right: 24,
              top: 24,
              child: TouchButton(
                state: state,
                action: top.action,
                label: top.label,
                radius: 30.0,
              ),
            ),
          Positioned(
            right: 24,
            bottom: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (hand != null) ...<Widget>[
                  TouchButton.pedal(
                    state: state,
                    action: hand,
                    label: handbrakeLabel ?? words.handbrake,
                  ),
                  const SizedBox(width: 14),
                ],
                TouchButton.pedal(
                  state: state,
                  action: brake,
                  label: brakeLabel ?? words.brake,
                ),
                const SizedBox(width: 14),
                // Nearest the thumb, because it is the one that is held the
                // longest.
                TouchButton.pedal(
                  state: state,
                  action: throttle,
                  label: throttleLabel ?? words.throttle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
