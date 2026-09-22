/// `ux-26`'s own panel, and the two things it added to the strip.
///
///     flutter test test/console_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/console_log.dart';
import 'package:flutter3d_modeler/src/mouse_hints.dart';
import 'package:flutter3d_modeler/src/settings.dart' show NavigationScheme;
import 'package:flutter3d_modeler/src/ui/console_panel.dart';
import 'package:flutter3d_modeler/src/ui/status_line.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

ConsoleLog _log() {
  var at = DateTime.utc(2026, 9, 16, 14);
  DateTime tick() => at = at.add(const Duration(seconds: 1));
  return ConsoleLog()
    ..add(
      ConsoleEntry(at: tick(), text: 'opened', author: ConsoleAuthor.person),
    )
    ..add(
      ConsoleEntry(
        at: tick(),
        text: 'added a box',
        author: ConsoleAuthor.agent,
        tool: 'addPrimitive',
      ),
    )
    ..add(
      ConsoleEntry(
        at: tick(),
        text: 'nothing is selected to extrude',
        author: ConsoleAuthor.person,
        kind: ConsoleKind.refusal,
      ),
    );
}

Future<void> _pumpPanel(WidgetTester tester, ConsoleLog log) async {
  tester.view
    ..physicalSize = const Size(900, 400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: modelerTheme(),
      home: Scaffold(body: ConsolePanel(log: log)),
    ),
  );
}

void main() {
  group('ux-26: the console panel', () {
    testWidgets('shows everything said, newest first', (
      WidgetTester tester,
    ) async {
      await _pumpPanel(tester, _log());

      expect(find.textContaining('opened'), findsOneWidget);
      expect(find.textContaining('added a box'), findsOneWidget);
      expect(find.textContaining('nothing is selected'), findsOneWidget);

      // Mutation: draw it oldest-first, the order the log itself keeps. The
      // thing that just happened is then at the bottom of a scrolling list,
      // which is the one interaction a console must not ask for.
      final double newest = tester
          .getTopLeft(find.textContaining('nothing is selected'))
          .dy;
      final double oldest = tester.getTopLeft(find.textContaining('opened')).dy;
      expect(newest, lessThan(oldest));
    });

    testWidgets('and the filter keeps one side of the conversation', (
      WidgetTester tester,
    ) async {
      await _pumpPanel(tester, _log());

      // Each row names its own author as well, so "Agent" and "You" are on
      // this panel twice over and a bare text finder cannot say which one it
      // means — the filter is the one inside the `SegmentedButton`.
      Finder filter(String named) => find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text(named),
      );

      await tester.tap(filter('Agent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('added a box'), findsOneWidget);
      expect(find.textContaining('opened'), findsNothing);

      await tester.tap(filter('You'));
      await tester.pumpAndSettle();

      expect(find.textContaining('added a box'), findsNothing);
      expect(find.textContaining('opened'), findsOneWidget);
    });

    testWidgets('a refusal is not the same colour as a report', (
      WidgetTester tester,
    ) async {
      await _pumpPanel(tester, _log());

      Color colourOf(String said) =>
          tester.widget<Text>(find.textContaining(said)).style!.color!;

      // Mutation: one colour for every line. The console is then a wall of
      // grey that a person scans instead of reads — which is exactly what
      // `ux-17` found the status line had become.
      expect(colourOf('nothing is selected'), isNot(colourOf('opened')));
    });

    testWidgets('an empty log says so rather than showing nothing', (
      WidgetTester tester,
    ) async {
      await _pumpPanel(tester, ConsoleLog());

      expect(find.textContaining('nothing has been said'), findsOneWidget);
    });
  });

  group('ux-26: what the strip gained', () {
    Future<void> pumpStrip(
      WidgetTester tester, {
      MouseHints? hints,
      VoidCallback? onConsole,
    }) async {
      tester.view
        ..physicalSize = const Size(1400, 200)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: StatusLine(
              said: 'saved',
              readiness: ExportReadiness.check(const ModelProject()),
              triangles: 12,
              vertices: 8,
              materialCount: 0,
              mouseHints: hints,
              onConsole: onConsole,
            ),
          ),
        ),
      );
    }

    testWidgets('the hints, when there are buttons to describe', (
      WidgetTester tester,
    ) async {
      await pumpStrip(
        tester,
        hints: mouseHintsFor(scheme: NavigationScheme.middleMouseOrbit),
      );

      expect(find.textContaining('M Orbit'), findsOneWidget);
    });

    testWidgets('and nothing at all where there are none', (
      WidgetTester tester,
    ) async {
      await pumpStrip(tester);

      // Mutation: always draw them. A touch shell then says what three
      // buttons do on a device with none, which is three lies in the one
      // place a person goes for the truth.
      expect(find.textContaining('M Orbit'), findsNothing);
    });

    testWidgets('and the sentence opens the console', (
      WidgetTester tester,
    ) async {
      var opened = 0;
      await pumpStrip(tester, onConsole: () => opened++);

      await tester.tap(find.text('saved'));
      await tester.pump();

      expect(opened, 1);
    });
  });
}
