/// Pushable crates, which cost one class because the wiring was already there.
///
/// `PlatformerSimulation` has taken a `Dynamics`, stepped it and called `push`
/// since it was written; nothing had ever made a body for it to move. These
/// tests are as much about that seam as about the crate.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor, a runner, and crates where the test puts them.
final class _Yard {
  _Yard() {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0));
    mechanisms = MechanismWorld(world);
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: Vector3.zero(),
      mechanisms: mechanisms,
      dynamics: dynamics,
    );
  }

  final CollisionWorld world = CollisionWorld();
  late final Dynamics dynamics = Dynamics(world: world);
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final Runner runner;
  late final PlatformerSimulation sim;

  Crate crateAt(Vector3 at, {double mass = 30.0}) {
    final crate = Crate(world: world, at: at, mass: mass);
    dynamics.add(crate.body);
    return crate;
  }

  bool _forward = false;

  void step({bool forward = false}) {
    input.beginStep();
    if (forward != _forward) {
      forward
          ? input.press(GameAction.moveForward)
          : input.release(GameAction.moveForward);
      _forward = forward;
    }
    sim.step(_dt);
    input.endStep();
  }

  void run(int steps, {bool forward = true}) {
    for (var i = 0; i < steps; i++) {
      step(forward: forward);
    }
  }
}

void main() {
  test('a crate rests on the floor rather than sinking through it', () {
    // Mutation: give `Crate` a mass of zero. An immovable body neither falls
    // nor is pushed, so this passes and every other test here fails — which is
    // why the resting height is checked as well as the pushing.
    final yard = _Yard();
    final crate = yard.crateAt(Vector3(0.0, 4.0, 3.0));

    yard.run(120, forward: false);

    expect(crate.position.y, closeTo(0.6, 0.05),
        reason: 'a 1.2 m box on a floor topped at zero');
  });

  test('walking into a crate moves it', () {
    // The whole point of `Dynamics.push`, which the simulation has been calling
    // into thin air. Mutation: pass no `dynamics` to `PlatformerSimulation` and
    // the crate stands still while the runner walks into it for ever.
    final yard = _Yard();
    final crate = yard.crateAt(Vector3(0.0, 0.6, 2.5));
    final before = crate.position.z;

    yard.run(180);

    expect(crate.position.z, greaterThan(before + 0.5));
    expect(crate.position.y, closeTo(0.6, 0.05), reason: 'and stays down');
  });

  test('mass does not change how fast a crate is shoved, and that is on purpose',
      () {
    // Written expecting the opposite, and the numbers said otherwise: twenty
    // kilos and two hundred travel exactly the same distance. `Dynamics.push`
    // is **velocity-based, not force-based** — it raises the crate's speed to
    // the walker's and no further, whatever it weighs.
    //
    // That is a decision recorded in `dynamics.dart`, and it is the right one
    // for a kinematic character: a player who could not shove a heavy crate
    // would instead stand still pressing against it, which reads as the game
    // being broken rather than the crate being heavy. Mass still decides what
    // happens between crates, and gravity still pulls them.
    //
    // Pinned here so the day somebody makes pushing force-based, this test
    // fails and says why it was not.
    double shove(double mass) {
      final yard = _Yard();
      final crate = yard.crateAt(Vector3(0.0, 0.6, 2.5), mass: mass);
      final before = crate.position.z;
      yard.run(180);
      return crate.position.z - before;
    }

    expect(shove(200.0), closeTo(shove(10.0), 0.01));
  });

  test('a crate stacked on a crate stays stacked', () {
    // Stage-1 rigid bodies promise exactly this and no more: no rotation, so a
    // stack is square or it is nothing. Worth pinning here because a platformer
    // level will stack them the moment they exist.
    final yard = _Yard();
    final lower = yard.crateAt(Vector3(0.0, 0.6, 4.0));
    final upper = yard.crateAt(Vector3(0.0, 2.4, 4.0));

    yard.run(180, forward: false);

    expect(lower.position.y, closeTo(0.6, 0.05));
    expect(upper.position.y, closeTo(1.8, 0.08), reason: 'one box up');
    expect((upper.position.z - lower.position.z).abs(), lessThan(0.1));
  });

  test('a crate can be stood on', () {
    // A `RigidBody`'s collider is kinematic, which is what makes the character
    // controller carry a passenger — so a crate is a platform for free. If this
    // ever fails, the ground probe has stopped recognising them.
    final yard = _Yard();
    yard.crateAt(Vector3(0.0, 0.6, 0.0));
    yard.runner.body.teleport(Vector3(0.0, 3.0, 0.0));

    yard.run(120, forward: false);

    expect(yard.runner.isGrounded, isTrue);
    expect(yard.runner.position.y, closeTo(2.1, 0.15),
        reason: 'standing on a box whose top is at 1.2');
  });
}
