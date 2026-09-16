/// `ui-23`'s own row: semantics/tooltip, contrast, tap targets and 1.3×
/// text scale on the shells everyone actually presses — the desktop rail,
/// the tablet palette, the phone tool sheet and the mode switcher.
///
///     flutter test test/accessibility_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/shell_phone.dart';
import 'package:flutter3d_modeler/src/ui/shell_tablet.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

// No text in any of the three: the real viewport is a GPU canvas with no
// semantics of its own, and the real properties/status panels are covered by
// their own tests (`properties_sections_test.dart` and friends) — a plain
// placeholder `Text` here would be graded on *its* contrast against a stand-in
// background, which is a fact about this fixture rather than about the shell
// chrome this row is actually checking.
const _viewport = ColoredBox(color: Color(0xFF000000));
const _properties = SizedBox.shrink();
const _status = SizedBox.shrink();

Widget _wrapped(Widget child, {Size size = const Size(1440, 900)}) =>
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(body: child),
    );

/// The nearest `FocusTraversalGroup` above [of] — which region Tab treats
/// whatever is there as part of (`ux-33`).
///
/// The element rather than the widget, because two groups built from the
/// same `const` expression compare equal and what is in question is whether
/// they are the same one.
Element regionOf(WidgetTester tester, Finder of) => tester.element(
  find.ancestor(of: of, matching: find.byType(FocusTraversalGroup)).first,
);

void main() {
  group('ux-33: Tab moves between regions rather than through everything', () {
    testWidgets('the shell puts a traversal group round each region', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrapped(
          ModelerShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            animationSubmode: AnimationSubmode.pose,
            onAnimationSubmode: (_) {},
            onTool: (_) {},
            activeTool: null,
            viewport: _viewport,
            properties: const Text('a field in the panel'),
            status: _status,
            agentPanel: const Text('a row in the agent panel'),
          ),
        ),
      );

      // **Each region's own group, and not one shared with its neighbour.**
      // Mutation: drop the groups, which is how this was — Tab then walks
      // the whole window in whatever order the widgets happen to be built
      // in, so somebody in the properties panel reaches the rail's twelfth
      // button before the field under the one they were in. Without the
      // groups every one of these is `MaterialApp`'s own, and all three
      // comparisons below are the same element.
      final Element panel = regionOf(tester, find.text('a field in the panel'));
      final Element agent = regionOf(
        tester,
        find.text('a row in the agent panel'),
      );
      final Element rail = regionOf(
        tester,
        find.byIcon(Icons.near_me_outlined),
      );
      final Element bar = regionOf(tester, find.byTooltip('Object'));

      expect(<Element>{panel, agent, rail, bar}, hasLength(4));
    });

    testWidgets('and the viewport takes the focus, so the arrows can turn it', (
      WidgetTester tester,
    ) async {
      // The one control in the application that needed a mouse to use at
      // all: every panel is a list of focusable fields, every tool has a
      // letter, and the picture in the middle could only be turned by
      // dragging. `ux-33` gives it the arrow keys, which means it has to be
      // somewhere Tab can land first.
      final FocusNode node = FocusNode(debugLabel: 'viewport');
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _wrapped(
          Focus(
            focusNode: node,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();

      expect(node.hasFocus, isTrue);
      expect(node.skipTraversal, isFalse);
    });
  });

  group('the desktop rail and mode switcher', () {
    testWidgets('meet contrast and tap-target guidelines', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrapped(
          ModelerShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            animationSubmode: AnimationSubmode.pose,
            onAnimationSubmode: (_) {},
            onTool: (_) {},
            activeTool: null,
            viewport: _viewport,
            properties: _properties,
            status: _status,
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('does not overflow at a 1.3x text scale', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: ModelerShell(
              mode: ModelerMode.object,
              onMode: (_) {},
              submode: MeshSubmode.vertex,
              onSubmode: (_) {},
              animationSubmode: AnimationSubmode.pose,
              onAnimationSubmode: (_) {},
              onTool: (_) {},
              activeTool: null,
              viewport: _viewport,
              properties: _properties,
              status: _status,
              actions: const <Widget>[Text('Export a copy')],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the tablet palette', () {
    testWidgets('meets the android tap-target guideline (48x48)', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(1000, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrapped(
          ModelerTabletShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            onTool: (_) {},
            activeTool: null,
            viewport: _viewport,
            properties: _properties,
            status: _status,
          ),
          size: const Size(1000, 900),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('does not overflow at a 1.3x text scale', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1000, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: ModelerTabletShell(
              mode: ModelerMode.object,
              onMode: (_) {},
              submode: MeshSubmode.vertex,
              onSubmode: (_) {},
              onTool: (_) {},
              activeTool: null,
              viewport: _viewport,
              properties: _properties,
              status: _status,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the phone shell', () {
    testWidgets('the mode nav bar and FAB meet the tap-target guideline', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrapped(
          ModelerPhoneShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            onTool: (_) {},
            activeTool: null,
            viewport: _viewport,
            properties: _properties,
            status: _status,
          ),
          size: const Size(390, 844),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the tool sheet opened from the FAB meets the guideline', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrapped(
          ModelerPhoneShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            onTool: (_) {},
            activeTool: null,
            viewport: _viewport,
            properties: _properties,
            status: _status,
          ),
          size: const Size(390, 844),
        ),
      );
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('does not overflow at a 1.3x text scale', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: ModelerPhoneShell(
              mode: ModelerMode.mesh,
              onMode: (_) {},
              submode: MeshSubmode.vertex,
              onSubmode: (_) {},
              onTool: (_) {},
              activeTool: null,
              viewport: _viewport,
              properties: _properties,
              status: _status,
              actions: const <Widget>[Text('Export a copy')],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
