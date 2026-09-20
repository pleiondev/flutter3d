/// `edu-01`'s panel: adding, selecting, reordering and deleting steps, and
/// dropping an annotation or a clip plane — all through the same ten
/// commands `editor_command.dart` already had.
///
///     flutter test test/step_panel_test.dart
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/step_panel.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

Editing _open(String json) => Editing.parse(json, path: '/levels/test.json');

Editing _emptyLevel() => _open(
  jsonEncode(<String, Object?>{'name': 'lesson', 'entities': <Object?>[]}),
);

Editing _twoStepLevel() => _open(
  jsonEncode(<String, Object?>{
    'name': 'lesson',
    'entities': <Object?>[
      <String, Object?>{
        'type': 'edu_step',
        'name': 'step-1',
        'at': <double>[0, 0, 0],
        'caption': 'First',
      },
      <String, Object?>{
        'type': 'edu_step',
        'name': 'step-2',
        'at': <double>[0, 0, 0],
        'caption': 'Second',
      },
      <String, Object?>{
        'type': 'edu_sequence',
        'name': 'seq',
        'steps': <String>['step-1', 'step-2'],
      },
    ],
  }),
);

Widget _panel(Editing editing, {void Function(String)? onChanged}) =>
    MaterialApp(
      home: Scaffold(
        body: StepPanel(editing: editing, onChanged: onChanged ?? (_) {}),
      ),
    );

void main() {
  testWidgets('with no lesson yet, the panel says so', (tester) async {
    await tester.pumpWidget(_panel(_emptyLevel()));
    expect(find.text('No lesson yet'), findsOneWidget);
    expect(find.text('No steps yet.'), findsOneWidget);
  });

  testWidgets('a lesson with two steps shows both captions in order', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(_twoStepLevel()));
    final first = tester.getTopLeft(find.text('First'));
    final second = tester.getTopLeft(find.text('Second'));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('tapping + on an empty level starts a lesson and one step', (
    tester,
  ) async {
    final editing = _emptyLevel();
    String? said;
    await tester.pumpWidget(_panel(editing, onChanged: (s) => said = s));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(said, isNotNull);
    final sequence = editing.level.entities.singleWhere(
      (e) => e.type == 'edu_sequence',
    );
    final steps = (sequence.properties['steps']! as List).cast<String>();
    expect(steps, hasLength(1));
    final step = editing.level.named(steps.single)!;
    expect(step.type, 'edu_step');
    expect(step.string('caption'), 'New step');
  });

  testWidgets('tapping a step selects it', (tester) async {
    final editing = _twoStepLevel();
    await tester.pumpWidget(_panel(editing));

    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(editing.entity?.name, 'step-2');
  });

  testWidgets('moving the first step down swaps the lesson order', (
    tester,
  ) async {
    final editing = _twoStepLevel();
    await tester.pumpWidget(_panel(editing));

    await tester.tap(find.byIcon(Icons.arrow_downward).first);
    await tester.pump();

    final sequence = editing.level.named('seq')!;
    expect((sequence.properties['steps']! as List).cast<String>(), <String>[
      'step-2',
      'step-1',
    ]);
  });

  testWidgets('the first step cannot move up and the last cannot move down', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(_twoStepLevel()));
    final upButtons = tester.widgetList<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward),
    );
    final downButtons = tester.widgetList<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_downward),
    );
    expect(upButtons.first.onPressed, isNull);
    expect(downButtons.last.onPressed, isNull);
  });

  testWidgets('deleting a step removes it from the level and the lesson', (
    tester,
  ) async {
    final editing = _twoStepLevel();
    await tester.pumpWidget(_panel(editing));

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();

    expect(editing.level.named('step-1'), isNull);
    final sequence = editing.level.named('seq')!;
    expect((sequence.properties['steps']! as List).cast<String>(), <String>[
      'step-2',
    ]);
  });

  testWidgets('adding an annotation to a step attaches it by name', (
    tester,
  ) async {
    final editing = _twoStepLevel();
    await tester.pumpWidget(_panel(editing));

    await tester.tap(find.byIcon(Icons.sticky_note_2_outlined).first);
    await tester.pump();

    final step = editing.level.named('step-1')!;
    final annotations = (step.properties['annotations']! as List)
        .cast<String>();
    expect(annotations, hasLength(1));
    final annotation = editing.level.named(annotations.single)!;
    expect(annotation.type, 'edu_annotation');
  });

  testWidgets('adding a clip plane creates one and selects it', (tester) async {
    final editing = _twoStepLevel();
    await tester.pumpWidget(_panel(editing));

    await tester.tap(find.text('Add a clip plane'));
    await tester.pump();

    expect(editing.entity?.type, 'edu_clip_plane');
    expect(
      editing.level.entities.where((e) => e.type == 'edu_clip_plane'),
      hasLength(1),
    );
  });

  testWidgets(
    'a new clip plane gets a real normal, not an absent field nothing '
    'ever offers to add — `Editing.offerable` has nothing for an entity',
    (tester) async {
      final editing = _twoStepLevel();
      await tester.pumpWidget(_panel(editing));

      await tester.tap(find.text('Add a clip plane'));
      await tester.pump();

      expect(editing.entity!.properties['normal'], <double>[0.0, 0.0, 1.0]);
    },
  );

  testWidgets(
    'tapping a step\'s teardown button turns offset-editing on for it',
    (tester) async {
      final editing = _twoStepLevel();
      String? said;
      await tester.pumpWidget(_panel(editing, onChanged: (s) => said = s));

      await tester.tap(find.byIcon(Icons.open_with).first);
      await tester.pump();

      expect(editing.activeStepForOffsets, 'step-1');
      expect(said, contains('step-1'));
    },
  );

  testWidgets('tapping it again turns offset-editing back off', (tester) async {
    final editing = _twoStepLevel()..activeStepForOffsets = 'step-1';
    await tester.pumpWidget(_panel(editing));

    await tester.tap(find.byIcon(Icons.open_with).first);
    await tester.pump();

    expect(editing.activeStepForOffsets, isNull);
  });

  testWidgets(
    'tapping a different step\'s teardown button moves it there instead',
    (tester) async {
      // Only one row at a time — `StepPanel._toggleActiveOffsets`'s own
      // doc comment names this as the ordinary meaning a checkbox or a radio
      // button already has, not two switches somebody has to remember to
      // turn off by hand.
      final editing = _twoStepLevel()..activeStepForOffsets = 'step-1';
      await tester.pumpWidget(_panel(editing));

      await tester.tap(find.byIcon(Icons.open_with).last);
      await tester.pump();

      expect(editing.activeStepForOffsets, 'step-2');
    },
  );
}
