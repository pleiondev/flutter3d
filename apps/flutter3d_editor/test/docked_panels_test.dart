/// The editor's own panels, docked as the editor docks them: every one of
/// them laid out in its side at an ordinary window size and a small one,
/// with nothing overflowing — the shell's half that needs no device.
///
///     flutter test test/docked_panels_test.dart
///
/// The screen itself opens a GPU device and cannot be built here; the panels
/// it docks come from `editorPanels`, which this builds exactly as the
/// screen does, around a placeholder where the picture goes.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editor_cubit.dart';
import 'package:flutter3d_editor/src/editor_panels.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// A level with something of each kind in it, the first torch selected.
Editing _level() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'test',
    'materials': <String, Object?>{
      'stone': <String, Object?>{
        'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
      },
    },
    'brushes': <Object?>[
      for (var i = 0; i < 12; i++)
        <String, Object?>{
          'at': <double>[i * 4.0, 0.0, 0.0],
          'size': <double>[2.0, 2.0, 2.0],
          'material': 'stone',
        },
    ],
    'lights': <Object?>[
      <String, Object?>{
        'type': 'point',
        'at': <double>[0.0, 3.0, 0.0],
      },
    ],
    'entities': <Object?>[
      <String, Object?>{'type': 'spawn'},
      for (var i = 0; i < 6; i++)
        <String, Object?>{
          'type': 'torch',
          'at': <double>[i * 2.0, 2.0, 0.0],
          'flicker': 0.3,
        },
    ],
  }),
  path: '/levels/test.json',
)..select(Piece.entity, 1);

final class _Shell extends StatefulWidget {
  const _Shell(this.state);

  final EditorReady state;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  DockArrangement arrangement = const DockArrangement();
  final EditorLog log = EditorLog()..add('opened 12 brushes');

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: editorTheme(),
    home: Scaffold(
      body: DockLayout(
        arrangement: arrangement,
        onChanged: (DockArrangement next) => setState(() => arrangement = next),
        center: const ColoredBox(color: Color(0xFF000000)),
        panels: editorPanels(
          state: widget.state,
          log: log,
          game: null,
          frame: null,
          onSelect: (Picked _, {required bool add}) {},
          onFlyTo: (Picked _) {},
          onChanged: (String _) {},
          onLive: (String _, Map<String, Object?> _) {},
        ),
      ),
    ),
  );
}

Future<void> _everyTab(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final state = EditorReady(
    editing: _level(),
    assetRoot: null,
    looks: noLooks,
    said: '',
  );
  await tester.pumpWidget(_Shell(state));

  for (final id in <String>[
    'outliner',
    'place',
    'inspector',
    'materials',
    'steps',
    'console',
    'graph',
  ]) {
    // A side narrower than its tabs scrolls them, as a person would.
    final tab = find.byKey(ValueKey<String>('dock.tab.$id'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pump();
    expect(
      find.byKey(ValueKey<String>('dock.panel.$id')),
      findsOneWidget,
      reason: '$id is not showing',
    );
    expect(tester.takeException(), isNull, reason: '$id did not lay out');
  }
}

void main() {
  testWidgets('every panel lays out docked in an ordinary window', (
    WidgetTester tester,
  ) async {
    await _everyTab(tester, const Size(1280, 800));
  });

  testWidgets('and in a small one', (WidgetTester tester) async {
    // The bottom strip is what is left between two sides, and its header
    // has to fit there.
    //
    // Mutation: give the console's filter an `Expanded` and its choices no
    // scroll view, as the header first had. The header overflows here.
    await _everyTab(tester, const Size(900, 560));
  });
}
