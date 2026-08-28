/// Whether the game should be standing still.
///
///     flutter test test/pause_gate_test.dart
///
/// **The line this covers has been wrong three times**, each time the same way:
/// it answered a question about the player's attention by asking about a device.
/// Each of the three is a test below, named as the player would describe it.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desktop build, where the pointer is the gate.
bool desktop({
  bool ready = true,
  bool menuOpen = false,
  bool pointerHeld = true,
  bool padConnected = false,
}) => shouldPause(
  ready: ready,
  menuOpen: menuOpen,
  pointerIsTheGate: true,
  pointerHeld: pointerHeld,
  padConnected: padConnected,
);

/// A browser or a phone: there is no pointer to take.
bool touch({bool ready = true, bool menuOpen = false}) => shouldPause(
  ready: ready,
  menuOpen: menuOpen,
  pointerIsTheGate: false,
  pointerHeld: false,
  padConnected: false,
);

void main() {
  test('a level that has not loaded is not running', () {
    expect(desktop(ready: false), isTrue);
    expect(touch(ready: false), isTrue);
  });

  test('letting the mouse go stops the game', () {
    // The original rule, and still right: the crosshair is gone and the cursor
    // is back, so a game that kept simulating would run behind the player.
    expect(desktop(pointerHeld: false), isTrue);
    expect(desktop(), isFalse);
  });

  test('but a controller is a second way of being here', () {
    // **Wrong the first time.** A player holding a pad never captures the
    // pointer, so the game sat frozen while they pressed everything on it.
    expect(desktop(pointerHeld: false, padConnected: true), isFalse);
  });

  test('and a build with no pointer to take is not permanently paused', () {
    // **Wrong the second time.** A browser and a phone have nothing to capture,
    // so the same clause opened them on a still picture.
    expect(touch(), isFalse);
  });

  test('and a menu stops the game wherever it is open', () {
    // **Wrong the third time, and the longest lived.** The settings panel looked
    // as though it paused, because opening it released the mouse and the mouse
    // was the gate. It never paused anything: on the web and on a phone the game
    // ran behind the panel from the day each shipped, and on the desktop it
    // started running behind it the day a pad could hold the gate open.
    expect(desktop(menuOpen: true), isTrue);
    expect(
      desktop(menuOpen: true, padConnected: true),
      isTrue,
      reason: 'a connected pad kept the game running behind the settings',
    );
    expect(
      touch(menuOpen: true),
      isTrue,
      reason: 'the panel never paused a browser or a phone at all',
    );
  });
}
