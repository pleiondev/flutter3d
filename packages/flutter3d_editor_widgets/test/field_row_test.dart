/// `FieldRow`: one row, typed by a `MaterialHint` when there is one and by
/// the value's own type when there is not — assembled from the rest of this
/// package (`RangeSliderField`, `EnumField`, `ColorSwatchField`,
/// `TexturePathField`, `HintTextBox`, `NumbersRow`) — `ui-27`'s own P2, moved
/// verbatim from `apps/flutter3d_editor`'s own `editor_inspector.dart`.
///
///     flutter test test/field_row_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget row({
  required Object? value,
  MaterialHint? hint,
  void Function(Object? value)? onWrite,
  bool faded = false,
  PathOffers offers = nothingToOffer,
}) => MaterialApp(
  home: Scaffold(
    body: FieldRow(
      name: 'field',
      value: value,
      hint: hint,
      faded: faded,
      offers: offers,
      onWrite: onWrite ?? (Object? _) {},
    ),
  ),
);

void main() {
  group('by type, with no hint at all', () {
    testWidgets('a bool is a switch, and toggling it writes the flip', (
      WidgetTester tester,
    ) async {
      Object? written;
      await tester.pumpWidget(
        row(value: true, onWrite: (Object? it) => written = it),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(written, isFalse);
    });

    testWidgets('a number is a box, and submitting it writes the number', (
      WidgetTester tester,
    ) async {
      Object? written;
      await tester.pumpWidget(
        row(value: 2, onWrite: (Object? it) => written = it),
      );

      expect(find.widgetWithText(TextField, '2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '6');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(written, 6);
    });

    testWidgets('a whole double shows with no trailing .0', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(row(value: 4.0));

      expect(find.widgetWithText(TextField, '4'), findsOneWidget);
    });

    testWidgets('a value that will not parse changes nothing', (
      WidgetTester tester,
    ) async {
      var told = 0;
      await tester.pumpWidget(row(value: 2, onWrite: (Object? _) => told++));

      await tester.enterText(find.byType(TextField), 'wide');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(told, 0);
    });

    testWidgets('a string is a box, and emptying it writes null', (
      WidgetTester tester,
    ) async {
      Object? written = 'unset';
      await tester.pumpWidget(
        row(value: 'stone', onWrite: (Object? it) => written = it),
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(written, isNull);
    });

    testWidgets(
      'a vector of numbers is one box per component, each writing its own',
      (WidgetTester tester) async {
        Object? written;
        await tester.pumpWidget(
          row(value: <double>[0, 2, 0], onWrite: (Object? it) => written = it),
        );

        final twos = find.widgetWithText(TextField, '2');
        expect(twos, findsOneWidget);
        expect(find.widgetWithText(TextField, '0'), findsNWidgets(2));

        await tester.enterText(twos, '6');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(written, <num>[0, 6, 0]);
      },
    );

    testWidgets('anything else is shown and not editable', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(row(value: <String, Object?>{'a': 1}));

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('a'), findsOneWidget);
    });

    testWidgets('with no hint, the label is the field\'s own name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(row(value: 2));

      expect(find.text('field'), findsOneWidget);
    });

    testWidgets('faded dims the label without changing the control', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(row(value: 2, faded: true));

      final Text label = tester.widget(find.text('field'));
      expect(label.style?.color, const Color(0xFF5E6672));
    });
  });

  group('a range hint', () {
    testWidgets('is a slider paired with a box, unlike the bare number', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(value: 0.4, hint: const MaterialHint(RangeHint(0.0, 1.0))),
      );

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('dragging writes the value its own step lands on', (
      WidgetTester tester,
    ) async {
      Object? written;
      await tester.pumpWidget(
        row(
          value: 0.4,
          hint: const MaterialHint(RangeHint(0.0, 1.0, step: 0.25)),
          onWrite: (Object? it) => written = it,
        ),
      );

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0.7);
      await tester.pump();

      expect(written, 0.75);
    });

    testWidgets('a value outside the range is shown, not clamped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(value: 1.5, hint: const MaterialHint(RangeHint(0.0, 1.0))),
      );

      expect(find.text('1.5 is outside 0–1'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1.5'), findsOneWidget);
    });

    testWidgets('a hint that disagrees with the value falls back to type', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(value: 'stone', hint: const MaterialHint(RangeHint(0.0, 1.0))),
      );

      expect(find.byType(Slider), findsNothing);
      expect(find.widgetWithText(TextField, 'stone'), findsOneWidget);
    });

    testWidgets('a hint renames the row without renaming the field', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(
          value: 0.4,
          hint: const MaterialHint(RangeHint(0.0, 1.0), label: 'Roughness'),
        ),
      );

      expect(find.text('Roughness'), findsOneWidget);
      expect(find.text('field'), findsNothing);
    });
  });

  testWidgets('an enum hint is a dropdown, and picking one writes its value', (
    WidgetTester tester,
  ) async {
    Object? written;
    await tester.pumpWidget(
      row(
        value: 'opaque',
        hint: MaterialHint(
          EnumHint(<EnumHintValue>[
            const EnumHintValue('opaque', 'Opaque'),
            const EnumHintValue('blend', 'Blended'),
          ]),
        ),
        onWrite: (Object? it) => written = it,
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blended').last);
    await tester.pumpAndSettle();

    expect(written, 'blend');
  });

  group('a colour hint', () {
    testWidgets('is a swatch beside exactly one box per channel', (
      WidgetTester tester,
    ) async {
      // Pinned at exactly four: a level's colour is RGBA and every one of
      // those four numbers has to stay typeable, not just the three a
      // `ColorField`'s own hex box would leave reachable.
      await tester.pumpWidget(
        row(
          value: <double>[0.5, 0.5, 0.5, 0.25],
          hint: const MaterialHint(ColorHint()),
        ),
      );

      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('picking a swatch keeps the alpha the document carried', (
      WidgetTester tester,
    ) async {
      Object? written;
      await tester.pumpWidget(
        row(
          value: <double>[0.5, 0.5, 0.5, 0.25],
          hint: const MaterialHint(ColorHint()),
          onWrite: (Object? it) => written = it,
        ),
      );

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pumpAndSettle();

      expect(written, isA<List<num>>());
      expect((written! as List<num>).length, 4);
      expect((written! as List<num>).last, 0.25);
    });

    testWidgets('a three-channel hint never offers a fourth box', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(
          value: <double>[0.5, 0.5, 0.5],
          hint: const MaterialHint(ColorHint(channels: 3)),
        ),
      );

      expect(find.byType(TextField), findsNWidgets(3));
    });
  });

  group('a texture hint', () {
    testWidgets('offers the files its caller listed for it', (
      WidgetTester tester,
    ) async {
      Object? written;
      await tester.pumpWidget(
        row(
          value: 'stone.png',
          hint: const MaterialHint(TextureHint()),
          offers: (List<String> suffixes) => const <String>['brick.png'],
          onWrite: (Object? it) => written = it,
        ),
      );

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.text('brick.png'));
      await tester.pumpAndSettle();

      expect(written, 'brick.png');
    });

    testWidgets('an offer of nothing draws no button at all', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(value: 'stone.png', hint: const MaterialHint(TextureHint())),
      );

      expect(find.byIcon(Icons.folder_open), findsNothing);
    });

    testWidgets('says when a path is not one of the suffixes it decodes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        row(value: 'stone.tga', hint: const MaterialHint(TextureHint())),
      );

      expect(find.text('not one of .png .jpg .jpeg .ktx2'), findsOneWidget);
    });

    testWidgets('emptying the path clears it rather than writing ""', (
      WidgetTester tester,
    ) async {
      Object? written = 'unset';
      await tester.pumpWidget(
        row(
          value: 'stone.png',
          hint: const MaterialHint(TextureHint()),
          onWrite: (Object? it) => written = it,
        ),
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(written, isNull);
    });
  });

  testWidgets(
    'a text box swallows the key it was just typed, so it never reaches an '
    'ancestor reading it as a shortcut',
    (WidgetTester tester) async {
      // `HintTextBox`'s own `Focus(onKeyEvent: skipRemainingHandlers)`: an
      // ancestor `Focus` around the whole panel reads bare letters as tool
      // shortcuts, and must not see `W`, `A`, `S`, `D` while a name is being
      // typed into one of this row's own boxes.
      var ancestorSaw = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              autofocus: false,
              onKeyEvent: (FocusNode node, KeyEvent event) {
                ancestorSaw++;
                return KeyEventResult.ignored;
              },
              child: FieldRow(
                name: 'name',
                value: 'stone',
                onWrite: (Object? _) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pump();

      expect(
        ancestorSaw,
        0,
        reason: 'the row\'s own Focus should have stopped the event first',
      );
    },
  );
}
