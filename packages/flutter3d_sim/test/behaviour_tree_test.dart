/// Behaviour trees as data: what a document is refused for, what each node
/// does, and that a decision half made comes back from a snapshot.
library;

import 'dart:convert';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Adds one to [key] every tick and succeeds — a leaf a game would register,
/// here to count how often a node was really ticked.
final class _Count extends BehaviorLeaf {
  const _Count(this.key);
  final String key;

  @override
  BehaviorStatus tick(BehaviorContext context) {
    context.board.set(key, (context.board.number(key) ?? 0.0) + 1.0);
    return BehaviorStatus.success;
  }
}

/// Runs for ever.
final class _Hold extends BehaviorLeaf {
  const _Hold();

  @override
  BehaviorStatus tick(BehaviorContext context) => BehaviorStatus.running;
}

BehaviorKinds _kinds() => BehaviorKinds()
  ..leaf('count', (p) => _Count(p.text('key')))
  ..leaf('hold', (p) => const _Hold());

BehaviorTree _tree(Map<String, Object?> json) {
  final read = BehaviorTree.read(json, _kinds());
  expect(read.problems, isEmpty);
  return read.tree!;
}

/// One actor with no body, thinking every step: the focus is at the origin
/// and so is it, which keeps it inside the close range.
final class _Rig {
  _Rig(BehaviorTree tree, {Map<String, Object?>? board})
    : system = ActorSystem(world: CollisionWorld(), random: GameRandom(1)) {
    actor = system.spawn(brain: BehaviorBrain(tree));
    if (board != null) {
      system.entities.set(actor.entity, Blackboard(values: board));
    }
  }

  final ActorSystem system;
  late final Actor actor;

  Blackboard get board => system.entities.get<Blackboard>(actor.entity)!;

  List<String> get path => <String>[
    for (final step in BehaviorBrain.pathOf(actor))
      '${step.label}:${step.status.name}',
  ];

  void step([int times = 1]) {
    for (var i = 0; i < times; i++) {
      system
        ..beginStep()
        ..step(_dt, focus: Vector3.zero());
    }
  }
}

