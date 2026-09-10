/// The two things in the properties panel that hold numbers.
///
///     flutter test test/panel_test.dart
///
/// The field's rule about commas is arithmetic and is tested as such; the rest
/// needs a widget, because what is being checked is *when* a number is
/// reported — a field that emitted on every keystroke would turn `1.5` into a
/// move to `1` and then a move to `1.5`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/number_field.dart';
import 'package:flutter3d_modeler/src/ui/operation_card.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// One field in a window, and what it has reported.
Future<List<double>> pumpField(WidgetTester tester, {double value = 0}) async {
  final said = <double>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
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
  });

  group('the operation card', () {
    test('shows the numbers and leaves the ids alone', () {
      // Mutation: show every argument. Editing the `id` of a rename means "do
      // this to a different object", which is not an adjustment — it is a
      // different command, and the person asking for it is asking to select
      // something else.
      expect(OperationCard.numbersOf(const Extrude(0.25)).keys, <String>[
        'distance',
      ]);
      expect(OperationCard.numbersOf(const BakeToMesh(3)).keys, isEmpty);
      expect(
        OperationCard.numbersOf(const LoopCut(cuts: 2)).keys,
        containsAll(<String>['cuts', 'factor']),
      );
    });

    testWidgets('an adjustment comes back as the same command, renumbered', (
      WidgetTester tester,
    ) async {
      final amended = <ModelCommand>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: OperationCard(
              command: const Extrude(0.25),
              onAmend: amended.add,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '0,75');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Through the command's own JSON, so the card knows nothing about which
      // command it is holding. Mutation: build the replacement with a `switch`
      // over command types instead, and every command added to the sealed set
      // afterwards is one the card silently cannot adjust.
      expect(amended, hasLength(1));
      expect((amended.single as Extrude).distance, 0.75);
    });

    testWidgets('a whole-number argument stays whole', (
      WidgetTester tester,
    ) async {
      final amended = <ModelCommand>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: OperationCard(
              command: const LoopCut(cuts: 1),
              onAmend: amended.add,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byWidgetPredicate(
          (Widget w) => w is TextField && w.controller?.text == '1',
        ),
        '3',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Mutation: put the number back as a double. `fromJson` matches `cuts`
      // against `int`, a `3.0` does not match, the whole command reads back as
      // null, and the card silently does nothing — for the one command whose
      // most useful argument is a count.
      expect(amended, hasLength(1));
      expect((amended.single as LoopCut).cuts, 3);
    });

    testWidgets('says so when there is nothing to adjust', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(body: OperationCard(command: null, onAmend: (_) {})),
        ),
      );

      expect(find.text('nothing done yet'), findsOneWidget);
    });
  });
}
