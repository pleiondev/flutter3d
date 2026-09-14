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
  AnimationSubmode animationSubmode = AnimationSubmode.pose,
  String? activeTool,
  ValueChanged<String>? onTool,
  Size size = const Size(1440, 900),
  String documentName = 'untitled',
  bool isDirty = false,
}) async {
  tester.view
    ..physicalSize = size
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
        animationSubmode: animationSubmode,
        onAnimationSubmode: (_) {},
        activeTool: activeTool,
        onTool: onTool ?? (_) {},
        viewport: const ColoredBox(
          color: Color(0xFF000000),
          child: SizedBox.expand(child: Text('viewport')),
        ),
        properties: const Text('properties'),
        status: const Text('status'),
        actions: const <Widget>[Text('actions')],
        documentName: documentName,
        isDirty: isDirty,
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

    testWidgets('material, animation and scene are enabled (ui-39d)', (
      WidgetTester tester,
    ) async {
      // One assertion per mode, not one shared tap: a switcher that enables
      // material but not the other two would still pass a single combined
      // check if it only ever pressed the first icon it found.
      for (final ModelerMode target in <ModelerMode>[
        ModelerMode.material,
        ModelerMode.animation,
        ModelerMode.scene,
      ]) {
        final asked = <ModelerMode>[];
        await pumpShell(tester, onMode: asked.add);

        await tester.tap(find.byIcon(target.icon));
        await tester.pump();

        expect(asked, <ModelerMode>[
          target,
        ], reason: '${target.label} did not switch');
      }
    });

    testWidgets('uv, sculpt and render stay refused (ui-39d)', (
      WidgetTester tester,
    ) async {
      // `sculpt` alone was pinned above already; `uv` and `render` are the
      // other two pro-mode rows this pass deliberately leaves out.
      for (final ModelerMode target in <ModelerMode>[
        ModelerMode.uv,
        ModelerMode.sculpt,
        ModelerMode.render,
      ]) {
        final asked = <ModelerMode>[];
        await pumpShell(tester, onMode: asked.add);

        await tester.tap(find.byIcon(target.icon), warnIfMissed: false);
        await tester.pump();

        expect(
          asked,
          isEmpty,
          reason: '${target.label} should still be refused',
        );
      }
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

    // `ui-40d`'s own row: the second switcher's other tenant. Object mode
    // shows neither the mesh element levels nor the animation sub-mode —
    // "every other mode shows nothing" is the handoff's own frame rule 2.
    testWidgets(
      'the animation sub-mode is shown in the animation mode and nowhere '
      'else',
      (WidgetTester tester) async {
        await pumpShell(tester, mode: ModelerMode.object);
        expect(find.text('Pose'), findsNothing);
        expect(find.text('Weights'), findsNothing);
        expect(find.text('Retarget'), findsNothing);
        expect(find.text('Morphs'), findsNothing);

        await pumpShell(tester, mode: ModelerMode.mesh);
        expect(find.text('Pose'), findsNothing);

        await pumpShell(tester, mode: ModelerMode.animation);
        expect(find.text('Pose'), findsOneWidget);
        expect(find.text('Weights'), findsOneWidget);
        expect(find.text('Retarget'), findsOneWidget);
        expect(find.text('Morphs'), findsOneWidget);
      },
    );
  });

  group('the top bar', () {
    testWidgets('does not overflow at any width a window can be', (
      WidgetTester tester,
    ) async {
      // Eight modes, three element levels and two buttons do not fit side by
      // side under about eleven hundred logical pixels, and a window that
      // narrow is an ordinary one. Mutation: put the modes back in a plain
      // `Row` with a `Spacer` — which is what the bar was — and 1024 reports
      // `A RenderFlex overflowed by 111 pixels on the right`, with Flutter's
      // striped banner painted over the element level, the one control in the
      // mesh mode that a person has to reach.
      for (final double width in <double>[1440, 1200, 1024, 900, 800]) {
        await pumpShell(tester, mode: ModelerMode.mesh, size: Size(width, 700));
        expect(
          tester.takeException(),
          isNull,
          reason: 'the bar overflowed at $width',
        );
      }
    });
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

    test('object and mesh have tools on the rail, nothing else does yet', () {
      // Material, animation and scene are `ready` (`ui-39d`) but work through
      // their own properties-panel sections rather than the tool rail, so
      // `toolsFor` still answers empty for them — same as the modes that
      // are not `ready` at all. Only object and mesh have a rail today.
      const withTools = <ModelerMode>{ModelerMode.object, ModelerMode.mesh};
      for (final ModelerMode mode in ModelerMode.values) {
        expect(
          toolsFor(mode).isNotEmpty,
          withTools.contains(mode),
          reason: '${mode.label} disagrees with its own tool table',
        );
      }
    });
  });

  group('the theme', () {
    test('every role is a hex somebody chose', () {
      final scheme = modelerTheme().colorScheme;

      // A handful, spelled out: the surface the panels sit on, the text on it,
      // the container the selection wash already uses, and the outline the
      // design hand-over gives captions and utility values — not the grid's
      // own colour, which this test used to assert before an intermediate UI
      // review caught the mismatch; `theme_test.dart` holds the rest of the
      // scheme's own roles to the same hand-over. Mutation: build the scheme
      // with `ColorScheme.fromSeed` and every one of these moves — which is
      // the whole reason the scheme is written out rather than generated.
      expect(scheme.surface, const Color(0xFF14181A));
      expect(scheme.onSurface, const Color(0xFFE1E3E3));
      expect(scheme.primaryContainer, const Color(0xFF004F58));
      expect(scheme.outline, const Color(0xFF899295));
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

  group('the top bar names what is open', () {
    testWidgets('the document name is visible, plain when clean', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, documentName: 'teapot.f3dproj');
      expect(find.text('teapot.f3dproj'), findsOneWidget);
    });

    testWidgets('a dirty document is marked, not just named', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, documentName: 'teapot.f3dproj', isDirty: true);
      // Mutation: read `documentName` alone and drop the dirty branch — the
      // plain name would still be findsOneWidget and this would not notice.
      expect(find.text('teapot.f3dproj'), findsNothing);
      expect(find.text('• teapot.f3dproj'), findsOneWidget);
    });
  });
}
