/// A fixed-step game's steps are the engine loop's: its logic is systems in
/// the loop's phases, in the order the mixin always stepped in, and Flame's
/// collision detection runs in the steps when the game asks for it.
library;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes down every part of a step as it runs.
final class _Logged extends FlameGame with HasFixedStep {
  final List<String> log = <String>[];

  @override
  void fixedUpdate(double step) => log.add('game');
}

final class _LoggedPart extends Component with FixedStepUpdate {
  _LoggedPart(this.log);

  final List<String> log;

  @override
  void fixedUpdate(double step) => log.add('component');
}

final class _Follower implements StepFollower {
  _Follower(this.log);

  final List<String> log;

  @override
  void rememberPlace() => log.add('follower');
}

/// Collisions once a frame, as Flame runs them.
final class _FrameCollisions extends FlameGame
    with HasFixedStep, HasCollisionDetection {}

/// Collisions in the steps.
final class _StepCollisions extends FlameGame
    with HasFixedStep, HasCollisionDetection, HasFixedStepCollisions {}

/// A box that counts each time the detection finds it touching another.
final class _Box extends PositionComponent with CollisionCallbacks {
  _Box() : super(size: Vector2.all(10.0));

  int touches = 0;

  @override
  Future<void> onLoad() async => add(RectangleHitbox());

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    touches++;
    super.onCollision(intersectionPoints, other);
  }
}

void main() {
  testWithGame<_Logged>(
    "a step runs the mixin's systems in the loop's phases, in its old order",
    _Logged.new,
    (game) async {
      // Mutation: add `flame.fixedUpdate` after `flame.components`, or the
      // followers to the `rules` phase.
      await game.add(_LoggedPart(game.log));
      await game.ready();
      game.follow(_Follower(game.log));
      game
        ..beforeEachStep(() => game.log.add('start'))
        ..afterEachStep(() => game.log.add('end'));

      final loop = game.engineLoop;
      expect(loop.systemsIn(LoopPhase.input), <String>[
        'flame.followers',
        'flame.stepStarts',
      ]);
      expect(loop.systemsIn(LoopPhase.rules), <String>[
        'flame.fixedUpdate',
        'flame.components',
      ]);
      expect(loop.systemsIn(LoopPhase.publish), <String>['flame.stepEnds']);
      expect(
        loop.phases(PhaseKind.step).map((LoopPhase p) => p.name),
        containsAllInOrder(<String>['input', 'rules', 'publish']),
      );

      game.update(1 / 60);
      expect(game.log, <String>[
        'follower',
        'start',
        'game',
        'component',
        'end',
      ]);
      expect(loop.step, 1, reason: "the loop's own count is the game's");
    },
  );

  testWithGame<_Logged>(
    'a system added to the loop runs in the steps beside the game',
    _Logged.new,
    (game) async {
      // Mutation: step the game from a clock of its own, beside the loop.
      await game.ready();
      game.engineLoop.addSystem(
        'test.after',
        LoopPhase.rules,
        (_) => game.log.add('after'),
        after: const <String>['flame.components'],
      );

      game.update(2 / 60);
      expect(game.stepsThisFrame, 2);
      expect(game.log, <String>['game', 'after', 'game', 'after']);
    },
  );

  testWithGame<_FrameCollisions>(
    "without the opt-in, Flame's collisions run once a frame",
    _FrameCollisions.new,
    (game) async {
      // Mutation: run the detection in the steps for every fixed-step game.
      final a = _Box();
      final b = _Box();
      await game.addAll(<Component>[a, b]);
      await game.ready();

      game
        ..update(1 / 120)
        ..update(1 / 120);
      expect(a.touches, 2, reason: 'two frames, one step');
      expect(
        game.engineLoop.systemsIn(LoopPhase.rules),
        isNot(contains('flame.collisions')),
      );
    },
  );

  testWithGame<_StepCollisions>(
    "with the opt-in, Flame's collisions run once a step, after the logic",
    _StepCollisions.new,
    (game) async {
      // Mutation: leave the frame's `collisionDetection.run()` open.
      final a = _Box();
      final b = _Box();
      await game.addAll(<Component>[a, b]);
      await game.ready();

      expect(game.engineLoop.systemsIn(LoopPhase.rules), <String>[
        'flame.fixedUpdate',
        'flame.components',
        'flame.collisions',
      ]);

      game
        ..update(1 / 120)
        ..update(1 / 120);
      expect(game.stepsThisFrame, 1);
      expect(a.touches, 1, reason: 'two frames, one step');

      game.update(3 / 60);
      expect(game.stepsThisFrame, 3);
      expect(a.touches, 4, reason: 'one frame, three steps');
    },
  );
}
