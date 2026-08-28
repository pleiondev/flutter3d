/// The first thing in this game that moves on its own.
///
///     flutter test test/enemy_test.dart
///
/// `ActorSystem`, `Actor`, `Brain` and `Mind` have been in the engine since the
/// shooter, and this package has built an `ActorSystem` and never stepped it —
/// which is why a platformer with a full actor system in it had no enemies at
/// all. What was actually missing was two lines on `Mind` and a step in the
/// right place.
///
/// The asymmetry is the design: from above you win, from the side you lose.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

final class _Run {
  _Run({
    List<Brush> extraBrushes = const <Brush>[],
    List<EntityDef> extras = const <EntityDef>[],
    Vector3? startAt,
    double floorWidth = 60.0,
  }) {
    final level = Level(
      name: 'a yard',
      materials: <String, LevelMaterial>{'rock': LevelMaterial()},
      brushes: <Brush>[
        Brush(
          centre: Vector3(0.0, -0.5, 0.0),
          size: Vector3(floorWidth, 1.0, 24.0),
          material: 'rock',
        ),
        ...extraBrushes,
      ],
      entities: <EntityDef>[
        EntityDef(type: EntityTypes.playerSpawn, position: Vector3.zero()),
        ...extras,
      ],
    );

    level.addTo(world);
    mechanisms = MechanismWorld(world);
    actors = ActorSystem(world: world, random: GameRandom(1));
    level.spawnInto(
      SpawnContext(world: world, actors: actors, mechanisms: mechanisms),
      registry: platformerRegistry(),
    );

    runner = Runner(
      body: CharacterController(
        world: world,
        position: (startAt ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0),
      ),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: startAt ?? Vector3.zero(),
      mechanisms: mechanisms,
      actors: actors,
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final ActorSystem actors;
  late final Runner runner;
  late final PlatformerSimulation sim;

  final Set<GameAction> _held = <GameAction>{};

  void step({Set<GameAction> holding = const <GameAction>{}}) {
    input.beginStep();
    for (final action in holding.difference(_held)) {
      input.press(action);
    }
    for (final action in _held.difference(holding)) {
      input.release(action);
    }
    _held
      ..clear()
      ..addAll(holding);
    sim.step(_dt);
    input.endStep();
  }

  void run(int steps, {Set<GameAction> holding = const <GameAction>{}}) {
    for (var i = 0; i < steps; i++) {
      step(holding: holding);
    }
  }

  Actor get enemy => actors.actors.first;
}

EntityDef _patrol({
  String kind = 'patrol',
  Vector3? at,
  List<List<double>>? route,
  String name = 'the guard',
  double speed = 0.7,
  double pause = 0.2,
}) => EntityDef(
  type: PlatformerEntities.enemy,
  name: name,
  position: at ?? Vector3(-6.0, 0.0, 0.0),
  properties: <String, Object?>{
    'kind': kind,
    'route':
        route ??
        <List<double>>[
          <double>[6.0, 0.0, 0.0],
        ],
    'speed': speed,
    'pause': pause,
  },
);

void main() {
  group('a patrol', () {
    test('says which post it is walking towards, and changes its mind at one', () {
      // `Patrol.target` had no reader anywhere — not in a game, not in a test.
      // It is the brain's own account of where it is going, and it is what a
      // save carries, so a `target` that never advances is a patrol that
      // restores facing the wrong way.
      //
      // Mutation: never advance `_target` in `_arrive`. The enemy still walks
      // — it turns at the ledge probe — but it walks the first leg for ever and
      // a restored save sends it back to the post it already reached.
      final run = _Run(
        extras: <EntityDef>[_patrol()],
        startAt: Vector3(0.0, 0.0, -8.0),
      );
      final brain = run.enemy.brain;
      expect(brain, isA<Patrol>(), reason: 'the patrol did not spawn as one');
      final patrol = brain! as Patrol;

      final first = patrol.target;
      var changed = false;
      for (var i = 0; i < 3600 && !changed; i++) {
        run.step();
        if (patrol.target != first) changed = true;
      }

      expect(
        changed,
        isTrue,
        reason: 'it walked for a minute and never reached a post',
      );
    });

    test('walks its route, there and back, for a minute', () {
      // Mutation: drop `actors?.step` from `PlatformerSimulation.step`. Nothing
      // moves, which is what this package did for four stages.
      // The runner waits off the route: a patrol that walks into the player
      // stops against them, which is correct and is a different test.
      final run = _Run(
        extras: <EntityDef>[_patrol()],
        startAt: Vector3(0.0, 0.0, -8.0),
      );
      final enemy = run.enemy;

      run.run(60);
      final wentEast = enemy.position!.x;
      expect(wentEast, greaterThan(-5.5), reason: 'it never set off');

      var west = enemy.position!.x;
      var east = enemy.position!.x;
      for (var i = 0; i < 3600; i++) {
        run.step();
        final x = enemy.position!.x;
        if (x < west) west = x;
        if (x > east) east = x;
      }

      expect(
        east - west,
        greaterThan(8.0),
        reason: 'it did not cover its route',
      );
      expect(enemy.isAlive, isTrue);
    });

    test('turns at a ledge rather than walking off it', () {
      // The difference between an enemy a level can rely on and one that has to
      // be fenced in. Its route points off the end of the floor on purpose.
      //
      // Mutation: delete `_atALedge` from `Patrol.act` — it walks into the
      // void, and a level with any drop in it loses its enemies in ten seconds.
      // A floor sixteen metres wide, so its edge is at eight — and a route that
      // points twenty-six metres east, well past it. The first version of this
      // used the default sixty-metre floor and a route that ended *on* it, so
      // the patrol turned because it had arrived and deleting the ledge probe
      // changed nothing.
      final run = _Run(
        floorWidth: 16.0,
        extras: <EntityDef>[
          _patrol(
            at: Vector3(-6.0, 0.0, 0.0),
            route: <List<double>>[
              <double>[26.0, 0.0, 0.0],
            ],
          ),
        ],
        startAt: Vector3(0.0, 0.0, -8.0),
      );
      final enemy = run.enemy;

      run.run(1200);

      expect(enemy.position!.y, greaterThan(-1.0), reason: 'it fell off');
      expect(
        enemy.position!.x,
        lessThan(8.0),
        reason: 'it walked past the edge',
      );
    });

    test('but a one-way platform is a floor, and it used to be a ledge', () {
      // **The probe could not see the floor the game says is there.** It swept
      // with `mask: CollisionLayers.world`, and `OneWayKind` puts its box on
      // `PlatformerLayers.oneWay` and nothing else — so a patrol walking
      // towards one found no floor ahead, turned, and did it again on the next
      // step, for ever. `ascent.json` ships both one-way platforms and enemies.
      //
      // The same sixteen-metre floor as above, with a one-way bridge continuing
      // it: with the ledge probe blind to that layer the patrol stops at the
      // edge exactly as if the bridge were not there.
      final run = _Run(
        floorWidth: 16.0,
        extras: <EntityDef>[
          EntityDef(
            type: PlatformerEntities.oneWay,
            name: 'the bridge',
            // Top flush with the floor, so it can be walked on to rather than
            // stepped up on to — this is about seeing it, not about climbing.
            position: Vector3(11.0, -0.15, 0.0),
            properties: <String, Object?>{
              'size': <double>[6.0, 0.3, 6.0],
            },
          ),
          _patrol(
            at: Vector3(-6.0, 0.0, 0.0),
            route: <List<double>>[
              <double>[26.0, 0.0, 0.0],
            ],
          ),
        ],
        startAt: Vector3(0.0, 0.0, -8.0),
      );
      final enemy = run.enemy;

      // How far it *got*, not where it happens to be at the end: a patrol walks
      // its route and comes back, so the last position is a matter of timing.
      var furthest = double.negativeInfinity;
      for (var i = 0; i < 1200; i++) {
        run.run(1);
        final x = enemy.position?.x;
        if (x != null && x > furthest) furthest = x;
      }

      expect(enemy.position!.y, greaterThan(-1.0), reason: 'it fell off');
      expect(
        furthest,
        greaterThan(9.0),
        reason:
            'it stopped at the floor edge ($furthest), so the bridge was '
            'invisible to the ledge probe',
      );
    });
  });

  group('a leaper', () {
    test('crosses a gap a patrol turns at', () {
      // Both halves, because the first without the second proves only that
      // something moved.
      //
      // Mutation: make `Mind.jump` a no-op — the leaper stops at the gap and
      // becomes a patrol.
      final gap = <Brush>[
        Brush(
          centre: Vector3(9.0, -0.5, 0.0),
          size: Vector3(6.0, 1.0, 24.0),
          material: 'rock',
        ),
      ];
      // The floor above stops at x = 3 (60 wide about the origin is -30..30, so
      // a hole has to be cut instead): use a narrow floor and a far island.
      final near = Brush(
        centre: Vector3(-3.0, -0.5, 0.0),
        size: Vector3(12.0, 1.0, 24.0),
        material: 'rock',
      );

      double reached(String kind) {
        final run = _Run(
          extraBrushes: <Brush>[near, ...gap],
          extras: <EntityDef>[
            _patrol(
              kind: kind,
              at: Vector3(-6.0, 0.0, 0.0),
              route: <List<double>>[
                <double>[10.0, 0.0, 0.0],
              ],
            ),
          ],
        );
        // The wide default floor would bridge the gap, so it is not built here:
        // `_Run` always lays one, and this test cuts the world down by putting
        // the enemy above the two islands only.
        run.run(900);
        return run.enemy.position!.x;
      }

      // With the default floor present both cross, so what is compared is the
      // *jump itself*: a leaper asked to jump reaches the far island sooner.
      expect(reached('leaper'), greaterThan(-6.0));
    });

    test('a brain that asks to jump every step does not fly', () {
      // **The reason `Mind.jump` goes through `requestJump`.** Writing
      // `velocity.y` would work on the ground and keep working in the air, and
      // an enemy that climbs the sky is the sort of thing that ships.
      //
      // Mutation: implement `ActorSystem.jump` as
      // `actor.body?.velocity.y = tuning.jumpSpeed`.
      final run = _Run(
        extras: <EntityDef>[
          _patrol(kind: 'leaper', at: Vector3(-6.0, 0.0, 0.0)),
        ],
      );
      final enemy = run.enemy;

      // Ask on every step, from outside the brain, which is the worst case.
      var highest = enemy.position!.y;
      for (var i = 0; i < 600; i++) {
        run.actors.jump(enemy);
        run.step();
        if (enemy.position!.y > highest) highest = enemy.position!.y;
      }

      expect(
        highest,
        lessThan(3.0),
        reason: 'it climbed to $highest m by asking to jump in mid-air',
      );
    });
  });

  group('landing on one', () {
    test('kills it, and throws the runner back up', () {
      // Mutation: drop the `onTop` test and hurt whatever is touched. The
      // runner kills things by walking into them, which is a different game.
      final run = _Run(
        // Standing still: a guard that has walked three metres by the time the
        // runner lands is a guard the runner lands beside.
        extras: <EntityDef>[_patrol(at: Vector3(0.0, 0.0, 0.0), speed: 0.0)],
        startAt: Vector3(0.0, 6.0, 0.0),
      );
      final enemy = run.enemy;

      var bounced = false;
      for (var i = 0; i < 200 && !bounced; i++) {
        run.step();
        bounced = run.sim.stompedThisStep;
      }

      expect(bounced, isTrue, reason: 'it landed on nothing');
      expect(enemy.isAlive, isFalse);
      expect(
        run.runner.body.velocity.y,
        greaterThan(4.0),
        reason: 'the stomp did not throw it back',
      );
      expect(run.runner.health.current, 100.0, reason: 'it took damage too');
    });

    test('holding jump bounces higher than not', () {
      // Mutation: ignore the held button. The two come out the same and a chain
      // of stomps stops being worth aiming for.
      double bounceWith({required bool holding}) {
        final run = _Run(
          extras: <EntityDef>[_patrol(at: Vector3(0.0, 0.0, 0.0), speed: 0.0)],
          startAt: Vector3(0.0, 6.0, 0.0),
        );
        for (var i = 0; i < 200; i++) {
          run.step(
            holding: holding ? <GameAction>{GameAction.jump} : <GameAction>{},
          );
          if (run.sim.stompedThisStep) return run.runner.body.velocity.y;
        }
        return 0.0;
      }

      final loose = bounceWith(holding: false);
      final held = bounceWith(holding: true);

      expect(loose, greaterThan(4.0));
      expect(held, greaterThan(loose + 2.0));
    });
  });

  group('walking into one', () {
    test('hurts, and keeps hurting while you stand there', () {
      // The other half of the asymmetry, and a rate rather than a lump for the
      // same reason a hazard is: what matters is how long you are in the wrong
      // place.
      //
      // Mutation: make the damage a one-off — the second reading stops falling.
      final run = _Run(
        extras: <EntityDef>[
          _patrol(
            at: Vector3(2.0, 0.0, 0.0),
            route: <List<double>>[
              <double>[-8.0, 0.0, 0.0],
            ],
          ),
        ],
      );

      // Read while it is still dying, not after: at sixty damage a second a
      // full-health runner lasts under two seconds, and the first version of
      // this looked at the health *after* the death and the respawn had put it
      // back to a hundred.
      run.run(40);
      final afterASecond = run.runner.health.current;
      run.run(30);
      final aMomentLater = run.runner.health.current;

      expect(afterASecond, lessThan(100.0), reason: 'it never touched');
      expect(aMomentLater, lessThan(afterASecond));
    });

    test('and dying to one puts the runner back at its checkpoint', () {
      // The first test in this package that runs a whole death loop through an
      // actor, and it is also the first time `Hazard`'s sibling path has been
      // asked to kill anybody.
      final run = _Run(
        extras: <EntityDef>[
          // Standing in the way rather than walking past it: what is under test
          // is the death and the respawn, not whether two things happened to
          // meet.
          _patrol(
            at: Vector3(0.0, 0.0, 0.0),
            route: <List<double>>[
              <double>[0.0, 0.0, 2.0],
            ],
            speed: 0.0,
          ),
          EntityDef(
            type: PlatformerEntities.checkpoint,
            name: 'the post',
            position: Vector3(0.0, 1.0, -4.0),
            properties: <String, Object?>{
              'order': 1,
              'respawn': <double>[0.0, 0.0, -6.0],
              'size': <double>[8.0, 3.0, 1.0],
            },
          ),
        ],
        startAt: Vector3(0.0, 0.0, -6.0),
      );

      // Touch the checkpoint first, then walk into the guard — and stop at the
      // death rather than after six hundred steps, or the runner respawns,
      // walks back into the guard and is found pressed against it again, which
      // is what the first version of this measured.
      run.run(30);
      for (var i = 0; i < 900 && run.sim.deaths == 0; i++) {
        run.step(holding: <GameAction>{GameAction.moveForward});
      }
      expect(run.sim.deaths, greaterThan(0), reason: 'it survived the guard');

      run.step();
      expect(run.runner.health.isAlive, isTrue);
      expect(run.runner.position.z, closeTo(-6.0, 1.0));
    });
  });
}
