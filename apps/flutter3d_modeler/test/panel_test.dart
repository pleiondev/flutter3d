/// The operation card: the last command run, with its own arguments still
/// editable through `NumberField`s it does not own.
///
///     flutter test test/panel_test.dart
///
/// `NumberField` itself moved to `flutter3d_editor_widgets` (`ui-27`'s own
/// P0), reading and showing a number verbatim as it did here —
/// `number_field_test.dart` in that package now covers it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/operation_card.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    testWidgets(
      "ui-09's own acceptance: a slider on a ranged argument calls amend",
      (WidgetTester tester) async {
        final amended = <ModelCommand>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: OperationCard(
                // `factor` carries `DoubleHint(min: 0.0, max: 1.0)` — full
                // bounds, which is what makes a slider possible at all.
                command: const LoopCut(cuts: 1, factor: 0.5),
                onAmend: amended.add,
              ),
            ),
          ),
        );

        expect(find.byType(Slider), findsNWidgets(2));

        // Dragging is many `onChanged` frames, each one `amend`, never a new
        // step — `ModelHistory`'s own "amend adjusts the last step instead of
        // adding one" test already proves the document side of that; this
        // proves the widget actually offers the drag at all.
        await tester.drag(find.byType(Slider).first, const Offset(80, 0));
        await tester.pump();

        expect(amended, isNotEmpty);
        expect((amended.last as LoopCut).cuts, greaterThan(1));
      },
    );

    testWidgets(
      "ui-09's own acceptance: the close button hides the card without "
      'touching amend',
      (WidgetTester tester) async {
        final amended = <ModelCommand>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: OperationCard(
                command: const LoopCut(cuts: 2),
                onAmend: amended.add,
              ),
            ),
          ),
        );

        expect(find.byType(NumberField), findsWidgets);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();

        // Mutation: have the close button call `onAmend` or reach for
        // `ModelHistory` some other way. The row's own "крестик не трогает
        // историю" is exactly this — the step this card was showing stays
        // exactly where it was, only the card's own detail disappears.
        expect(amended, isEmpty);
        expect(find.byType(NumberField), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(find.text('cut 2 loops'), findsOneWidget);
      },
    );

    testWidgets('a new command reopens a card the old one had dismissed', (
      WidgetTester tester,
    ) async {
      Widget cardFor(ModelCommand? command) => MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: OperationCard(command: command, onAmend: (_) {}),
        ),
      );

      await tester.pumpWidget(cardFor(const LoopCut(cuts: 2)));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byType(NumberField), findsNothing);

      // A different command arriving — a new step landed on top of the one
      // that was dismissed — gets its own, undismissed card rather than
      // inheriting the old one's hidden state.
      await tester.pumpWidget(cardFor(const LoopCut(cuts: 3)));
      await tester.pump();
      expect(find.byType(NumberField), findsWidgets);
    });

    testWidgets(
      'a screen reader is told which parameter the slider adjusts, not a '
      'bare number',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: OperationCard(
                command: const LoopCut(cuts: 1, factor: 0.5),
                onAmend: (_) {},
              ),
            ),
          ),
        );

        // Mutation: drop `semanticFormatterCallback`. The design hand-over's
        // own KEY REQUIREMENT names this exact slider as the worked example
        // of "a mouse operation, immediately editable" — a screen-reader
        // user who cannot see which row the slider sits in still needs to
        // be told. Every slider gets its own label rather than assuming an
        // order: `cuts` (an `IntHint` range) and `factor` both draw one.
        final List<Slider> sliders = tester
            .widgetList<Slider>(find.byType(Slider))
            .toList();
        expect(sliders, isNotEmpty);
        for (final Slider slider in sliders) {
          expect(slider.semanticFormatterCallback, isNotNull);
        }
        final Iterable<String> announced = sliders.map(
          (Slider s) => s.semanticFormatterCallback!(0.5),
        );
        expect(announced, contains(contains('factor')));
      },
    );

    testWidgets(
      'the card reads as a card — a coloured, rounded container, not a bare '
      'column blending into the panel around it',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: OperationCard(
                command: const LoopCut(cuts: 2),
                onAmend: (_) {},
              ),
            ),
          ),
        );

        // Mutation: return the bare `Column` again, with no `Container`
        // around it. `finder.container` below would then find nothing with
        // a non-null `BoxDecoration`.
        final Finder container = find.byWidgetPredicate(
          (Widget w) => w is Container && w.decoration is BoxDecoration,
        );
        expect(container, findsOneWidget);
        final BoxDecoration decoration =
            tester.widget<Container>(container).decoration! as BoxDecoration;
        expect(decoration.borderRadius, isNotNull);
      },
    );
  });
}
