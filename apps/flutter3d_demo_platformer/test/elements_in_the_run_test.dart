/// The water and the fires acting on the runner, through the run's own step.
///
///     flutter test test/elements_in_the_run_test.dart
///
/// `run_elements.dart` puts the level's water and fires in the run: the
/// core's water at the runner's feet holds them up by Archimedes and back by
/// a cylinder's drag, and the core's fires burn them by the radiant flux
/// ISO 13571 counts. These are the claims a replay cannot make — a replay
/// says the run is the same run twice, not that the water does anything.
///
/// The level here is a piece of the Cisterns cut out to measure in: the
/// deep's own pit, made a place to walk through rather than a death, and the
/// floor the first two braziers stand on. Named `Cisterns`, so it is dressed
/// as the Cisterns are.
library;

import 'dart:math' as math;

import 'package:flutter3d_demo_platformer/src/run_elements.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _measuringPiece() => Level.fromJson(<String, Object?>{
  'version': 1,
  'name': 'Cisterns',
  'materials': <String, Object?>{
    'stone': <String, Object?>{'roughness': 1.0},
  },
  'brushes': <Object?>[
    // The deep's floor, four metres down.
    <String, Object?>{
      'at': <double>[0.0, -4.5, 96.0],
      'size': <double>[40.0, 1.0, 32.0],
      'material': 'stone',
    },
    // The landing the first two braziers stand on.
    <String, Object?>{
      'at': <double>[0.0, -0.5, -12.0],
      'size': <double>[40.0, 1.0, 10.0],
      'material': 'stone',
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'player_spawn',
      'at': <double>[0.0, 0.0, -10.0],
    },
    <String, Object?>{
      'type': 'hazard',
      'name': 'the deep',
      'at': <double>[0.0, -2.0, 96.0],
      'size': <double>[40.0, 4.0, 32.0],
      'damage': 0.0,
    },
  ],
});

({Staged staged, InputState input}) _stage({required Vector3 at}) {
  final level = _measuringPiece();
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(
    level,
    world,
    input: input,
    registry: platformerRegistry(),
    startAt: at,
  );
  world.update();
  addTearDown(() {
    staged.elements?.dispose();
    if (staged.dynamics case final NativeDynamics native) native.dispose();
  });
  return (staged: staged, input: input);
}

