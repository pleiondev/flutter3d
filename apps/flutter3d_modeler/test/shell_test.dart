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
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
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
  double? propertiesWidth,
  ValueChanged<double>? onPropertiesWidth,
  bool foldedPanel = false,
  bool foldedRail = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
        propertiesWidth: propertiesWidth,
        onPropertiesWidth: onPropertiesWidth,
        foldedPanel: foldedPanel,
        foldedRail: foldedRail,
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

    testWidgets(
      'ui-41d: a 270 bottom slot leaves the viewport 545 tall at 1440×900',
      (WidgetTester tester) async {
        tester.view
          ..physicalSize = const Size(1440, 900)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: modelerTheme(),
            home: ModelerShell(
              mode: ModelerMode.animation,
              onMode: (_) {},
              submode: MeshSubmode.vertex,
              onSubmode: (_) {},
              animationSubmode: AnimationSubmode.pose,
              onAnimationSubmode: (_) {},
              activeTool: null,
              onTool: (_) {},
              viewport: const ColoredBox(
                color: Color(0xFF000000),
                child: SizedBox.expand(child: Text('viewport')),
              ),
              properties: const Text('properties'),
              status: const Text('status'),
              bottom: const ColoredBox(
                color: Color(0xFF000000),
                child: Center(child: Text('bottom')),
              ),
              bottomHeight: 270,
            ),
          ),
        );

        // 816 (today's own full-height viewport, see the test above) less
        // the 270 slot and the one hairline between them.
        final Size viewport = tester.getSize(find.text('viewport'));
        expect(viewport.height, 545);
        expect(regionOf(tester, 'bottom', SizedBox).height, 270);
      },
    );

    testWidgets('a mode past phase one is not on the bar at all', (
      WidgetTester tester,
    ) async {
      final asked = <ModelerMode>[];
      await pumpShell(tester, onMode: asked.add);

      // **This used to be "shown and refused", and `ux-07` reversed it.** The
      // old reasoning was that a mode missing altogether would read as a mode
      // nobody had planned. The live run cost that its case: the switcher is
      // eight unlabelled icons, three of them look active, and pressing one
      // of those three is indistinguishable from a press that missed. A
      // roadmap belongs on the site, not in the one control a person uses
      // every minute.
      //
      // Mutation: put the disabled segments back. `sculpt` is on the bar
      // again and this finds it.
      expect(find.byIcon(ModelerMode.sculpt.icon), findsNothing);
      expect(find.byIcon(ModelerMode.uv.icon), findsNothing);
      expect(find.byIcon(ModelerMode.render.icon), findsNothing);

      // And the mesh mode, which is ready, is there and answers.
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

    testWidgets('uv, sculpt and render are unreachable (ui-39d, ux-07)', (
      WidgetTester tester,
    ) async {
      // One assertion per mode rather than one shared sweep: a switcher that
      // hid `sculpt` and left the other two would pass a check that only
      // looked for the first.
      for (final ModelerMode target in <ModelerMode>[
        ModelerMode.uv,
        ModelerMode.sculpt,
        ModelerMode.render,
      ]) {
        final asked = <ModelerMode>[];
        await pumpShell(tester, onMode: asked.add);

        expect(
          find.byIcon(target.icon),
          findsNothing,
          reason: '${target.label} is not built and should not be offered',
        );
        expect(asked, isEmpty);
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

    testWidgets("ux-18: the tooltip says what the tool does, not only what "
        'it is called', (WidgetTester tester) async {
      await pumpShell(tester, mode: ModelerMode.mesh);

      final ModelerTool dissolve = toolsFor(
        ModelerMode.mesh,
      ).firstWhere((ModelerTool it) => it.id == 'mesh.dissolve');
      final Tooltip tip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byIcon(dissolve.icon),
          matching: find.byType(Tooltip),
        ),
      );

      // **"Dissolve edges" is a name.** The review watched people press it
      // to find out what it was. Mutation: leave the tooltip as the label
      // and its key, and the one place the interface could have explained
      // itself repeats the word already on the button.
      expect(tip.message, contains(dissolve.label));
      expect(tip.message, contains('\n'));
      expect(tip.message, endsWith(dissolve.about));
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

  group('ux-08: the properties panel is somewhere a ListTile can live', () {
    testWidgets('a ListTile in the panel does not bring the build down', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // **A `ListTile`, because that is what the Scene panels are made of.**
      // `scene_source_panel.dart`, `scene_shadows_panel.dart` and
      // `scene_post_panel.dart` are lists of `ListTile`/`SwitchListTile`, and
      // a `ListTile` asserts in a debug build when it can find no `Material`
      // ancestor to paint its background and ink into. The panel was a
      // `ColoredBox` — the same colour, not a `Material` — so entering Scene
      // mode threw on every frame and stacked a crash dialog per frame over
      // a black window.
      //
      // Mutation: put the `ColoredBox` back. This throws "ListTile
      // background color or ink splashes may be invisible".
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: ModelerShell(
            mode: ModelerMode.scene,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            animationSubmode: AnimationSubmode.pose,
            onAnimationSubmode: (_) {},
            activeTool: null,
            onTool: (_) {},
            viewport: const ColoredBox(
              color: Color(0xFF000000),
              child: SizedBox.expand(),
            ),
            properties: Column(
              children: <Widget>[
                // **Tappable, and that is not incidental.** The check only
                // runs for a tile with an `onTap`/`onLongPress` or an opaque
                // tile colour — `ListTile.build`, Flutter 3.47 — because
                // those are the tiles whose background and ink an opaque
                // ancestor would swallow. Every tile in the Scene panels has
                // one; a decorative tile would make this test vacuous.
                ListTile(title: const Text('Sources'), onTap: () {}),
                SwitchListTile(
                  value: true,
                  onChanged: (_) {},
                  title: const Text('Shadows'),
                ),
              ],
            ),
            status: const Text('status'),
            actions: const <Widget>[Text('actions')],
            documentName: 'untitled',
            isDirty: false,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sources'), findsOne);
    });

    testWidgets('and every ready mode can be entered with asserts on', (
      WidgetTester tester,
    ) async {
      for (final ModelerMode mode in ModelerMode.values) {
        if (!mode.ready) continue;
        await pumpShell(tester, mode: mode);
        expect(
          tester.takeException(),
          isNull,
          reason: '${mode.label} threw on the way in',
        );
      }
    });
  });

  group('ux-27: panels that resize and fold', () {
    testWidgets('a folded panel gives its width to the picture', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final double before = regionOf(tester, 'viewport', Expanded).width;

      await pumpShell(tester, foldedPanel: true);

      // Mutation: hide the panel and leave its width behind. The point of
      // folding it is the picture, and a gap where the panel was is the one
      // outcome nobody wants.
      expect(find.text('properties'), findsNothing);
      expect(
        regionOf(tester, 'viewport', Expanded).width,
        greaterThan(before + 200),
      );
    });

    testWidgets('and a folded rail gives its own', (WidgetTester tester) async {
      await pumpShell(tester);
      final double before = regionOf(tester, 'viewport', Expanded).width;

      await pumpShell(tester, foldedRail: true);

      expect(
        regionOf(tester, 'viewport', Expanded).width,
        closeTo(before + ModelerMetrics.rail + 1, 0.5),
      );
    });

    testWidgets('the panel is as wide as it is told, within its range', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, propertiesWidth: 400);

      expect(regionOf(tester, 'properties', SizedBox).width, 400);

      // Past the widest it may be, it is the widest it may be — the number
      // arrives from a saved document as well as from a drag.
      await pumpShell(tester, propertiesWidth: 4000);
      expect(
        regionOf(tester, 'properties', SizedBox).width,
        ModelerMetrics.propertiesWidest,
      );
    });

    testWidgets('dragging the splitter reports a wider panel', (
      WidgetTester tester,
    ) async {
      final widths = <double>[];
      await pumpShell(
        tester,
        propertiesWidth: 300,
        onPropertiesWidth: widths.add,
      );

      // The splitter lies over the panel's own left edge, so that nothing in
      // the row moves to make room for it.
      final Offset panel = tester.getTopLeft(find.text('properties'));
      await tester.dragFrom(Offset(panel.dx + 3, 400), const Offset(-40, 0));
      await tester.pump();

      // Mutation: report the raw delta, or report it with the wrong sign.
      // Dragging left would then narrow the panel it is pulling wider.
      expect(widths, isNotEmpty);
      expect(widths.last, greaterThan(300));
    });

    testWidgets('and offering the drag at all moves nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final double without = regionOf(tester, 'viewport', Expanded).width;

      await pumpShell(tester, onPropertiesWidth: (_) {});

      // Mutation: put the grab zone in the row as a widget of its own. Six
      // pixels wide enough to hit is six pixels the picture loses, and every
      // screenshot in the tutorial moves by six pixels to pay for it — which
      // is how this was found.
      expect(regionOf(tester, 'viewport', Expanded).width, without);
    });
  });
}
