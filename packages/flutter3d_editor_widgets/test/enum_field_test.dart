/// `EnumField`: a dropdown merging the level editor's own "show a bound
/// value even when the picker's own list does not offer it" with the
/// modeller's own fallback for a value nothing has set — `ui-27`'s own P1.
///
///     flutter test test/enum_field_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter_test/flutter_test.dart';

const List<EnumHintValue> _modes = <EnumHintValue>[
  EnumHintValue('opaque', 'Opaque'),
  EnumHintValue('mask', 'Cut out at the threshold'),
  EnumHintValue('blend', 'Blended'),
];

Future<void> pump(
  WidgetTester tester, {
  String? value,
  List<EnumHintValue> options = _modes,
  ValueChanged<String>? onChanged,
  String Function(String value)? unknownLabel,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: EnumField(
        value: value,
        options: options,
        unknownLabel: unknownLabel,
        onChanged: onChanged ?? (String _) {},
      ),
    ),
  ),
);

DropdownButton<String> _dropdown(WidgetTester tester) =>
    tester.widget(find.byType(DropdownButton<String>));

void main() {
  testWidgets('offers every option by its label, and reports its value', (
    WidgetTester tester,
  ) async {
    final said = <String>[];
    await pump(tester, value: 'opaque', onChanged: said.add);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Blended'), findsOneWidget);
    await tester.tap(find.text('Blended').last);
    await tester.pumpAndSettle();

    expect(said, <String>['blend']);
  });

  testWidgets(
    'a bound value the options do not list is shown, not swapped out',
    (WidgetTester tester) async {
      // A material written by a newer build may name a mode this one has
      // never heard of; the dropdown has to go on showing it rather than
      // silently switching to whatever it does offer.
      await pump(tester, value: 'stencil');

      expect(_dropdown(tester).value, 'stencil');
      expect(find.text('stencil — not one this build offers'), findsOneWidget);
    },
  );

  testWidgets('unknownLabel replaces the default wording for that value', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      value: 'stencil',
      unknownLabel: (String v) => 'unsupported: $v',
    );

    expect(find.text('unsupported: stencil'), findsOneWidget);
  });

  testWidgets('a null value falls back to the first option, not to nothing', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(_dropdown(tester).value, 'opaque');
  });

  testWidgets('empty options with a null value picks nothing at all', (
    WidgetTester tester,
  ) async {
    await pump(tester, options: const <EnumHintValue>[]);

    expect(_dropdown(tester).value, isNull);
  });
}
