/// Editing an experiment document: each edit goes back through the reader,
/// the reader's refusals come out as the edit's, and undo keeps documents.
///
///     dart test test/experiment_editing_test.dart
///
/// Against the pendulum fixture `flutter3d_education` reads first. Each test
/// was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_education/experiment.dart';
import 'package:test/test.dart';

ExperimentEditing _pendulum() => ExperimentEditing.parse(
  File(
    '../flutter3d_education/test/fixtures/v1/pendulum.f3d.experiment',
  ).readAsStringSync(),
  path: 'pendulum.f3d.experiment',
);

const Map<String, Object?> _metres = <String, Object?>{
  'value': 1.5,
  'unit': 'm',
};

void main() {
  test('a parameter is changed and the step keeps naming it', () {
    final editing = _pendulum();
    expect(editing.run(const SetParameter('length', _metres)), isNull);
    // Mutation: write the parameter beside the old one rather than in its
    // place, which the reader refuses as two of one id.
    expect(editing.document.parameter('length')!.value.value, 1.5);
    expect(editing.document.parameters, hasLength(3));
    expect(editing.isDirty, isTrue);
  });

  test(
    'what the reader refuses is refused by its words, and nothing changes',
    () {
      final editing = _pendulum();
      final before = editing.write();
      // `release` and `shorten` set the length.
      final refused = editing.run(const RemoveParameter('length'));
      // Mutation: apply the edit without reading the result back.
      expect(refused, contains('"length"'));
      expect(refused, contains('not a parameter'));
      expect(editing.write(), before);
      expect(editing.canUndo, isNull);

      expect(
        editing.run(const SetExpectation('release', 'speed', _metres, _metres)),
        contains('not a probe'),
      );
      expect(
        editing.run(
          const SetExpectation(
            'release',
            'period',
            <String, Object?>{'value': 2.0, 'unit': 's'},
            <String, Object?>{'value': 1.0, 'unit': 'm'},
          ),
        ),
        contains('does not measure'),
      );
      expect(editing.run(const RemoveStep('nowhere')), contains('no step'));
    },
  );

  test(
    'a step is added, moved and taken out; undo and redo keep documents',
    () {
      final editing = _pendulum();
      expect(
        editing.run(
          const SetStep(<String, Object?>{
            'name': 'lengthen',
            'set': <String, Object?>{'length': '2 m'},
            'run': '30 s',
          }),
        ),
        isNull,
      );
      expect(editing.document.steps.map((s) => s.name), <String>[
        'release',
        'shorten',
        'lengthen',
      ]);
      expect(editing.run(const MoveStep('lengthen', 0)), isNull);
      expect(editing.document.steps.first.name, 'lengthen');
      expect(
        editing.run(
          const SetExpectation(
            'lengthen',
            'period',
            <String, Object?>{'value': 2.84, 'unit': 's'},
            <String, Object?>{'value': 0.01, 'unit': 's'},
          ),
        ),
        isNull,
      );
      expect(editing.document.step('lengthen')!.expect.single.probe, 'period');

      // Mutation: keep an inverse instead of the document before.
      expect(editing.undo(), contains('expect period'));
      expect(editing.undo(), 'move step lengthen to 0');
      expect(editing.document.steps.last.name, 'lengthen');
      expect(editing.redo(), 'move step lengthen to 0');
      expect(editing.document.steps.first.name, 'lengthen');
      expect(editing.run(const RemoveStep('lengthen')), isNull);
      expect(editing.canRedo, isNull);
    },
  );

  test('substances, probes and the document\'s own words', () {
    final editing = _pendulum()
      ..run(const SetSubstance('f3d.water', role: 'bath'))
      ..run(const RemoveSubstance('f3d.air'))
      ..run(const SetExperimentField('title', 'A pendulum in water'))
      ..run(
        const SetProbe(<String, Object?>{
          'id': 'depth',
          'quantity': 'f3d.depth',
          'unit': 'm',
          'region': <String, Object?>{'kind': 'body'},
          'on': 'bob',
        }),
      );
    final document = editing.document;
    expect(document.substances.map((s) => s.id), <String>[
      'f3d.steel',
      'f3d.water',
    ]);
    expect(document.title, 'A pendulum in water');
    expect(document.probe('depth')!.on, 'bob');
    // The probe expected by a step cannot go.
    expect(editing.run(const RemoveProbe('period')), contains('not a probe'));
    expect(editing.run(const RemoveProbe('depth')), isNull);
    expect(
      editing.run(const SetExperimentField('colour', 'red')),
      contains('no field'),
    );
  });

  test('an edit is read back from what it writes', () {
    const edits = <ExperimentEdit>[
      SetExperimentField('title', 'x'),
      SetSubstance('f3d.water', role: 'bath'),
      RemoveSubstance('f3d.air'),
      SetParameter('length', _metres, min: '0.1 m'),
      RemoveParameter('damping'),
      SetProbe(<String, Object?>{'id': 'p'}),
      RemoveProbe('p'),
      SetStep(<String, Object?>{'name': 's'}, at: 1),
      RemoveStep('s'),
      MoveStep('s', 2),
      SetExpectation('s', 'p', '1 m', '0.1 m'),
      RemoveExpectation('s', 'p'),
    ];
    // Mutation: drop one name from `experimentEditNames`.
    expect(edits.map((e) => e.name), experimentEditNames);
    for (final edit in edits) {
      final back = ExperimentEdit.fromJson(
        jsonDecode(jsonEncode(edit.toJson())) as Map<String, Object?>,
      );
      expect(back?.toJson(), edit.toJson(), reason: edit.name);
    }
    expect(ExperimentEdit.fromJson(<String, Object?>{'edit': 'fly'}), isNull);
    expect(
      ExperimentEdit.fromJson(<String, Object?>{'edit': 'moveStep'}),
      isNull,
    );
  });

  test('the file written reads back as the document edited', () {
    final editing = _pendulum()..run(const SetParameter('length', _metres));
    final again = ExperimentDocument.parse(editing.write());
    expect(again.parameter('length')!.value.value, 1.5);
    editing.saved();
    expect(editing.isDirty, isFalse);
    editing.undo();
    expect(editing.isDirty, isTrue);
  });
}
