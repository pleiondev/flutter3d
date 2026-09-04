/// The two verbs a shooter has that the engine's binding table has never
/// heard of.
///
/// `ShooterActions` exists so that the engine's input layer need not know that
/// games shoot — its own doc says so — and the price of that is exactly this:
/// `fire` and `crouch` are not in `DesktopInput.defaultBindings`, and the game
/// has to put them in. `fire` was put in, at the pad, by hand, in two places
/// that had to agree. `crouch` was put in nowhere at all, on any device, so
/// `player.crouch(held: input.held(ShooterActions.crouch))` — which the
/// simulation runs every step — had never once been true in the only game
/// built on the package. The body could crouch; nobody could ask it to.
///
/// A file of its own rather than a static on the screen's state, because the
/// state is private and this is the sort of claim that wants a test.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_app/flutter3d_app.dart'; // PadButton, from pad_input
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';

/// Adds this genre's own bindings to [bindings], and returns it.
///
/// C and the right stick's click for crouching, which is where a hand looks
/// for it; the right trigger and the right shoulder for firing, which is where
/// this game already had it.
Bindings addShooterKeysTo(Bindings bindings) => bindings
  ..bind(InputSource.pad(PadButton.triggerRight.id), ShooterActions.fire)
  ..bind(InputSource.pad(PadButton.shoulderRight.id), ShooterActions.fire)
  ..bind(InputSource.key(LogicalKeyboardKey.keyC.keyId), ShooterActions.crouch)
  ..bind(InputSource.pad(PadButton.stickRightClick.id), ShooterActions.crouch);
