/// `ux-21`'s own row: what the web build needs on a window it was not
/// designed for — the three big dialogs on a narrow screen, the document's
/// own name on the two touch shells, a finger-sized panel, and a FAB whose
/// icon is not its only label.
///
///     flutter test test/touch_shells_test.dart
///
/// **800×1200 is the shape of the argument.** It is a tablet held upright
/// and it is also a browser window somebody has dragged narrow, and it is
/// the width at which every fixed-size dialog in this application paints the
/// overflow stripes over its own right-hand panel.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_modeler/src/ui/lathe_dialog.dart';
import 'package:flutter3d_modeler/src/ui/material_studio_dialog.dart';
import 'package:flutter3d_modeler/src/ui/roomy_dialog.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/shell_phone.dart';
import 'package:flutter3d_modeler/src/ui/shell_tablet.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

Renderer testRenderer() {
  final it = cpuTestDevice();
  return Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
}

/// A fixed number of frames rather than `pumpAndSettle`, for the reason
/// `lathe_dialog_test.dart` writes out: a live render loop never reaches a
/// frame where nothing at all is scheduled.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> atSize(
  WidgetTester tester,
  ui.Size size,
  Future<void> Function() body,
) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await body();
}

/// The theme with the platform pinned, for the reason `modeler_keys_test.dart`
/// pins it: `ThemeData` derives `materialTapTargetSize` from the platform —
/// `padded` on a phone, `shrinkWrap` on a desktop — so a test that let it
/// fall back to the host would pass in CI and fail on a Mac, or the other
/// way round, depending only on where it happened to run. A desktop platform
/// is also the harder case and the real one: this application ships to macOS
/// and to a browser reporting itself as one.
ThemeData deskTheme() =>
    modelerTheme().copyWith(platform: TargetPlatform.macOS);

/// A properties panel of the shape the real one has: rows of labels with a
/// control each, which is what a finger has to hit.
Widget panel() => ListView(
  children: <Widget>[
    for (final String each in <String>['Position', 'Rotation', 'Scale'])
      ListTile(
        title: Text(each),
        trailing: IconButton(
          tooltip: 'Reset $each',
          icon: const Icon(Icons.refresh),
          onPressed: () {},
        ),
      ),
    SwitchListTile(
      title: const Text('Visible'),
      value: true,
      onChanged: (_) {},
    ),
  ],
);

Future<void> pumpPhone(
  WidgetTester tester, {
  String documentName = 'teapot',
  bool isDirty = false,
  Widget? properties,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: ModelerPhoneShell(
      mode: ModelerMode.mesh,
      onMode: (_) {},
      submode: MeshSubmode.vertex,
      onSubmode: (_) {},
      activeTool: 'mesh.extrude',
      onTool: (_) {},
      viewport: const SizedBox.expand(),
      properties: properties ?? const Text('properties'),
      status: const Text('status'),
      documentName: documentName,
      isDirty: isDirty,
    ),
  ),
);

Future<void> pumpTablet(
  WidgetTester tester, {
  String documentName = 'teapot',
  bool isDirty = false,
  Widget? properties,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: ModelerTabletShell(
      mode: ModelerMode.object,
      onMode: (_) {},
      submode: MeshSubmode.vertex,
      onSubmode: (_) {},
      activeTool: null,
      onTool: (_) {},
      viewport: const SizedBox.expand(),
      properties: properties ?? const Text('properties'),
      status: const Text('status'),
      documentName: documentName,
      isDirty: isDirty,
    ),
  ),
);

