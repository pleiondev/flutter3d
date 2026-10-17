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

import 'package:flutter/cupertino.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
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
    testWidgets('says so, and says what rebuilds the bundle', (
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
      expect(
        find.textContaining('build the application again'),
        findsOneWidget,
      );
      // A path into the engine's repository means nothing to a person who
      // installed the package.
      expect(find.textContaining('packages/'), findsNothing);
    });
  });

  group('the moment in between', () {
    testWidgets('says something rather than showing black', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoadingScreen()));

      expect(find.text('Loading…'), findsOneWidget);
    });

    testWidgets('in the reader\'s language', (WidgetTester tester) async {
      // Mutation: type the English word back into the screen and a game in
      // Russian loads in English.
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: Flutter3dAppLocalizations.supportedLocales,
          localizationsDelegates: <LocalizationsDelegate<Object>>[
            Flutter3dAppLocalizations.delegate,
            _MaterialInAnyLanguage(),
            _CupertinoInAnyLanguage(),
          ],
          home: LoadingScreen(),
        ),
      );

      expect(find.text('Загрузка…'), findsOneWidget);
    });
  });
}

/// Material's English words under any locale, so a test can pump a Russian
/// app without `flutter_localizations`.
final class _MaterialInAnyLanguage
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialInAnyLanguage();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const DefaultMaterialLocalizations(),
      );

  @override
  bool shouldReload(_MaterialInAnyLanguage old) => false;
}

/// Cupertino's English words under any locale, for the same reason: a
/// `MaterialApp` asks for both and warns when a locale has no Cupertino one.
final class _CupertinoInAnyLanguage
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoInAnyLanguage();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const DefaultCupertinoLocalizations(),
      );

  @override
  bool shouldReload(_CupertinoInAnyLanguage old) => false;
}