void main() {
  setUpAll(() => startPhysics(asked: 'native'));

  test('water over the head holds a walker to the speed its drag leaves '
      'them', () {
    // The runner walks the deep's floor, under three and a half metres of
    // the core's water. Each step the drag takes v − v/(1 + k v dt) off and
    // the legs give back what their grip allows, a·dt, so the walk settles
    // where the two are equal: k v² = a (1 + k v dt), with
    // k = ½ ρ C_d w h / m over the whole of a body under water and
    // a = μ g (1 − ρ/1064), the soles pressed on the floor by the 6 % of
    // the weight the water does not hold up.
    //
    // Mutation: drop the drag in `wadeIn` and the walk is the controller's
    // six metres a second. Mutation: take the width the water meets as the
    // box the run steps rather than the body, or weigh it as water, and
    // the walk settles elsewhere. Mutation: leave the lift out of the grip,
    // and the legs push at μ g and the walk settles at 2.4 m/s, not 0.56.
    final (:staged, :input) = _stage(at: Vector3(0.0, -4.0, 84.0));
    final runner = staged.runner;
    expect(staged.elements, isNotNull);

    input.press(GameAction.moveForward);
    final along = <double>[];
    for (var i = 0; i < 150; i++) {
      input.beginStep();
      staged.step(_dt);
      input.endStep();
      along.add(runner.position.z);
    }
    expect(runner.body.isGrounded, isTrue);
    // A second in, measured over the second half.
    final speed = (along[149] - along[89]) / (60 * _dt);

    // The reference man, 73 kg and 1.76 m at 1064 kg/m³, as a cylinder of
    // his own volume; Hoerner's 1.2 for a cylinder; fresh water.
    const rho = 1000.0, mass = 73.0, height = 1.76;
    final width = 2.0 * math.sqrt(mass / 1064.0 / (math.pi * height));
    final a = runner.tuning.grip * runner.body.gravity * (1.0 - rho / 1064.0);
    final k = 0.5 * rho * 1.2 * width * height / mass;
    final settled =
        (a * k * _dt + math.sqrt(a * a * k * k * _dt * _dt + 4 * k * a)) /
        (2 * k);
    expect(settled, lessThan(0.9 * runner.body.tuning.walkSpeed));
    // The water's own flow, which the walker stirs, is the difference.
    expect(speed, closeTo(settled, 0.05 * settled));
  });

  test('water a shin deep holds a walk to what the grip and the drag leave '
      'it', () {
    // 0.3 m of still water about the legs, on the landing's dry stone: the
    // water holds up ρ/1064 · 0.3/1.76 of the weight, 16 %, so the soles
    // push at μ g (1 − 0.16) = 13.7 m/s², and the drag on 0.3 m of a
    // 0.22 m cylinder takes k v² back, k = ½ ρ C_d w 0.3 / m. The walk
    // settles where k v² = a (1 + k v dt): 5.11 m/s of its 6. Before the
    // grip the legs pushed at the controller's 70 m/s² and the same water
    // would have let the walk be, settling only at 11.9.
    //
    // Mutation: leave the lift out of `wadeIn`, and the soles push at the
    // dry μ g and the walk settles at 5.59. Mutation: drop the grip, and
    // it is the walk's 6. Mutation: drop the drag, and it is 6 again.
    final (:staged, :input) = _stage(at: Vector3(15.0, 0.0, -12.0));
    final runner = staged.runner;
    final body = runner.body;
    const rho = 1000.0, mass = 73.0, height = 1.76, wet = 0.3;
    // With the camera at yaw nought, the screen's right is −x.
    input.press(GameAction.moveRight);
    final along = <double>[];
    for (var i = 0; i < 180; i++) {
      final feet = body.position.y - body.halfExtents.y;
      RunElements.wadeIn(
        runner,
        _dt,
        surface: feet + wet,
        density: rho,
        flowX: 0.0,
        flowZ: 0.0,
      );
      input.beginStep();
      staged.step(_dt);
      input.endStep();
      along.add(-runner.position.x);
    }
    expect(body.isGrounded, isTrue);
    final speed = (along[179] - along[119]) / (60 * _dt);

    final width = 2.0 * math.sqrt(mass / 1064.0 / (math.pi * height));
    final a =
        runner.tuning.grip * body.gravity * (1.0 - rho / 1064.0 * wet / height);
    final k = 0.5 * rho * 1.2 * width * wet / mass;
    final settled =
        (a * k * _dt + math.sqrt(a * a * k * k * _dt * _dt + 4 * k * a)) /
        (2 * k);
    expect(settled, closeTo(5.11, 0.01));
    expect(speed, closeTo(settled, 0.01));
  });

  test('water to the waist takes that share of the weight off in the air', () {
    // Archimedes: a body of 1064 kg/m³ with h of its 1.76 m under water of
    // ρ is held up by ρ/1064 · h/1.76 of its weight, so the run's own
    // gravity is that much weaker on it while it is off the floor.
    //
    // Mutation: hold up the whole body whatever is under water, or weigh
    // it against water as dense as itself, and the lift is not this.
    final (:staged, input: _) = _stage(at: Vector3(0.0, 0.0, -10.0));
    final runner = staged.runner;
    final body = runner.body;
    expect(body.isGrounded, isFalse, reason: 'nothing has stepped it yet');
    body.velocity.setZero();
    final feet = body.position.y - body.halfExtents.y;
    RunElements.wadeIn(
      runner,
      _dt,
      surface: feet + 0.9,
      density: 1000.0,
      flowX: 0.0,
      flowZ: 0.0,
    );
    final g = body.gravity;
    expect(body.velocity.y, greaterThan(0.0));
    expect(
      body.velocity.y,
      // A velocity is single precision.
      closeTo(g * 1000.0 / 1064.0 * 0.9 / 1.76 * _dt, 1e-7),
    );
  });

  test('a current carries a runner who stands in it, and never past its own '
      'speed', () {
    // The drag acts on the velocity relative to the water: a runner at rest
    // in a current of u is taken towards u by 1 − 1/(1 + k u dt) of it a
    // step, and no number of steps takes them past it.
    //
    // Mutation: drag the runner's own velocity rather than the one relative
    // to the water, and the runner never moves; integrate it explicitly,
    // v −= k|v|v dt, and at this depth and flow it overshoots the current.
    final (:staged, input: _) = _stage(at: Vector3(0.0, 0.0, -10.0));
    final runner = staged.runner;
    final body = runner.body;
    body.velocity.setZero();
    final feet = body.position.y - body.halfExtents.y;
    const u = 30.0;
    for (var i = 0; i < 600; i++) {
      RunElements.wadeIn(
        runner,
        _dt,
        surface: feet + RunElements.runnerHeight,
        density: 1000.0,
        flowX: u,
        flowZ: 0.0,
      );
      expect(body.velocity.x, lessThanOrEqualTo(u));
    }
    expect(body.velocity.x, closeTo(u, 0.5));
  });

  test('a brazier hurts a runner standing against it, and not one passing '
      'five metres off', () {
    // The core's fires, each as Modak's point source capped by its soot's
    // own σT⁴, and the dose ISO 13571 counts to second-degree burns above
    // its 2.5 kW/m²: health falls by its whole times dt / 6.9 q^−1.56
    // minutes each step.
    //
    // Mutation: leave the burn out of the step, and the first runner keeps
    // its health. Mutation: drop the 2.5 kW/m² floor, and the second runner
    // is hurt. Mutation: spread the point source over the distance and not
    // its square, or burn by the pain law's 4.2 q^−1.9 rather than the
    // burns', and the one-step dose disagrees.
    final (:staged, input: near) = _stage(
      at: Vector3(-17.5 + 0.45, 0.0, -12.0),
    );
    final (staged: far, input: away) = _stage(
      at: Vector3(-17.5 + 5.0, 0.0, -12.0),
    );
    final elements = staged.elements!;
    // Long enough for the burner's fire to come up.
    for (var i = 0; i < 240; i++) {
      for (final (run, input) in <(Staged, InputState)>[
        (staged, near),
        (far, away),
      ]) {
        input.beginStep();
        run.step(_dt);
        input.endStep();
      }
    }
    final health = staged.runner.health;
    expect(health.current, lessThan(health.maximum));
    expect(far.runner.health.current, far.runner.health.maximum);
    expect(
      RunElements.fluxOnto(far.runner, far.elements!.world.fires()),
      lessThan(RunElements.harmlessFlux),
    );

    // One more step, against the laws written out here again: the flux off
    // the fires the step left, and the dose it gives.
    final before = health.current;
    near.beginStep();
    staged.step(_dt);
    near.endStep();
    final body = staged.runner.body;
    final lo = body.position - body.halfExtents;
    final hi = body.position + body.halfExtents;
    var flux = 0.0;
    for (final fire in elements.world.fires()) {
      final mid = fire.at + fire.axis * (fire.reach / 2.0);
      final skin = Vector3(
        mid.x.clamp(lo.x, hi.x),
        mid.y.clamp(lo.y, hi.y),
        mid.z.clamp(lo.z, hi.z),
      );
      final r = mid.distanceTo(skin);
      final soot = stefanBoltzmann * math.pow(fire.sootTemperature, 4);
      flux += math.min(
        fire.radiantShare * fire.power / (4.0 * math.pi * r * r),
        soot,
      );
    }
    expect(flux, greaterThan(2500.0));
    final minutes = 6.9 * math.pow(flux / 1000.0, -1.56);
    expect(
      before - health.current,
      closeTo(health.maximum * _dt / (minutes * 60.0), 1e-6),
    );
  });
}
