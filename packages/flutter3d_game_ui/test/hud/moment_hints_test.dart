/// Hints said once, at the moment they are true.
///
///     flutter test test/moment_hints_test.dart
library;

import 'package:flutter3d_game_ui/hud.dart';
import 'package:flutter_test/flutter_test.dart';

const MomentHint<String> _jump = MomentHint<String>(
  'Hold to jump higher.',
  when: _isJump,
);
const MomentHint<String> _land = MomentHint<String>(
  'Land on the ledge.',
  when: _isLand,
);

bool _isJump(String event) => event == 'jump';
bool _isLand(String event) => event == 'land';

void main() {
  test('a hint is said when its moment is among the events', () {
    expect(
      _jump.hintFor(<String>['walk', 'jump'], alreadyTaught: false),
      _jump.text,
    );
    // Mutation: say it on any step — this is not null.
    expect(_jump.hintFor(<String>['walk'], alreadyTaught: false), isNull);
  });

  test('a hint already taught is not said again', () {
    // Mutation: ignore `alreadyTaught` — the hint repeats every time.
    expect(_jump.hintFor(<String>['jump'], alreadyTaught: true), isNull);
  });

  test('several hints are each said once, in order, one a step', () {
    final hints = MomentHints<String>(<MomentHint<String>>[_jump, _land]);
    // Both moments on one step: the first in order is said, the second waits.
    // Mutation: say every matching hint — two sentences at once.
    expect(hints.next(<String>['land', 'jump']), _jump.text);
    expect(hints.taught(_jump), isTrue);
    expect(hints.taught(_land), isFalse);
    expect(hints.next(<String>['land']), _land.text);
    // Mutation: forget to mark a hint taught — it is said again here.
    expect(hints.next(<String>['jump', 'land']), isNull);
  });

  test('forgetting starts a run afresh', () {
    final hints = MomentHints<String>(<MomentHint<String>>[_jump]);
    expect(hints.next(<String>['jump']), _jump.text);
    hints.forget();
    // Mutation: make `forget` a no-op — a restarted run is never taught.
    expect(hints.next(<String>['jump']), _jump.text);
  });
}
