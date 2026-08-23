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

import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
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
    level.addTo(world);
    // `stage` is what `main.dart` calls. A harness that assembles the level its
    // own way is a harness that agrees with any bug the game has.
    staged = stage(level, world, input: input, registry: kinds);
  }

  final EntityRegistry kinds = platformerRegistry();
  late final Staged staged;
  Dynamics get dynamics => staged.dynamics;
  MechanismWorld get mechanisms => staged.mechanisms;
  ActorSystem get actors => staged.actors;
  Runner get runner => staged.runner;
  PlatformerSimulation get sim => staged.sim;

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();

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

  group('the gate of two skills', () {
    // **Ascent asked for neither the wall jump nor the dash for two hundred and
    // sixty metres.** Both were paid for in the engine and taught in
    // `first_steps`, and then the level a player spends nine tenths of their
    // time in wanted nothing but walking, jumping and a crouch — so two moves
    // were learned in the tutorial and never used again.
    //
    // The approach to the summit is a corridor now: a two-metre chimney to
    // climb, and a nine-metre gap to dash, against a double jump that clears
    // seven and a half.
    //
    // **What is asserted here is that they are there and that they are the
    // right size — not that they are unavoidable.** Three tests that claimed
    // the second thing were written and deleted: this field is a hundred and
    // twenty metres wide, two thin fences do not seal an approach, and a runner
    // simply goes round. Making the gate compulsory is a redesign of the whole
    // end of the level, and claiming it in a comment while a bot strolls past
    // would be worse than saying so.

    test('the chimney is a chimney and not a room', () {
      // The measurement that decides whether it can be climbed at all: the
      // runner's wall probe reaches fourteen centimetres, so a slot much wider
      // than two metres is one it falls down the middle of. Four was tried in
      // `first_steps` and the autopilot sat at the bottom of it.
      //
      // Mutation: widen the slot. This says by how much.
      final level = _shipped();
      final walls = <Brush>[
        for (final brush in level.brushes)
          if ((brush.centre.z - 180.0).abs() < 5.0 &&
              brush.centre.y > 2.0 &&
              brush.centre.x.abs() > 1.0 &&
              brush.centre.x.abs() < 12.0)
            brush,
      ];
      expect(walls, hasLength(2), reason: 'the chimney is not two walls');

      final inner = walls
          .map((Brush b) => b.centre.x.abs() - b.size.x / 2.0)
          .reduce(math.min);
      expect(inner * 2.0, closeTo(2.0, 0.1),
          reason: 'the slot is ${inner * 2} m across, and a wall jump needs '
              'about two');
    });

    test('and the gap past it is wider than a double jump', () {
      // Nine metres against a measured 7.5. Mutation: narrow it, and the dash
      // stops being the answer.
      final level = _shipped();
      final tops = <Brush>[
        for (final brush in level.brushes)
          if (brush.centre.x.abs() < 1.0 &&
              brush.centre.z > 178.0 &&
              brush.centre.z < 200.0 &&
              brush.centre.y > 3.0)
            brush,
      ];
      expect(tops, isNotEmpty, reason: 'nothing to jump from or to');

      final near = tops
          .map((Brush b) => b.centre.z + b.size.z / 2.0)
          .where((double z) => z < 190.0)
          .reduce(math.max);
      final far = tops
          .map((Brush b) => b.centre.z - b.size.z / 2.0)
          .where((double z) => z > 190.0)
          .reduce(math.min);

      expect(far - near, greaterThan(7.5),
          reason: 'the gap is ${far - near} m, which a double jump clears');
      expect(far - near, lessThan(14.0),
          reason: 'the gap is ${far - near} m, which a dash does not');
    });
  });

  test('a double jump rises 3.13 metres, and the level is built to that', () {
    // **Reported as "part of the level cannot be reached", and it was.** The
    // route above walks *past* the ice on the shore line, so nothing had ever
    // asked whether the staircase in the middle of it could be climbed. Its
    // first step's top was 3.6 — half a metre above anything that could reach
    // it — so the spring on top of the staircase, and the coin above that, were
    // reachable only by pushing a crate ten metres and standing on it.
    //
    // The number is measured here rather than taken from `runner.dart`, because
    // what a jump is worth is not `jumpSpeed`: gravity, the air jump's own
    // speed and the moment the second one is pressed all decide it. **Jump is
    // held**, because releasing while rising cuts the jump short — a probe that
    // presses and releases in one frame measures 0.47 m and believes it.
    final climb = _Climb();
    climb.runner.body.teleport(Vector3(0.0, 1.0, 143.0));
    for (var i = 0; i < 120; i++) {
      climb._step(<GameAction>{}, Vector3(0.0, 1.0, 143.0));
    }
    final ground = climb.runner.position.y;

    double rise({required int secondAt}) {
      climb.runner.body.teleport(Vector3(0.0, ground, 143.0));
      for (var i = 0; i < 30; i++) {
        climb._step(<GameAction>{}, Vector3(0.0, ground, 143.0));
      }
      var top = climb.runner.position.y;
      for (var i = 0; i < 150; i++) {
        // Held throughout, except for the one frame that gives the second jump
        // an edge to fire on — near the apex, where the cut costs nothing.
        final want = i == secondAt - 1
            ? <GameAction>{}
            : <GameAction>{GameAction.jump};
        climb._step(want, Vector3(0.0, ground + 10.0, 143.0));
        top = math.max(top, climb.runner.position.y);
      }
      return top - ground;
    }

    var reach = 0.0;
    for (var at = 15; at <= 30; at++) {
      reach = math.max(reach, rise(secondAt: at));
    }

    expect(reach, closeTo(3.13, 0.15),
        reason: 'the jump changed, and every step in every level was measured '
            'against the old number');

    // And the staircase is built to it. Each climb is the gap between one
    // standable top and the next, from the ice floor at zero.
    final tops = <double>[
      0.0,
      for (final brush in climb.level.brushes)
        if (brush.material == 'ice' &&
            brush.centre.z > 143.0 &&
            brush.centre.z < 154.0 &&
            brush.size.x > 6.0)
          brush.centre.y + brush.size.y / 2,
    ]..sort();

    expect(tops.length, greaterThan(2), reason: 'the staircase is not there');
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i] - tops[i - 1], lessThan(reach - 0.3),
          reason: 'the step from ${tops[i - 1]} to ${tops[i]} is more than a '
              'double jump with anything to spare');
    }
  });
}