void main() {
  group('ux-21: the document has a name on every shell', () {
    testWidgets('the phone shell shows it, with no actions to hang it on', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(420, 900), () async {
        await pumpPhone(tester);

        // Mutation: draw the bar only when there are actions, as this shell
        // did. A web build opened on a phone then shows no file name at all
        // — and unlike a desktop build it has no window title behind it.
        expect(find.text('teapot'), findsOneWidget);
      });
    });

    testWidgets('and marks it when it is unsaved', (WidgetTester tester) async {
      await atSize(tester, const ui.Size(420, 900), () async {
        await pumpPhone(tester, isDirty: true);

        expect(find.text('• teapot'), findsOneWidget);
      });
    });

    testWidgets('the tablet shell says the same thing the same way', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(900, 700), () async {
        await pumpTablet(tester, isDirty: true);

        expect(find.text('• teapot'), findsOneWidget);
      });
    });

    test('and one spelling answers for all three', () {
      expect(documentLabel('teapot', isDirty: false), 'teapot');
      expect(documentLabel('teapot', isDirty: true), '• teapot');
    });
  });

  // The guideline itself runs over the real `PropertiesPanel`, in
  // `properties_panel_test.dart` — that file already has the sixty-odd
  // callbacks wired, and a stand-in panel would be a test of the stand-in.
  // What is left here is the two halves of the mechanism.
  group('ux-21: a finger can hit what is in the panel', () {
    testWidgets('the shells hand the panel over grown', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(800, 1200), () async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: deskTheme(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) =>
                    withTouchTargets(context, panel()),
              ),
            ),
          ),
        );

        // Mutation: hand the panel over untouched, the way both touch
        // shells did. `materialTapTargetSize` is `shrinkWrap` on exactly the
        // platforms this row is about, so every button in the sheet a thumb
        // is aiming at is drawn at its own visual size with no padding.
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });
    });

    testWidgets('and the desktop keeps its own smaller ones', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(1440, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: deskTheme(),
            home: Scaffold(body: panel()),
          ),
        );

        // Not a guideline check — the point is that nothing here grew. A
        // desktop panel built at 48 a row spends a third of its height
        // guarding against a misclick a cursor with a one-pixel hotspot
        // cannot make, and shows two thirds as much of the document for it.
        late double row;
        await tester.pumpWidget(
          MaterialApp(
            theme: deskTheme(),
            home: Builder(
              builder: (BuildContext context) {
                row = rowHeightOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(row, ModelerMetrics.row);
      });
    });
  });

  group('ux-21: the phone FAB says what it is', () {
    testWidgets('it names the armed tool rather than showing only an icon', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(420, 900), () async {
        await pumpPhone(tester);

        // Mutation: leave the tooltip off, as it was. The one control on
        // this shell whose icon changes with the armed tool is then the one
        // control with no way at all to find out what it means.
        final Finder fab = find.byType(FloatingActionButton);
        expect(tester.widget<FloatingActionButton>(fab).tooltip, isNotNull);
        expect(
          tester.widget<FloatingActionButton>(fab).tooltip,
          contains('Extrude'),
        );
      });
    });
  });

  group('ux-18: a phone has no hover, so the sheet carries the sentence', () {
    testWidgets('every row of the tool sheet says what the tool does', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(420, 900), () async {
        await pumpPhone(tester);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        // **A tooltip nobody can reach is not an explanation.** The desktop
        // rail keeps this on the second line of a hover; a thumb has no
        // hover, so the row itself has to say it. Mutation: drop the
        // subtitle here and the one shell with no tooltips at all is the
        // one shell where "Dissolve edges" stays a word.
        final ModelerTool first = toolsFor(ModelerMode.mesh).first;
        final ListTile row = tester.widget<ListTile>(
          find
              .ancestor(
                of: find.text(first.label),
                matching: find.byType(ListTile),
              )
              .first,
        );
        expect((row.subtitle! as Text).data, first.about);
      });
    });
  });

  group('ux-21: the big dialogs on a window that cannot hold them', () {
    testWidgets('Lathe opens full-screen at 800×1200, and does not overflow', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(800, 1200), () async {
        final Renderer renderer = testRenderer();
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () => showLatheDialog(context, renderer: renderer),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await settle(tester);

        // Mutation: keep the 900×720 `AlertDialog`. Flutter does not shrink
        // it — it paints the overflow stripes over the right-hand column,
        // which on this dialog is the segment count and the vertex summary.
        expect(find.byType(Dialog), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (Widget it) => it is SizedBox && it.width == 900,
          ),
          findsNothing,
        );
        expect(find.text('Segments'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('and keeps its desktop size where there is room', (
      WidgetTester tester,
    ) async {
      await atSize(tester, const ui.Size(1400, 900), () async {
        final Renderer renderer = testRenderer();
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () => showLatheDialog(context, renderer: renderer),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await settle(tester);

        // The working surface is a working surface: a profile editor that
        // came up a different size every session would be worse than one
        // that is sometimes too big for the window.
        expect(
          find.byWidgetPredicate(
            (Widget it) => it is SizedBox && it.width == 900,
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('Material Studio too', (WidgetTester tester) async {
      await atSize(tester, const ui.Size(800, 1200), () async {
        final Renderer renderer = testRenderer();
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () => showMaterialStudioDialog(
                    context,
                    renderer: renderer,
                    material: engine.Material(
                      name: 'clay',
                      baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await settle(tester);

        expect(find.text('Material Studio'), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (Widget it) => it is SizedBox && it.width == 720,
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('and the rule itself is one question about the window', (
      WidgetTester tester,
    ) async {
      late bool roomy;
      await atSize(tester, const ui.Size(1199, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                roomy = hasRoomForDialogs(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });
      expect(roomy, isFalse);

      await atSize(tester, const ui.Size(1200, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                roomy = hasRoomForDialogs(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });
      // The same 1200 `LayoutClass` already draws the desktop shell at, and
      // deliberately the same number: a window wide enough for the rail and
      // the panel is a window wide enough for the dialogs they open.
      expect(roomy, isTrue);
    });
  });
}
