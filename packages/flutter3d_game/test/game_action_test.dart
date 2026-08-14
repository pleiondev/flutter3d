/// [GameAction] stopped being an enum so that a genre could add its own, and
/// these are the two properties that makes true rather than merely claimed.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Declared here, in a package that ships neither — which is the whole point.
const GameAction _dash = GameAction('dash');
const GameAction _grab = GameAction('grab');

/// The same action as [_dash], built the way a rebinding file is read back.
///
/// **Deliberately not `const`, and the first version of this test was.** Two
/// identical const expressions are canonicalised by Dart into one instance, so
/// identity equality answered them correctly and the test passed with `==`
/// deleted — a test that could not fail. Going through a string the compiler
/// cannot fold is what makes the question real, and it is also the case that
/// actually matters: a saved config holds names, not objects.
GameAction _fromSavedConfig(String name) => GameAction(name);

void main() {
  test('an action read back from a name is the action it names', () {
    // Mutation: drop the `==` and `hashCode` overrides. The two are separate
    // instances, the held-state set stops recognising the second as the first,
    // and every rebinding a player saved is silently forgotten on load.
    final loaded = _fromSavedConfig('dash');

    expect(identical(loaded, _dash), isFalse, reason: 'or the test is vacuous');
    expect(loaded, _dash);
    expect(loaded.hashCode, _dash.hashCode);

    final input = InputState()..press(_dash);
    expect(input.held(loaded), isTrue);
  });

  test('an action the engine never heard of latches like a built-in one', () {
    // Mutation: make `press` skip actions not in `GameAction.common`. Every
    // assertion below still passes for `jump` and none of them for `_grab`,
    // which is the failure a genre package would hit on its first step.
    final input = InputState()..beginStep();

    input.press(_grab);
    expect(input.pressed(_grab), isTrue);
    expect(input.held(_grab), isTrue);

    input
      ..release(_grab)
      ..endStep();
    expect(input.held(_grab), isFalse);
    expect(input.pressed(_grab), isFalse, reason: 'the latch is cleared');
  });

  test('a custom action does not move the player', () {
    // The movement axis reads four named actions. A fifth must not join them by
    // accident — which it would if the axis were computed from "everything
    // held" rather than from the four it names.
    final input = InputState()..press(_dash);
    expect(input.moveAxis.length, 0.0);

    input.press(GameAction.moveForward);
    expect(input.moveAxis.y, 1.0);
  });
}
