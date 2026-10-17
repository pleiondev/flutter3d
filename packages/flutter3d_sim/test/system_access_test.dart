/// `reads:`/`writes:` on a system, and the pairs that touch one state with
/// nothing ordering them: named by `EngineLoop.unorderedAccess`, thrown by
/// `validateOrder`, and refused at the first step of a debug build.
///
///     dart test test/system_access_test.dart
///
/// Each test names the mutation that would defeat it.
library;

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

const double _frame = 1.0 / 60.0;

void _nothing(LoopContext _) {}

void main() {
  group('unorderedAccessIn', () {
    test('two writers of one state with no order are a pair', () {
      // Mutation: drop the writes-against-writes half of `_shared`.
      final pairs = unorderedAccessIn(LoopPhase.rules, const <SystemAccess>[
        SystemAccess('a', writes: <String>['game.score']),
        SystemAccess('b', writes: <String>['game.score']),
      ]);
      expect(pairs, <UnorderedAccess>[
        const UnorderedAccess(
          phase: LoopPhase.rules,
          first: 'a',
          second: 'b',
          state: <String>['game.score'],
        ),
      ]);
    });

    test('a reader and a writer are a pair, whichever registered first', () {
      // Mutation: check only the first system's writes against the second's
      // reads. The reader registered first slips through.
      final pairs = unorderedAccessIn(LoopPhase.rules, const <SystemAccess>[
        SystemAccess('reader', reads: <String>['game.score']),
        SystemAccess('writer', writes: <String>['game.score']),
      ]);
      expect(pairs.single.first, 'reader');
      expect(pairs.single.second, 'writer');
      expect(pairs.single.state, <String>['game.score']);
    });

    test('two readers are not a pair', () {
      expect(
        unorderedAccessIn(LoopPhase.rules, const <SystemAccess>[
          SystemAccess('a', reads: <String>['game.score']),
          SystemAccess('b', reads: <String>['game.score']),
        ]),
        isEmpty,
      );
    });

    test('after or before on either side orders the pair', () {
      // Mutation: read only `after`. The `before` pair is reported.
      for (final systems in <List<SystemAccess>>[
        const <SystemAccess>[
          SystemAccess('a', writes: <String>['s']),
          SystemAccess('b', writes: <String>['s'], after: <String>['a']),
        ],
        const <SystemAccess>[
          SystemAccess('a', writes: <String>['s'], before: <String>['b']),
          SystemAccess('b', writes: <String>['s']),
        ],
        const <SystemAccess>[
          SystemAccess('a', writes: <String>['s'], after: <String>['b']),
          SystemAccess('b', reads: <String>['s']),
        ],
      ]) {
        expect(unorderedAccessIn(LoopPhase.rules, systems), isEmpty);
      }
    });

    test('a chain through a system that declares nothing orders the ends', () {
      // Mutation: walk only between declaring systems. `a → m → b` is read
      // as unordered.
      expect(
        unorderedAccessIn(LoopPhase.rules, const <SystemAccess>[
          SystemAccess('a', writes: <String>['s']),
          SystemAccess('m', after: <String>['a']),
          SystemAccess('b', reads: <String>['s'], after: <String>['m']),
        ]),
        isEmpty,
      );
    });

    test('a constraint naming a missing system orders nothing', () {
      expect(
        unorderedAccessIn(LoopPhase.rules, const <SystemAccess>[
          SystemAccess('a', writes: <String>['s'], after: <String>['fire']),
          SystemAccess('b', writes: <String>['s']),
        ]),
        hasLength(1),
      );
    });

    test('the shared state is what the first writes, then what it reads', () {
      final pairs = unorderedAccessIn(LoopPhase.rules, const <SystemAccess>[
        SystemAccess(
          'a',
          reads: <String>['x', 'q'],
          writes: <String>['y', 'z'],
        ),
        SystemAccess('b', reads: <String>['z'], writes: <String>['x', 'y']),
      ]);
      expect(pairs.single.state, <String>['y', 'z', 'x']);
    });
  });

  group('EngineLoop', () {
    test('names an unordered pair in a step phase', () {
      // Mutation: drop `reads`/`writes` on the way into `_System`. The loop
      // sees two systems that declare nothing.
      final loop = EngineLoop(input: InputState())
        ..addSystem(
          'game.damage',
          LoopPhase.rules,
          _nothing,
          writes: const <String>['game.health'],
        )
        ..addSystem(
          'game.heal',
          LoopPhase.rules,
          _nothing,
          writes: const <String>['game.health'],
        );
      expect(loop.unorderedAccess(), <UnorderedAccess>[
        const UnorderedAccess(
          phase: LoopPhase.rules,
          first: 'game.damage',
          second: 'game.heal',
          state: <String>['game.health'],
        ),
      ]);
      expect(
        loop.validateOrder,
        throwsA(
          isA<UnorderedAccessException>()
              .having((e) => e.pairs, 'pairs', hasLength(1))
              .having(
                (e) => e.message,
                'message',
                allOf(contains('game.damage'), contains('game.heal')),
              ),
        ),
      );
    });

    test('a debug build refuses the pair at the first frame', () {
      // Mutation: drop the assert in `_orderToRun`. The frame runs, and the
      // pair waits for a replay to differ.
      final loop = EngineLoop(input: InputState())
        ..addSystem(
          'game.damage',
          LoopPhase.rules,
          _nothing,
          writes: const <String>['game.health'],
        )
        ..addSystem(
          'game.heal',
          LoopPhase.rules,
          _nothing,
          reads: const <String>['game.health'],
        );
      var asserts = false;
      assert(asserts = true, 'only a debug build asserts');
      if (asserts) {
        expect(
          () => loop.frame(_frame),
          throwsA(isA<UnorderedAccessException>()),
        );
      } else {
        loop.frame(_frame);
      }
    });

    test('an order between them clears it, and the loop steps', () {
      final ran = <String>[];
      final loop = EngineLoop(input: InputState())
        ..addSystem(
          'game.damage',
          LoopPhase.rules,
          (_) => ran.add('damage'),
          writes: const <String>['game.health'],
        )
        ..addSystem(
          'game.heal',
          LoopPhase.rules,
          (_) => ran.add('heal'),
          writes: const <String>['game.health'],
          after: const <String>['game.damage'],
        );
      expect(loop.unorderedAccess(), isEmpty);
      loop
        ..validateOrder()
        ..frame(_frame);
      expect(ran, isNot(isEmpty));
    });

    test('two phases order their systems, and frame phases are not held', () {
      // Mutation: check every system of a kind together rather than phase
      // by phase. The physics and rules pair is reported.
      final loop = EngineLoop(input: InputState())
        ..addSystem(
          'game.move',
          LoopPhase.physics,
          _nothing,
          writes: const <String>['game.position'],
        )
        ..addSystem(
          'game.score',
          LoopPhase.rules,
          _nothing,
          reads: const <String>['game.position'],
        )
        ..addSystem(
          'view.a',
          LoopPhase.animate,
          _nothing,
          writes: const <String>['view.pose'],
        )
        ..addSystem(
          'view.b',
          LoopPhase.animate,
          _nothing,
          writes: const <String>['view.pose'],
        );
      expect(loop.unorderedAccess(), isEmpty);
      loop.frame(_frame);
    });

    test('a removed system takes its pair with it', () {
      final loop = EngineLoop(input: InputState())
        ..addSystem(
          'game.a',
          LoopPhase.rules,
          _nothing,
          writes: const <String>['s'],
        );
      final second = loop.addSystem(
        'game.b',
        LoopPhase.rules,
        _nothing,
        writes: const <String>['s'],
      );
      expect(loop.unorderedAccess(), hasLength(1));
      second.cancel();
      expect(loop.unorderedAccess(), isEmpty);
    });

    test('a subsystem reading a field another writes is held to an order', () {
      // Mutation: drop `readsFields`/`writesFields` from the subsystem's
      // system. The reader runs before or after the writer by install
      // order, unnamed.
      final loop = EngineLoop(input: InputState());
      loop.fields.declare(
        FieldDeclaration(
          id: 'game.heat',
          quantity: 'f3d.temperature',
          unit: Unit.kelvin,
          grid: const FieldGrid(2, 1, 1),
          writer: const FieldAccess.simulation('game.burn'),
        ),
      );
      Subsystem solver(SubsystemDeclaration declaration) =>
          Subsystem.of(declaration, (SubsystemContext _) {});
      loop.subsystems
        ..register(
          solver(
            const SubsystemDeclaration(
              id: 'game.burn',
              version: 1,
              writesFields: <String>['game.heat'],
            ),
          ),
        )
        ..register(
          solver(
            const SubsystemDeclaration(
              id: 'game.melt',
              version: 1,
              readsFields: <String>['game.heat'],
            ),
          ),
        );
      expect(loop.unorderedAccess().single.state, <String>['game.heat']);
    });
  });
}
