/// `RangeSliderField`: a slider merging the level editor's own hint-driven
/// row (a text box, a nullable `step` that snaps and rounds) with the
/// modeller's own lighter one (an internal `label`, no box) — `ui-27`'s own
/// P1.
///
///     flutter test test/range_slider_field_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(
  WidgetTester tester, {
  String? label,
  required double value,
  double min = 0.0,
  double max = 1.0,
  double? step,
  ValueChanged<double>? onChanged,
  bool enabled = true,
  bool editable = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: RangeSliderField(
        label: label,
        value: value,
        min: min,
        max: max,
        step: step,
        enabled: enabled,
        editable: editable,
        onChanged: onChanged ?? (double _) {},
      ),
    ),
  ),
);

void main() {
  group('the modeller\'s own row (not editable)', () {
    testWidgets('is keyed by its label, so a panel can tell two apart', (
      WidgetTester tester,
    ) async {
      await pump(tester, label: 'Metallic', value: 0.2);

      expect(
        find.byKey(const ValueKey<String>('slider-Metallic')),
        findsOneWidget,
      );
    });

    testWidgets('disabled: neither callback is wired', (
      WidgetTester tester,
    ) async {
      await pump(tester, label: 'Metallic', value: 0.2, enabled: false);

      final Slider slider = tester.widget(find.byType(Slider));
      expect(slider.onChanged, isNull);
      expect(slider.onChangeEnd, isNull);
    });

    testWidgets('enabled: a whole drag reports exactly once', (
      WidgetTester tester,
    ) async {
      final said = <double>[];
      await pump(tester, label: 'Metallic', value: 0.2, onChanged: said.add);

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(said, hasLength(1));
    });

    testWidgets('a null step writes what the drag produced, unrounded', (
      WidgetTester tester,
    ) async {
      // The whole point of `step: null`: a material's own field is written
      // bit for bit, not quantised to four decimal places the way a step
      // would round it — `mat-33d`'s own acceptance for the panel that
      // calls this with `step: null`.
      double? written;
      await pump(
        tester,
        label: 'Metallic',
        value: 0.2,
        step: null,
        onChanged: (double v) => written = v,
      );

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0.123456789);

      expect(written, 0.123456789);
    });

    testWidgets('no label draws no label column — only the read-out', (
      WidgetTester tester,
    ) async {
      await pump(tester, value: 0.2);

      // Just the two-decimal read-out; a label column would be a second
      // `Text` beside it.
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('shows the value to two decimal places, no text box', (
      WidgetTester tester,
    ) async {
      await pump(tester, label: 'Roughness', value: 0.5);

      expect(find.text('0.50'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('the level editor\'s own row (editable)', () {
    testWidgets('draws a slider paired with a text box', (
      WidgetTester tester,
    ) async {
      await pump(tester, value: 0.4, step: 0.01, editable: true);

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('dragging writes the value the step lands on', (
      WidgetTester tester,
    ) async {
      Object? written;
      await pump(
        tester,
        value: 0.4,
        step: 0.25,
        editable: true,
        onChanged: (double v) => written = v,
      );

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0.7);

      expect(written, 0.75, reason: 'a step of a quarter has no 0.7 on it');
    });

    testWidgets('a value outside the range is shown, not clamped', (
      WidgetTester tester,
    ) async {
      await pump(tester, value: 1.5, min: 0.0, max: 1.0, editable: true);

      expect(find.text('1.5 is outside 0–1'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, '1.5'),
        findsOneWidget,
        reason: 'the box must go on printing what the document says',
      );
    });

    testWidgets('inside the range, nothing is said about it', (
      WidgetTester tester,
    ) async {
      await pump(tester, value: 0.4, min: 0.0, max: 1.0, editable: true);

      expect(find.textContaining('is outside'), findsNothing);
    });

    testWidgets('typing a number and submitting reports it directly, '
        'with no step applied', (WidgetTester tester) async {
      Object? written;
      await pump(
        tester,
        value: 0.4,
        step: 0.25,
        editable: true,
        onChanged: (double v) => written = v,
      );

      await tester.enterText(find.byType(TextField), '0.37');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(written, 0.37);
    });
  });

  group("ux-23: where the label goes is measured, not guessed", () {
    /// The row inside a panel [width] wide, the way a real panel holds it.
    Future<void> inPanel(
      WidgetTester tester,
      double width, {
      required bool editable,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: RangeSliderField(
                label: 'Ambient',
                value: 0.5,
                min: 0,
                max: 1,
                editable: editable,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    /// Whether the label is drawn above the slider rather than beside it —
    /// which is exactly where its own top edge sits: level with the top of
    /// the row when stacked, centred against a 48-tall slider when not.
    bool stacked(WidgetTester tester) =>
        tester.getTopLeft(find.text('Ambient')).dy <
        tester.getTopLeft(find.byType(Slider)).dy;

    testWidgets('a wide panel keeps the label beside the slider', (
      WidgetTester tester,
    ) async {
      await inPanel(tester, 600, editable: false);
      expect(stacked(tester), isFalse);
    });

    testWidgets("and the review's own 250-wide panel does not", (
      WidgetTester tester,
    ) async {
      // 96 of label, 6 of gap and 34 of read-out leave the slider 114
      // pixels: a stub, with "Ambient" the first thing the ellipsis eats.
      await inPanel(tester, 250, editable: false);
      expect(stacked(tester), isTrue);
    });

    testWidgets('a row with a typed box stacks sooner than one with a '
        'read-out, because its box is twenty pixels wider', (
      WidgetTester tester,
    ) async {
      // Mutation: measure the label column alone, as this did. Both answers
      // are then the same at every width, and the twenty pixels the box
      // actually takes come out of the slider nobody can aim at.
      await inPanel(tester, 295, editable: false);
      expect(stacked(tester), isFalse);

      await inPanel(tester, 295, editable: true);
      expect(stacked(tester), isTrue);
    });
  });
}
