/// A level's behaviour trees, kept in its document and checked by the game.
///
///     dart test test/behaviour_rule_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A leaf only a game that registers it knows.
final class _Attack extends BehaviorLeaf {
  const _Attack();

  @override
  BehaviorStatus tick(BehaviorContext context) => BehaviorStatus.success;
}

const Map<String, Object?> _fight = <String, Object?>{
  'kind': 'sequence',
  'children': <Object?>[
    <String, Object?>{'kind': 'goToFocus', 'within': 1.5},
    <String, Object?>{'kind': 'attack'},
  ],
};

List<String> _issues(Level level, BehaviorKinds kinds) => <String>[
  for (final issue in LevelValidator(
    registry: EntityRegistry(const <EntityKind>[]),
    rules: <LevelRule>[BehaviorsRead(kinds)],
  ).validate(level))
    if (issue.message.contains('behaviour')) issue.message,
];

void main() {
  test('a level keeps its trees through its document', () {
    final level = Level.fromJson(<String, Object?>{
      'behaviours': <String, Object?>{'fight': _fight},
    });
    expect(level.behaviors['fight'], _fight);
    expect(Level.fromJson(level.toJson()).behaviors['fight'], _fight);
    // Mutation: writing the key when there are none puts an empty
    // `behaviors` into every level saved.
    expect(Level().toJson().containsKey('behaviours'), isFalse);
  });

  test('a tree with the game\'s own leaf reads in that game only', () {
    final level = Level(
      behaviors: <String, Map<String, Object?>>{'fight': _fight},
    );
    final game = BehaviorKinds()..leaf('attack', (_) => const _Attack());
    expect(_issues(level, game), isEmpty);
    // Mutation: reading the trees against the standard kinds whatever the
    // game said.
    expect(_issues(level, BehaviorKinds()), <Matcher>[
      allOf(contains('behaviour "fight"'), contains('attack')),
    ]);
  });

  test('an entity naming a tree the level has not got is an error', () {
    final level = Level(
      behaviors: <String, Map<String, Object?>>{'fight': _fight},
      entities: <EntityDef>[
        EntityDef(
          type: 'monster',
          properties: <String, Object?>{'behaviour': 'guard'},
        ),
        EntityDef(
          type: 'monster',
          properties: <String, Object?>{'behaviour': 'fight'},
        ),
      ],
    );
    final game = BehaviorKinds()..leaf('attack', (_) => const _Attack());
    expect(_issues(level, game), <Matcher>[contains('runs behaviour "guard"')]);
  });
}
