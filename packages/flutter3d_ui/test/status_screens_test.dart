/// The three screens a game is on when it is not the game.
///
///     flutter test test/status_screens_test.dart
///
/// **Four hand-rolled copies and three inline spinners**, and none of them in
/// the package that exports every other non-game screen. The two that had
/// grown something the others had not are what this keeps: the crypt's
/// renderer failure carried the shader-bundle diagnostic, which is engine
/// knowledge that had no business living in a game, and the platformer's level
/// failure carried a way out, which is the half that matters most.
///
/// The widget half of `flutter3d_demo_platformer/test/level_error_test.dart`
/// moved here with the widget. Its other half — that a broken level document
/// really does throw — stayed there, because that is a claim about that game's
/// levels.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a level that would not load', () {
    testWidgets('names the level and the reason', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LevelLoadFailed(
            asset: 'assets/levels/ascent.json',
            error: 'brush 0 has no size',
          ),
        ),
      );

      expect(find.textContaining('would not load'), findsOneWidget);
      expect(find.text('assets/levels/ascent.json'), findsOneWidget);
      expect(find.textContaining('brush 0 has no size'), findsOneWidget);
    });

    testWidgets('and offers the only thing that can help', (
      WidgetTester tester,
    ) async {
      // **The failing level is usually the saved one.** A player whose save
      // points at a level that will not read cannot be rescued by retrying it,
      // only by throwing the run away — and they cannot do that from a black
      // screen.
      var started = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LevelLoadFailed(
            asset: 'assets/levels/ascent.json',
            error: 'anything',
            onStartOver: () => started++,
          ),
        ),
      );

      await tester.tap(find.textContaining('start again'));
      expect(started, 1);
    });

    testWidgets('and offers nothing when there is nothing to offer', (
      WidgetTester tester,
    ) async {
      // Optional rather than required, which is the difference between the two
      // copies this replaces: a game with no save to throw away should not
      // have to invent a button, and the crypt did not have one.
      //
      // Mutation: make `onStartOver` required and always render the button.
      // The crypt grows a control that does nothing.
      await tester.pumpWidget(
        const MaterialApp(
          home: LevelLoadFailed(asset: 'a.json', error: 'anything'),
        ),
      );

      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('a renderer that did not start', () {
    testWidgets('says so, and says where the bundle comes from', (
      WidgetTester tester,
    ) async {
      // The diagnostic is the engine's own build step, and a person meeting
      // this screen is far more likely to have changed the Flutter SDK than to
      // have broken their game. It lived in one application.
      await tester.pumpWidget(
        const MaterialApp(home: RendererFailure(error: 'no shader bundle')),
      );

      expect(find.textContaining('did not start'), findsOneWidget);
      expect(find.textContaining('no shader bundle'), findsOneWidget);
      expect(find.textContaining('build_shaders.sh'), findsOneWidget);
    });
  });

  group('the moment in between', () {
    testWidgets('says something rather than showing black', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoadingScreen()));

      expect(find.text('Loading…'), findsOneWidget);
    });
  });
}
