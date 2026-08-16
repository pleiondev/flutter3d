/// Ascent, proved finishable.
///
///     flutter test test/ascent_route_test.dart
///
/// **The level the player spends nine tenths of the game in had never been
/// finished by anything**, and that was by design: `playthrough_test.dart` says
/// so in its own header, on the grounds that a script for a field 120 by 260
/// metres is a script rewritten every time a brush moves. The argument is
/// sound and the consequence was not — nobody had ever fetched either key, both
/// gate tests call `keyRing.take('blue')` directly, and a level whose key is
/// walled in is a game with no ending that no test would notice.
///
/// So this is a route, but not a script: it names **places worth being**, and a
/// repertoire autopilot works out how to get between them, escalating through
/// walk, jump, dash and a fast wall-jump rhythm whenever it stops making
/// progress. Move a brush and this still passes; wall a key in and it does not.
///
/// What it found on its first run: the blue key at (0, 9, 46) sits at the top
/// of a slot six metres wide — too wide to wall-jump, and eight metres above
/// its floor, against a double jump of 3.13. Aimed at from below, the autopilot
/// parks directly underneath it for ever. It is reached from *above*, over the
/// eight-metre blocks beside the slot. The key is fine; the approach is the
/// puzzle, and nothing said
/// which approach it was.
///
/// **And the blocks are reached from the tower, not from the pad on top of it**
/// — measured, because the first version of that sentence said the pad and was
/// wrong. Deleting `the quarry pad` changes nothing here: the tower's top is
/// 5.8 m and a double jump adds 3.13, which clears an eight-metre block with
/// centimetres to spare. Deleting the tower fails immediately. The spring may
/// well be the route a *player* finds, and that is a different question from
/// whether a route exists at all, which is the only one this test asks.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
      jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// The shipped level, the shipped registry, and a runner that can be steered.
final class _Climb {
  _Climb() {
    final kinds = platformerRegistry();
    level.addTo(world);
    (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;
    level.spawnInto(
      SpawnContext(world: world, mechanisms: mechanisms, actors: actors),
      registry: kinds,
    );

    final start = level.ofType(EntityTypes.playerSpawn).first.position;
    runner = Runner(
      body: CharacterController(
        world: world,
        position: start + Vector3(0.0, 0.9, 0.0),
      ),
      surfaces: Surfaces.common(),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: start,
      mechanisms: mechanisms,
      dynamics: dynamics,
      actors: actors,
      levelNext: level.next,
    );
  }

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  late final Dynamics dynamics = Dynamics(world: world);
  final InputState input = InputState();
  late final MechanismWorld mechanisms = MechanismWorld(world);
  late final ActorSystem actors = ActorSystem(world: world);
  late final Runner runner;
  late final PlatformerSimulation sim;

  final Set<GameAction> _held = <GameAction>{};

  void _step(Set<GameAction> want, Vector3 goal) {
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
    // The camera owns "forward", exactly as in the game — so steering is a
    // camera yaw and a held key, and never a written-down velocity.
    final to = goal - runner.position;
    sim.cameraYaw = math.atan2(to.x, to.z);
    sim.step(_dt);
    input.endStep();
  }

  /// Heads for [goal] until it is within [within], or gives up.
  ///
  /// The trick ladder is the one `first_steps_test.dart` uses and for the same
  /// reason: a player who stops getting anywhere tries the next thing they
  /// know. Progress resets it, so a dash learned in one place is not carried
  /// into the next.
  bool driveTo(Vector3 goal,
      {double within = 1.6, int steps = 5400, bool Function()? until}) {
    var trick = 0;
    var stuck = 0;
    var best = (runner.position - goal).length;

    for (var i = 0; i < steps; i++) {
      final want = <GameAction>{GameAction.moveForward};
      if (trick >= 1 && i % 30 < 22) want.add(GameAction.jump);
      if (trick == 2 && i % 30 == 5) want.add(PlatformerActions.dash);
      if (trick == 3 && i % 14 < 3) want.add(GameAction.jump);
      _step(want, goal);

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

  Vector3 named(String name) => level.entities
      .firstWhere((EntityDef e) => e.name == name)
      .position;
}

void main() {
  test('both keys can be fetched and the summit reached', () {
    final climb = _Climb();

    // Places worth being, in order. Three of them are not on the walked line
    // and that is the point: the green key is a detour west, and the blue one
    // is reached over the blocks beside its slot rather than up it.
    final route = <(String, Vector3)>[
      ('the green key', climb.named('the green key')),
      ('the quarry pad', Vector3(-14.0, 6.5, 40.0)),
      ('the blocks beside the slot', Vector3(-7.0, 8.5, 44.0)),
      ('the blue key', climb.named('the blue key')),
      ('the forecourt', Vector3(0.0, 1.0, 72.0)),
      ("the blue gate's plate", climb.named("the blue gate's plate")),
      ('past the blue gate', Vector3(0.0, 1.0, 90.0)),
      ("the green gate's plate", climb.named("the green gate's plate")),
      ('the cold', Vector3(0.0, 1.0, 124.0)),
      ('past the ice', Vector3(0.0, 1.0, 170.0)),
      ('the foot of the stair', Vector3(0.0, 1.0, 190.0)),
      ('the summit', climb.named('the summit')),
    ];

    final reached = <String>[];
    for (final (name, at) in route) {
      // The summit is not a place to stand near, it is an event: the exit is a
      // volume, and what ends the level is touching it.
      final arrived = name == 'the summit'
          ? climb.driveTo(at, until: () => climb.sim.state == RunState.finished)
          : climb.driveTo(at);
      if (!arrived) {
        fail('stopped on the way to "$name" at ${climb.runner.position}, '
            'having reached: ${reached.join(', ')}');
      }
      reached.add(name);
    }

    expect(climb.runner.keys, containsAll(<String>['green', 'blue']),
        reason: 'walked the whole level and did not pick up both keys');
    expect(climb.sim.state, RunState.finished,
        reason: 'stood on the summit and the level did not end');
  });
}
