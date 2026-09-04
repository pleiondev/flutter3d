import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:pad_input/pad_input.dart';

import '../config/game_config.dart';

/// What a [PadStickUse] is allowed to do with a deflection.
///
/// Narrow on purpose. A stick use gets the two things a stick has ever meant
/// here and the one number it needs to mean the second of them, and nothing
/// else about the pad, the bindings or the frame — so a use written outside
/// this package cannot reach past its own job.
abstract interface class PadStickTarget {
  /// Movement, in the simulation's units, forward positive.
  ///
  /// The caller has already flipped what the device reports; see
  /// [PadStickUse.move].
  void setStickAxis(double x, double y);

  /// Adds to this frame's view turn, in the mouse's units.
  void addLook(double dx, double dy);

  /// How far the view turns per second at full deflection. [PadRoutes.lookRate].
  double get lookRate;
}

/// What a stick's two axes are for.
///
/// **Open, and opening the list alone would have been useless.** This was an
/// enum of three, switched over in one method — so a game could not say its
/// stick leans the ship, and adding a value to say so broke every `switch` in
/// every game already shipped. Opening only the vocabulary would have left an
/// open list with a closed interpreter: a game could name its use and nothing
/// would know how to run it.
///
/// So the interpretation moved onto the value. A use *is* what it does with a
/// deflection, and a game's own use brings its own [route] — which is why the
/// three below are instances rather than cases, and why there is no `switch`
/// left to break.
/// `base`: extend it, do not implement it. A stick use that implemented this
/// would stop compiling the day [route] gains an argument, and an open type
/// whose additions break its users is not open for long.
abstract base class PadStickUse {
  const PadStickUse();

  /// For logs and error messages. Not persisted: what a stick is for is a
  /// property of the genre, written in code, and never read back from a file.
  String get name;

  /// Applies one frame's deflection, already dead-zoned, in `-1..1`.
  ///
  /// `y` is what the device reported: positive downwards, which is Apple's
  /// convention and the browser's. Whether that wants negating depends on what
  /// the use means, so it is left for the use to decide rather than flipped
  /// where a reader cannot see it.
  void route(PadStickTarget to, double x, double y, double dt);

  /// Returns whatever this use writes to neutral, when the pad is let go of.
  ///
  /// Default: nothing. A use that only accumulates into the frame's own look
  /// delta has nothing to release, because the delta is cleared with the pad.
  /// Override it when the use writes somewhere that outlives the frame.
  void letGo(PadStickTarget of) {}

  @override
  String toString() => 'PadStickUse.$name';

  /// Nothing. A racing game's left stick steers through [PadAxisPair] instead,
  /// and its right stick does not exist.
  static const PadStickUse ignored = _IgnoredStick();

  /// Movement, through [InputState.setStickAxis].
  static const PadStickUse move = _MoveStick();

  /// Turning the view, integrated over time — see [PadRoutes.lookRate].
  static const PadStickUse look = _LookStick();
}

final class _IgnoredStick extends PadStickUse {
  const _IgnoredStick();

  @override
  String get name => 'ignored';

  @override
  void route(PadStickTarget to, double x, double y, double dt) {}
}

final class _MoveStick extends PadStickUse {
  const _MoveStick();

  @override
  String get name => 'move';

  @override
  void route(PadStickTarget to, double x, double y, double dt) {
    // Y is negated because a pad reports positive downwards. Forward is
    // positive in the simulation, so the flip happens in the open.
    to.setStickAxis(x, -y);
  }

  /// The axis outlives the frame, so letting go of the pad has to clear it —
  /// and only a stick that was writing it may, since a game whose stick is
  /// routed to nothing has never touched the axis and must not start now.
  @override
  void letGo(PadStickTarget of) => of.setStickAxis(0.0, 0.0);
}

final class _LookStick extends PadStickUse {
  const _LookStick();

  @override
  String get name => 'look';

  @override
  void route(PadStickTarget to, double x, double y, double dt) {
    // Not negated: the mouse also reports positive downwards, and the camera
    // subtracts. A stick that agreed with the mouse about x and disagreed
    // about y would be a bug nobody could find by reading.
    to.addLook(x * to.lookRate * dt, y * to.lookRate * dt);
  }
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
  }) => PadRoutes(
    leftStick: PadStickUse.ignored,
    rightStick: PadStickUse.ignored,
    axisActions: <PadAxis, PadAxisPair>{
      PadAxis.leftStickX: PadAxisPair(
        negative: steerLeft,
        positive: steerRight,
      ),
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
