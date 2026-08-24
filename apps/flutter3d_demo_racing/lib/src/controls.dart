/// What a player can ask this car for, and what a keyboard or a pad has to do
/// to ask for it.
///
/// Split out of `main.dart`: nothing here reads a scene, a car or a frame —
/// it is the table `_RaceScreenState` hands to `DesktopInput` and `PadInput`
/// at startup, and the actions `_readDriver` and `_readPitStop` read back out
/// of `InputState` once a step is running.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_app/flutter3d_app.dart'; // PadButton, from pad_input
import 'package:flutter3d_game/flutter3d_game.dart';

/// What this game lets a driver ask for.
///
/// Its own actions rather than the engine's `moveForward` and friends: a car
/// has a throttle and a brake, not a forward and a back, and `GameAction` is a
/// string for exactly this reason.
abstract final class Drive {
  static const GameAction throttle = GameAction('throttle');
  static const GameAction brake = GameAction('brake');
  static const GameAction left = GameAction('steerLeft');
  static const GameAction right = GameAction('steerRight');
  static const GameAction handbrake = GameAction('handbrake');

  /// Change tyres. A verb the car has rather than a screen, so it can be
  /// rebound like every other one and so a pad has it too.
  static const GameAction tyres = GameAction('tyres');
}

/// What a player can move, in the order the panel lists it.
///
/// A driver's words rather than a walker's: this game has a throttle and a
/// brake where the others have a forward and a back.
const List<GameAction> rebindableActions = <GameAction>[
  Drive.throttle,
  Drive.brake,
  Drive.left,
  Drive.right,
  Drive.handbrake,
  Drive.tyres,
];

/// The driving pad.
///
/// The triggers where every racing game has put them for twenty years, the
/// handbrake on the face button a thumb is already resting on, and the
/// engine's own defaults left out: this game does not walk, and a d-pad bound
/// to `moveForward` here would be a control that means nothing.
Bindings padBindings(Bindings bindings) => bindings
  ..bind(InputSource.pad(PadButton.triggerRight.id), Drive.throttle)
  ..bind(InputSource.pad(PadButton.triggerLeft.id), Drive.brake)
  ..bind(InputSource.pad(PadButton.faceSouth.id), Drive.handbrake)
  ..bind(InputSource.pad(PadButton.faceNorth.id), Drive.tyres)
  ..bind(InputSource.pad(PadButton.dpadLeft.id), Drive.left)
  ..bind(InputSource.pad(PadButton.dpadRight.id), Drive.right);

/// The driving keys.
///
/// A table of its own rather than the engine's defaults, which name walking:
/// a car has a throttle and a brake, not a forward and a back. The arrows are
/// bound alongside the letters because half the people who sit down at a
/// racing game reach for them first.
Bindings driveKeys() {
  final bindings = Bindings(<InputSource, GameAction>{});
  void bind(LogicalKeyboardKey key, GameAction action) =>
      bindings.bind(InputSource.key(key.keyId), action);

  bind(LogicalKeyboardKey.keyW, Drive.throttle);
  bind(LogicalKeyboardKey.arrowUp, Drive.throttle);
  bind(LogicalKeyboardKey.keyS, Drive.brake);
  bind(LogicalKeyboardKey.arrowDown, Drive.brake);
  bind(LogicalKeyboardKey.keyA, Drive.left);
  bind(LogicalKeyboardKey.arrowLeft, Drive.left);
  bind(LogicalKeyboardKey.keyD, Drive.right);
  bind(LogicalKeyboardKey.arrowRight, Drive.right);
  bind(LogicalKeyboardKey.space, Drive.handbrake);
  bind(LogicalKeyboardKey.keyT, Drive.tyres);
  return bindings;
}
