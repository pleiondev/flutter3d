/// A pile of crates settling, and whether it settles the same way everywhere.
///
///     dart test test/solver_parity_test.dart
///     dart test --platform chrome test/solver_parity_test.dart
///
/// **The third scenario, and the one that was named as unmeasured for as long
/// as the other two were measured.** `parity_test.dart` beside this file drives
/// a character controller and `flutter3d_game_racing`'s drives a car; the
/// rigid-body solver — the thing that holds a stack of crates up — had never
/// been asked whether it replays. It is the part of a run a player is least
/// likely to notice diverging and the most likely to: a crate that ends up a
/// centimetre to the left blocks a door on one machine and not on another.
///
/// ## What was predicted, and why it was still worth asking
///
/// `flutter3d_physics` calls **no transcendental at all** — no sine, no
/// exponential, nothing whose answer belongs to the machine — so the prediction
/// was that this was always exact and that the answer would be dull. A
/// prediction is not a measurement, and this one had three ways to be wrong
/// that have nothing to do with `dart:math`:
///
///  * **Iteration order.** The solver keeps its warm-start impulses in a `Map`
///    keyed by an object, and walks its bodies and its contact pairs in order.
///    Dart's maps iterate by insertion, on both platforms — but "in the order
///    they were inserted" is only deterministic if the insertions are, and the
///    insertions come out of a broadphase that bins by cell.
///  * **Accumulated order of addition.** Floating-point addition is not
///    associative. Twenty velocity iterations and six position passes over a
///    pile of nine crates is a long chain of sums, and a chain whose *order*
///    differs gives a different number even though every operation is exact.
///  * **The integer arithmetic underneath the grid.** A browser's `int` is a
///    `double`, which is the trap that has cost this repository three defects
///    already, all of them invisible outside a browser.
///
/// So the value of a dull answer is that it is now recorded, and the next
/// change to the broadphase or to the solver's loop order has something to fail
/// against.
///
/// ## The scene
///
/// Built to make the solver work rather than to look like a level: a stack that
/// only stands if warm starting works, a wall of crates for something to be
/// pushed into, spheres with a bounce to keep the restitution path live, and
/// bodies that arrive at an angle so that contacts are found in an order the
/// broadphase decides rather than the scene.
///
/// ## Why the trace is two hundred steps and not a thousand
///
/// **Because a thousand was mostly measuring that a sleeping pile stays
/// asleep.** The first version checkpointed every twenty-five steps of a
/// thousand, the way the other two parity files do, and the pile had come to
/// rest by about step 175: thirty-four of the forty checkpoints were the same
/// number. A trace whose second half cannot change is a trace whose second half
/// cannot fail, and forty checkpoints that are really six is an instrument
/// reporting more agreement than it found.
///
/// So the window is the part where something happens — two hundred steps, one
/// checkpoint every five — and thirty-three of the forty differ. The seven that
/// repeat are at the end and are the point of being there: they record that the
/// pile came to rest and stayed, and the sleep clock is a branch, which is the
/// kind of thing that fires on one platform and not the other.
///
/// The last test runs the full thousand and asserts the outcome rather than the
/// path, which is where the length belongs.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a pile of crates settling', () {
    test('is the settling that was recorded, wherever it settles', () {
      final trace = _settle(steps: 200);
      final divergence = trace.divergenceFromHex(_recorded);
      expect(
        divergence,
        isNull,
        reason:
            'the solver reached a different pile here: $divergence. Nothing in '
            '`flutter3d_physics` calls a function whose answer belongs to the '
            'machine, so this is not the arithmetic — look at what decides an '
            'order: the broadphase\'s cells, the pair list, the map the warm '
            'start is held in.',
      );
    });

    test('and settling it twice in one process settles it the same way', () {
      // The weaker question, and the one that would still be worth asking if
      // the recorded numbers were thrown away: a solver that disagrees with
      // itself has a clock or an identity hash in its loop, and the
      // cross-platform question does not arise.
      expect(_settle(steps: 200).digests, _settle(steps: 200).digests);
    });

    test('and over a thousand steps it moves, settles and sleeps', () {
      // Without this the file could be recording that nine crates left in the
      // air stayed in the air on both platforms, which is true and worth
      // nothing. Three claims, because each covers a different half of the
      // solver: things fall, the pile ends up standing, and the sleep clock —
      // a branch, and the kind of branch that fires on one platform only —
      // actually fires.
      final world = _room();
      final dynamics = _pile(world);
      final droppedFrom = dynamics.bodies.map((b) => b.position.y).toList();

      for (var step = 0; step < 1000; step++) {
        dynamics.step(_dt);
        dynamics.world.update();
      }

      expect(
        dynamics.bodies.where((b) => b.position.y < 40.0).length,
        dynamics.bodies.length,
        reason: 'nothing was flung out of the room',
      );
      expect(
        <int>[
          for (var i = 0; i < droppedFrom.length; i++)
            if (dynamics.bodies[i].position.y < droppedFrom[i] - 0.5) i,
        ],
        isNotEmpty,
        reason: 'nothing fell',
      );
      expect(
        dynamics.bodies.where((b) => b.velocity.length < 0.1).length,
        greaterThan(dynamics.bodies.length ~/ 2),
        reason: 'the pile never came to rest',
      );
      expect(
        dynamics.bodies.where((b) => b.isAsleep).isNotEmpty,
        isTrue,
        reason: 'nothing went to sleep, so that branch is untested here',
      );
    });
  });
}

