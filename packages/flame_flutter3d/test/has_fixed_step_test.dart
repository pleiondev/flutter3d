/// A game whose own logic runs in fixed steps, and input that waits for a
/// step to read it.
library;

import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show Bindings, InputSource;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Stepped extends FlameGame with HasFixedStep {
  int steps = 0;

  @override
  void fixedUpdate(double step) => steps++;
}

final class _Ticker extends Component with FixedStepUpdate {
  int steps = 0;

  @override
  void fixedUpdate(double step) => steps++;
}

void main() {
  testWithGame<_Stepped>(
    'the game and its stepped components run once per step, not per frame',
    _Stepped.new,
    (game) async {
      final ticker = _Ticker();
      await game.add(ticker);
      await game.ready();

      for (var i = 0; i < 4; i++) {
        game.update(1 / 120);
      }
      expect(game.steps, 2, reason: 'four half-steps are two steps');
      expect(ticker.steps, 2);

      game.update(1 / 30);
      expect(game.stepsThisFrame, 2);
      expect(ticker.steps, 4);
    },
  );

  testWithGame<_Stepped>(
    'a press in a frame with no step waits for the next step',
    _Stepped.new,
    (game) async {
      // Mutation: close the input step every frame, step or not.
      final input = FlameInputBridge(
        bindings: Bindings(<InputSource, GameAction>{}),
        inputState: InputState(),
      );
      await game.add(input.stepEnd());
      await game.ready();
      const fire = GameAction('fire');

      input.inputState.press(fire);
      game.update(1 / 240);
      expect(game.stepsThisFrame, 0);
      expect(input.inputState.pressed(fire), isTrue, reason: 'still unread');

      game.update(1 / 60);
      expect(game.stepsThisFrame, 1);
      expect(input.inputState.pressed(fire), isFalse, reason: 'read, closed');
    },
  );
}
