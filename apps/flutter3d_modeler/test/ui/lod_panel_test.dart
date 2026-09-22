/// `pro-lod-04`'s own panel, and the rule its wiring adds levels by.
///
///     flutter test test/ui/lod_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/lod_panel_state.dart';
import 'package:flutter3d_modeler/src/ui/lod_panel.dart';
import 'package:flutter_test/flutter_test.dart';

const List<LodLevelRow> _two = <LodLevelRow>[
  (ratio: 0.5, maxScreenFraction: 0.25, triangles: 6000),
  (ratio: 0.25, maxScreenFraction: 0.125, triangles: null),
];

Widget _panel({
  List<LodLevelRow> levels = _two,
  void Function(int, double)? onRatio,
  VoidCallback? onAddLevel,
  VoidCallback? onRegenerate,
  VoidCallback? onClose,
  String? now,
  String? refusal,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Material(
    child: SizedBox(
      width: 300,
      child: LodPanel(
        objectName: 'barrel',
        levels: levels,
        onRatio: onRatio ?? (_, _) {},
        onAddLevel: onAddLevel ?? () {},
        onRegenerate: onRegenerate ?? () {},
        onClose: onClose ?? () {},
        now: now,
        refusal: refusal,
      ),
    ),
  ),
);

void main() {
  group('LodPanel', () {
    testWidgets('a card per level: what it keeps, what that came to, where', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_panel(now: 'Now: 34% of the screen — LOD 0'));

      expect(find.text('barrel'), findsOneWidget);
      expect(find.text('LOD 0'), findsOneWidget);
      expect(find.text('LOD 1'), findsOneWidget);
      // The count the simplifier landed on, grouped — and no line at all for
      // the level that has no mesh to count, rather than a nought.
      expect(find.text('6 000 triangles'), findsOneWidget);
      expect(find.textContaining('triangles'), findsOneWidget);
      expect(find.text('drawn up to 25% of the screen'), findsOneWidget);
      expect(find.text('drawn up to 13% of the screen'), findsOneWidget);
      expect(find.text('Now: 34% of the screen — LOD 0'), findsOneWidget);
    });

    testWidgets('a drag of a card\'s slider is one report, for that level', (
      WidgetTester tester,
    ) async {
      final reported = <(int, double)>[];
      await tester.pumpWidget(
        _panel(onRatio: (int i, double to) => reported.add((i, to))),
      );

      // Mutation: report on every change rather than when the thumb is let
      // go. One drag is then a dozen `SetLodRatio`s, a dozen simplifications
      // of the mesh and a dozen presses of undo to take back.
      await tester.drag(find.byType(Slider).last, const Offset(60, 0));
      await tester.pump();

      expect(reported, hasLength(1));
      expect(reported.single.$1, 1);
      expect(reported.single.$2, greaterThan(0.25));
    });

    testWidgets('no levels says what the first one will be', (
      WidgetTester tester,
    ) async {
      var regenerated = 0;
      await tester.pumpWidget(
        _panel(
          levels: const <LodLevelRow>[],
          onRegenerate: () => regenerated++,
        ),
      );

      expect(find.textContaining('No levels yet'), findsOneWidget);
      // Nothing to regenerate is a disabled button, not a command that
      // refuses: `RegenerateLods` would, a press later.
      await tester.tap(
        find.byKey(const ValueKey<String>('lodRegenerate')),
        warnIfMissed: false,
      );
      expect(regenerated, 0);
    });

    testWidgets('a refusal disables Add and says why; the rest still work', (
      WidgetTester tester,
    ) async {
      var added = 0;
      var closed = 0;
      await tester.pumpWidget(
        _panel(
          refusal: 'no mesh to simplify',
          onAddLevel: () => added++,
          onClose: () => closed++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('lodAddLevel')),
        warnIfMissed: false,
      );
      await tester.tap(find.byKey(const ValueKey<String>('lodClose')));
      await tester.pump();

      expect(added, 0);
      expect(closed, 1);
      expect(find.text('no mesh to simplify'), findsOneWidget);
    });
  });

  group('nextLodAfter', () {
    test('the first level is half the mesh, below a quarter of the screen', () {
      expect(nextLodAfter(const <LodSpec>[]), (
        ratio: 0.5,
        maxScreenFraction: 0.25,
      ));
    });

    test('each one after halves the coarsest and the smallest so far', () {
      // Out of order on purpose: the coarsest is not the last, and the rule
      // is about the chain, not about the list. Mutation: halve the *last*
      // level. Adding after a hand-ordered list then makes a level finer
      // than one that is already there.
      final next = nextLodAfter(const <LodSpec>[
        LodSpec(ratio: 0.2, maxScreenFraction: 0.1),
        LodSpec(ratio: 0.5, maxScreenFraction: 0.25),
      ]);
      expect(next.ratio, closeTo(0.1, 1e-9));
      expect(next.maxScreenFraction, closeTo(0.05, 1e-9));
    });

    test('and never reaches the nought `AddLod` refuses', () {
      final next = nextLodAfter(const <LodSpec>[
        LodSpec(ratio: 0.05, maxScreenFraction: 0.01),
      ]);
      expect(next.ratio, 0.05);
      expect(next.maxScreenFraction, 0.01);
    });
  });
}
