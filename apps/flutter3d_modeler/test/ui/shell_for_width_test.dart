/// `ShellForWidth`: which of `ui-05`'s three shells a width draws as, and
/// `S2`'s own row — `bottom`/`bottomHeight` reach the desktop shell alone.
///
///     flutter test test/ui/shell_for_width_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
import 'package:flutter3d_modeler/src/ui/screen_parts.dart';
import 'package:flutter3d_modeler/src/ui/shell_for_width.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

const _parts = ScreenParts(
  actions: <Widget>[Text('actions')],
  status: Text('status'),
  properties: Text('properties'),
  viewport: ColoredBox(color: Color(0xFF000000)),
);

Future<void> _pump(
  WidgetTester tester, {
  Widget? bottom,
  double? bottomHeight,
  ModelerMode mode = ModelerMode.object,
  Keymap? keymap,
}) {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: ShellForWidth(
          parts: _parts,
          mode: mode,
          onMode: (_) {},
          submode: MeshSubmode.vertex,
          onSubmode: (_) {},
          animationSubmode: AnimationSubmode.pose,
          onAnimationSubmode: (_) {},
          activeTool: null,
          onTool: (_) {},
          documentName: 'untitled',
          isDirty: false,
          bottom: bottom,
          bottomHeight: bottomHeight,
          keymap: keymap,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a null bottom draws no bottom slot', (tester) async {
    await _pump(tester);

    expect(find.text('bottom'), findsNothing);
  });

  testWidgets('a given bottom reaches the desktop shell, at its own height', (
    tester,
  ) async {
    await _pump(
      tester,
      bottom: const ColoredBox(
        color: Color(0xFF123456),
        child: Center(child: Text('bottom')),
      ),
      bottomHeight: 270,
    );

    expect(find.text('bottom'), findsOneWidget);
    final sizedBox = find.ancestor(
      of: find.text('bottom'),
      matching: find.byType(SizedBox),
    );
    expect(tester.widget<SizedBox>(sizedBox.first).height, 270);
  });

  /// Every tooltip the shell draws, as text — the rail's own are the only
  /// ones in this harness, since `_parts` hands it plain `Text` everywhere
  /// else.
  Set<String> tooltips(WidgetTester tester) => tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .map((Tooltip it) => it.message ?? '')
      .toSet();

  group('ux-10: the rail names the key the live preset binds', () {
    testWidgets('with no keymap, the tool table\'s own letter', (tester) async {
      await _pump(tester, mode: ModelerMode.mesh);

      expect(tooltips(tester), contains('Extrude  ·  E'));
    });

    testWidgets('with the tool-keys preset, the letter that preset moved it '
        'to', (tester) async {
      // That preset spends `E` on rotate, so extrude moves up a row to
      // `Shift+E` — and a tooltip that still said `E` would be teaching the
      // wrong key, which is the whole reason this is threaded.
      await _pump(
        tester,
        mode: ModelerMode.mesh,
        keymap: keymapFor(KeymapPreset.toolKeys, apple: false),
      );

      expect(tooltips(tester), contains('Extrude  ·  Shift+E'));
      expect(tooltips(tester), isNot(contains('Extrude  ·  E')));
    });
  });
}
