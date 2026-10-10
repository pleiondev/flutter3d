/// A composite a game registers: read from a document like the reader's own,
/// ticked with its memory on the board, refused when its name clashes, and
/// withdrawn with the plugin that brought it.
///
///     dart test test/behaviour_composite_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Adds one to [key] every tick and fails.
final class _Miss extends BehaviorLeaf {
  const _Miss(this.key);
  final String key;

  @override
  BehaviorStatus tick(BehaviorContext context) {
    context.board.set(key, (context.board.number(key) ?? 0.0) + 1.0);
    return BehaviorStatus.failure;
  }
}

/// Runs for ever.
final class _Hold extends BehaviorLeaf {
  const _Hold();

  @override
  BehaviorStatus tick(BehaviorContext context) => BehaviorStatus.running;
}

/// The first child that does not fail, and — unlike a selector — it
/// remembers the one that is running and resumes there.
final class _FirstSuccess extends BehaviorComposite {
  const _FirstSuccess();

  @override
  BehaviorStatus tick(BehaviorContext context, BehaviorChildren children) {
    final from = switch (context.memory) {
      final num at => at.toInt(),
      _ => 0,
    };
    for (var i = from; i < children.length; i++) {
      final status = children.tick(context, i);
      if (status == BehaviorStatus.failure) continue;
      context.memory = status == BehaviorStatus.running ? i : null;
      return status;
    }
    context.memory = null;
    return BehaviorStatus.failure;
  }
}

/// A decorator over one child: always fails, whatever the child says.
final class _Veto extends BehaviorComposite {
  const _Veto();

  @override
  BehaviorStatus tick(BehaviorContext context, BehaviorChildren children) {
    children.tick(context, 0);
    return BehaviorStatus.failure;
  }
}

BehaviorKinds _kinds() => BehaviorKinds()
  ..leaf('miss', (p) => _Miss(p.text('key')))
  ..leaf('hold', (p) => const _Hold())
  ..composite('firstSuccess', (p) => const _FirstSuccess());

const Map<String, Object?> _doc = <String, Object?>{
  'kind': 'firstSuccess',
  'name': 'pick',
  'children': <Object?>[
    <String, Object?>{'kind': 'miss', 'key': 'misses'},
    <String, Object?>{'kind': 'hold', 'name': 'stay'},
  ],
};

final class _Rig {
  _Rig(BehaviorTree tree)
    : system = ActorSystem(world: CollisionWorld(), random: GameRandom(1)) {
    actor = system.spawn(brain: BehaviorBrain(tree));
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

final class _Scope extends PluginScope {
  _Scope(String id)
    : manifest = PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  final PluginManifest manifest;

  @override
  int get rank => 0;

  final List<Registration> tracked = <Registration>[];

  @override
  void track(Registration registration) => tracked.add(registration);
}

void main() {
  group('a registered composite', () {
    test('is read from a document and resumes at the child it remembers', () {
      final read = BehaviorTree.read(_doc, _kinds());
      expect(read.problems, isEmpty);
      final rig = _Rig(read.tree!)..step(5);

      // Mutation: drop the memory write in the composite, or let
      // `BehaviorChildren.tick` leave the context on the child. The miss
      // is ticked again on every step, and `misses` counts five.
      expect(rig.board.number('misses'), 1.0);
      // Mutation: leave `_Custom` out of the path the tree records. The
      // overlay loses the composite, and the running leaf with it.
      expect(rig.path, <String>['pick:running', 'stay:running']);
    });

    test('takes one "child" as a decorator', () {
      final kinds = _kinds()..composite('veto', (p) => const _Veto());
      final read = BehaviorTree.read(<String, Object?>{
        'kind': 'veto',
        'child': <String, Object?>{'kind': 'miss', 'key': 'misses'},
      }, kinds);

      // Mutation: read only "children". The document is refused for a
      // missing list.
      expect(read.problems, isEmpty);
      final rig = _Rig(read.tree!)..step();
      expect(rig.board.number('misses'), 1.0);
    });

    test('is listed among the kinds a refusal names', () {
      final read = BehaviorTree.read(<String, Object?>{
        'kind': 'fly',
      }, _kinds());

      // Mutation: leave the registered composites out of describeKnown.
      expect(read.problems.single, contains('firstSuccess'));
    });
  });

  group('names', () {
    test('a composite may not take a built-in composite\'s name', () {
      // Mutation: drop the check against `composites`. The reader's own
      // `selector` would be shadowed in one game and not in another.
      expect(
        () => BehaviorKinds().composite('selector', (p) => const _Veto()),
        throwsArgumentError,
      );
    });

    test('a composite and a leaf may not share a name, either way', () {
      // Mutation: drop either cross-check. One name would mean a leaf in
      // one place and a composite in another, decided by the reader's
      // order.
      expect(
        () => _kinds().composite('hold', (p) => const _Veto()),
        throwsArgumentError,
      );
      expect(
        () => _kinds().leaf('firstSuccess', (p) => const _Hold()),
        throwsArgumentError,
      );
    });

    test('a second registration is refused unless it replaces', () {
      final kinds = _kinds();
      // Mutation: ignore `replace`. Both calls throw, or neither does.
      expect(
        () => kinds.composite('firstSuccess', (p) => const _Veto()),
        throwsArgumentError,
      );
      kinds.composite('firstSuccess', (p) => const _Veto(), replace: true);
    });
  });

  group('through the plugin host', () {
    test('a plugin\'s kinds go when it is switched off', () {
      final kinds = BehaviorKinds();
      final scope = _Scope('tactics');
      final registry = BehaviorKindsRegistry(kinds).forPlugin(scope)
        ..composite('firstSuccess', (p) => const _FirstSuccess())
        ..leaf('hold', (p) => const _Hold());
      expect(registry, isA<BehaviorKindsRegistry>());
      expect(kinds.compositeBuilder('firstSuccess'), isNotNull);

      for (final registration in scope.tracked.reversed) {
        registration.cancel();
      }

      // Mutation: do not hand the registration to the scope. Nothing is
      // tracked, and both kinds stay after the plugin is gone.
      expect(scope.tracked, hasLength(2));
      expect(kinds.compositeBuilder('firstSuccess'), isNull);
      expect(kinds.leafBuilder('hold'), isNull);
    });

    test('a replaced standard kind comes back when the plugin goes', () {
      final kinds = BehaviorKinds();
      final standard = kinds.leafBuilder('wait');
      final scope = _Scope('patience');
      BehaviorKindsRegistry(
        kinds,
      ).forPlugin(scope).leaf('wait', (p) => const _Hold(), replace: true);
      expect(kinds.leafBuilder('wait'), isNot(same(standard)));

      scope.tracked.single.cancel();

      // Mutation: remove the kind on cancel instead of restoring. Every
      // tree with a `wait` in it is refused once the plugin is off.
      expect(kinds.leafBuilder('wait'), same(standard));
    });

    test('a clash names the plugin', () {
      final scope = _Scope('tactics');
      // Mutation: rethrow the bare error. The message no longer says whose
      // registration it was.
      expect(
        () => BehaviorKindsRegistry(
          BehaviorKinds(),
        ).forPlugin(scope).composite('sequence', (p) => const _Veto()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('plugin "tactics"'),
          ),
        ),
      );
    });
  });
}