const double _dt = 1.0 / 60.0;

/// A floor, four walls and a shelf to fall off.
///
/// Static geometry, so the broadphase has something in every cell the bodies
/// travel through: a solver that only ever sees other bodies is a solver whose
/// static path is untested.
CollisionWorld _room() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(24.0, 1.0, 24.0))
    ..addBox(Vector3(0.0, 2.0, -8.0), Vector3(24.0, 6.0, 1.0))
    ..addBox(Vector3(0.0, 2.0, 8.0), Vector3(24.0, 6.0, 1.0))
    ..addBox(Vector3(-8.0, 2.0, 0.0), Vector3(1.0, 6.0, 24.0))
    ..addBox(Vector3(8.0, 2.0, 0.0), Vector3(1.0, 6.0, 24.0))
    // The shelf, so that some of what is dropped lands on geometry and some of
    // it lands on what landed before.
    ..addBox(Vector3(3.0, 1.5, 2.0), Vector3(3.0, 0.4, 3.0));
  world.update();
  return world;
}

/// The bodies, rolled from [GameRandom] rather than written out.
///
/// The one generator this repository has proved gives the same sequence
/// everywhere — `determinism_test.dart` is that proof — so the scene is
/// identical on both platforms even though it is not a literal.
Dynamics _pile(CollisionWorld world) {
  final dynamics = Dynamics(world: world);
  final dice = GameRandom(20260906);

  // A tower, straight up and slightly out of line. It only stands if warm
  // starting works: without it the pile creeps down about ten centimetres
  // before the position correction catches it, which is a different pile.
  for (var i = 0; i < 6; i++) {
    dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3(
          -2.0 + (dice.nextDouble() - 0.5) * 0.04,
          0.5 + i * 1.02,
          -1.0 + (dice.nextDouble() - 0.5) * 0.04,
        ),
        friction: 0.6,
      ),
    );
  }

  // Crates arriving from the side, into the tower, at an angle — so the
  // contacts of one step are not the contacts of the step before and the pair
  // list is rebuilt with something in it.
  for (var i = 0; i < 5; i++) {
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.4, 0.4, 0.4)),
        position: Vector3(4.0 + i * 0.9, 3.0 + i * 0.7, -1.0 + i * 0.35),
        mass: 1.0 + dice.nextDouble(),
        friction: 0.4,
      ),
    );
    body.velocity.setValues(
      -6.0 - dice.nextDouble() * 2.0,
      0.0,
      dice.nextDouble() - 0.5,
    );
  }

  // Spheres with a bounce, to keep the restitution path and its threshold in
  // the measurement. Dropped over the shelf so half of them come off it.
  for (var i = 0; i < 4; i++) {
    dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionSphere(0.35),
        position: Vector3(
          2.0 + dice.nextDouble() * 2.5,
          5.0 + i * 1.5,
          1.0 + dice.nextDouble() * 2.5,
        ),
        mass: 0.6,
        restitution: 0.45,
        friction: 0.25,
      ),
    );
  }

  return dynamics;
}

/// Steps the pile and digests every body every twenty-five steps.
DigestTrace _settle({required int steps, int every = 5}) {
  final world = _room();
  final dynamics = _pile(world);
  final trace = DigestTrace(every: every);

  for (var step = 1; step <= steps; step++) {
    dynamics.step(_dt);
    dynamics.world.update();
    trace.observe(step, <String, Object?>{
      'bodies': <Object?>[for (final body in dynamics.bodies) body.save()],
    });
  }
  return trace;
}

/// Recorded on macOS-arm64 under the VM, 2026-09-06, and matched by Chrome.
///
/// One table, and it was expected to be one: the solver reaches for nothing the
/// platform supplies. See the head of this file for the three ways that could
/// have been wrong anyway.
///
/// **Matched again on ubuntu-x64, under the VM and under Chrome, in CI run
/// 34121423137 on 2026-09-07** — every checkpoint, both environments. No number
/// here moved; the expectation is simply held by a second processor and a
/// second operating system now, which is worth writing down because the same
/// run also found eleven rows of `parity_test.dart`'s libm table answering
/// differently on that machine. The solver walked past all of it.
const List<String> _recorded = <String>[
  '37f28474',
  'a752b50a',
  '7dfe1c61',
  '5046a17c',
  '64a067c1',
  '4fbb69dd',
  'ccf2f091',
  'a7e25eb4',
  '4baeec4c',
  'a437ba80',
  'e9f8ecdc',
  '85c34be6',
  '8b15ddae',
  'a6623621',
  '7d6888c6',
  'f8f8a3a3',
  'd68bbbd2',
  '4b3edaf9',
  '87b41367',
  'd3d501c8',
  '0e0cb93e',
  '5e36cced',
  'a118f1fa',
  '732ebe6a',
  '18858f58',
  'a6bf8401',
  'cfe03e1b',
  '3e260d78',
  '18cde76a',
  '1abdea02',
  '3b626073',
  '408a32c4',
  'caaed919',
  'caaed919',
  'caaed919',
  'caaed919',
  'caaed919',
  'caaed919',
  'caaed919',
  'caaed919',
];
