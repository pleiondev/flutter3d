/// A wheel and pedals, for a player with no keyboard.
///
///     flutter test test/touch_drive_test.dart
///
/// **This game had nothing to offer a phone.** A car has no thumb stick, so
/// the shared widget does not fit, and the two things a driver holds — a
/// steering axis and a pedal held for a whole corner — had to be their own.
/// They are `flutter3d_game_ui`'s now (`SteeringBand`, `TouchButton.pedal`, `TouchDrive`), with
/// their tests. What is left here is that this game draws them, and with the
/// pit stop on the corner button.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the game shows them where there is no keyboard', () {
    final game = File('lib/main.dart').readAsStringSync();

    // Mutation: draw the wheel unconditionally — the second expectation
    // fails; drop it from the stack and the first does.
    expect(
      game,
      contains('TouchDrive('),
      reason: 'a phone gets a car it cannot drive',
    );
    expect(
      game,
      contains('_playing.touch'),
      reason: 'a wheel is drawn over a desktop that has a keyboard',
    );
  });

  test('and the pit stop is a control rather than an instruction', () {
    // **The HUD told a driver to stop and change, and a phone had no way to.**
    // The tyre line reads `STOP FIRST` when a change is refused at speed,
    // which is an instruction — and `Drive.tireSet` was bound to a key, to a pad
    // button and to nothing a finger could reach.
    //
    // Mutation: drop the `corner:` argument from the game's `TouchDrive` —
    // this fails.
    final game = File('lib/main.dart').readAsStringSync();
    expect(
      game,
      contains("corner: const TouchAction(Drive.tyres, 'pit')"),
      reason: 'no way to call a pit stop',
    );
  });
}
