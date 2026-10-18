/// The strip across the top, with the toolbar's buttons in it.
///
///     flutter test test/editor_bar_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editor_bar.dart';
import 'package:flutter3d_editor/src/editor_state.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

Future<void> _bar(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: editorTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: EditorBar(
            state: EditorReady(
              editing: openTestDocument(),
              assetRoot: null,
              looks: noLooks,
              said: 'opened 2 brushes',
            ),
            onFewerLights: () {},
            onBehaviours: () {},
            onCutscenes: () {},
            actions: <Widget>[
              for (var i = 0; i < 7; i++)
                IconButton(
                  key: ValueKey<int>(i),
                  icon: const Icon(Icons.circle),
                  onPressed: () {},
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('in a narrow window the buttons take a row of their own', (
    WidgetTester tester,
  ) async {
    // On one row in an 800-point window the path was cut to "/Users/d…".
    //
    // Mutation: always build the one-row layout. The path is squeezed to
    // a sliver beside the buttons and the overflow is reported.
    await _bar(tester, 800);

    final path = tester.getSize(find.text('/levels/test.json')).width;
    final row = tester.getTopLeft(find.text('/levels/test.json')).dy;
    final button = tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dy;
    expect(path, greaterThan(150));
    expect(button, greaterThan(row));
    expect(tester.takeException(), isNull);
  });

  testWidgets('and in a wide one they sit beside the path', (
    WidgetTester tester,
  ) async {
    await _bar(tester, 1600);

    final row = tester.getCenter(find.text('/levels/test.json')).dy;
    final button = tester.getCenter(find.byKey(const ValueKey<int>(0))).dy;
    expect((button - row).abs(), lessThan(16));
  });
}
