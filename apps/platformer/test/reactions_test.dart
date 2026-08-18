/// What the game shows, asked of the level the game ships.
///
///     flutter test test/reactions_test.dart
///
/// **The gap `soundtrack_test.dart` believed was already covered.** That file's
/// subject says particles and camera shake stay in the widget because they
/// "are already covered by the frame tests" — and before this file, no test in
/// this application mentioned a particle, an effect or a shake at all. A coin
/// that vanished with no sparkle, a death with no dust and a stomp with no
/// camera kick were each a thing somebody had to happen to notice.
///
/// So the decisions are `Reactions` now, and this drives the **shipped level**
/// through it, the same way the sound is driven.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/staging.dart';
import 'package:platformer/src/effects.dart';
import 'package:platformer/src/reactions.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// The teaching level, the shipped registry, and eyes on the result.
final class _Run {
  _Run() {
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

  final Level level = Level.fromJson(
    jsonDecode(File('assets/levels/first_steps.json').readAsStringSync())
        as Map<String, Object?>,
  );
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();

  final Reactions reactions = Reactions();
  final List<Shown> shown = <Shown>[];
  final List<Felt> felt = <Felt>[];

  bool _forward = false;

  void run(int steps, {bool forward = true}) {
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      if (forward != _forward) {
        forward
            ? input.press(GameAction.moveForward)
            : input.release(GameAction.moveForward);
        _forward = forward;
      }
      sim.step(_dt);
      input.endStep();
      final reaction = reactions.listen(sim, runner);
      shown.addAll(reaction.bursts);
      felt.addAll(reaction.jolts);
    }
  }

  /// Whether [effect] was thrown at any point in the run.
  bool saw(Object effect) => shown.any((Shown s) => identical(s.effect, effect));

  Iterable<Jolt> get jolts => felt.map((Felt f) => f.jolt);
}

void main() {
  test('walking the shipped level shows something', () {
    // **The claim the whole file exists for**, and the reason it is a smoke
    // alarm rather than a tuning fork: a build with the reaction wired to
    // nothing and a build with it wired correctly were the same green.
    //
    // Mutation: return an empty `Reaction`. Everything below fails at once.
    final run = _Run()..run(1800);

    expect(run.shown, isNotEmpty, reason: 'the game showed nothing at all');
    expect(run.saw(Effects.coin), isTrue,
        reason: 'it walked over the opening coins and they vanished silently');
  });

  test('and a landing raises dust, sized by how hard it was', () {
    // Dropped rather than walked off, because the guard this checks is a speed
    // threshold: a runner stepping off a kerb raises nothing, on purpose.
    final soft = _Run();
    soft.runner.body.teleport(Vector3(0.0, 1.1, 0.0));
    soft.run(60, forward: false);

    final hard = _Run();
    hard.runner.body.teleport(Vector3(0.0, 12.0, 0.0));
    hard.run(90, forward: false);

    expect(hard.saw(Effects.dust), isTrue, reason: 'it landed hard on nothing');
    expect(hard.jolts, contains(Jolt.kick),
        reason: 'a twelve-metre drop did not move the camera');
    expect(soft.jolts, isEmpty,
        reason: 'the camera dips when the player steps off a kerb');
  });

  test('and dying is shown as well as heard', () {
    // Mutation: drop the `diedThisStep` branch. The most important moment in
    // the game passes with the picture unchanged.
    final run = _Run();
    run.runner.body.teleport(Vector3(0.0, -60.0, 0.0));
    run.run(120, forward: false);

    expect(run.sim.deaths, greaterThan(0), reason: 'the pit did not kill it');
    expect(run.saw(Effects.death), isTrue);
    expect(run.jolts, contains(Jolt.shake),
        reason: 'death did not rattle the camera');
  });

  test('and a described camera move performs the verb it names', () {
    // The reason `Felt` is a description rather than a closure over a camera:
    // a test can ask what a stomp does without owning one. What is checked
    // here is the one place the description turns back into a call — a switch
    // whose arms are one line each, and where sending two of the three verbs
    // to the same camera method would look right and read wrong.
    //
    // `extraFov` is the only one of the three that is observable from outside,
    // so it is used as the discriminator in both directions.
    final widened = FollowCamera(world: CollisionWorld());
    const Felt.widen(0.2).applyTo(widened);
    expect(widened.extraFov, greaterThan(0.0), reason: 'a widen did nothing');

    final jolted = FollowCamera(world: CollisionWorld());
    Felt.kick(Vector3(0.0, -1.0, 0.0)).applyTo(jolted);
    expect(jolted.extraFov, 0.0, reason: 'a kick widened the view');
    const Felt.shake(0.5, seconds: 0.4).applyTo(jolted);
    expect(jolted.extraFov, 0.0, reason: 'a shake widened the view');
  });
}
