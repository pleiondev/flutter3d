/// `pro-uv-07`, end to end: the UV mode reached through the real switcher,
/// in the real editor, over the cube a launch opens on.
///
///     flutter test test/uv_mode_test.dart
///
/// **A whole-screen test, because what was missing was the wiring.**
/// `UvScreen`, its panel and its layout each had a test of their own while
/// no line of `lib/` imported any of them: every one of those tests passed
/// over a mode nobody could open. What this file holds is the part they
/// cannot — that the switcher reaches the screen, that the rail and the
/// button run the commands, and that undo takes each one back.
///
/// Three launches rather than one per sentence: opening the software
/// rasteriser is most of what a test here costs.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter3d_modeler/src/ui/uv_layout_view.dart';
import 'package:flutter3d_modeler/src/ui/uv_screen.dart';
import 'package:flutter3d_modeler/src/ui/uv_unwrap_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tutorial_screenshots_support.dart';

const ValueKey<String> _unwrap = ValueKey<String>('uvUnwrap');

Future<void> _openUvMode(WidgetTester tester) =>
    openUvModeOnTheCube(tester, fonts: true);

Future<void> _cutEveryEdge(WidgetTester tester) => cutEveryEdge(tester);

/// What the chip over the picture says.
String _seamChip(WidgetTester tester) =>
    tester.widgetList<Text>(find.textContaining('Seams · ')).single.data!;

UvLayoutView _layout(WidgetTester tester) =>
    tester.widget<UvLayoutView>(find.byType(UvLayoutView));

void main() {
  testWidgets('the switcher reaches screen 06, and an uncut cube is told to '
      'be cut', (WidgetTester tester) async {
    await _openUvMode(tester);

    // Mutation: leave `ModelerMode.uv` at `ready: false`. `switchMode` finds
    // no segment to press, which is where this mode stood.
    expect(find.byType(UvScreen), findsOneWidget);
    expect(find.text('No islands'), findsOneWidget);
    expect(find.text('Seams · 0 edges'), findsOneWidget);
    // The mesh mode's own level switch, since a seam is an edge selection.
    expect(find.byType(SegmentedButton<MeshSubmode>), findsOneWidget);

    // A closed surface with no seam on it flattens onto a line, and the
    // command calls that done. Mutation: drop the wiring's own look at what
    // landed. The square stays empty, the strip says "unwrap", and nothing
    // anywhere says why.
    await tester.tap(find.byKey(_unwrap));
    await settleFrames(tester);
    expect(find.text('No islands'), findsOneWidget);
    expect(find.textContaining('Mark seams'), findsWidgets);
  });

  testWidgets('seams, an unwrap, an island and two undos', (
    WidgetTester tester,
  ) async {
    await _openUvMode(tester);

    await _cutEveryEdge(tester);
    // A triangulated cube has eighteen edges. Mutation: hand the rail's
    // button to nothing — `commandFor` answering null for `uv.markSeam`
    // arms the tool and marks no seam.
    expect(_seamChip(tester), 'Seams · 18 edges');

    await tester.tap(find.byKey(_unwrap));
    await settleFrames(tester);
    // Mutation: build the panel's button and hand it no callback, or one
    // that never reaches `ModelerCubit.ran`. The list stays empty.
    expect(find.text('No islands'), findsNothing);
    expect(find.text('Island 0'), findsOneWidget);
    expect(find.textContaining('Unwrap fill'), findsOneWidget);

    // One field behind both halves, which is `UvScreen.onIslandSelected`'s
    // own promise carried up into the screen's state. Mutation: keep a
    // second field for the list. The row lights and the outline does not.
    await tester.tap(find.text('Island 0'));
    await settleFrames(tester);
    expect(_layout(tester).selectedIslandId, 0);
    expect(
      tester.widget<UvUnwrapPanel>(find.byType(UvUnwrapPanel)).selectedIslandId,
      0,
    );
    // And the same row again puts it out: a list has no background to
    // click on instead.
    await tester.tap(find.text('Island 0'));
    await settleFrames(tester);
    expect(_layout(tester).selectedIslandId, isNull);

    // The tooltip names the step, which is how this knows the unwrap went
    // through the history as itself. Mutation: write the UVs from the
    // wiring instead of through `UnwrapCommand` — the step on top is the
    // seam, and this finds no "undo unwrap" to press.
    await tester.tap(find.byTooltip('undo unwrap'));
    await settleFrames(tester);
    expect(find.text('No islands'), findsOneWidget);
    expect(find.text('Seams · 18 edges'), findsOneWidget);

    // Eighteen edges, one step.
    await tester.tap(find.byTooltip('undo mark the seam'));
    await settleFrames(tester);
    expect(find.text('Seams · 0 edges'), findsOneWidget);
  });

  testWidgets('Pack with one object selected says what Pack is for', (
    WidgetTester tester,
  ) async {
    await _openUvMode(tester);

    // The rail's own button, by the glyph only it carries in this mode.
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await settleFrames(tester);

    // Mutation: drop the wiring's own check and let `PackAtlas` refuse. It
    // does, in English, whatever language the interface is in.
    expect(find.textContaining('An atlas is shared'), findsWidgets);
  });
}
