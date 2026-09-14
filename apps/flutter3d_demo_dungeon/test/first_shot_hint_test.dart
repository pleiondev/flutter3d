/// `ls-g-01`'s own rule: the first shot of a run says [firstShotHint], and
/// nothing else — a pure function, checked without a running simulation.
///
///     flutter test test/first_shot_hint_test.dart
library;

import 'package:flutter3d_demo_dungeon/src/first_shot_hint.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' show Weapons;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

List<GameEvent> _shotFired() => <GameEvent>[
  ShotFired(weapon: Weapons.pistol, from: Vector3.zero()),
];

void main() {
  test('the first shot of a run says the hint', () {
    expect(firstShotHintFor(_shotFired(), alreadyTaught: false), firstShotHint);
  });

  test('already taught this run: says nothing, even on another shot', () {
    expect(firstShotHintFor(_shotFired(), alreadyTaught: true), isNull);
  });

  test('no shot this step: says nothing', () {
    expect(firstShotHintFor(const <GameEvent>[], alreadyTaught: false), isNull);
  });

  test('a step with more than one shot still says the hint once', () {
    expect(
      firstShotHintFor(<GameEvent>[
        ..._shotFired(),
        ..._shotFired(),
      ], alreadyTaught: false),
      firstShotHint,
    );
  });
}
