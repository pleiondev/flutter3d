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

void main() {
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
