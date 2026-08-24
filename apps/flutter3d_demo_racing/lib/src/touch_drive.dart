import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import 'pedal.dart';
import 'steering_band.dart';

/// A wheel and two pedals, drawn over a game nobody can reach a keyboard for.
///
/// **`TouchControls` does not fit and should not be made to.** It is a thumb
/// stick and a row of buttons, which is a platformer's hands and a shooter's; a
/// car has no stick, its steering is one axis rather than two, and its two most
/// important controls are held for whole corners at a time rather than tapped.
/// Bending the shared widget into this shape would have made it worse at the
/// two games that already use it.
///
/// It lives in this application rather than in `flutter3d_game_racing` for the rule
/// the repository keeps everywhere else: there is one racing game. The day
/// there are two, this moves.
///
/// The wheel is [SteeringBand] and the pedals are [Pedal], each in its own
/// file: what is here is only how the two are laid out over the picture.
class TouchDrive extends StatelessWidget {
  const TouchDrive({
    super.key,
    required this.state,
    required this.steerLeft,
    required this.steerRight,
    required this.throttle,
    required this.brake,
    this.handbrake,
  });

  final InputState state;

  final GameAction steerLeft;
  final GameAction steerRight;
  final GameAction throttle;
  final GameAction brake;

  /// Optional, because a game may not have one and a control for nothing is
  /// worse than a gap.
  final GameAction? handbrake;

  @override
  Widget build(BuildContext context) {
    final hand = handbrake;
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
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (hand != null) ...<Widget>[
                  Pedal(state: state, action: hand, label: 'handbrake'),
                  const SizedBox(width: 14),
                ],
                Pedal(state: state, action: brake, label: 'brake'),
                const SizedBox(width: 14),
                // Nearest the thumb, because it is the one that is held for the
                // whole lap.
                Pedal(state: state, action: throttle, label: 'throttle'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
