/// The frame, measured, and the one table the tools come from.
///
///     flutter test test/shell_test.dart
///
/// **Measured through `RenderBox` rather than by finding the constants.** A
/// test that asserted `ModelerMetrics.topBar == 52` would pass on a shell that
/// never used the constant; what `ui-04` asks for is that the bar on the screen
/// is 52 tall at 1440×900, and the only thing that can answer is the laid-out
/// box.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shell with four labelled boxes in it, at the size the design was drawn
/// against.
Future<void> pumpShell(
  WidgetTester tester, {
  ModelerMode mode = ModelerMode.object,
  ValueChanged<ModelerMode>? onMode,
  MeshSubmode submode = MeshSubmode.vertex,
  String? activeTool,
  ValueChanged<String>? onTool,
}) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: ModelerShell(
        mode: mode,
        onMode: onMode ?? (_) {},
        submode: submode,
        onSubmode: (_) {},
        activeTool: activeTool,
        onTool: onTool ?? (_) {},
        viewport: const ColoredBox(
          color: Color(0xFF000000),
          child: SizedBox.expand(child: Text('viewport')),
        ),
        properties: const Text('properties'),
        status: const Text('status'),
        actions: const <Widget>[Text('actions')],
      ),
    ),
  );
}

/// The box a piece of text is painted in, walked up to the region that sizes it.
Size regionOf(WidgetTester tester, String said, Type region) => tester.getSize(
  find.ancestor(of: find.text(said), matching: find.byType(region)).first,
);

void main() {
  group('the frame', () {
    testWidgets('is the sizes the design names, at 1440 by 900', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      // Every one of these is a number from `ui-04`. Mutation: give the
      // properties panel an `Expanded` instead of a width — the obvious way to
      // make a layout "flexible" — and it becomes 1336 wide, which is a
      // modeller whose picture is a strip down the left.
      expect(regionOf(tester, 'actions', SizedBox).height, 52);
      expect(regionOf(tester, 'status', SizedBox).height, 30);
      expect(regionOf(tester, 'properties', SizedBox).width, 250);
      expect(tester.getSize(find.byType(ModelerShell)), const Size(1440, 900));
    });

    testWidgets('the picture gets what the panels do not', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      // 1440 less the rail, the panel and the two hairlines between them.
      final Size viewport = tester.getSize(find.text('viewport'));
      expect(viewport.width, 1440 - 52 - 250 - 2);
      // 900 less the two bars and the two dividers over and under them.
      expect(viewport.height, 900 - 52 - 30 - 2);
    });

    testWidgets('a mode past phase one is shown and refused', (
      WidgetTester tester,
    ) async {
      final asked = <ModelerMode>[];
      await pumpShell(tester, onMode: asked.add);

      // Sculpt is phase four. It is on the bar — a mode that was missing
      // altogether would read as a mode nobody had planned — and pressing it
      // does nothing.
      await tester.tap(
        find.byIcon(ModelerMode.sculpt.icon),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(asked, isEmpty);

      // And the mesh mode, which is phase one, does answer. Mutation: drop the
      // `enabled:` on the segment and both of these arrive, so a person in a
      // half-built sculpt mode is looking at an empty rail and wondering what
      // they broke.
      await tester.tap(find.byIcon(ModelerMode.mesh.icon));
      await tester.pump();
      expect(asked, <ModelerMode>[ModelerMode.mesh]);
    });

    testWidgets(
      'the element level is shown in the mesh mode and nowhere else',
      (WidgetTester tester) async {
        await pumpShell(tester, mode: ModelerMode.object);
        expect(find.text('Vertex'), findsNothing);

        await pumpShell(tester, mode: ModelerMode.mesh);
        expect(find.text('Vertex'), findsOneWidget);
        expect(find.text('Face'), findsOneWidget);
      },
    );
  });

  group('the rail', () {
    testWidgets('holds the tools of the mode it is in', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, mode: ModelerMode.mesh);

      // Extrude belongs to the mesh mode and to no other, so finding it is
      // finding that the rail read `toolsFor` rather than a list of its own.
      expect(find.byIcon(Icons.upload_outlined), findsOneWidget);

      await pumpShell(tester, mode: ModelerMode.object);
      expect(find.byIcon(Icons.upload_outlined), findsNothing);
    });

    testWidgets('reports the tool that was pressed, by id', (
      WidgetTester tester,
    ) async {
      final pressed = <String>[];
      await pumpShell(tester, mode: ModelerMode.mesh, onTool: pressed.add);

      await tester.tap(find.byIcon(Icons.upload_outlined));
      await tester.pump();

      // By id and not by label: the label is a string that will be translated
      // in `ui-22`, and a caller switching on a translated string is a caller
      // whose tools stop working in Russian.
      expect(pressed, <String>['mesh.extrude']);
    });
  });

  group('the tool table', () {
    test('ids are unique across every mode', () {
      final seen = <String>{};
      for (final ModelerMode mode in ModelerMode.values) {
        for (final ModelerTool tool in toolsFor(mode)) {
          expect(
            seen.add(tool.id),
            isTrue,
            reason: '${tool.id} is in two modes',
          );
        }
      }
      expect(seen, isNotEmpty);
    });

    test('a shortcut means one thing within a mode', () {
      for (final ModelerMode mode in ModelerMode.values) {
        final seen = <LogicalKeyboardKey>{};
        for (final ModelerTool tool in toolsFor(mode)) {
          // Across modes a key may repeat — G moves an object and G moves a
          // vertex, which is the point of a modal interface. Within one mode a
          // repeat means one of the two tools can never be reached from the
          // keyboard, and which of them wins is whichever the `Shortcuts` map
          // happened to build last.
          expect(
            seen.add(tool.shortcut),
            isTrue,
            reason: '${tool.shortcut.keyLabel} is two tools in ${mode.label}',
          );
        }
      }
    });

    test('every phase-one mode has tools and no other does', () {
      for (final ModelerMode mode in ModelerMode.values) {
        expect(
          toolsFor(mode).isNotEmpty,
          mode.isReady,
          reason: '${mode.label} disagrees with its own phase',
        );
      }
    });
  });

  group('the theme', () {
    test('every role is a hex somebody chose', () {
      final scheme = modelerTheme().colorScheme;

      // A handful, spelled out: the surface the panels sit on, the text on it,
      // the container the selection wash already uses, and the outline that is
      // the grid's own colour. Mutation: build the scheme with
      // `ColorScheme.fromSeed` and every one of these moves — which is the
      // whole reason the scheme is written out rather than generated.
      expect(scheme.surface, const Color(0xFF14181A));
      expect(scheme.onSurface, const Color(0xFFE6E9EA));
      expect(scheme.primaryContainer, const Color(0xFF004F58));
      expect(scheme.outline, const Color(0xFF2A3234));
      expect(scheme.brightness, Brightness.dark);
    });

    test('the modeller colours travel on the theme', () {
      final colours = modelerTheme().extension<ModelerColors>();

      // Read off the theme rather than imported as constants, so a second
      // theme has somewhere to put its own answers. The viewport's is the one
      // that matters most: it is the colour every judgement about a shape is
      // made against, and it is the design's `#0E1112`.
      expect(colours, isNotNull);
      expect(colours!.viewport, const Color(0xFF0E1112));
      expect(colours.gridMinor, const Color(0xFF2A3234));
    });
  });
}
