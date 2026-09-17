/// `pro-uv-07`'s own screen 06: composing the viewport, the UV layout and
/// the method/margin/list panel — and the one thing composing them has to
/// get right, that a tap on either the layout or the panel reports through
/// the same `onIslandSelected` rather than two ideas of "which island is
/// selected" that could disagree.
///
///     flutter test test/ui/uv_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/uv_layout_view.dart';
import 'package:flutter3d_modeler/src/ui/uv_screen.dart';
import 'package:flutter3d_modeler/src/ui/uv_unwrap_panel.dart';
import 'package:flutter3d_modeler/src/uv_unwrap_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two islands, each one triangle, the same fixture
/// `uv_layout_view_test.dart` uses — small right triangles far enough apart
/// that a tap at either one's own centroid cannot land on the other.
List<UvIslandData> _islands() => const <UvIslandData>[
  UvIslandData(
    id: 0,
    faceCount: 1,
    stretch: 1.0,
    triangles: <UvTriangle>[
      UvTriangle(Offset(0, 0), Offset(0.4, 0), Offset(0, 0.4)),
    ],
  ),
  UvIslandData(
    id: 1,
    faceCount: 1,
    stretch: 10.0,
    triangles: <UvTriangle>[
      UvTriangle(Offset(0.6, 0.6), Offset(1, 0.6), Offset(0.6, 1)),
    ],
  ),
];

Widget _screen({int? selectedIslandId, ValueChanged<int>? onIslandSelected}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(
        child: UvScreen(
          // A real caller hands in `ModelerViewport`; this screen's own doc
          // comment says its job stops at composing screens, so a placeholder
          // proves the composition without needing a `Renderer`/`ModelerStage`
          // this test has no business building.
          viewport: const Placeholder(key: ValueKey<String>('viewport')),
          islands: _islands(),
          methods: const <UnwrapMethod>[UnwrapMethod.lscm],
          method: UnwrapMethod.lscm,
          onMethodChanged: (_) {},
          margin: 0.01,
          onMarginChanged: (_) {},
          selectedIslandId: selectedIslandId,
          onIslandSelected: onIslandSelected,
        ),
      ),
    );

void main() {
  testWidgets('composes the viewport, the layout and the panel', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_screen());

    expect(find.byKey(const ValueKey<String>('viewport')), findsOneWidget);
    expect(find.byType(UvLayoutView), findsOneWidget);
    expect(find.byType(UvUnwrapPanel), findsOneWidget);
    expect(find.text('Island 0'), findsOneWidget);
    expect(find.text('Island 1'), findsOneWidget);
  });

  testWidgets(
    'a tap on the layout and a tap on the panel report through the same '
    'callback',
    (WidgetTester tester) async {
      final selected = <int>[];
      await tester.pumpWidget(_screen(onIslandSelected: selected.add));

      // The centroid of island 1's own triangle in `UvLayoutView`'s own
      // 400×400 painter — the same point `uv_layout_view_test.dart` taps.
      final topLeft = tester.getTopLeft(find.byType(UvLayoutView));
      await tester.tapAt(topLeft + const Offset(293.3, 106.7));
      await tester.pump();

      // `UvUnwrapPanel` sits under `UvLayoutView` in a scrollable column, and
      // "Island 0" lands below the default test surface without this.
      await tester.ensureVisible(find.text('Island 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Island 0'));
      await tester.pump();

      // Mutation: wire the layout's own tap and the panel's own row tap to
      // two different callbacks. `UvScreen`'s own doc comment says a caller
      // "keeps one idea of which island is selected" — this is what proves
      // it, rather than each half quietly having its own.
      expect(selected, <int>[1, 0]);
    },
  );

  testWidgets(
    'the selected island is the same one in both the layout and the panel',
    (WidgetTester tester) async {
      await tester.pumpWidget(_screen(selectedIslandId: 1));

      final layoutView = tester.widget<UvLayoutView>(find.byType(UvLayoutView));
      final panel = tester.widget<UvUnwrapPanel>(find.byType(UvUnwrapPanel));
      expect(layoutView.selectedIslandId, 1);
      expect(panel.selectedIslandId, 1);
    },
  );

  testWidgets('with no onIslandSelected, neither half offers a tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_screen());

    final layoutView = tester.widget<UvLayoutView>(find.byType(UvLayoutView));
    final panel = tester.widget<UvUnwrapPanel>(find.byType(UvUnwrapPanel));
    expect(layoutView.onTriangleTap, isNull);
    expect(panel.onIslandSelected, isNull);
  });
}