void main() {
  group('reading a document', () {
    test('lists every problem with where it is, and the kinds it knows', () {
      final read = BehaviorTree.read(<String, Object?>{
        'kind': 'selector',
        'children': <Object?>[
          <String, Object?>{'kind': 'fly'},
          <String, Object?>{'kind': 'wait'},
          <String, Object?>{'kind': 'utility'},
          <String, Object?>{'kind': 'sequence'},
        ],
      }, BehaviorKinds());

      // Mutation: stopping at the first problem leaves three of these out.
      expect(read.tree, isNull);
      expect(read.problems, hasLength(4));
      expect(
        read.problems[0],
        startsWith('root.children[0]: no leaf kind "fly"'),
      );
      expect(read.problems[0], contains('goToFocus'));
      expect(
        read.problems[1],
        'root.children[1]: wait needs a number "seconds"',
      );
      expect(
        read.problems[2],
        'root.children[2]: a utility lists its "options"',
      );
      expect(
        read.problems[3],
        'root.children[3]: a sequence lists its "children"',
      );
    });

    test('an unknown consideration is refused with the ones that exist', () {
      final read = BehaviorTree.read(<String, Object?>{
        'kind': 'utility',
        'options': <Object?>[
          <String, Object?>{
            'considerations': <Object?>[
              <String, Object?>{'kind': 'mood'},
            ],
            'do': <String, Object?>{'kind': 'hold'},
          },
        ],
      }, _kinds());
      expect(read.problems, hasLength(1));
      expect(
        read.problems.single,
        startsWith(
          'root.options[0].considerations[0]: no consideration kind "mood"',
        ),
      );
      expect(read.problems.single, contains('focusDistance'));
    });

    test('a leaf may not take a composite\'s name', () {
      expect(
        () => BehaviorKinds().leaf('sequence', (p) => const _Hold()),
        throwsArgumentError,
      );
      expect(
        () => BehaviorKinds().leaf('wait', (p) => const _Hold()),
        throwsArgumentError,
      );
      // Replacing on purpose is the way a game swaps a standard kind.
      BehaviorKinds().leaf('wait', (p) => const _Hold(), replace: true);
    });
  });

  group('nodes', () {
    test('a sequence resumes at the child that was running', () {
      final rig = _Rig(
        _tree(<String, Object?>{
          'kind': 'sequence',
          'children': <Object?>[
            <String, Object?>{'kind': 'count', 'key': 'n'},
            <String, Object?>{'kind': 'wait', 'seconds': 0.5},
          ],
        }),
      );
      rig.step(10);
      // Mutation: a sequence that starts again from its first child every
      // tick counts ten here instead of one.
      expect(rig.board.number('n'), 1.0);
      expect(rig.path, <String>['sequence:running', 'wait:running']);

      // Half a second on, the wait ends, the sequence succeeds, and the next
      // tick starts it again from the top.
      rig.step(30);
      expect(rig.board.number('n'), 2.0);
    });

    test('a selector asks its first child again every tick', () {
      final rig = _Rig(
        _tree(<String, Object?>{
          'kind': 'selector',
          'children': <Object?>[
            <String, Object?>{
              'kind': 'sequence',
              'name': 'alarm',
              'children': <Object?>[
                <String, Object?>{'kind': 'check', 'key': 'alarm'},
                <String, Object?>{'kind': 'hold'},
              ],
            },
            <String, Object?>{'kind': 'wait', 'name': 'idle', 'seconds': 100},
          ],
        }),
      );
      rig.step(5);
      expect(rig.path.last, 'idle:running');
      final waitNode = BehaviorBrain.pathOf(rig.actor).last.node;
      expect(rig.board.memory, contains(waitNode));

      rig.board.set('alarm', true);
      rig.step();
      // Mutation: a selector that remembers its running child stays idle
      // until the hundred-second wait ends.
      expect(rig.path, <String>[
        'selector:running',
        'alarm:running',
        'hold:running',
      ]);
      // The abandoned wait's start time is forgotten, so it starts afresh.
      expect(rig.board.memory, isNot(contains(waitNode)));
    });

    test('a utility runs the best option, and holds on to it', () {
      final rig = _Rig(
        _tree(<String, Object?>{
          'kind': 'utility',
          'inertia': 0.2,
          'options': <Object?>[
            <String, Object?>{
              'name': 'rest',
              'considerations': <Object?>[
                <String, Object?>{
                  'kind': 'blackboard',
                  'key': 'tired',
                  'from': 0,
                  'to': 1,
                },
              ],
              'do': <String, Object?>{'kind': 'hold'},
            },
            <String, Object?>{
              'name': 'work',
              'considerations': <Object?>[
                <String, Object?>{'kind': 'constant', 'value': 0.5},
              ],
              'do': <String, Object?>{'kind': 'hold'},
            },
            <String, Object?>{
              'name': 'never',
              'considerations': <Object?>[
                <String, Object?>{'kind': 'constant', 'value': 0},
              ],
              'weight': 100,
              'do': <String, Object?>{'kind': 'hold'},
            },
          ],
        }),
        board: <String, Object?>{'tired': 0.2},
      );
      rig.step();
      // Mutation: a sum rather than a product lets the zero-scored option
      // win on its weight.
      expect(rig.path.last, 'work:running');

      // Past work's half, but not by its inertia: the running option stays.
      rig.board.set('tired', 0.6);
      rig.step();
      // Mutation: without inertia this flips to rest.
      expect(rig.path.last, 'work:running');

      rig.board.set('tired', 0.8);
      rig.step();
      expect(rig.path.last, 'rest:running');
    });

    test('a cooldown refuses its child until the time is up', () {
      final rig = _Rig(
        _tree(<String, Object?>{
          'kind': 'selector',
          'children': <Object?>[
            <String, Object?>{
              'kind': 'cooldown',
              'seconds': 1,
              'child': <String, Object?>{'kind': 'count', 'key': 'n'},
            },
            <String, Object?>{'kind': 'hold'},
          ],
        }),
      );
      rig.step(30);
      expect(rig.board.number('n'), 1.0);
      rig.step(31);
      // Mutation: a cooldown kept in memory that is forgotten off the
      // running path would count every tick.
      expect(rig.board.number('n'), 2.0);
    });

    test('invert and alwaysSucceed turn their child\'s answer', () {
      final rig = _Rig(
        _tree(<String, Object?>{
          'kind': 'sequence',
          'children': <Object?>[
            <String, Object?>{
              'kind': 'invert',
              'child': <String, Object?>{'kind': 'check', 'key': 'x'},
            },
            <String, Object?>{
              'kind': 'alwaysSucceed',
              'child': <String, Object?>{'kind': 'check', 'key': 'x'},
            },
          ],
        }),
      );
      // Nothing runs, so every decision starts from the top and both
      // answers are seen.
      rig.step();
      // Mutation: an alwaysSucceed that passed its child's failure through
      // fails the sequence here.
      expect(rig.path, <String>[
        'sequence:success',
        'alwaysSucceed:success',
        'check:failure',
      ]);
      rig.board.set('x', true);
      rig.step();
      // Mutation: an invert that passed its child's answer through lets the
      // sequence carry on to the second child.
      expect(rig.path, <String>[
        'sequence:failure',
        'invert:failure',
        'check:success',
      ]);
    });
  });

  group('the board', () {
    test('refuses what a snapshot cannot hold', () {
      final board = Blackboard();
      expect(() => board.set('at', Vector3.zero()), throwsArgumentError);
      board
        ..setPoint('at', Vector3(1.0, 2.0, 3.0))
        ..set('seen', true)
        ..set('names', <Object?>['a', 1, null]);
      final read = Blackboard.fromJson(jsonDecode(jsonEncode(board.toJson())))!;
      final at = Vector3.zero();
      expect(read.point('at', at), isTrue);
      expect(at, Vector3(1.0, 2.0, 3.0));
      expect(read.flag('seen'), isTrue);
      expect(read['names'], <Object?>['a', 1, null]);
    });

    test('a tree that changed starts its decision again', () {
      final first = _tree(<String, Object?>{
        'kind': 'sequence',
        'children': <Object?>[
          <String, Object?>{'kind': 'count', 'key': 'n'},
          <String, Object?>{'kind': 'hold'},
        ],
      });
      final rig = _Rig(first)..step(3);
      expect(rig.board.number('n'), 1.0);

      // Same shape, one more child: node numbers are the same, the digest
      // is not.
      final second = _tree(<String, Object?>{
        'kind': 'sequence',
        'children': <Object?>[
          <String, Object?>{'kind': 'count', 'key': 'n'},
          <String, Object?>{'kind': 'hold'},
          <String, Object?>{'kind': 'hold'},
        ],
      });
      rig.system.entities.get<Thinking>(rig.actor.entity)!.brain =
          BehaviorBrain(second);
      rig.step();
      // Mutation: a board that trusted its node numbers would resume at the
      // hold and never count again.
      expect(rig.board.number('n'), 2.0);
      expect(rig.board.tree, second.digestHex);
    });

    test('noise and pain are written where the tree can read them', () {
      // A body, because hearing is by distance and a bodiless actor is
      // nowhere to hear from.
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
        ..update();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final actor = system.spawn(
        body: CharacterController(world: world, position: Vector3(0, 0.9, 0)),
        health: Health(10.0),
        brain: BehaviorBrain(_tree(<String, Object?>{'kind': 'hold'})),
      );
      for (var i = 0; i < 6; i++) {
        system
          ..beginStep()
          ..step(_dt, focus: Vector3(0.0, 0.9, 5.0));
      }
      final board = BehaviorBrain.boardOf(actor);

      system.hear(Vector3(1.0, 0.0, 0.0), radius: 1000.0);
      // Mutation: an onNoise left at Brain's default writes nothing here.
      expect(board.number(BehaviorBrain.heardAt), closeTo(0.1, 1e-12));
      final at = Vector3.zero();
      expect(board.point(BehaviorBrain.heard, at), isTrue);
      expect(at.x, 1.0);

      system.beginStep();
      actor.applyDamage(1.0);
      expect(board.number(BehaviorBrain.hurtAt), closeTo(0.1, 1e-12));
    });
  });

  group('determinism', () {
    test('a run of trees has the digests it had', () {
      final run = _Arena();
      final trace = DigestTrace(every: 60);
      final chosen = <String>{};
      for (var step = 1; step <= 600; step++) {
        run.step(step);
        trace.observe(step, run.state());
        for (final actor in run.system.actors) {
          final path = BehaviorBrain.pathOf(actor);
          if (path.length > 1) chosen.add(path[1].label);
        }
      }
      // A trace of a run that never left one option would hold its digests
      // while the other two were broken.
      expect(
        chosen,
        containsAll(<String>['close in', 'look into it', 'patrol']),
      );
      // Recorded once on the VM. Every number here is `+`, `-`, `*`, `/`,
      // `sqrt` and `Portable`, so these are the same on every platform; a
      // change of any of them is a change of behaviour, and says at which
      // second it started.
      expect(trace.hexDigests, _arenaDigests);
    });

    test('a decision half made comes back from a snapshot', () {
      // The snapshot is taken on the first step past four seconds at which
      // somebody is part-way through a wait: mid-decision, with a sequence's
      // cursor and a wait's start on a board, which is the case worth
      // checking. Found the same way on every run, so the test is too.
      final original = _Arena();
      var at = 0;
      while (at < 240 || !original.waiting) {
        at++;
        original.step(at);
      }
      expect(at, lessThan(500));
      final saved = jsonDecode(jsonEncode(original.state())) as Map;

      final restored = _Arena()..restore(saved);
      final blind = _Arena()
        ..restore(<String, Object?>{
          ...saved.cast<String, Object?>(),
          'ecs': _withoutBoards(saved['ecs'] as Map),
        });
      final agree = <bool>[];
      final blindAgrees = <bool>[];
      for (var step = at + 1; step <= at + 300; step++) {
        original.step(step);
        restored.step(step);
        blind.step(step);
        final want = StateDigest.of(original.state());
        agree.add(StateDigest.of(restored.state()) == want);
        blindAgrees.add(StateDigest.of(blind.state()) == want);
      }
      expect(agree, everyElement(isTrue));
      // Mutation: the boards are what carry the decision; a restore without
      // them is a different run, and this says the test can tell.
      expect(blindAgrees, contains(isFalse));
    });
  });
}

