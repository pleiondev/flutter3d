/// Colours with meanings, and the ones a player picks in their place.
///
///     flutter test test/color_roles_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two marks a deutan cannot tell apart as the game has them: a red and a
/// green of nearly one lightness.
final ColorRoles _marks = ColorRoles(const <ColorRole>[
  ColorRole('enemy', 'Enemies', Color.fromARGB(255, 204, 64, 51)),
  ColorRole('friend', 'Friends', Color.fromARGB(255, 115, 140, 51)),
]);

void main() {
  test('a role is its own colour until the player picks another', () {
    const config = GameSettings();
    final enemy = _marks.named('enemy')!;
    expect(_marks.of(enemy, config), enemy.color);
    // Mutation: counting the palette from the role's own colour puts every
    // choice one along.
    expect(
      _marks.of(enemy, config.withValue(enemy.setting, 2)),
      ColorRoles.palette[1],
    );
    expect(_marks.of(enemy, config.withValue(enemy.setting, 40)), enemy.color);
  });

  test('the lint reads the colours as the player has them', () {
    const config = GameSettings();
    expect(
      _marks.confusions(<String>['enemy', 'friend'], config).map((c) => c.by),
      contains(ColorVisionDeficiency.deutan),
    );
    // Orange and blue, from the palette: apart for everybody. Mutation:
    // linting the roles' own colours whatever the player chose.
    final chosen = config
        .withValue(GameSettingKeys.colorRole('enemy'), 2)
        .withValue(GameSettingKeys.colorRole('friend'), 6);
    expect(_marks.confusions(<String>['enemy', 'friend'], chosen), isEmpty);
  });
}
