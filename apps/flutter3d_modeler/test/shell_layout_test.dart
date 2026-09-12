/// `ui-05`'s own row: which shell a width draws as, and that every one of the
/// three answers the same tool keys.
///
///     flutter test test/shell_layout_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/layout_class.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/shell_phone.dart';
import 'package:flutter3d_modeler/src/ui/shell_tablet.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// One of the three shells, chosen by [layoutClass], with a pointer/keyboard
/// counter wired to every tool press so a test can ask "how many of
/// [toolsFor]'s own tools fired" without knowing which widget answered.
Widget _shellFor(
  LayoutClass layoutClass, {
  required ModelerMode mode,
  required ValueChanged<String> onTool,
  String? activeTool,
}) {
  const viewport = ColoredBox(
    color: Color(0xFF000000),
    child: SizedBox.expand(child: Text('viewport')),
  );
  const properties = Text('properties');
  const status = Text('status');
  const actions = <Widget>[Text('actions')];

  return switch (layoutClass) {
    LayoutClass.desktop => ModelerShell(
      mode: mode,
      onMode: (_) {},
      submode: MeshSubmode.vertex,
      onSubmode: (_) {},
      activeTool: activeTool,
      onTool: onTool,
      viewport: viewport,
      properties: properties,
      status: status,
      actions: actions,
    ),
    LayoutClass.tablet => ModelerTabletShell(
      mode: mode,
      onMode: (_) {},
      submode: MeshSubmode.vertex,
      onSubmode: (_) {},
      activeTool: activeTool,
      onTool: onTool,
      viewport: viewport,
      properties: properties,
      status: status,
      actions: actions,
    ),
    LayoutClass.phone => ModelerPhoneShell(
      mode: mode,
      onMode: (_) {},
      submode: MeshSubmode.vertex,
      onSubmode: (_) {},
      activeTool: activeTool,
      onTool: onTool,
      viewport: viewport,
      properties: properties,
      status: status,
      actions: actions,
    ),
  };
}

Future<void> _pump(
  WidgetTester tester,
  LayoutClass layoutClass, {
  ModelerMode mode = ModelerMode.mesh,
  ValueChanged<String>? onTool,
  String? activeTool,
  Size size = const Size(800, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: _shellFor(
        layoutClass,
        mode: mode,
        onTool: onTool ?? (_) {},
        activeTool: activeTool,
      ),
    ),
  );
}