Map<String, Object?> _withoutBoards(Map ecs) => <String, Object?>{
  ...ecs.cast<String, Object?>(),
  'components': <String, Object?>{
    ...(ecs['components'] as Map).cast<String, Object?>(),
  }..remove('blackboard'),
};

/// Three actors on a floor with a wall, one tree, a focus that walks a
/// square, and a noise every few seconds.
///
/// The tree uses every composite and most standard leaves: go for the focus
/// when it is seen and near, look into a noise heard recently, otherwise
/// patrol between two posts with a pause at each.
final class _Arena {
  _Arena() {
    world
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
      ..addBox(Vector3(0.0, 1.5, 4.0), Vector3(8.0, 3.0, 0.5))
      ..update();
    for (final (i, x) in <(int, double)>[(0, -6.0), (1, 3.0), (2, 22.0)]) {
      final actor = system.spawn(
        body: CharacterController(
          world: world,
          position: Vector3(x, 0.9, -3.0 - i),
        ),
        health: Health(30.0),
        brain: BehaviorBrain(_arenaTree),
        facing: Facing(),
        name: 'a$i',
      );
      system.entities.set(
        actor.entity,
        Blackboard(
          values: <String, Object?>{
            'postA': <double>[x - 3.0, 0.9, -8.0],
            'postB': <double>[x + 3.0, 0.9, -8.0],
          },
        ),
      );
    }
  }

