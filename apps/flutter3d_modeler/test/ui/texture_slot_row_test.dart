/// `TextureSlotRow`: the presentational half of `mat-05`'s texture slot.
///
///     flutter test test/ui/texture_slot_row_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/texture_slot.dart';
import 'package:flutter3d_modeler/src/ui/texture_slot_row.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _thumbnailBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

TextureSlotDisplay _displayWith({
  String? formatBadge,
  Uint8List? thumbnail,
}) => TextureSlotDisplay(
  name: 'albedo.png',
  dimensionsText: '256×128',
  weightText: '170 КБ',
  formatBadge: formatBadge,
  thumbnail: thumbnail ?? _thumbnailBytes,
);

Future<void> _show(
  WidgetTester tester, {
  String label = 'Base colour',
  TextureSlotDisplay? display,
  VoidCallback? onPick,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: TextureSlotRow(
        label: label,
        display: display,
        onPick: onPick ?? () {},
      ),
    ),
  ),
);

void main() {
  group('with an image bound', () {
    testWidgets('shows the name, dimensions, weight and thumbnail', (
      WidgetTester tester,
    ) async {
      await _show(tester, display: _displayWith(thumbnail: _thumbnailBytes));

      expect(find.text('albedo.png'), findsOneWidget);
      expect(find.text('256×128 · 170 КБ'), findsOneWidget);

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      expect(provider, isA<MemoryImage>());
      expect((provider as MemoryImage).bytes, same(_thumbnailBytes));
    });

    testWidgets('shows a format badge when the display has one', (
      WidgetTester tester,
    ) async {
      await _show(tester, display: _displayWith(formatBadge: 'BC7'));

      expect(find.text('BC7'), findsOneWidget);
    });

    testWidgets('shows no badge when the format is plain', (
      WidgetTester tester,
    ) async {
      await _show(tester, display: _displayWith());

      expect(find.text('BC7'), findsNothing);
    });

    testWidgets('a tap anywhere on the row fires onPick', (
      WidgetTester tester,
    ) async {
      var picked = false;
      await _show(
        tester,
        display: _displayWith(),
        onPick: () => picked = true,
      );

      await tester.tap(find.byType(TextureSlotRow));
      expect(picked, isTrue);
    });
  });

  group('with nothing bound', () {
    testWidgets('shows the slot label and no dimensions line', (
      WidgetTester tester,
    ) async {
      await _show(tester, label: 'Normal');

      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('still fires onPick on a tap', (WidgetTester tester) async {
      var picked = false;
      await _show(tester, onPick: () => picked = true);

      await tester.tap(find.byType(TextureSlotRow));
      expect(picked, isTrue);
    });
  });
}
