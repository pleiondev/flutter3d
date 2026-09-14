/// `NumberField`: reading a number, and when it reports one — moved here
/// verbatim from `apps/flutter3d_modeler`'s `panel_test.dart`, `ui-27`'s own
/// P0.
///
///     flutter test test/number_field_test.dart
///
/// The field's rule about commas is arithmetic and is tested as such; the rest
/// needs a widget, because what is being checked is *when* a number is
/// reported — a field that emitted on every keystroke would turn `1.5` into a
/// move to `1` and then a move to `1.5`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One field in a window, and what it has reported.
Future<List<double>> pumpField(WidgetTester tester, {double value = 0}) async {
  final said = <double>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NumberField(label: 'X', value: value, onChanged: said.add),
      ),
    ),
  );
  return said;
}

void main() {
  group('reading a number', () {
    test('a comma is a decimal point, and so is a full stop', () {
      // Mutation: parse the text as it arrives. A person on a Russian or a
      // German keyboard types `1,5`, `double.tryParse` answers null, and the
      // field quietly keeps the old value — which is the version nobody
      // notices until the model is the wrong size.
      expect(NumberField.parse('1,5'), 1.5);
      expect(NumberField.parse('1.5'), 1.5);
      expect(NumberField.parse('  -2,25 '), -2.25);
    });

    test('nonsense is nothing, and so is an infinity', () {
      expect(NumberField.parse(''), isNull);
      expect(NumberField.parse('x'), isNull);
      expect(NumberField.parse('1,5,'), isNull);
      // Mutation: accept what `double.tryParse` accepts. `Infinity` and `NaN`
      // both parse; a transform holding either draws nothing and every number
      // computed from it afterwards is a NaN as well, so the failure arrives
      // nowhere near the field somebody typed it into.
      expect(NumberField.parse('Infinity'), isNull);
      expect(NumberField.parse('NaN'), isNull);
    });

    test('a whole number is shown whole', () {
      // Mutation: always show three places. A panel of `1.000` and `0.000`
      // reads as a machine rather than a measurement, and the three zeroes are
      // three characters of noise on every row of every object.
      expect(NumberField.show(1), '1');
      expect(NumberField.show(-2.5), '-2.5');
      expect(NumberField.show(1 / 3), '0.333');
    });
  });

  group('the field', () {
    testWidgets('reports when the person has finished, not while typing', (
      WidgetTester tester,
    ) async {
      final said = await pumpField(tester);

      await tester.enterText(find.byType(TextField), '1.5');
      await tester.pump();

      // Mutation: report from `onChanged` on the `TextField`. Typing `1.5` is
      // then three reports — `1`, nothing, `1.5` — which is two steps of
      // history and one visible jump of the object to a whole unit away.
      expect(said, isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(said, <double>[1.5]);
    });

    testWidgets('rubbish puts back what the document says', (
      WidgetTester tester,
    ) async {
      final said = await pumpField(tester, value: 2);

      await tester.enterText(find.byType(TextField), 'about three');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Nothing reported, and the box shows the value again — a field left
      // holding `about three` is a field a person will read as a value.
      expect(said, isEmpty);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('the same number twice is reported once', (
      WidgetTester tester,
    ) async {
      final said = await pumpField(tester, value: 2);

      await tester.enterText(find.byType(TextField), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Mutation: report whatever was read. A person who tabs through the three
      // fields of a transform without changing anything makes three steps of
      // history, and ⌘Z three times takes back nothing visible.
      expect(said, isEmpty);
    });

    testWidgets('a screen reader is told what the field is, by default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberField(label: 'X', value: 1, onChanged: (_) {}),
          ),
        ),
      );

      // Mutation: drop the `Semantics` wrapper. A screen reader would then
      // announce a bare "1" with nothing to say it is X, Y, Z, or anything
      // else — the exact gap the review found on this app's own most-used
      // control.
      expect(find.bySemanticsLabel('X'), findsOneWidget);
    });

    testWidgets(
      'a grid cell hides its own visible label but keeps a fuller one for '
      'a screen reader',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NumberField(
                label: 'X',
                value: 1,
                showLabel: false,
                semanticLabel: 'Position X',
                onChanged: (_) {},
              ),
            ),
          ),
        );

        // The visible "X" is gone (a grid already has a column header for
        // it) but the field is still findable by a richer semantic label
        // that says which row and column it is, not just "X" three times
        // with nothing else to tell them apart.
        expect(find.text('X'), findsNothing);
        expect(find.bySemanticsLabel('Position X'), findsOneWidget);
      },
    );
  });
}
