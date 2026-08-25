/// The floor, and what a platformer wants it to do.
///
///     flutter test test/surfaces_test.dart
///
/// Four things a player can feel, and none of them is a word the engine knows:
/// a platform you jump up through and stand on, falling through the one you are
/// standing on, ice, and a belt. The engine holds the mechanisms — a contact
/// filter, `ground`, `surfaceVelocity`, a swappable `MovementTuning` — and every
/// opinion about what they mean is here.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A level in code: a floor of the named surface, and whatever else is asked
/// for.
final class _Run {
  _Run({
    String floor = 'stone',
    bool oneWay = false,
    Vector3? conveyor,
    double startY = 0.9,
    double startX = 0.0,
  }) {
    final level = Level(
      name: 'a floor',
      materials: <String, LevelMaterial>{'rock': LevelMaterial()},
      brushes: <Brush>[
        Brush(
          centre: Vector3(0.0, -0.5, 0.0),
          size: Vector3(60.0, 1.0, 60.0),
          material: 'rock',
          surface: floor,
        ),
      ],
      entities: <EntityDef>[
        EntityDef(type: EntityTypes.playerSpawn, position: Vector3.zero()),
        if (oneWay)
          EntityDef(
            type: PlatformerEntities.oneWay,
            name: 'the gantry',
            position: Vector3(0.0, 4.0, 0.0),
            properties: <String, Object?>{
              'size': <double>[6.0, 0.3, 6.0],
            },
          ),
        if (conveyor != null)
          EntityDef(
            type: PlatformerEntities.conveyor,
            name: 'the belt',
            position: Vector3(0.0, 0.2, 0.0),
            properties: <String, Object?>{
              'size': <double>[8.0, 0.4, 20.0],
              'flow': <double>[conveyor.x, conveyor.y, conveyor.z],
            },
          ),
      ],
    );

    level.addTo(world);
    mechanisms = MechanismWorld(world);
    level.spawnInto(
      SpawnContext(
        world: world,
        actors: ActorSystem(world: world, random: GameRandom(1)),
        mechanisms: mechanisms,
      ),
      registry: platformerRegistry(),
    );

    runner = Runner(
      body: CharacterController(
        world: world,
        position: Vector3(startX, startY, 0.0),
      ),
      surfaces: Surfaces.common(),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: Vector3.zero(),
      mechanisms: mechanisms,
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
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

  double get y => runner.position.y;

  /// Where the feet are, which is what a level authors and what a crouch
  /// leaves alone.
  double get feet => runner.position.y - runner.body.halfExtents.y;
}

void main() {
  group('a one-way platform', () {
    test('is a floor when you come down onto it', () {
      final run = _Run(oneWay: true, startY: 9.0)..run(120);

      expect(run.runner.isGrounded, isTrue);
      expect(run.y, closeTo(5.05, 0.2), reason: 'standing on the gantry');
    });

    test('and nothing at all when you jump up through it', () {
      // Mutation: make `_countsAsSolid` a mask — `other.layer & oneWay == 0`
      // is never true for the gantry, so it stops being solid altogether and
      // the first assertion fails; or drop the `velocity.y <= 0` clause and the
      // runner bumps its head.
      final run = _Run(oneWay: true);
      run.run(30);
      expect(run.runner.isGrounded, isTrue, reason: 'on the ground first');

      // A spring's worth of speed. Eighteen metres a second reaches six and a
      // half, which clears a gantry whose top is at 4.15; fourteen reaches
      // 3.9, which puts the runner's feet *inside* it at the apex and proves
      // only that gravity works — which is what the first draft did.
      run.runner.launch(18.0);
      var highest = run.y;
      for (var i = 0; i < 90; i++) {
        run.step();
        if (run.y > highest) highest = run.y;
      }

      expect(highest, greaterThan(6.0), reason: 'it hit the underside');
      expect(run.runner.isGrounded, isTrue);
      expect(run.y, closeTo(5.05, 0.2), reason: 'and came back down onto it');
    });

    // **The platform's sides are not solid either**, which is the whole reason
    // the engine takes a predicate rather than a mask — and it is proven where
    // the mechanism is, in `flutter3d_physics/test/surfaces_test.dart`, by the
    // test called `and is not caught by the platform edge on the way past`.
    // Reproducing it here would mean arranging a trajectory that passes a
    // platform's corner at exactly its own height, which is a test about
    // ballistics rather than about a floor.
  });

  group('dropping through', () {
    test('the platform underfoot stops being a floor, briefly', () {
      // Mutation: make `_dropping` a single step rather than a window. The
      // runner falls three centimetres, the platform is solid again, and it
      // lands straight back on it — which reads as the key being ignored.
      final run = _Run(oneWay: true, startY: 9.0)..run(120);
      expect(run.runner.isGrounded, isTrue, reason: 'on the gantry');

      run.run(60, holding: <GameAction>{PlatformerActions.dropThrough});

      expect(run.y, lessThan(3.0), reason: 'still on the platform');
    });

    test('and the ground below is still ground', () {
      final run = _Run(oneWay: true, startY: 9.0)..run(120);
      run.run(240, holding: <GameAction>{PlatformerActions.dropThrough});

      expect(run.runner.isGrounded, isTrue);
      // Measured at the feet, because the key that drops you through is also
      // the key that crouches you, and a crouched body's centre is lower.
      expect(run.feet, closeTo(0.0, 0.15), reason: 'it fell to the floor');
    });

    test('asking for it on ordinary ground crouches instead of falling', () {
      // A drop-through that works anywhere is a runner falling out of the
      // level, and the check is one line that is easy not to write.
      //
      // Mutation: drop the `layer & oneWay` test from `Runner.dropThrough` —
      // the runner leaves the level through its own floor.
      final run = _Run()..run(30);
      run.run(120, holding: <GameAction>{PlatformerActions.dropThrough});

      expect(run.runner.isGrounded, isTrue);
      expect(run.feet, closeTo(0.0, 0.05));
      expect(run.runner.isCrouching, isTrue);
    });
  });

  group('what the floor is made of', () {
    test('ice keeps the speed a stone floor takes away', () {
      // Mutation: drop `_readSurface()` from `Runner.step`, or make
      // `Surfaces.tuningFor` return the fallback always. The two floors stop
      // differing and this fails by a factor it cannot round its way out of.
      double slideAfterRunning(String floor) {
        final run = _Run(floor: floor)
          ..run(90, holding: <GameAction>{GameAction.moveForward});
        final letGoAt = run.runner.position.z;
        run.run(90);
        return run.runner.position.z - letGoAt;
      }

      final onStone = slideAfterRunning('stone');
      final onIce = slideAfterRunning('ice');

      expect(onStone, lessThan(0.6), reason: 'stone should stop you');
      expect(onIce, greaterThan(onStone * 3.0),
          reason: 'ice slid $onIce m and stone slid $onStone m');
    });

    test('a surface nobody named walks like ordinary ground', () {
      // A level may name a surface for its footstep sound alone, and that must
      // not quietly change how it walks.
      //
      // Mutation: make `tuningFor` throw or return something else for an
      // unknown name.
      double slide(String floor) {
        final run = _Run(floor: floor)
          ..run(90, holding: <GameAction>{GameAction.moveForward});
        final letGoAt = run.runner.position.z;
        run.run(90);
        return run.runner.position.z - letGoAt;
      }

      expect(slide('gravel'), closeTo(slide('stone'), 0.02));
    });

    test('leaving ice puts the old numbers back', () {
      // Mutation: assign the surface's tuning and never restore it. The runner
      // skates for the rest of the level, and only a level with two floors in
      // it can see that.
      final run = _Run(floor: 'ice')..run(60);
      expect(run.runner.body.tuning.groundFriction, lessThan(10.0));

      // Off the level's floor and onto nothing that was authored: the ground
      // probe finds no brush, and the runner is back on its own numbers.
      run.runner.body.teleport(Vector3(0.0, 40.0, 0.0));
      run.run(5);

      expect(run.runner.body.tuning.groundFriction, greaterThan(10.0));
    });
  });

  group('a conveyor', () {
    test('carries a runner who asks for nothing', () {
      // Mutation: drop `collider.surfaceVelocity.setFrom(flow)` from
      // `ConveyorKind.spawn`. The belt becomes an ordinary block.
      final run = _Run(conveyor: Vector3(0.0, 0.0, 3.0), startY: 0.9);
      run.runner.body.teleport(Vector3(0.0, 0.7, -6.0));
      run.run(60);

      expect(run.runner.position.z, greaterThan(-4.0),
          reason: 'the belt carried nobody');
    });

    test('and a runner walking against it makes slow progress', () {
      // The felt version, and the one that proves the drag is added to motion
      // rather than replacing it.
      final run = _Run(conveyor: Vector3(0.0, 0.0, -4.0));
      run.runner.body.teleport(Vector3(0.0, 0.7, -6.0));
      run.run(60, holding: <GameAction>{GameAction.moveForward});
      final against = run.runner.position.z + 6.0;

      final with_ = _Run(conveyor: Vector3(0.0, 0.0, 4.0));
      with_.runner.body.teleport(Vector3(0.0, 0.7, -6.0));
      with_.run(60, holding: <GameAction>{GameAction.moveForward});
      final along = with_.runner.position.z + 6.0;

      expect(along, greaterThan(against + 3.0),
          reason: 'walking with the belt was no faster than against it');
    });
  });

  group('what the table knows', () {
    // `knows` and `names` had no reader anywhere in the repository. They are
    // the seam a game uses to decide whether a floor is worth a footstep sound
    // — the thing that turns a surface name from a movement number into
    // something you can hear — and until there is one, this is what says they
    // work.
    test('an unknown surface walks like ordinary ground', () {
      // Mutation: make `tuningFor` return the first entry for anything it does
      // not recognise. Every unnamed floor in every level silently becomes ice.
      final table = Surfaces.common();
      expect(table.knows('nonsense'), isFalse);
      expect(table.tuningFor('nonsense'), same(table.fallback));
      expect(table.tuningFor(null), same(table.fallback));
    });

    test('and the names it does know are the ones it lists', () {
      // Mutation: have `names` return a hardcoded list. It drifts from the
      // table the moment anybody adds a surface, and a game asking "is this
      // worth a sound" gets the wrong answer for the newest floor.
      // Named rather than merely counted: `names` returning a hardcoded
      // one-element list passed the version of this that only walked whatever
      // it was given, because everything it was given was consistent with
      // itself. What it could not know is what was left out.
      final table = Surfaces.common();
      expect(table.names, containsAll(<String>['ice', 'mud']),
          reason: 'the table lists ${table.names}, which is missing a surface '
              'it defines');
      for (final name in table.names) {
        expect(table.knows(name), isTrue, reason: 'listed but not known: $name');
        expect(table.tuningFor(name), isNot(same(table.fallback)),
            reason: '$name is listed and walks like plain ground');
      }
    });
  });

  group('falling past the side of a one-way platform', () {
    // **The rule the filter exists for, applied to the probe that forgot it.**
    // `_countsAsSolid` says a one-way platform is solid only as a floor —
    // "jumping up through it, and running into its side in mid-air, both find
    // nothing" — and its own doc explains that this is why it is a predicate
    // rather than a layer mask: with a mask "a player sprinting past one stops
    // dead on an invisible lip at chest height".
    //
    // The body obeys that, because the filter is its `solidFilter`. The wall
    // probe ran its own sweep without it, so the side of a one-way platform was
    // a wall to cling to and to jump off — the invisible lip, arrived at from
    // the other direction.

    test('is not a wall to cling to', () {
      // Beside the platform's right edge at x = 3, close enough for a 0.14
      // probe to reach it from a body 0.35 wide, and high enough to fall past.
      final run = _Run(oneWay: true, startX: 3.42, startY: 7.0);

      var clung = false;
      for (var i = 0; i < 120 && !clung; i++) {
        run.step();
        clung = run.runner.isOnWall;
      }

      expect(clung, isFalse,
          reason: 'the side of a one-way platform was treated as a wall, so a '
              'runner falling past its edge slows to a wall slide and can jump '
              'off nothing');
    });

    test('and a real wall still is one', () {
      // The other half, or the fix is "never find a wall" and passes the same.
      // Its face at x = 0.45, which a 0.14 probe reaches from a body whose own
      // face is at 0.35. Checked while still falling: a grounded runner is
      // never on a wall, and the floor is 60 metres wide.
      final run = _Run(startX: 0.0, startY: 6.0);
      run.world.addBox(Vector3(0.95, 5.0, 0.0), Vector3(1.0, 8.0, 4.0));

      var clung = false;
      for (var i = 0; i < 40 && !clung; i++) {
        run.step(holding: <GameAction>{GameAction.moveRight});
        clung = run.runner.isOnWall;
      }

      expect(clung, isTrue, reason: 'nothing is a wall any more');
    });
  });
}
