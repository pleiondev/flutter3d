/// What the player already told the operating system.
///
///     flutter test test/accommodations_test.dart
///
/// Somebody made ill by moving pictures turned reduce-motion on in the system
/// settings, probably years ago. A game that ignores it and offers its own
/// slider three menus deep has asked them to solve the same problem twice — in a
/// menu they may have to get through a moving camera to reach.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _under({required bool reduceMotion, required Widget child}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: child,
    );

void main() {
  testWidgets('a system that asks for less movement gets none', (
    WidgetTester tester,
  ) async {
    late Accommodations seen;
    await tester.pumpWidget(
      _under(
        reduceMotion: true,
        child: Builder(
          builder: (BuildContext context) {
            seen = Accommodations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen.reduceMotion, isTrue);
    expect(seen.cameraMotion, 0.0);
    expect(seen.screenFlash, 0.0);
  });

  testWidgets('and one that does not ask leaves the game alone', (
    WidgetTester tester,
  ) async {
    late Accommodations seen;
    await tester.pumpWidget(
      _under(
        reduceMotion: false,
        child: Builder(
          builder: (BuildContext context) {
            seen = Accommodations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen.cameraMotion, 1.0);
  });

  testWidgets('and no platform at all is not an accessibility exception', (
    WidgetTester tester,
  ) async {
    // A game mounted outside a `MediaQuery` — a test, a golden — should get the
    // unaccommodated defaults. Throwing from an accessibility feature would be a
    // particularly poor way to fail.
    late Accommodations seen;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          seen = Accommodations.of(context);
          return const SizedBox();
        },
      ),
    );

    expect(seen.reduceMotion, isFalse);
  });

  test('the system answer is a default and the player still overrules it', () {
    // **The direction that matters.** The other way round — a system flag
    // winning over a slider the player just moved — is the game arguing with
    // them, and the argument is unwinnable because they cannot see why.
    const system = Accommodations(reduceMotion: true);
    const config = GameSettings();
    double motion(GameSettings settings) =>
        settings.chosenValueOf(GameSettingKeys.cameraMotion) ??
        system.cameraMotion;

    expect(motion(config), 0.0);
    expect(motion(config.withValue(GameSettingKeys.cameraMotion, 0.6)), 0.6);
  });

  group('high contrast — N9', () {
    testWidgets('a system asking for more contrast is heard', (
      WidgetTester tester,
    ) async {
      // Mutation: leave `highContrast` out of `Accommodations.of`, and a
      // player who turned Increase Contrast on gets the game's default.
      late Accommodations seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: Builder(
            builder: (BuildContext context) {
              seen = Accommodations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.highContrast, isTrue);
      expect(const Accommodations().highContrast, isFalse);
    });

    test('and turns the look on until the player says otherwise', () {
      // The rule the camera's motion keeps, for the look: the system's
      // answer is the fallback, the player's switch is the answer. Mutation:
      // read the system flag over the setting, and the switch in the panel
      // stops working for exactly the players who need it to.
      const asked = Accommodations(highContrast: true);
      const config = GameSettings();
      expect(highContrastOf(config, asked).enabled, isTrue);
      expect(highContrastOf(config, const Accommodations()).enabled, isFalse);

      final off = config.withValue(GameSettingKeys.highContrast, false);
      expect(highContrastOf(off, asked).enabled, isFalse);
      final on = config.withValue(GameSettingKeys.highContrast, true);
      expect(highContrastOf(on, const Accommodations()).enabled, isTrue);
    });

    test('and only the switch is the player\'s; the rest is the game\'s', () {
      // A game that tuned its rings keeps them when the player turns the
      // look on. Mutation: build fresh settings rather than copying the base.
      final config = const GameSettings().withValue(
        GameSettingKeys.highContrast,
        true,
      );
      final look = highContrastOf(
        config,
        const Accommodations(),
        const HighContrastSettings(roleWidth: 4.0, saturation: 0.0),
      );
      expect(look.enabled, isTrue);
      expect(look.roleWidth, 4.0);
      expect(look.saturation, 0.0);
    });
  });
}
