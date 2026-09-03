/// The autopilot the big levels are proved with, and the one copy of it.
///
/// Not a test. It is imported by `ascent_route_test.dart` and by the three
/// level tests after it, and it exists because the fourth copy was about to be
/// written: a route driver is forty lines of steering, a trick ladder and a
/// give-up rule, and four of those drift apart the way `staging.dart`'s own
/// header describes five copies of the game's assembly drifting apart.
///
/// **What this is not is a script.** It names *places worth being* and works
/// out how to get between them, escalating through walk, jump, dash and a fast
/// wall-jump rhythm whenever it stops making progress — which is as close to a
/// player meeting a level for the first time as a test can get. Move a brush
/// and a route built on this still passes; wall a key in, drop a landing out of
/// reach, or widen a gap past what the runner can jump, and it does not.
///
/// The world is assembled by `stage`, which is what `main.dart` calls. A
/// harness that assembles a level its own way is a harness that agrees with any
/// bug the game has.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// The document the game ships, read off disk.
Level shippedLevel(String asset) => Level.fromJson(
  jsonDecode(File(asset).readAsStringSync()) as Map<String, Object?>,
);

/// Everything a level test needs to walk a level: the shipped document, the
/// shipped registry, and a runner that can be steered.
final class Climb {
  Climb(this.asset) {
    level.addTo(world);
    staged = stage(level, world, input: input, registry: kinds);
  }

  /// The level document's path, as the game names it.
  final String asset;

  final EntityRegistry kinds = platformerRegistry();
  late final Staged staged;
  Dynamics get dynamics => staged.dynamics;
  MechanismWorld get mechanisms => staged.mechanisms;
  ActorSystem get actors => staged.actors;
  Runner get runner => staged.runner;
  PlatformerSimulation get sim => staged.sim;

  late final Level level = shippedLevel(asset);
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();

  final Set<GameAction> _held = <GameAction>{};

  /// One frame, holding [want] and facing [goal].
  ///
  /// The camera owns "forward", exactly as it does in the game — so steering is
  /// a camera yaw and a held key, and never a written-down velocity.
  void step(Set<GameAction> want, Vector3 goal) {
    input.beginStep();
    for (final action in want.difference(_held)) {
      input.press(action);
    }
    for (final action in _held.difference(want)) {
      input.release(action);
    }
    _held
      ..clear()
      ..addAll(want);
    final to = goal - runner.position;
    sim.cameraYaw = math.atan2(to.x, to.z);
    sim.step(_dt);
    input.endStep();
  }

  /// Heads for [goal] until it is within [within], or gives up.
  ///
  /// The trick ladder is the one a player uses: walk, and when that has stopped
  /// getting you anywhere try the next thing you know. Progress resets it, so a
  /// dash learned in one place is not carried into the next.
  bool driveTo(
    Vector3 goal, {
    double within = 1.6,
    int steps = 5400,
    bool Function()? until,
  }) {
    var trick = 0;
    var stuck = 0;
    var best = (runner.position - goal).length;

    for (var i = 0; i < steps; i++) {
      final want = <GameAction>{GameAction.moveForward};
      if (trick >= 1 && i % 30 < 22) want.add(GameAction.jump);
      if (trick == 2 && i % 30 == 5) want.add(PlatformerActions.dash);
      if (trick == 3 && i % 14 < 3) want.add(GameAction.jump);
      step(want, goal);

      if (until != null && until()) return true;
      final away = (runner.position - goal).length;
      if (until == null && away <= within) return true;
      if (away < best - 0.2) {
        best = away;
        stuck = 0;
        trick = 0;
      } else if (++stuck > 240) {
        stuck = 0;
        trick = (trick + 1) % 4;
      }
    }
    return false;
  }

  /// Where the entity called [name] is. Fails loudly rather than throwing a
  /// bare state error: a renamed set piece should say which name went missing.
  Vector3 named(String name) {
    final found = <EntityDef>[
      for (final entity in level.entities)
        if (entity.name == name) entity,
    ];
    if (found.isEmpty) fail('$asset has nothing called "$name"');
    return found.first.position;
  }

  /// Walks [route] in order, and says where it stopped and what it had already
  /// reached if it does not arrive.
  ///
  /// [finishAt] names the exit, which is not somewhere to stand near but an
  /// event: what ends a level is touching the volume, so arriving there is the
  /// run being finished rather than a distance falling under a threshold.
  ///
  /// [fetching] names a key, and is the same kind of correction for the same
  /// kind of mistake. **A key is not a place either.** Standing a metre and a
  /// half from one is arriving by any distance a route driver uses and is not
  /// picking it up, and a route that says it fetched a key it never touched is
  /// worse than no route at all: the level after the gate was reached by a bot
  /// that dashed through a locked door, which is a thing this engine's runner
  /// can do to two metres of oak at eighteen metres a second.
  void walkThrough(
    List<(String, Vector3)> route, {
    int steps = 5400,
    String? finishAt,
    String? fetching,
  }) {
    final wanted = fetching == null
        ? null
        : level.entities
              .firstWhere((EntityDef e) => e.name == fetching)
              .string('color');

    final reached = <String>[];
    for (final (name, at) in route) {
      final arrived = switch (name) {
        _ when name == finishAt => driveTo(
          at,
          steps: steps,
          until: () => sim.state == RunState.finished,
        ),
        _ when name == fetching => driveTo(
          at,
          steps: steps,
          until: () => runner.keys.contains(wanted),
        ),
        _ => driveTo(at, steps: steps),
      };
      if (!arrived) {
        fail(
          'stopped on the way to "$name" at ${runner.position}, having '
          'reached: ${reached.isEmpty ? 'nothing' : reached.join(', ')}',
        );
      }
      reached.add(name);
    }
  }

  /// Every checkpoint in the level, in the order the document numbers them.
  List<Checkpoint> get posts => <Checkpoint>[
    for (final m in mechanisms.all)
      if (m is Checkpoint) m,
  ]..sort((Checkpoint a, Checkpoint b) => a.order.compareTo(b.order));
}

/// The errors in a level document, as the game's own validator reports them.
List<LevelIssue> issuesIn(Level level) => LevelValidator(
  registry: platformerRegistry(),
  rules: platformerRules(),
).validate(level);
