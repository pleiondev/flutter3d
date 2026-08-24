import 'package:pad_input/pad_input.dart';

import '../config/game_config.dart';
import 'game_action.dart';
import 'input_state.dart';

/// What a stick's two axes are for.
enum PadStickUse {
  /// Nothing. A racing game's left stick steers through [PadAxisPair] instead,
  /// and its right stick does not exist.
  ignored,

  /// Movement, through [InputState.setStickAxis].
  move,

  /// Turning the view, integrated over time — see [PadRoutes.lookRate].
  look,
}

/// A signed axis routed to two actions, one per direction.
///
/// For a control that is an axis on a pad and a pair of keys on a keyboard:
/// steering is `steerLeft`/`steerRight` at the keyboard and one stick axis on a
/// pad, and the simulation should not be able to tell which it got. Each side
/// gets a magnitude as well as a press, so a stick half over asks for half the
/// steering.
///
/// **Not a [Bindings] entry**, and that is the important part: binding half an
/// axis as an [InputSource] would run it through `press`/`held` and make every
/// stick digital, which is exactly what `flutter3d_game_shooter`'s "half a deflection
/// is half a wish" test forbids.
final class PadAxisPair {
  const PadAxisPair({required this.negative, required this.positive});

  /// What a negative reading asks for. Left, or up on a stick.
  final GameAction negative;

  /// What a positive reading asks for. Right, or down on a stick.
  final GameAction positive;
}

/// Where each of a pad's analogue controls goes, for one kind of game.
///
/// Buttons are bound, in the table the player can edit and the game saves.
/// Axes are **routed**, here, in code — because what a stick is *for* is a
/// property of the genre rather than a preference: a racing game's left stick
/// steers and there is no version of that game where it walks.
final class PadRoutes {
  const PadRoutes({
    this.leftStick = PadStickUse.move,
    this.rightStick = PadStickUse.look,
    this.axisActions = const <PadAxis, PadAxisPair>{},
    this.lookRate = defaultLookRate,
  });

  /// A stick that walks and a stick that looks: a platformer, a shooter, and
  /// almost everything else.
  static const PadRoutes walking = PadRoutes();

  /// One stick that steers, and no stick that looks.
  ///
  /// The pedals are not here: a trigger is a button as well as an axis, so it is
  /// bound like one and a player can move it. Which way the stick turns the car
  /// is not something a player rebinds.
  static PadRoutes driving({
    required GameAction steerLeft,
    required GameAction steerRight,
  }) =>
      PadRoutes(
        leftStick: PadStickUse.ignored,
        rightStick: PadStickUse.ignored,
        axisActions: <PadAxis, PadAxisPair>{
          PadAxis.leftStickX:
              PadAxisPair(negative: steerLeft, positive: steerRight),
        },
      );

  /// How far the view turns per second at full deflection, **in the mouse's
  /// units**.
  ///
  /// Odd-looking, and deliberately so. [InputState.lookDelta] is in whatever the
  /// device reports and the camera applies one sensitivity to all of it, so a
  /// stick that arrives in a currency of its own would be a second sensitivity
  /// nobody can see. `flutter3d_game_shooter`'s player turns 0.0022 radians per unit,
  /// which puts this default at about 2.4 radians per second — a brisk but
  /// controllable turn.
  ///
  /// It is a number that can only be settled with a controller in hand, like a
  /// dead zone, and so is a slider: `pad.look` in [GameConfig.settings], applied
  /// by [PadInput.applySettings].
  ///
  /// Deliberately **linear**. A response curve is the other thing everybody
  /// tunes here and the other thing nobody can tune without a device; adding one
  /// blind would be inventing a shape and calling it a decision.
  static const double defaultLookRate = 1100.0;

  final PadStickUse leftStick;
  final PadStickUse rightStick;

  /// Axes that mean a pair of actions rather than movement or a view.
  final Map<PadAxis, PadAxisPair> axisActions;

  final double lookRate;

  PadRoutes copyWith({double? lookRate}) => PadRoutes(
        leftStick: leftStick,
        rightStick: rightStick,
        axisActions: axisActions,
        lookRate: lookRate ?? this.lookRate,
      );
}
