/// The editor's way to the light optimizer: a button on the bar, and a
/// dialog that shows the two pictures and the numbers before anything
/// changes.
library;

import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor/src/editor_bar.dart';
import 'package:flutter3d_editor/src/editor_cubit.dart';
import 'package:flutter3d_editor/src/light_plan_dialog.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'editor_cubit_helpers.dart';

/// A small closed room with three lamps in one place.
Editing _litRoom() {
  Map<String, Object?> box(List<double> at, List<double> size) =>
      <String, Object?>{'at': at, 'size': size, 'material': 'stone'};
  final lamp = <String, Object?>{
    'type': 'point',
    'at': <double>[0.0, 2.2, 0.0],
    'intensity': 2.0,
    'range': 8.0,
  };
  return Editing.parse(
    jsonEncode(<String, Object?>{
      'version': 1,
      'materials': <String, Object?>{
        'stone': <String, Object?>{
          'baseColor': <double>[0.6, 0.6, 0.6, 1.0],
        },
      },
      'brushes': <Object?>[
        box(<double>[0.0, -0.25, 0.0], <double>[5.0, 0.5, 5.0]),
        box(<double>[0.0, 2.75, 0.0], <double>[5.0, 0.5, 5.0]),
        box(<double>[-2.25, 1.25, 0.0], <double>[0.5, 2.5, 4.0]),
        box(<double>[2.25, 1.25, 0.0], <double>[0.5, 2.5, 4.0]),
        box(<double>[0.0, 1.25, -2.25], <double>[4.0, 2.5, 0.5]),
        box(<double>[0.0, 1.25, 2.25], <double>[4.0, 2.5, 0.5]),
      ],
      'lights': <Object?>[lamp, lamp, lamp],
    }),
    path: '/levels/room.json',
  );
}

EditorReady _ready(Editing editing) =>
    EditorReady(editing: editing, assetRoot: null, looks: noLooks, said: '');

void main() {
  testWidgets('the bar offers fewer lights only when there are lights', (
    WidgetTester tester,
  ) async {
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorBar(
            state: _ready(_litRoom()),
            onFewerLights: () => asked++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fewer lights'));
    expect(asked, 1);

    // Mutation: drop the `lights.isEmpty` test from the button. It is
    // enabled on a level with nothing to optimise and the tap lands.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorBar(
            state: _ready(openTestDocument()),
            onFewerLights: () => asked++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fewer lights'));
    expect(asked, 1);
  });

  testWidgets('the dialog shows the plan and applies it only when asked', (
    WidgetTester tester,
  ) async {
    final editing = _litRoom();
    final plan = await tester.runAsync(
      () async => const LightOptimizer(width: 40, height: 25).optimize(
        editing.level,
        views: <LightView>[
          (from: Vector3(1.5, 1.6, 1.5), at: Vector3(-1.0, 0.5, -1.0)),
        ],
      ),
    );
    late Future<bool> answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => answer = showLightPlan(context, plan!),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 → 1 lights'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });
}
