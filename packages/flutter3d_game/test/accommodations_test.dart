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
    final config = GameConfig();

    expect(config.settingOf('a11y.cameraMotion', system.cameraMotion), 0.0);

    config.setSetting('a11y.cameraMotion', 0.6);
    expect(config.settingOf('a11y.cameraMotion', system.cameraMotion), 0.6);
  });
}