  final CollisionWorld world = CollisionWorld();
  late final ActorSystem system = ActorSystem(
    world: world,
    random: GameRandom(7),
  );

  static final BehaviorTree _arenaTree = BehaviorTree.read(
    _arenaJson,
    BehaviorKinds(),
  ).tree!;

  /// The focus walks a square of side twelve, once every twenty seconds.
  Vector3 focusAt(int step) {
    final t = (step % 1200) / 1200.0 * 4.0;
    final side = t.floor();
    final along = (t - side) * 12.0 - 6.0;
    return switch (side) {
      0 => Vector3(along, 0.9, 10.0),
      1 => Vector3(6.0, 0.9, 10.0 - (along + 6.0)),
      2 => Vector3(-along, 0.9, -2.0),
      _ => Vector3(-6.0, 0.9, -2.0 + (along + 6.0)),
    };
  }

  void step(int step) {
    system
      ..beginStep()
      ..step(_dt, focus: focusAt(step));
    if (step % 170 == 0) {
      system.hear(
        Vector3(step % 340 == 0 ? 10.0 : -10.0, 0.9, 0.0),
        radius: 40,
      );
    }
  }

  /// Whether any actor is in a wait right now.
  bool get waiting => system.actors.any(
    (actor) => BehaviorBrain.pathOf(actor).any((s) => s.kind == 'wait'),
  );

