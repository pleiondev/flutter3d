/// `edu-01`'s own arithmetic (`lesson_authoring.dart`), and the proof that a
/// five-step lesson is buildable through nothing but the ten commands
/// `editor_command.dart` already has — no new command, no hand-written JSON.
///
///     dart test test/lesson_authoring_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Level _level(String json) =>
    Level.fromJson(jsonDecode(json) as Map<String, Object?>);

void main() {
  group('indexOfNamed', () {
    test('finds an entity by name', () {
      final level = _level('''
{"entities": [
  {"type": "model", "name": "engine-body", "at": [0,0,0]},
  {"type": "edu_step", "name": "step-1", "at": [0,0,0]}
]}
''');
      expect(indexOfNamed(level, 'step-1'), 1);
      expect(indexOfNamed(level, 'engine-body'), 0);
    });

    test('answers null for a name nothing carries', () {
      final level = _level('{"entities": []}');
      expect(indexOfNamed(level, 'nothing'), isNull);
    });
  });

  group('orderedSteps', () {
    test('resolves names in the order the sequence names them', () {
      final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "step-2", "caption": "second", "at": [0,0,0]},
  {"type": "edu_step", "name": "step-1", "caption": "first", "at": [0,0,0]},
  {"type": "edu_sequence", "name": "seq", "steps": ["step-1", "step-2"]}
]}
''');
      final steps = orderedSteps(level, 'seq');
      expect(steps.map((s) => s.name), <String>['step-1', 'step-2']);
      expect(steps.map((s) => s.string('caption')), <String>[
        'first',
        'second',
      ]);
    });

    test('skips a name the sequence lists but no entity carries', () {
      final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "step-1", "at": [0,0,0]},
  {"type": "edu_sequence", "name": "seq", "steps": ["step-1", "step-missing"]}
]}
''');
      expect(orderedSteps(level, 'seq').map((s) => s.name), <String>['step-1']);
    });

    test('an unknown sequence name resolves to no steps', () {
      final level = _level('{"entities": []}');
      expect(orderedSteps(level, 'nope'), isEmpty);
    });
  });

  group('mergedOffsets', () {
    test('adds a new node path, keeping none there before', () {
      // 0.25, not an arbitrary decimal: `Vector3` stores its components as
      // 32-bit floats (see `package:vector_math`), so a value that is not
      // exactly representable there — 0.35, say — comes back as
      // 0.3499999940395355. The editor's own grid is quarters of a metre
      // for the same underlying reason, and this test stays on it.
      final step = EntityDef(type: 'edu_step', name: 'step-1');
      final offsets = mergedOffsets(
        step,
        'engine-body#valve_cover',
        Vector3(0, 0.25, 0),
      );
      expect(offsets, <String, Object?>{
        'engine-body#valve_cover': <double>[0.0, 0.25, 0.0],
      });
    });

    test('overwrites one node path and leaves the others alone', () {
      final step = EntityDef.fromJson(<String, Object?>{
        'type': 'edu_step',
        'name': 'step-1',
        'at': <double>[0, 0, 0],
        'offsets': <String, Object?>{
          'engine-body#valve_cover': <double>[0.0, 0.35, 0.0],
          'engine-body#gasket': <double>[0.0, 0.1, 0.0],
        },
      });
      final offsets = mergedOffsets(
        step,
        'engine-body#valve_cover',
        Vector3(0, 0.5, 0),
      );
      expect(offsets['engine-body#valve_cover'], <double>[0.0, 0.5, 0.0]);
      expect(offsets['engine-body#gasket'], <double>[0.0, 0.1, 0.0]);
    });
  });

  group('movedStep', () {
    test('moves a name earlier in the list', () {
      expect(movedStep(<String>['a', 'b', 'c'], 2, 0), <String>['c', 'a', 'b']);
    });

    test('moves a name later in the list', () {
      expect(movedStep(<String>['a', 'b', 'c'], 0, 2), <String>['b', 'c', 'a']);
    });

    test('an out-of-range source index changes nothing', () {
      final steps = <String>['a', 'b'];
      expect(movedStep(steps, 5, 0), same(steps));
    });

    test('an overshooting target clamps to the end', () {
      expect(movedStep(<String>['a', 'b', 'c'], 0, 99), <String>[
        'b',
        'c',
        'a',
      ]);
    });
  });

  group('freshName', () {
    test('the first name of a kind nothing carries yet', () {
      final level = _level('{"entities": []}');
      expect(freshName(level, 'step'), 'step-1');
    });

    test('skips names already taken', () {
      final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "step-1", "at": [0,0,0]},
  {"type": "edu_step", "name": "step-2", "at": [0,0,0]}
]}
''');
      expect(freshName(level, 'step'), 'step-3');
    });
  });

  group('a teacher assembles a five-step teardown through commands alone', () {
    test('every step comes from Place/SetField, never from hand-written JSON', () {
      // Nothing below is a level document literal — every field the finished
      // level carries arrives through an `EditorCommand.apply`, the exact
      // path a click on a step-panel button or an MCP `place`/`setField`
      // tool call takes. That is the whole of what `edu-01`'s acceptance —
      // "a teacher assembles a five-step teardown without code" — asks for:
      // not that no code runs, but that no JSON is typed by hand.
      final editing = Editing.parse(
        jsonEncode(<String, Object?>{
          'name': 'engine-lesson',
          'entities': <Object?>[
            <String, Object?>{
              'type': 'model',
              'name': 'engine-body',
              'at': <double>[0, 0, 0],
              'asset': 'assets/models/engine.f3d',
            },
          ],
        }),
        path: '/levels/engine-lesson.json',
      );

      // The sequence itself, empty for now — its `steps` list is filled in
      // as each step is placed, the same order a panel would build it.
      expect(
        Place(Piece.entity, 'edu_sequence', Vector3(0, 0, 0)).apply(editing),
        isTrue,
      );
      expect(const SetField('name', 'engine-teardown').apply(editing), isTrue);
      expect(const SetField('steps', <String>[]).apply(editing), isTrue);
      expect(
        const SetField('title', 'Разборка двигателя').apply(editing),
        isTrue,
      );
      final sequenceIndex = indexOfNamed(editing.level, 'engine-teardown')!;

      final captions = <String>[
        'Двигатель в сборе',
        'Снимаем крышку клапанов',
        'Момент затяжки',
        'Снимаем прокладку',
        'Готово',
      ];
      for (final caption in captions) {
        final name = freshName(editing.level, 'step');
        expect(
          Place(
            Piece.entity,
            'edu_step',
            Vector3(1.0, 1.6, -0.4),
          ).apply(editing),
          isTrue,
        );
        expect(SetField('name', name).apply(editing), isTrue);
        expect(SetField('caption', caption).apply(editing), isTrue);

        editing.select(Piece.entity, sequenceIndex);
        final steps = List<String>.of(
          (editing.entity!.properties['steps'] as List?)?.cast<String>() ??
              const <String>[],
        )..add(name);
        expect(SetField('steps', steps).apply(editing), isTrue);
      }

      // The teardown itself: the second step's valve cover lifts a quarter
      // metre, via a merge computed the way a viewport would compute it
      // from a drag, not typed as a literal offsets map.
      final stepTwoName =
          (editing.level.named('engine-teardown')!.properties['steps']!
                  as List)[1]
              as String;
      editing.select(Piece.entity, indexOfNamed(editing.level, stepTwoName)!);
      final withOffset = mergedOffsets(
        editing.entity!,
        'engine-body#valve_cover',
        Vector3(0.0, 0.25, 0.0),
      );
      expect(SetField('offsets', withOffset).apply(editing), isTrue);

      // An annotation, attached to the same node the offset just moved.
      expect(
        Place(
          Piece.entity,
          'edu_annotation',
          Vector3(1.0, 1.6, -0.4),
        ).apply(editing),
        isTrue,
      );
      final annotationName = freshName(editing.level, 'note');
      expect(SetField('name', annotationName).apply(editing), isTrue);
      expect(SetField('widget', 'torque-spec-card').apply(editing), isTrue);
      expect(
        SetField('attachTo', 'engine-body#valve_cover').apply(editing),
        isTrue,
      );

      editing.select(Piece.entity, indexOfNamed(editing.level, stepTwoName)!);
      expect(
        SetField('annotations', <String>[annotationName]).apply(editing),
        isTrue,
      );

      // A clip plane, dropped and turned — the turn is the same generic
      // rotate any entity already gets, arrow keys and all; nothing new
      // was built for it. `packages/flutter3d_editor_core/lib/src/lesson_authoring.dart`'s
      // own doc comment says why: an `edu_clip_plane` is an ordinary
      // `EntityDef` with a `yaw`, exactly like everything else in this format.
      expect(
        Place(
          Piece.entity,
          'edu_clip_plane',
          Vector3(0.0, 1.0, 0.0),
        ).apply(editing),
        isTrue,
      );
      expect(SetField('name', 'cutaway-1').apply(editing), isTrue);
      expect(const Turn(1.5707963267948966).apply(editing), isTrue);

      // The whole thing, read back the way any host reads a level: not the
      // in-memory `Editing`, but a fresh `Level.fromJson` over its own
      // `toJson()` — the same round trip `doc/edu-00-interactive-format.md`
      // §11 proved for a hand-written example, now proved for one that
      // nothing but commands built.
      final finished = Level.fromJson(editing.level.toJson());
      final sequence = finished.named('engine-teardown')!;
      final stepNames = (sequence.properties['steps']! as List).cast<String>();
      expect(stepNames, hasLength(5));

      final steps = orderedSteps(finished, 'engine-teardown');
      expect(steps, hasLength(5));
      expect(steps.map((s) => s.string('caption')), captions);

      final registry = vocabularyOf(finished);
      for (final type in <String>[
        'edu_sequence',
        'edu_step',
        'edu_annotation',
        'edu_clip_plane',
      ]) {
        expect(registry.knows(type), isTrue, reason: type);
      }

      final movedStepEntity = finished.named(stepNames[1])!;
      expect(movedStepEntity.properties['offsets'], <String, Object?>{
        'engine-body#valve_cover': <double>[0.0, 0.25, 0.0],
      });
      final annotations = (movedStepEntity.properties['annotations']! as List)
          .cast<String>();
      expect(annotations, <String>[annotationName]);
      final note = finished.named(annotationName)!;
      expect(note.string('widget'), 'torque-spec-card');
      expect(note.string('attachTo'), 'engine-body#valve_cover');

      final clip = finished.named('cutaway-1')!;
      // `Editing.turn` rounds yaw to four decimal places on the way in — the
      // same grid discipline `_round` documents for a status-bar sentence,
      // applied to the stored value itself this time.
      expect(clip.yaw, closeTo(1.5707963267948966, 1e-4));
    });
  });
}
