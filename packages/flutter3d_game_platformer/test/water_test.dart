/// Water, which is the first thing in this genre that is not underfoot.
///
///     flutter test test/water_test.dart
///
/// Everything else a runner is affected by is a floor with numbers hung off it
/// — ice, mud, a conveyor — and the surface table handles all of them. A runner
/// is *in* water, at any height, and what changes is gravity, the top speed and
/// whether up is a direction they can go.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

({Runner runner, Water pool}) _pool({
  SwimSettings tuning = const SwimSettings(),
}) {
  final world = CollisionWorld(properties: platformerWorld)
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
    ..update();
  final pool = Water(
    collider: world.add(
      Collider(
        shape: CollisionBox(Vector3(6.0, 4.0, 6.0)),
        position: Vector3(0.0, 4.0, 0.0),
      ),
    ),
    tuning: tuning,
  );
  return (
    runner: Runner(
      body: CharacterController(
        world: world,
        position: Vector3(0.0, 30.0, 0.0),
      ),
    ),
    pool: pool,
  );
}

double _fallAfter(Runner runner, {required bool submerged, Water? pool}) {
  final input = InputState();
  runner.inWater = submerged ? pool : null;
  for (var i = 0; i < 60; i++) {
    input.beginStep();
    runner.step(_dt, input);
    input.endStep();
    runner.inWater = submerged ? pool : null;
  }
  return -runner.body.velocity.y;
}

void main() {
  test('a pool says what is inside it and what is not', () {
    final it = _pool();

    expect(it.pool.holds(Vector3(0.0, 4.0, 0.0)), isTrue);
    expect(it.pool.holds(Vector3(0.0, 20.0, 0.0)), isFalse);
    expect(it.pool.holds(Vector3(40.0, 4.0, 0.0)), isFalse);
  });

  test('and it is nothing to press', () {
    // Water is somewhere you are, not something you activate.
    final it = _pool();

    expect(it.pool.activate(const Activation()), isA<NothingToDo>());
  });

  test('a submerged runner sinks slowly rather than falling', () {
    final dry = _pool();
    final wet = _pool();

    final falling = _fallAfter(dry.runner, submerged: false);
    final sinking = _fallAfter(wet.runner, submerged: true, pool: wet.pool);

    expect(falling, greaterThan(8.0), reason: 'it never got going');
    // The sink speed plus the step of gravity that lands between the swim
    // and the body's own step, for the reason the rise measures short.
    expect(sinking, closeTo(2.2, 0.4));
  });

  test('and does not float up by itself', () {
    // Floating to the top reads as a bug the first time a player wants to
    // reach something underneath.
    final it = _pool();

    expect(
      _fallAfter(it.runner, submerged: true, pool: it.pool),
      greaterThan(0.0),
    );
  });

  test('holding jump carries it upwards', () {
    final it = _pool();
    final input = InputState();
    for (var i = 0; i < 30; i++) {
      input.beginStep();
      input.press(GameAction.jump);
      it.runner.inWater = it.pool;
      it.runner.step(_dt, input);
      input.endStep();
    }

    // A step of gravity lands between setting the rise and reading it — the
    // swim runs before the body's own step, which is where gravity is
    // applied — so this is the rise minus a sixtieth of it.
    expect(it.runner.body.velocity.y, closeTo(3.0, 0.5));
  });

  test('and a tar pit and a stream are two different pools', () {
    // A level with two says so by giving them different tuning; putting these
    // on the runner would have made every pool in a level identical.
    final tar = _pool(tuning: const SwimSettings(sinkSpeed: 0.5, drag: 8.0));
    final stream = _pool(tuning: const SwimSettings(sinkSpeed: 4.0, drag: 1.0));

    expect(
      _fallAfter(tar.runner, submerged: true, pool: tar.pool),
      lessThan(_fallAfter(stream.runner, submerged: true, pool: stream.pool)),
    );
  });
  test('on the Moon a runner still sinks: the water pushes by its gravity', () {
    // Mutation: put back a fixed 6 m/s² of buoyancy and the Moon's runner,
    // pulled down by 1.62, is pushed up by nearly four times that and flies
    // out of the pool.
    final world = CollisionWorld(
      properties: WorldProperties(gravity: Vector3(0.0, -1.62, 0.0)),
    )..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    world.update();
    final pool = Water(
      collider: world.add(
        Collider(
          shape: CollisionBox(Vector3(6.0, 4.0, 6.0)),
          position: Vector3(0.0, 4.0, 0.0),
        ),
      ),
    );
    final runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 4.0, 0.0)),
    );
    expect(runner.gravity, closeTo(1.62, 1e-6));
    expect(_fallAfter(runner, submerged: true, pool: pool), greaterThan(0.0));
  });

  test('and the quarter of the run\'s gravity is the 6 m/s² it always was', () {
    expect(const SwimSettings().buoyancyRatio * Runner.runGravity, 6.0);
  });
}
