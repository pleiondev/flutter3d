/// The title, the ending, a cutscene's overlay and the lens.
///
///     flutter test test/screens_test.dart
///
/// Each screen draws what a game hands it and nothing it made up: the lines
/// about the keys, the tallies, the credits owed. The lens keeps one base and
/// moves only the field of view.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show PerspectiveProjection;
import 'package:flutter3d_game_ui/screens.dart';
import 'package:flutter_test/flutter_test.dart';

const Credit _owed = Credit(
  file: 'models/car.glb',
  work: 'A car',
  author: 'Somebody',
  source: 'https://example.org/car',
  license: 'CC BY 4.0',
  licenseUrl: 'http://creativecommons.org/licenses/by/4.0/',
);

Widget _app(Widget home) => MaterialApp(home: Scaffold(body: home));

void main() {
  group('the title sheet', () {
    testWidgets('says the name, the lines handed in and how to begin', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const TitleSheet(
            title: 'Ascent',
            tagline: 'A summit.',
            lines: <String>['W to walk.', 'Space to jump.'],
            credits: <Credit>[_owed],
            prompt: 'Click to play.',
          ),
        ),
      );
      // Mutation: drop the `for (final line in lines)` from the sheet — the
      // control lines are not on screen.
      expect(find.text('W to walk.'), findsOneWidget);
      expect(find.text('Space to jump.'), findsOneWidget);
      expect(find.text('Ascent'), findsOneWidget);
      expect(find.text('Click to play.'), findsOneWidget);
      // Mutation: drop the `CreditsSection` — the author owed a line is gone.
      expect(find.textContaining('Somebody'), findsOneWidget);
    });

    testWidgets('shows the notice only when there is one', (
      WidgetTester tester,
    ) async {
      Widget sheet(String? notice) => _app(
        TitleSheet(
          title: 'Ascent',
          tagline: 'A summit.',
          lines: const <String>[],
          credits: const <Credit>[],
          prompt: 'Go.',
          notice: notice,
        ),
      );
      await tester.pumpWidget(sheet('Your last checkpoint is waiting.'));
      expect(find.text('Your last checkpoint is waiting.'), findsOneWidget);

      // Mutation: draw the notice whatever it is, `?? ''` — an empty amber
      // line takes its place and the count of texts changes.
      await tester.pumpWidget(sheet(null));
      expect(find.text('Your last checkpoint is waiting.'), findsNothing);
      expect(find.text(''), findsNothing);
    });

    testWidgets('begins on a touch anywhere on it, when it is asked to', (
      WidgetTester tester,
    ) async {
      var begins = 0;
      await tester.pumpWidget(
        _app(
          TitleSheet(
            title: 'Ring',
            tagline: 'Five circuits.',
            lines: const <String>['The band steers.'],
            credits: const <Credit>[],
            prompt: 'Touch to start.',
            onBegin: () => begins++,
          ),
        ),
      );
      // Mutation: drop the `Listener` from `TitleSheet.build` — the sheet
      // is opaque and nothing under it hears the touch, so `begins` stays
      // at nought.
      await tester.tap(find.text('The band steers.'));
      expect(begins, 1);
    });
  });

  group('the ending sheet', () {
    testWidgets('draws each tally as one thing a reader says', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const EndingSheet(
            title: 'You reached the summit.',
            tallies: <EndingTally>[
              EndingTally('time', '4:12'),
              EndingTally('falls', '3'),
            ],
            credits: <Credit>[_owed],
            again: 'Press R to climb it again.',
          ),
        ),
      );
      expect(find.text('You reached the summit.'), findsOneWidget);
      expect(find.text('4:12'), findsOneWidget);
      expect(find.text('Press R to climb it again.'), findsOneWidget);
      // Mutation: drop `excludeSemantics` from `TallyView` — the number and
      // its label are read as two nodes and this label is not found.
      expect(find.bySemanticsLabel('falls 3'), findsOneWidget);
      expect(find.textContaining('Somebody'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('says the aside and the trailing lines it is handed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const EndingSheet(
            title: 'Out.',
            tallies: <EndingTally>[],
            credits: <Credit>[],
            again: 'Tap to go again.',
            aside: 'This machine lost 3s.',
            trailing: <Widget>[Text('Or N, to go deeper.')],
          ),
        ),
      );
      // Mutation: drop the `aside` block — the line about lost time is gone.
      expect(find.text('This machine lost 3s.'), findsOneWidget);
      // Mutation: drop `...trailing` from the column — this fails.
      expect(find.text('Or N, to go deeper.'), findsOneWidget);
    });
  });

  group('the cutscene overlay', () {
    testWidgets('shows the subtitle and skips on its button', (
      WidgetTester tester,
    ) async {
      var skipped = 0;
      await tester.pumpWidget(
        _app(
          CutsceneOverlay(
            fade: 0.4,
            subtitle: 'The door is open.',
            skipHint: 'Skip',
            onSkip: () => skipped++,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('cutscene:subtitle')),
        findsOneWidget,
      );
      // Mutation: wrap the skip button in the `IgnorePointer` the fade has —
      // the tap lands on nothing.
      await tester.tap(find.byKey(const ValueKey<String>('cutscene:skip')));
      expect(skipped, 1);
    });

    testWidgets('and says nothing when nothing is said', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          CutsceneOverlay(
            fade: 2.0,
            subtitle: null,
            skipHint: 'Skip',
            onSkip: () {},
          ),
        ),
      );
      // Mutation: drop the `said != null` condition and draw `''` — a
      // subtitle with nothing in it is still found.
      expect(
        find.byKey(const ValueKey<String>('cutscene:subtitle')),
        findsNothing,
      );
      // A fade past one is clamped rather than thrown on.
      expect(tester.takeException(), isNull);
    });
  });

  group('the lens', () {
    const base = PerspectiveProjection(fovY: 1.05, far: 220.0);

    test('widens only the field of view', () {
      const lens = Lens(base);
      final wide = lens.widened(0.12);
      // Mutation: build `widened` from `const PerspectiveProjection()` — the
      // far plane jumps back to the default and the second line fails.
      expect(wide.fovY, closeTo(1.17, 1e-9));
      expect(wide.far, base.far);
      expect(wide.near, base.near);
    });

    test('with no design aspect, ignores the screen', () {
      const lens = Lens(base);
      expect(lens.fovYAt(0.5), base.fovY);
      expect(lens.at(0.5).fovY, base.fovY);
    });

    test('keeps the horizontal view on a screen narrower than designed', () {
      const lens = Lens(base, designAspect: 16.0 / 9.0);
      double across(double fovY, double aspect) =>
          2.0 * math.atan(math.tan(fovY / 2.0) * aspect);

      // Wide enough: drawn as written.
      expect(lens.fovYAt(2.0), base.fovY);
      expect(lens.fovYAt(16.0 / 9.0), base.fovY);

      // Upright: the vertical view opens until the horizontal one is what it
      // was at the design aspect. Mutation: multiply by `aspect` rather than
      // divide in `fovYAt` — the view narrows instead.
      final upright = lens.fovYAt(9.0 / 16.0);
      expect(upright, greaterThan(base.fovY));
      expect(
        across(upright, 9.0 / 16.0),
        // `Portable`'s tangent against the platform's: close, not the same
        // bits.
        closeTo(across(base.fovY, 16.0 / 9.0), 1e-6),
      );
      expect(
        lens.at(9.0 / 16.0, extraFovY: 0.1).fovY,
        closeTo(upright + 0.1, 1e-9),
      );
      expect(lens.at(9.0 / 16.0).far, base.far);
    });
  });
}
