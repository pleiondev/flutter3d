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
import 'package:flutter/services.dart';
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

  group('ux-15: arithmetic, units and precision', () {
    test('four operators, brackets and pi', () {
      // Mutation: go back to `double.tryParse`. A third of a metre is then
      // something a person works out on a calculator and types back rounded,
      // and `2*pi` is not a number at all.
      expect(NumberField.parse('1/3'), closeTo(1 / 3, 1e-12));
      expect(NumberField.parse('2*pi'), closeTo(6.2832, 1e-4));
      expect(NumberField.parse('(1 + 2) * 3'), 9);
      expect(NumberField.parse('10 - 2 - 3'), 5);
      expect(NumberField.parse('-2 * -3'), 6);
    });

    test('a unit is converted into the field\'s own', () {
      expect(
        NumberField.parse('10cm', unit: NumberUnit.metres),
        closeTo(0.1, 1e-12),
      );
      expect(
        NumberField.parse('24 mm', unit: NumberUnit.metres),
        closeTo(0.024, 1e-12),
      );
      expect(
        NumberField.parse('1ft', unit: NumberUnit.metres),
        closeTo(0.3048, 1e-12),
      );
      expect(
        NumberField.parse('pi rad', unit: NumberUnit.degrees),
        closeTo(180, 1e-9),
      );
      expect(
        NumberField.parse('90deg', unit: NumberUnit.degrees),
        closeTo(90, 1e-12),
      );
    });

    test(
      'a unit the field does not know is a refusal, not an ignored word',
      () {
        // Mutation: drop whatever follows the number. `10kg` in a length field
        // then commits ten metres, which is worse than saying no.
        expect(NumberField.parse('10kg', unit: NumberUnit.metres), isNull);
        expect(NumberField.parse('10cm'), isNull, reason: 'a plain field');
        expect(NumberField.parse('90deg', unit: NumberUnit.metres), isNull);
      },
    );

    test('the places follow the magnitude', () {
      // The live finding: an STL read in at a scale of 0.001 filled these
      // fields with numbers that three places round to zero. Mutation: fix
      // three places — the field says `0` for a value that is not zero, and
      // typing back what it shows destroys the model.
      expect(NumberField.show(0.001), '0.001');
      expect(NumberField.show(0.0001), '0.0001');
      expect(NumberField.show(0.000025), '0.000025');
      // And the ordinary scale is unchanged, three places and no noise.
      expect(NumberField.show(1), '1');
      expect(NumberField.show(1 / 3), '0.333');
    });
  });

  group('ux-15: the keys and the scrub', () {
    testWidgets('an arrow key moves the value by a step', (
      WidgetTester tester,
    ) async {
      final said = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberField(
              label: 'X',
              value: 1,
              step: 0.1,
              onChanged: said.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      // Mutation: leave the arrows to the text box, where in a single-line
      // field they do nothing at all. A number is then only ever set by
      // typing it out in full.
      expect(said, <double>[1.1]);
    });

    testWidgets('and Shift is ten of them', (WidgetTester tester) async {
      final said = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberField(
              label: 'X',
              value: 1,
              step: 0.1,
              onChanged: said.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(said.single, closeTo(0, 1e-9));
    });

    testWidgets('dragging the label scrubs a step a pixel', (
      WidgetTester tester,
    ) async {
      final said = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: NumberField(
                label: 'X',
                value: 0,
                step: 0.1,
                onChanged: said.add,
              ),
            ),
          ),
        ),
      );

      // Ten pixels is ten steps — the acceptance this row states, and the
      // thing that makes a value settable by eye against the picture.
      await tester.drag(find.text('X'), const Offset(10, 0));
      await tester.pump();

      expect(said, isNotEmpty);
      expect(said.last, closeTo(1.0, 1e-9));
    });
  });
}