  Map<String, Object?> state() => <String, Object?>{
    'ecs': system.entities.save(),
    'system': system.save(),
  };

  void restore(Map<Object?, Object?> state) {
    system.entities.restore((state['ecs']! as Map).cast<String, Object?>());
    system
      ..restore(state['system'])
      ..syncCorpses();
  }
}

const Map<String, Object?> _arenaJson = <String, Object?>{
  'kind': 'utility',
  'inertia': 0.1,
  'options': <Object?>[
    <String, Object?>{
      'name': 'close in',
      'considerations': <Object?>[
        <String, Object?>{'kind': 'seesFocus'},
        <String, Object?>{'kind': 'focusDistance', 'from': 12, 'to': 4},
      ],
      'do': <String, Object?>{
        'kind': 'sequence',
        'children': <Object?>[
          <String, Object?>{'kind': 'markFocus', 'key': 'lastSeen'},
          <String, Object?>{'kind': 'goToFocus', 'within': 1.5},
          <String, Object?>{'kind': 'wait', 'seconds': 0.5},
        ],
      },
    },
    <String, Object?>{
      'name': 'look into it',
      'weight': 0.8,
      'considerations': <Object?>[
        <String, Object?>{
          'kind': 'since',
          'key': 'heardAt',
          'from': 6,
          'to': 1,
        },
      ],
      'do': <String, Object?>{
        'kind': 'cooldown',
        'seconds': 2,
        'child': <String, Object?>{'kind': 'goTo', 'key': 'heard', 'within': 1},
      },
    },
    <String, Object?>{
      'name': 'patrol',
      'considerations': <Object?>[
        <String, Object?>{'kind': 'constant', 'value': 0.2},
      ],
      'do': <String, Object?>{
        'kind': 'sequence',
        'children': <Object?>[
          <String, Object?>{'kind': 'goTo', 'key': 'postA'},
          <String, Object?>{'kind': 'wait', 'seconds': 1},
          <String, Object?>{'kind': 'goTo', 'key': 'postB'},
          <String, Object?>{'kind': 'wait', 'seconds': 1},
        ],
      },
    },
  ],
};

const List<String> _arenaDigests = <String>[
  '8e79608e',
  '147317ff',
  '86db2f1d',
  '0e366189',
  '4bab99a5',
  '35708b46',
  '79ff0948',
  '893cf555',
  '257ecce7',
  '6bee2463',
];