void main() {
  group('LayoutClass.of picks the shell', () {
    // The boundary itself is `layout_class_test.dart`'s own row; this only
    // checks that each class actually reaches a different widget type, since
    // `ui-05`'s acceptance is about the shell that is drawn, not only the
    // classification.
    test('phone, tablet and desktop are three different widgets', () {
      expect(
        _shellFor(LayoutClass.phone, mode: ModelerMode.mesh, onTool: (_) {}),
        isA<ModelerPhoneShell>(),
      );
      expect(
        _shellFor(LayoutClass.tablet, mode: ModelerMode.mesh, onTool: (_) {}),
        isA<ModelerTabletShell>(),
      );
      expect(
        _shellFor(LayoutClass.desktop, mode: ModelerMode.mesh, onTool: (_) {}),
        isA<ModelerShell>(),
      );
    });
  });

  group('the same tool keys in three shells', () {
    testWidgets('every mesh-mode tool id fires in all three shells', (
      WidgetTester tester,
    ) async {
      final tools = toolsFor(ModelerMode.mesh);
      expect(tools, isNotEmpty);

      for (final layoutClass in LayoutClass.values) {
        final pressed = <String>[];
        await _pump(
          tester,
          layoutClass,
          mode: ModelerMode.mesh,
          onTool: pressed.add,
          size: switch (layoutClass) {
            LayoutClass.phone => const Size(360, 800),
            LayoutClass.tablet => const Size(800, 900),
            LayoutClass.desktop => const Size(1440, 900),
          },
        );

        if (layoutClass == LayoutClass.phone) {
          // The phone shell's own tools sit in a `ListTile` sheet rather
          // than as tappable icons on a rail — found by label (unique per
          // tool, unlike an icon, which two tools can share).
          for (final tool in tools) {
            // Each tool gets its own trip through the FAB: `onTap` pops the
            // sheet, and the pop's own animation has to be pumped out before
            // the next one opens, or the scheduler carries an unsettled
            // performance-mode request into the next test.
            await tester.tap(find.byType(FloatingActionButton));
            await tester.pumpAndSettle();
            final tile = find.widgetWithText(ListTile, tool.label);
            // The sheet's own list is taller than the sheet: a row past the
            // first screenful is not built at all until scrolled to, not
            // merely offscreen.
            await tester.scrollUntilVisible(
              tile,
              50,
              scrollable: find.byType(Scrollable).last,
            );
            expect(
              tile,
              findsOneWidget,
              reason: '${tool.id} has no sheet row in $layoutClass',
            );
            // Fired by calling `onTap` directly rather than a simulated
            // tap: a modal sheet mid-slide-in animation is not a reliable
            // target for `tester.tap`'s own hit-testing, and what this loop
            // checks is that every tool's own callback is wired to the
            // right id, not that a finger can land on a moving sheet.
            tester.widget<ListTile>(tile).onTap!();
            await tester.pumpAndSettle();
          }
          expect(
            pressed.toSet(),
            tools.map((t) => t.id).toSet(),
            reason: '$layoutClass did not reach every tool',
          );
        } else {
          // Desktop and tablet show every tool as an icon button on a rail
          // or palette — found and tapped for real, since there is no sheet
          // animation to race here. Both are a scrollable `ListView`, so a
          // mode with enough tools to run past one screenful still needs
          // scrolling to before a row this far down is built at all.
          for (final tool in tools) {
            final icon = find.byIcon(tool.icon);
            await tester.scrollUntilVisible(
              icon,
              50,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              icon,
              findsWidgets,
              reason: '${tool.id} has no ${tool.icon} in $layoutClass',
            );
            await tester.tap(icon.first);
            await tester.pumpAndSettle();
          }
          expect(
            pressed.toSet(),
            tools.map((t) => t.id).toSet(),
            reason: '$layoutClass did not reach every tool',
          );
        }
      }
    });
  });

  group('the tablet shell', () {
    testWidgets('palette is 48 wide, sheet is 200 tall', (
      WidgetTester tester,
    ) async {
      await _pump(tester, LayoutClass.tablet, size: const Size(800, 900));

      // The palette's own `ListView` is the only one in this tree — the
      // mode switcher scrolls horizontally through a plain
      // `SingleChildScrollView`, not a `ListView` — so its ancestor `SizedBox`
      // is unambiguously the palette's own width. The literal 48 is the
      // row's own number, not `ModelerMetrics.tabletPalette` read back at
      // itself: a mutated constant would move both sides of that comparison
      // together and this test would never notice.
      final palette = tester.getSize(
        find
            .ancestor(of: find.byType(ListView), matching: find.byType(SizedBox))
            .first,
      );
      expect(palette.width, 48);

      // The sheet's own height, measured through the `SizedBox`
      // `ModelerPropertiesSheet` wraps its handle-and-child column in, found
      // by the drag handle's own `Container`, which is otherwise the only
      // bare `Container` in this tree. 200, the row's own literal, for the
      // same reason 48 is above.
      final handle = find.byWidgetPredicate(
        (Widget w) => w is Container && w.constraints?.maxHeight == 4,
      );
      expect(handle, findsOneWidget);
      expect(tester.getSize(handle), const Size(32, 4));
      final sheet = tester.getSize(
        find.ancestor(of: handle, matching: find.byType(SizedBox)).first,
      );
      expect(sheet.height, 200);
    });
  });

  group('the phone shell', () {
    testWidgets('has an 80-tall nav bar and a 56 FAB', (
      WidgetTester tester,
    ) async {
      await _pump(tester, LayoutClass.phone, size: const Size(360, 800));

      // Literals, not `ModelerMetrics.phoneNavBar`/`phoneFab` read back at
      // themselves — the same reason the tablet test above uses 48 and 200
      // rather than the constants a mutation would move together with the
      // assertion.
      expect(tester.getSize(find.byType(NavigationBar)).height, 80);
      final fabBox = tester.getSize(find.byType(FloatingActionButton));
      expect(fabBox.width, 56);
      expect(fabBox.height, 56);
    });

    testWidgets('an action in the "More" sheet is actually tappable', (
      WidgetTester tester,
    ) async {
      // The review's own bug: `PopupMenuItem(enabled: false, ...)` reads as
      // a disabled action even though the widget it wraps has a real
      // `onPressed`, because the disabled item swallows the tap before it
      // ever reaches its own child. This action's `onPressed` is the fact
      // under test, not the finder — a mutation that put the disabled
      // wrapper back would leave this button unreachable, not merely
      // relabelled.
      var pressed = false;
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: ModelerPhoneShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            activeTool: null,
            onTool: (_) {},
            viewport: const SizedBox.expand(),
            properties: const Text('properties'),
            status: const Text('status'),
            actions: <Widget>[
              ElevatedButton(
                onPressed: () => pressed = true,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('the status widget actually renders, not just declared', (
      WidgetTester tester,
    ) async {
      // The review's own other bug: `status` was a required constructor
      // parameter this shell never placed in its own build() tree, so
      // nothing set through it was ever visible at this width.
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: const ModelerPhoneShell(
            mode: ModelerMode.object,
            onMode: _noOnMode,
            submode: MeshSubmode.vertex,
            onSubmode: _noOnSubmode,
            activeTool: null,
            onTool: _noOnTool,
            viewport: SizedBox.expand(),
            properties: Text('properties'),
            status: Text('could not save: disk full'),
          ),
        ),
      );

      expect(find.text('could not save: disk full'), findsOneWidget);
    });
  });
}

void _noOnMode(ModelerMode mode) {}
void _noOnSubmode(MeshSubmode submode) {}
void _noOnTool(String id) {}
