/// `TextureSlotRow`: one texture slot in a material panel, merging the
/// modeller's own production row (a name or `"None"` beside `Choose…`/
/// `Clear`) with a richer, previously unwired row's own optional thumbnail,
/// subtitle and format badge — `ui-27`'s own P1.
///
///     flutter test test/texture_slot_row_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _thumbnailBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

Future<void> pump(
  WidgetTester tester, {
  String label = 'Base colour texture',
  String? name,
  String? subtitle,
  String? badge,
  Uint8List? thumbnail,
  VoidCallback? onChoose,
  VoidCallback? onClear,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: TextureSlotRow(
        label: label,
        name: name,
        subtitle: subtitle,
        badge: badge,
        thumbnail: thumbnail,
        onChoose: onChoose ?? () {},
        onClear: onClear,
      ),
    ),
  ),
);

void main() {
  group('the production shape — no thumbnail, subtitle or badge', () {
    testWidgets('an empty slot shows the label and "None", no thumbnail', (
      WidgetTester tester,
    ) async {
      await pump(tester, label: 'Normal map');

      expect(find.text('Normal map'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a bound slot shows its name, and offers Clear', (
      WidgetTester tester,
    ) async {
      await pump(tester, name: 'rust_albedo.png', onClear: () {});

      expect(find.text('rust_albedo.png'), findsOneWidget);
      expect(find.text('Choose…'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('an unbound slot offers no Clear', (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('Choose… reaches onChoose', (WidgetTester tester) async {
      var chosen = 0;
      await pump(tester, onChoose: () => chosen++);

      await tester.tap(find.text('Choose…'));

      expect(chosen, 1);
    });

    testWidgets('Clear reaches onClear, not onChoose', (
      WidgetTester tester,
    ) async {
      var chosen = 0;
      var cleared = 0;
      await pump(
        tester,
        name: 'rust_albedo.png',
        onChoose: () => chosen++,
        onClear: () => cleared++,
      );

      await tester.tap(find.text('Clear'));

      expect(cleared, 1);
      expect(chosen, 0);
    });
  });

  group('the richer shape — a caller with a thumbnail to show', () {
    testWidgets('shows the name, subtitle and thumbnail', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        name: 'albedo.png',
        subtitle: '256×128 · 170 KB',
        thumbnail: _thumbnailBytes,
      );

      expect(find.text('albedo.png'), findsOneWidget);
      expect(find.text('256×128 · 170 KB'), findsOneWidget);

      final Image image = tester.widget(find.byType(Image));
      final ImageProvider provider = image.image;
      expect(provider, isA<MemoryImage>());
      expect((provider as MemoryImage).bytes, same(_thumbnailBytes));
    });

    testWidgets('shows a format badge when given one', (
      WidgetTester tester,
    ) async {
      await pump(tester, thumbnail: _thumbnailBytes, badge: 'BC7');

      expect(find.text('BC7'), findsOneWidget);
    });

    testWidgets('shows no badge when none is given', (
      WidgetTester tester,
    ) async {
      await pump(tester, thumbnail: _thumbnailBytes);

      expect(find.text('BC7'), findsNothing);
    });

    testWidgets('no thumbnail draws no thumbnail well at all', (
      WidgetTester tester,
    ) async {
      await pump(tester, name: 'albedo.png', subtitle: '170 KB');

      expect(find.byType(Image), findsNothing);
    });
  });
}
