/// A monster that rests by a behaviour tree the level carries.
///
///     flutter test test/tree_monster_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_game_shooter/staging.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

/// A room with a wall across it; the player behind the wall, the guard on
/// the far side walking a beat of two posts from its board.
Map<String, Object?> _room({bool wall = true}) => <String, Object?>{
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
    if (wall)
      <String, Object?>{
        'at': <double>[0, 1.5, 0],
        'size': <double>[40, 3, 1],
        'material': 'stone',
      },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0, 3, -6],
      'intensity': 4,
      'range': 20,
    },
  ],
  'behaviours': <String, Object?>{
    'beat': <String, Object?>{
      'kind': 'sequence',
      'children': <Object?>[
        <String, Object?>{'kind': 'goTo', 'key': 'west'},
        <String, Object?>{'kind': 'wait', 'seconds': 0.5},
        <String, Object?>{'kind': 'goTo', 'key': 'east'},
        <String, Object?>{'kind': 'wait', 'seconds': 0.5},
      ],
    },
  },
  'entities': <Object?>[
    <String, Object?>{
      'type': 'player_spawn',
      'at': <double>[0, 0, 10],
    },
    <String, Object?>{
      'type': 'exit',
      'at': <double>[0, 0, 15],
    },
    <String, Object?>{
      'type': 'monster',
      'name': 'guard',
      'kind': 'runner',
      'at': <double>[0, 0, -8],
      'behaviour': 'beat',
      'board': <String, Object?>{
        'west': <double>[-8, 0.9, -8],
        'east': <double>[8, 0.9, -8],
      },
    },
  ],
};

final class _Run {
  _Run({bool wall = true}) : level = Level.fromJson(_room(wall: wall)) {
    level.addTo(world);
    staged = stage(
      level,
      world,
      input: InputState(),
      registry: sampleRegistry(),
      inventory: startingInventory(),
    );
    world.update();
  }

  final Level level;
  final CollisionWorld world = CollisionWorld();
  late final Staged staged;

  Actor get guard => staged.actors.actors.firstWhere((a) => a.name == 'guard');

  void run(int steps) {
    for (var i = 0; i < steps; i++) {
      staged.sim.step(_dt);
    }
  }
}

void main() {
  test('the level with a tree in it validates', () {
    final issues = LevelValidator(
      registry: sampleRegistry(),
      rules: sampleRules(),
    ).validate(Level.fromJson(_room()));
    expect(issues.where((i) => i.isError), isEmpty, reason: '$issues');
  });

  test('a monster naming a tree runs it, walking the posts on its board', () {
    final it = _Run();
    // Mutation: spawning the monster as it always was, a ChaseBrain that
    // stands.
    expect(it.guard.brain, isA<TreeBrain>());
    var west = false;
    var east = false;
    for (var i = 0; i < 900; i++) {
      it.run(1);
      final at = it.guard.position!;
      if (at.x < -6) west = true;
      if (at.x > 6 && west) east = true;
    }
    expect(west && east, isTrue, reason: 'the beat was not walked');
  });

  test('and it fights like any other once it sees the player', () {
    // No wall: the player in plain view. The tree has it only while it
    // rests; seeing wakes the chase.
    final it = _Run(wall: false)..run(10);
    final brain = it.guard.brain! as TreeBrain;
    expect(brain.state, isNot(patrolling));
    expect(brain.hasNoticed, isTrue);
  });

  test('a run restored mid-beat walks on to the same bits', () {
    final original = _Run()..run(200);
    final saved =
        jsonDecode(jsonEncode(original.staged.sim.save().toJson())) as Map;
    final restored = _Run()
      ..staged.sim.restore(Snapshot.fromJson(saved.cast<String, Object?>()));
    for (var i = 0; i < 200; i++) {
      original.run(1);
      restored.run(1);
      expect(
        restored.guard.position!.storage,
        original.guard.position!.storage,
        reason: 'step $i',
      );
    }
  });
}
