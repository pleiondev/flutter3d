/// `pro-uv-07`'s own method/margin/list panel: dumb, callback-driven, and
/// laid out the way `ModifierStackPanel` already is.
///
///     flutter test test/ui/uv_unwrap_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/uv_unwrap_panel.dart';
import 'package:flutter3d_modeler/src/uv_unwrap_layout.dart';
import 'package:flutter_test/flutter_test.dart';

List<UvIslandData> _islands() => const <UvIslandData>[
  UvIslandData(id: 0, faceCount: 2, stretch: 1.0, triangles: <UvTriangle>[]),
  UvIslandData(id: 1, faceCount: 3, stretch: 6.0, triangles: <UvTriangle>[]),
];

Widget _panel({
  UnwrapMethod method = UnwrapMethod.lscm,
  double margin = 0.01,
  int? selectedIslandId,
  ValueChanged<UnwrapMethod>? onMethodChanged,
  ValueChanged<double>? onMarginChanged,
  ValueChanged<int>? onIslandSelected,
  List<UvIslandData>? islands,
}) => MaterialApp(
  home: Material(
    child: UvUnwrapPanel(
      methods: const <UnwrapMethod>[UnwrapMethod.lscm],
      method: method,
      onMethodChanged: onMethodChanged ?? (_) {},
      margin: margin,
      onMarginChanged: onMarginChanged ?? (_) {},
      islands: islands ?? _islands(),
      selectedIslandId: selectedIslandId,
      onIslandSelected: onIslandSelected,
    ),
  ),
);

void main() {
  testWidgets('lists every island, with its own stretch beside it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_panel());

    expect(find.text('Island 0'), findsOneWidget);
    expect(find.text('Island 1'), findsOneWidget);
    expect(find.text('1.00'), findsOneWidget);
    expect(find.text('6.00'), findsOneWidget);
  });

  testWidgets('an empty island list says so rather than nothing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_panel(islands: const <UvIslandData>[]));

    expect(find.text('No islands'), findsOneWidget);
  });

  testWidgets('tapping a row reports that island\'s own id', (
    WidgetTester tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      _panel(onIslandSelected: (int id) => selected = id),
    );

    await tester.tap(find.text('Island 1'));
    await tester.pump();

    expect(selected, 1);
  });

  testWidgets('the margin field reports a typed value on submit', (
    WidgetTester tester,
  ) async {
    double? reported;
    await tester.pumpWidget(
      _panel(onMarginChanged: (double value) => reported = value),
    );

    await tester.enterText(find.byType(TextField), '0.05');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(reported, 0.05);
  });

  testWidgets('the one known method shows up as a segment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_panel());

    expect(find.text('LSCM'), findsOneWidget);
  });
}
