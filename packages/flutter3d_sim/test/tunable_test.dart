/// A tunable by type, over the table of numbers by name.
///
///     dart test test/tunable_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

final Tunable<double> _jump = Tunable.number('jump', 7.5);
final Tunable<int> _lives = Tunable.whole('lives', 3);
final Tunable<bool> _fog = Tunable.flag('fog', initial: true);

void main() {
  test('a table made of tunables starts each at its own value', () {
    final tunables = Tunables.of(<Tunable<Object>>[_jump, _lives, _fog]);
    expect(tunables.defaults, <String, double>{
      'jump': 7.5,
      'lives': 3.0,
      'fog': 1.0,
    });
    expect(_jump.of(tunables), 7.5);
    expect(_lives.of(tunables), 3);
    expect(_fog.of(tunables), isTrue);
  });

  test('set through the input, read typed on the next step', () {
    final tunables = Tunables.of(<Tunable<Object>>[_jump, _lives, _fog]);
    final input = InputState();
    _lives.set(input, 5);
    _fog.set(input, false);
    // An inspector drags the whole number past a whole: it reads rounded.
    // Mutation: decode a whole number with `toInt()` and 2.6 reads 2.
    input.tune('jump', 9.0);
    input.beginStep();
    tunables.readFrom(input);
    input.endStep();
    expect(_jump.of(tunables), 9.0);
    expect(_lives.of(tunables), 5);
    expect(_fog.of(tunables), isFalse);

    input.tune('lives', 2.6);
    input.beginStep();
    tunables.readFrom(input);
    input.endStep();
    expect(_lives.of(tunables), 3);
  });

  test('two tunables of one name are refused', () {
    expect(
      () => Tunables.of(<Tunable<Object>>[_jump, Tunable.number('jump', 1.0)]),
      throwsArgumentError,
    );
  });
}
