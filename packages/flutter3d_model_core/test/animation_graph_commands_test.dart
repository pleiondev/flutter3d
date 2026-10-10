/// A project's animation graphs — N1, the modeller's half.
///
///     dart test test/animation_graph_commands_test.dart
///
/// A graph set by name over the project's own clips, refused when it would
/// not run, kept by the project file and its history, exported into a
/// model's root `extras` and read back from there by the game's codec and
/// by an import.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart'
    show AnimationGraphJson, AnimationState, AnimationStateMachine;
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

/// A project with two clips, walk and run, and nothing else.
ModelProject _clipped() => const ModelProject(
  clips: <ProjectClip>[
    ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
    ProjectClip(name: 'run', tracks: <ProjectTrack>[]),
  ],
);

/// A graph that moves by a blend of walk and run, as JSON.
Map<String, Object?> _mover({String run = 'run'}) => <String, Object?>{
  'parameters': <Object?>[
    <String, Object?>{'name': 'speed', 'type': 'float'},
  ],
  'states': <Object?>[
    <String, Object?>{
      'name': 'move',
      'blend': <String, Object?>{
        'parameter': 'speed',
        'points': <Object?>[
          <String, Object?>{'at': 0.0, 'clip': 'walk'},
          <String, Object?>{'at': 1.0, 'clip': run},
        ],
      },
      'markers': <Object?>[
        <String, Object?>{'at': 0.5, 'name': 'step'},
      ],
    },
  ],
};

ProjectOpened _reopened(Uint8List bytes) => switch (readProject(bytes)) {
  final ProjectOpened opened => opened,
  final ProjectRefused refused => fail('refused: ${refused.because}'),
};

void main() {
  test('a graph is set by name over the project\'s clips, and removed', () {
    final history = ModelHistory(_clipped());
    expect(
      history.run(SetAnimationGraph(graphName: 'hero', graph: _mover())),
      isNull,
    );
    expect(history.project.animationGraphs.keys, <String>['hero']);
    final machine = AnimationGraphJson.decode(
      history.project.animationGraphs['hero'],
    );
    expect(machine.states.single.blend!.points.last.clip, 'run');
    expect(history.undoSays, 'set animation graph "hero"');

    expect(history.run(const RemoveAnimationGraph(graphName: 'hero')), isNull);
    expect(history.project.animationGraphs, isEmpty);
    history.undo();
    expect(history.project.animationGraphs.keys, <String>['hero']);
  });

  test('one that would not run is refused, saying why', () {
    final history = ModelHistory(_clipped());
    expect(
      history.run(
        SetAnimationGraph(
          graphName: 'hero',
          graph: _mover(run: 'sprint'),
        ),
      ),
      contains('`sprint`, which is not among'),
    );
    expect(
      history.run(
        const SetAnimationGraph(
          graphName: 'hero',
          graph: <String, Object?>{'states': 'move'},
        ),
      ),
      'parameters is null, not a list',
    );
    expect(
      history.run(const RemoveAnimationGraph(graphName: 'hero')),
      'there is no animation graph "hero"',
    );
    expect(history.project.animationGraphs, isEmpty);
  });

  test('the project file keeps them, and an undo after reopening too', () {
    final history = ModelHistory(_clipped())
      ..run(SetAnimationGraph(graphName: 'hero', graph: _mover()))
      ..run(SetAnimationGraph(graphName: 'monster', graph: _mover()))
      ..run(const RemoveAnimationGraph(graphName: 'hero'));
    final opened = _reopened(writeProject(history.project, history: history));
    expect(opened.warnings, isEmpty);
    expect(opened.project.animationGraphs.keys, <String>['monster']);

    final again = ModelHistory.withSteps(opened.project, opened.history);
    again.undo(); // the removal
    expect(again.project.animationGraphs.keys, <String>['hero', 'monster']);
    again.undo(); // the monster
    expect(again.project.animationGraphs.keys, <String>['hero']);
    again.undo(); // the hero
    expect(again.project.animationGraphs, isEmpty);
  });

  test('a project without one writes no key for it', () {
    final manifest = String.fromCharCodes(writeProject(_clipped()));
    expect(manifest, isNot(contains('animationGraphs')));
  });

  test('an export carries them to the game, and an import brings them '
      'back', () {
    final history = ModelHistory(_clipped())
      ..run(SetAnimationGraph(graphName: 'hero', graph: _mover()));
    final file = F3dDocument.parse(
      F3dWriter(toModelDocument(history.project)).write(),
    );
    final AnimationStateMachine machine = AnimationGraphJson.graphsIn(
      file.asset,
    )['hero']!;
    expect(machine.states.single, isA<AnimationState>());
    expect(machine.states.single.markers.single.name, 'step');

    final imported = fromModelDocument(file);
    expect(imported.animationGraphs, history.project.animationGraphs);
    expect(
      toModelDocument(_clipped()).asset,
      isNull,
      reason: 'a project with no graph exports the file it always did',
    );
  });
}
