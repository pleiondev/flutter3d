/// `pro-lod-04`, end to end: screen 17 reached from an object's inspector in
/// the real editor, over the cube a launch opens on.
///
///     flutter test test/lod_mode_test.dart
///
/// `LodScreen`, `LodZoneBar` and `lod_screen_fraction.dart` each had a test
/// of their own while nothing in `lib/` imported any of them. This is the
/// part those cannot hold: that the inspector opens the screen, that a press
/// is a command and a drag is an amend, and that undo takes each back.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/lod_level_viewport.dart';
import 'package:flutter3d_modeler/src/ui/lod_panel.dart';
import 'package:flutter3d_modeler/src/ui/lod_screen.dart';
import 'package:flutter3d_modeler/src/ui/lod_zone_bar.dart';
import 'package:flutter3d_modeler/src/ui/properties/object_row.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tutorial_screenshots_support.dart';

const ValueKey<String> _add = ValueKey<String>('lodAddLevel');

Future<void> _openLodScreen(WidgetTester tester) async {
  await launchModeller(tester, fonts: true);
  await tester.tap(find.byType(ObjectRow).first);
  await settleFrames(tester);
  await openLodScreen(tester);
}

Future<void> _pressOpen(WidgetTester tester) => openLodScreen(tester);

Future<void> _scrollToOpen(WidgetTester tester) => scrollToLodsRow(tester);

void main() {
  testWidgets('the inspector opens screen 17, a level is one step, and its '
      'marker places it without a second', (WidgetTester tester) async {
    await _openLodScreen(tester);

    // Mutation: build the section and hand it no callback. The button is
    // there and the three thirds never are — which is where this screen
    // stood, with the button missing as well.
    expect(find.byType(LodScreen), findsOneWidget);
    expect(find.byType(LodPanel), findsOneWidget);
    expect(find.textContaining('No levels yet'), findsOneWidget);
    expect(find.textContaining('Now: '), findsOneWidget);
    // Three thirds, none with a mesh yet.
    expect(find.byType(LodLevelViewport), findsNWidgets(3));
    expect(find.text('No LOD 0 yet'), findsOneWidget);

    await tester.tap(find.byKey(_add));
    await settleFrames(tester);

    // Half the cube's twelve triangles, below a quarter of the screen.
    expect(find.text('No LOD 0 yet'), findsNothing);
    expect(find.text('LOD 0 · 50%'), findsOneWidget);
    expect(find.text('drawn up to 25% of the screen'), findsOneWidget);
    expect(find.byTooltip('undo add a level of detail'), findsOneWidget);

    // The marker is dragged, and the level moves with it — by amending the
    // step that made it, since nothing in `lod_commands.dart` moves a
    // threshold. Mutation: run a second `AddLod` instead. The card count
    // goes to two; and with no amend at all, the sentence on the card stays
    // at 25%.
    final Rect bar = tester.getRect(find.byType(LodZoneBar));
    await tester.dragFrom(
      Offset(bar.left + bar.width * 0.25, bar.center.dy),
      Offset(bar.width * 0.25, 0),
    );
    await settleFrames(tester);
    expect(find.text('drawn up to 25% of the screen'), findsNothing);
    expect(find.textContaining('drawn up to '), findsOneWidget);

    // One undo takes the level back whole, threshold and all.
    await tester.tap(find.byTooltip('undo add a level of detail'));
    await settleFrames(tester);
    expect(find.textContaining('No levels yet'), findsOneWidget);
    expect(find.byTooltip('nothing to undo'), findsOneWidget);
  });

  testWidgets('a level made earlier says its threshold is fixed; Back and a '
      'mode switch both leave', (WidgetTester tester) async {
    await _openLodScreen(tester);
    await tester.tap(find.byKey(_add));
    await settleFrames(tester);
    await tester.tap(find.byKey(_add));
    await settleFrames(tester);
    expect(find.text('LOD 1 · 25%'), findsOneWidget);

    // The first level is no longer the step on top, so its marker cannot be
    // an amend. Mutation: amend regardless. The *second* level — the one
    // the top step made — is rewritten with the first one's threshold.
    final Rect bar = tester.getRect(find.byType(LodZoneBar));
    await tester.dragFrom(
      Offset(bar.left + bar.width * 0.25, bar.center.dy),
      Offset(bar.width * 0.2, 0),
    );
    await settleFrames(tester);
    expect(find.textContaining('no command that moves one'), findsWidgets);
    expect(find.text('drawn up to 25% of the screen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('lodClose')));
    await settleFrames(tester);
    expect(find.byType(LodScreen), findsNothing);
    await _scrollToOpen(tester);
    expect(find.text('Levels: 2'), findsOneWidget);

    // Open again, leave by the mode switch, and come back to the inspector
    // rather than to a screen nobody was looking at.
    await _pressOpen(tester);
    expect(find.byType(LodScreen), findsOneWidget);
    await switchMode(tester, ModelerMode.material);
    await switchMode(tester, ModelerMode.object);
    expect(find.byType(LodScreen), findsNothing);
  });
}
