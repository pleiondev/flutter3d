/// Colours with meanings, and the ones a player picks in their place.
///
///     flutter test test/color_roles_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show ColorVisionDeficiency;
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two marks a deutan cannot tell apart as the game has them: a red and a
/// green of nearly one lightness.
final ColorRoles _marks = ColorRoles(const <ColorRole>[
  ColorRole('enemy', 'Enemies', Color.fromARGB(255, 204, 64, 51)),
  ColorRole('friend', 'Friends', Color.fromARGB(255, 115, 140, 51)),
]);

void main() {
  test('a role is its own colour until the player picks another', () {
    final config = GameConfig();
    final enemy = _marks.named('enemy')!;
    expect(_marks.of(enemy, config), enemy.colour);
    config.setSetting(enemy.setting, 2);
    // Mutation: counting the palette from the role's own colour puts every
    // choice one along.
    expect(_marks.of(enemy, config), ColorRoles.palette[1]);
    config.setSetting(enemy.setting, 40);
    expect(_marks.of(enemy, config), enemy.colour);
  });

  test('the lint reads the colours as the player has them', () {
    final config = GameConfig();
    expect(
      _marks.confusions(<String>['enemy', 'friend'], config).map((c) => c.by),
      contains(ColorVisionDeficiency.deutan),
    );
    // Orange and blue, from the palette: apart for everybody. Mutation:
    // linting the roles' own colours whatever the player chose.
    config
      ..setSetting('colour.enemy', 2)
      ..setSetting('colour.friend', 6);
    expect(_marks.confusions(<String>['enemy', 'friend'], config), isEmpty);
  });

  testWidgets('the panel lists the roles and writes the choice', (
    WidgetTester tester,
  ) async {
    final written = <String, double>{};
    Widget panel(ColorRoles? colours) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          mixer: Mixer(),
          bindings: DesktopInput.defaultBindings(),
          config: GameConfig(),
          padConnected: false,
          onVolume: (AudioBus bus, double volume) {},
          onSetting: (String name, double value) => written[name] = value,
          onClose: () {},
          actions: const <GameAction>[],
          waitingFor: null,
          onRebind: (GameAction? action) {},
          onResetControls: () {},
          colours: colours,
        ),
      ),
    );
    await tester.pumpWidget(panel(null));
    expect(find.text('Colours'), findsNothing);

    await tester.pumpWidget(panel(_marks));
    final swatch = find.byKey(const ValueKey<String>('colour:Friends:3'));
    await tester.scrollUntilVisible(swatch, 100);
    await tester.tap(swatch);
    expect(find.text('Enemies'), findsOne);
    expect(written['colour.friend'], 3.0);
  });
}
