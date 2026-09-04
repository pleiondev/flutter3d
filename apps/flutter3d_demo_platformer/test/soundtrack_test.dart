/// What the game sounds like, asked of the level the game ships.
///
///     flutter test test/soundtrack_test.dart
///
/// **Total silence was undetectable.** `SoLoudBackend` falls back to
/// `SilentBackend` when it cannot open a device, every call site goes on
/// calling into the silence perfectly happily, and the decisions about what to
/// play lived inside a widget's private method — so nothing could ask what a
/// step ought to sound like without a device, a renderer and a window. Seven
/// sounds shipped and not one test mentioned any of them.
///
/// So the decisions are `Soundtrack` now, and this drives the **shipped
/// level** through it: a run that takes a coin and hears nothing fails here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_demo_platformer/src/sounds.dart';
import 'package:flutter3d_demo_platformer/src/soundtrack.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// The teaching level, the shipped registry, and ears on the result.
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

  final Soundtrack soundtrack = Soundtrack();
  final List<SoundDef> heard = <SoundDef>[];

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
      for (final Heard sound in soundtrack.listen(
        sim,
        runner,
        sim.events.drain(),
      )) {
        heard.add(sound.sound);
      }
    }
  }

  Iterable<String> get names => heard.map((SoundDef s) => s.name);
}

void main() {
  test('walking the shipped level is not silent', () {
    // **The claim the whole file exists for.** Before it, a build with no audio
    // device and a build with no sounds at all were the same green.
    //
    // Mutation: return an empty list from `Soundtrack.listen`. Everything below
    // fails at once, which is the point — this is a smoke alarm, not a tuning
    // fork.
    final run = _Run()..run(1800);

    expect(run.heard, isNotEmpty, reason: 'the game made no sound at all');
    expect(
      run.names,
      contains('coin'),
      reason: 'it walked over the opening coins and said nothing',
    );
  });

  test('and running is not silent either, which is most of playing', () {
    // Running is ninety-five per cent of what a player does and it had no sound
    // whatsoever. Mutation: delete the footstep branch in `Soundtrack._step`.
    final run = _Run()..run(600);

    expect(
      run.names.where((String n) => n.startsWith('step_')),
      isNotEmpty,
      reason: 'a thousand metres of running and not one footstep',
    );
  });

  test('and coming down from a jump is heard', () {
    // The sound the widget used to play by itself, which is why it is being
    // asked about for the first time here. Mutation: delete the
    // `landedThisStep` branch. A game where jumping makes a noise and landing
    // makes none feels like the floor is not there.
    final run = _Run();
    run.runner.body.teleport(Vector3(0.0, 6.0, 0.0));
    run.run(90, forward: false);

    expect(run.names, contains('land'), reason: 'it fell and nothing happened');
  });

  test('footsteps are paid for in metres, not in seconds', () {
    // Mutation: count time instead of distance in `Soundtrack._step`. A runner
    // standing still then makes footsteps for ever, which is the single most
    // noticeable way to get this wrong.
    final standing = _Run()..run(600, forward: false);

    expect(
      standing.names.where((String n) => n.startsWith('step_')),
      isEmpty,
      reason: 'it stood still and walked anyway',
    );
  });

  test('and none are taken in mid-air', () {
    // Mutation: drop the `isGrounded` guard. The runner crosses every gap in
    // the game to the sound of walking on nothing.
    final run = _Run();
    run.runner.body.teleport(Vector3(0.0, 20.0, 0.0));
    run.run(60, forward: true);

    expect(
      run.names.where((String n) => n.startsWith('step_')),
      isEmpty,
      reason: 'it took a step while falling',
    );
  });

  test('the surface underfoot chooses the step', () {
    // The reason there are three: the level's floors already differ underfoot,
    // and a step that sounds the same on ice as on moss says the surface change
    // was decoration.
    //
    // Mutation: return one sound from `Sounds.stepOn` whatever it is given.
    expect(Sounds.stepOn('ice'), isNot(Sounds.stepOn('moss')));
    expect(
      Sounds.stepOn(null),
      Sounds.stepOn('nonsense'),
      reason: 'a floor nobody named is still a floor, and gets stone',
    );
  });

  test('the way out is announced once, not sixty times a second', () {
    // `RunState.finished` stays true for every frame afterwards, so a fanfare
    // keyed on the state rather than on the change is a buzzer.
    //
    // Mutation: drop the `_wasFinished` latch in `Soundtrack.listen`.
    final run = _Run();
    // Straight to the exit rather than playing the level: what is under test is
    // the edge, not the route — `ascent_route_test.dart` is the route.
    final exit = run.level.ofType(EntityTypes.exit).first.position;
    run.runner.body.teleport(exit + Vector3(0.0, 0.9, 0.0));
    run.run(180, forward: false);

    expect(
      run.sim.state,
      RunState.finished,
      reason: 'it never reached the way out',
    );
    expect(
      run.names.where((String n) => n == 'exit'),
      hasLength(1),
      reason:
          'the fanfare played ${run.names.where((String n) => n == 'exit').length} times',
    );
  });
}
