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

Widget _screen({
  int? selectedIslandId,
  ValueChanged<int>? onIslandSelected,
  bool? autoPack,
  ValueChanged<bool>? onAutoPackChanged,
  VoidCallback? onUnwrap,
  String? unwrapRefusal,
}) => MaterialApp(
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
      autoPack: autoPack,
      onAutoPackChanged: onAutoPackChanged,
      onUnwrap: onUnwrap,
      unwrapRefusal: unwrapRefusal,
    ),
  ),
);

/// Pumps [screen] into a window [size] big, and puts the window back after.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget screen) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(screen);
}

void main() {
  group('three layouts for three widths', () {
    testWidgets('a desktop gets the hand-over\'s three columns', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, const Size(1400, 860), _screen());

      // Screen 06 as drawn: the model, the 400-pixel square, the panel —
      // left to right, none of them over another. Mutation: drop the wide
      // branch. The square goes back into the 330-wide column, where there
      // is room for 306 of it.
      final Rect model = tester.getRect(
        find.byKey(const ValueKey<String>('viewport')),
      );
      final Rect square = tester.getRect(find.byType(UvLayoutView));
      final Rect panel = tester.getRect(find.byType(UvUnwrapPanel));
      expect(square.size, const Size.square(400));
      expect(model.right, lessThanOrEqualTo(square.left));
      expect(square.right, lessThanOrEqualTo(panel.left));
    });

    testWidgets('a phone puts the layout and the panel under the model', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, const Size(400, 800), _screen());

      // Mutation: drop the narrow branch. The 330-wide column beside a
      // 400-wide window leaves the model seventy pixels.
      final Rect model = tester.getRect(
        find.byKey(const ValueKey<String>('viewport')),
      );
      final Rect square = tester.getRect(find.byType(UvLayoutView));
      expect(model.width, 400);
      expect(model.bottom, lessThanOrEqualTo(square.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a window too short for the square scrolls, and says nothing', (
      WidgetTester tester,
    ) async {
      // A landscape phone: wide enough for the stacked column and a third
      // as tall as it needs. Mutation: take the scroll view off the column
      // — the flex overflows and the framework reports it here.
      await _pumpAt(tester, const Size(800, 320), _screen());
      expect(tester.takeException(), isNull);
    });
  });

  group('the unwrap\'s own two extras', () {
    testWidgets('the tick and the button report, and neither shows unasked', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_screen());
      expect(find.byKey(const ValueKey<String>('uvAutoPack')), findsNothing);
      expect(find.byKey(const ValueKey<String>('uvUnwrap')), findsNothing);

      final ticks = <bool>[];
      var unwraps = 0;
      await tester.pumpWidget(
        _screen(
          autoPack: true,
          onAutoPackChanged: ticks.add,
          onUnwrap: () => unwraps++,
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('uvAutoPack')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('uvAutoPack')));
      await tester.tap(find.byKey(const ValueKey<String>('uvUnwrap')));
      await tester.pump();

      expect(ticks, <bool>[false]);
      expect(unwraps, 1);
    });

    testWidgets('a refusal disables the button and says why', (
      WidgetTester tester,
    ) async {
      var unwraps = 0;
      await tester.pumpWidget(
        _screen(onUnwrap: () => unwraps++, unwrapRefusal: 'nothing to unwrap'),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('uvUnwrap')),
      );
      await tester.pumpAndSettle();

      // Mutation: leave the button live under a refusal. The press goes
      // through to a command that refuses in the status line, a window away
      // from the button that was pressed.
      await tester.tap(
        find.byKey(const ValueKey<String>('uvUnwrap')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(unwraps, 0);
      expect(find.text('nothing to unwrap'), findsOneWidget);
    });
  });

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

      // The centroid of island 1's own triangle — (0.733, 0.733) in UV, V
      // flipped — in whatever square `UvLayoutView` was given room for. On
      // the default 800-wide test surface that is the stacked column's 306
      // and not the 400 it asks for, which is the case this used to get
      // wrong: the painter drew to 306 and the tap divided by 400.
      final topLeft = tester.getTopLeft(find.byType(UvLayoutView));
      final double side = tester.getSize(find.byType(UvLayoutView)).width;
      expect(side, lessThan(400));
      await tester.tapAt(topLeft + Offset(0.7333 * side, 0.2667 * side));
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
