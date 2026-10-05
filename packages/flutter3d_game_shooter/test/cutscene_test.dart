/// A cutscene in the shooter: started by a trigger, holding the player's
/// hands while it plays, directing a monster, and saved with the run.
///
///     flutter test test/cutscene_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_game_shooter/staging.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A room, the player standing in a trigger that starts the cutscene, and
/// a runner the cutscene walks across the room, well away from the player.
Map<String, Object?> _room() => <String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0, -0.5, 0],
      'size': <double>[40, 1, 40],
      'material': 'stone',
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0, 3, 0],
      'intensity': 4,
      'range': 20,
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'player_spawn',
      'at': <double>[0, 0, 0],
    },
    <String, Object?>{
      'type': 'trigger',
      'at': <double>[0, 1, 0],
      'size': <double>[3, 2, 3],
      'target': 'intro',
    },
    <String, Object?>{
      'type': 'cutscene',
      'name': 'intro',
      'at': <double>[0, 0, 0],
      'sequence': <String, Object?>{
        'seconds': 2,
        'subtitles': <Object?>[
          <String, Object?>{'from': 0, 'to': 1.5, 'text': 'Something stirs.'},
        ],
        'signals': <Object?>[
          <String, Object?>{'t': 1, 'name': 'bell'},
        ],
        'actors': <Object?>[
          <String, Object?>{
            't': 0,
            'actor': 'grunt',
            'do': 'goTo',
            'at': <double>[12, 0.9, 12],
          },
        ],
      },
    },
    <String, Object?>{
      'type': 'monster',
      'name': 'grunt',
      'kind': 'runner',
      'at': <double>[12, 0, -12],
    },
  ],
};

final class _Run {
  _Run() {
    level.addTo(world);
    staged = stage(
      level,
      world,
      input: input,
      registry: sampleRegistry(),
      inventory: startingInventory(),
    );
    world.update();
  }

  final Level level = Level.fromJson(_room());
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Staged staged;

  GameSimulation get sim => staged.sim;
  Vector3 get player => staged.player.body.position;
  Actor get grunt => staged.actors.actors.firstWhere((a) => a.name == 'grunt');

  void run(int steps, {bool forward = false}) {
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      if (forward) input.press(GameAction.moveForward);
      sim.step(_dt);
      input.endStep();
      if (forward) input.release(GameAction.moveForward);
    }
  }
}

void main() {
  test('the level with a cutscene in it validates', () {
    final issues = LevelValidator(
      registry: sampleRegistry(),
      rules: sampleRules(),
    ).validate(Level.fromJson(_room()));
    expect(issues.where((i) => i.isError), isEmpty, reason: '$issues');
  });

  test('a cutscene that does not read is a validation error', () {
    final room = _room();
    ((room['entities']! as List)[2] as Map)['sequence'] = <String, Object?>{
      'seconds': 2,
      'actors': <Object?>[
        <String, Object?>{'t': 0, 'actor': 'grunt', 'do': 'dance'},
      ],
    };
    final issues = LevelValidator(
      registry: sampleRegistry(),
      rules: sampleRules(),
    ).validate(Level.fromJson(room));
    expect(
      issues.where((i) => i.isError).map((i) => i.message),
      contains(contains('actors[0].do')),
    );
  });

  test('the trigger starts it, and it holds the player\'s hands', () {
    final it = _Run()..run(2);
    final cutscene = it.sim.cutscene;
    expect(cutscene, isNotNull);
    expect(cutscene!.player.subtitle, 'Something stirs.');
    final from = it.player.clone();
    it.run(40, forward: true);
    // Mutation: reading the player's input while a cutscene plays walks
    // them away from where they stood.
    expect(it.player.distanceTo(from), lessThan(0.05));
  });

  test('it fires its signal and walks the runner to its mark', () {
    final it = _Run()..run(2);
    final signals = <String>[];
    for (var i = 0; i < 120; i++) {
      it.run(1);
      // In the run's own events, where the game listens. Mutation: leaving
      // them in the cutscene's buffer hears nothing here.
      signals.addAll(
        it.sim.events.drain().whereType<SequenceSignal>().map((e) => e.name),
      );
    }
    expect(signals, <String>['bell']);
    final at = it.grunt.position!;
    expect(at.z, greaterThan(-12.0 + 5.0), reason: 'the runner never left');
  });

  test('when it ends the controls come back', () {
    final it = _Run()..run(2 + 120);
    // Mutation: a cutscene that does not stop at its end keeps the hands.
    expect(it.sim.cutscene, isNull);
    final from = it.player.clone();
    it.run(30, forward: true);
    expect(it.player.distanceTo(from), greaterThan(1.0));
  });

  test('it plays once', () {
    final it = _Run()..run(2 + 120);
    // Mutation: a cutscene that starts again whenever it is told to.
    final again = it.staged.mechanisms.activate(
      'intro',
      it.staged.mechanisms.activationBy(it.staged.player.body.collider),
    );
    expect(again, isA<NothingToDo>());
    expect(it.sim.cutscene, isNull);
  });

  test('a run saved mid-cutscene comes back to the same bits', () {
    final original = _Run()..run(40);
    final saved = jsonDecode(jsonEncode(original.sim.save().toJson())) as Map;
    final restored = _Run();
    // The player spawns inside the trigger, so the fresh run has started
    // the cutscene already; put it back to a world where nothing has, which
    // is what a load from the title screen restores into. Mutation: a
    // restore that does not make the cutscene the director again leaves the
    // runner to its own brain.
    restored.staged.actors.director = null;
    restored.sim.restore(Snapshot.fromJson(saved.cast<String, Object?>()));
    expect(restored.sim.cutscene, isNotNull);
    for (var i = 0; i < 120; i++) {
      original.run(1);
      restored.run(1);
      expect(
        restored.grunt.position!.storage,
        original.grunt.position!.storage,
        reason: 'step $i',
      );
    }
    expect(restored.sim.cutscene, isNull);
  });
}
