/// The two lies a platformer tells so that it feels fair.
///
///     flutter test test/forgiveness_test.dart
///
/// Coyote time: you may jump for a moment *after* walking off a ledge. Jump
/// buffer: you may press jump for a moment *before* landing. Neither is
/// physical, both are what every good platformer has, and a player notices
/// their absence instantly without being able to name it — the game simply
/// feels like it is ignoring them.
///
/// **Why this file exists at all.** The runner has its own pair of these, held
/// in `Runner._coyote` and `Runner._buffer` and spent in `_tryJump`, and it is
/// the pair the *player* runs on. `CharacterController` has a second,
/// independent pair, and that one is tested in
/// `packages/flutter3d_physics/test/character_controller_test.dart` — it is
/// what the shooter's player and every enemy run on. A test of one says nothing
/// about the other, and until this file only the one nobody plays was covered.
///
/// Everything here counts steps rather than metres. The windows are tenths of a
/// second, which at sixty hertz is a handful of frames, and a test that asserts
/// a height cannot tell "the jump was refused" from "the jump was short".
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A ledge to walk off, and nothing below it for a long way.
final class _Ledge {
  _Ledge({RunnerTuning tuning = const RunnerTuning()}) {
    // Ends at z = 0. Walking forward is walking off.
    world.addBox(Vector3(0.0, -0.5, -4.0), Vector3(8.0, 1.0, 8.0));
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, -2.0)),
      tuning: tuning,
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Runner runner;

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
    world.reindex();
    runner.step(_dt, input);
    world.update();
    input.endStep();
  }

  void run(int steps, {Set<GameAction> holding = const <GameAction>{}}) {
    for (var i = 0; i < steps; i++) {
      step(holding: holding);
    }
  }

  /// Walks forward until the ground is gone, then returns how it went.
  int walkOffTheEdge() {
    for (var i = 0; i < 600; i++) {
      step(holding: _forward);
      if (!runner.isGrounded) return i;
    }
    fail('never left the ledge');
  }
}

/// A floor with the runner dropped above it.
final class _Floor {
  _Floor({double from = 3.0, RunnerTuning tuning = const RunnerTuning()}) {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, from, 0.0)),
      tuning: tuning,
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Runner runner;

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
    world.reindex();
    runner.step(_dt, input);
    world.update();
    input.endStep();
  }

  void run(int steps, {Set<GameAction> holding = const <GameAction>{}}) {
    for (var i = 0; i < steps; i++) {
      step(holding: holding);
    }
  }

  /// How many steps until the feet are on the floor.
  int stepsUntilLanded({int limit = 600}) {
    for (var i = 0; i < limit; i++) {
      step();
      if (runner.isGrounded) return i;
    }
    fail('never landed');
  }
}

final Set<GameAction> _forward = <GameAction>{GameAction.moveForward};
final Set<GameAction> _jump = <GameAction>{GameAction.jump};

void main() {
  group('coyote time', () {
    // **How a coyote jump is told apart from the other three.** Measured, not
    // assumed, and the first version of this group got it wrong: it asked
    // whether the air jump was still in hand, which is true of a *wall* jump
    // too. Walking off a one-metre-thick ledge leaves its side face beside you,
    // the runner's wall probe finds it, and a wall jump both launches you and
    // hands the air jump back — so with coyote time deleted every test here
    // still passed.
    //
    // One step after the press, at 60 Hz:
    //
    //   ground or coyote jump   vy 9.10   air jump in hand   not a wall jump
    //   air jump                vy 7.80   air jump spent
    //   wall jump               vy 8.60   air jump refilled  wallJumpedThisStep
    //
    // So the claim is the velocity *and* the flag, and the two together admit
    // exactly one of the four.
    void expectCoyoteJump(Runner runner) {
      expect(runner.jumpedThisStep, isTrue, reason: 'nothing happened at all');
      expect(runner.wallJumpedThisStep, isFalse,
          reason: 'it jumped off the side of the ledge, not out of the coyote '
              'window');
      expect(runner.body.velocity.y, closeTo(9.10, 0.05),
          reason: 'launched at ${runner.body.velocity.y}, which is not the '
              'ground jump speed');
    }

    test('a jump just after the ledge is a full ground jump', () {
      // Mutation: `Runner.coyoteTime = 0.0`. What answers instead is the wall
      // jump off the ledge's own face at 8.60, and the velocity says so.
      final stage = _Ledge();
      stage.walkOffTheEdge();
      expect(stage.runner.isGrounded, isFalse);

      // One step into the fall, well inside a window of 0.12 s = 7 steps.
      stage.run(1, holding: _forward);
      expect(stage.runner.body.velocity.y, lessThan(0.0),
          reason: 'not actually in the air');

      stage.step(holding: <GameAction>{..._forward, ..._jump});
      expectCoyoteJump(stage.runner);
      expect(stage.runner.airJumpsLeft, const RunnerTuning().airJumps,
          reason: 'the coyote jump spent the air jump');
    });

    test('the window closes, so it is not a free jump for ever', () {
      // Mutation: never decay `_coyote` in `_tickTimers`. A runner who left the
      // ledge a third of a second ago still gets the full 9.10, and every gap
      // in the game becomes optional.
      final stage = _Ledge();
      stage.walkOffTheEdge();

      stage.run(20, holding: _forward);
      stage.step(holding: <GameAction>{..._forward, ..._jump});

      expect(stage.runner.jumpedThisStep, isTrue,
          reason: 'the air jump should still have answered');
      expect(stage.runner.body.velocity.y, lessThan(9.0),
          reason: 'launched at ${stage.runner.body.velocity.y}, which is the '
              'ground jump, long after the ledge');
      expect(stage.runner.airJumpsLeft, 0,
          reason: 'so it was not the air jump either');
    });

    test('and a runner who jumped off the ledge does not get it twice', () {
      // Mutation: leave `_coyote` alone in `_tryJump`. The runner jumps, is
      // airborne with the window still open, and jumps again at full height a
      // frame later — a second ground jump out of nowhere.
      final stage = _Ledge();
      stage.run(4, holding: _forward);
      stage.step(holding: <GameAction>{..._forward, ..._jump});
      expect(stage.runner.jumpedThisStep, isTrue, reason: 'the first jump');

      stage.run(2, holding: _forward);
      stage.step(holding: <GameAction>{..._forward, ..._jump});

      expect(stage.runner.body.velocity.y, lessThan(9.0),
          reason: 'the second jump launched at '
              '${stage.runner.body.velocity.y}, so coyote outlived the first');
    });
  });

  group('coming back from a death', () {
    // **Revived in mid-fall, which is how anybody actually dies here.** The
    // first version of these two revived a runner who was already standing on
    // the floor, and both mutations survived: `_tickTimers` reads
    // `body.isGrounded` from the previous step, which was true, so the jump
    // budget was refilled whether `reviveAt` did it or not. The claim only
    // bites when the last step said *airborne*, and that is exactly the state a
    // player is in when they fall into a pit.

    test('the first jump after a revive is a ground jump', () {
      // `CharacterController.isGrounded` answers for the last step that ran,
      // and after a teleport no step has run yet — so it says airborne about a
      // runner standing on a checkpoint, and the first press is spent as a
      // double jump. That is reported as "it ate my jump" and nobody can
      // reproduce it.
      //
      // Mutation: drop the `_land()` from `reviveAt`.
      final stage = _Floor(from: 20.0);
      stage.run(30);
      expect(stage.runner.isGrounded, isFalse, reason: 'not falling');

      stage.runner.reviveAt(Vector3(3.0, 0.0, 3.0));

      // Arrived at rest — a runner who came back still carrying the speed of
      // the fall that killed them would die again on landing.
      //
      // **No mutation named, deliberately.** Deleting the `velocity.setZero()`
      // in `reviveAt` changes nothing, because `CharacterController.teleport`
      // already zeroes velocity, grounding and its own two timers. The line is
      // belt-and-braces over a guarantee one layer down, and a comment claiming
      // a mutation that cannot fire is worse than no comment. What this pins is
      // the behaviour, whichever layer keeps providing it.
      expect(stage.runner.body.velocity.y, 0.0,
          reason: 'still falling at ${stage.runner.body.velocity.y}');

      stage.step(holding: _jump);

      expect(stage.runner.jumpedThisStep, isTrue, reason: 'nothing happened');
      expect(stage.runner.body.velocity.y, closeTo(9.10, 0.05),
          reason: 'launched at ${stage.runner.body.velocity.y}, which is the '
              'air jump: the revive ate the ground jump');
      expect(stage.runner.airJumpsLeft, const RunnerTuning().airJumps,
          reason: 'and the spare jump is gone too');
    });

    test('and a press made before dying does not survive the revive', () {
      // Mutation: drop `_buffer = 0.0` from `reviveAt`. A press made in the
      // last moments before a death is still waiting at the checkpoint, and the
      // runner leaves the ground the instant they arrive — which reads as the
      // checkpoint launching them.
      //
      // No air jump, so the press has nothing to spend itself on while falling
      // and is still in the buffer when the revive happens. With one in hand it
      // would be consumed in mid-air and there would be nothing to carry.
      final stage = _Floor(from: 20.0, tuning: const RunnerTuning(airJumps: 0));
      stage.run(30);
      stage.step(holding: _jump);
      expect(stage.runner.jumpedThisStep, isFalse, reason: 'it jumped in air');

      stage.runner.reviveAt(Vector3(3.0, 0.0, 3.0));

      var jumps = 0;
      for (var i = 0; i < 30; i++) {
        stage.step();
        if (stage.runner.jumpedThisStep) jumps++;
      }

      expect(jumps, 0,
          reason: 'it jumped $jumps times on arriving, so the press outlived '
              'the death');
    });
  });

  group('the jump buffer', () {
    // **Every test here turns the double jump off**, and that is not a
    // convenience. With an air jump in hand, a press in mid-air is consumed by
    // the air jump on the spot, so it never reaches the buffer and a buffer
    // that did nothing at all would pass. `airJumps: 0` is what makes the
    // window the only thing that can answer.
    const noSecondJump = RunnerTuning(airJumps: 0);

    /// How many steps a fall from [from] takes, measured rather than assumed.
    int fallOf(double from) =>
        _Floor(from: from, tuning: noSecondJump).stepsUntilLanded();

    test('a jump pressed just before landing happens on landing', () {
      // Mutation: `Runner.jumpBufferTime = 0.0`. The press is dropped, the
      // runner lands flat, and the player — who pressed jump and watched
      // nothing happen — presses again and jumps late.
      final toGo = fallOf(3.0);
      final run = _Floor(from: 3.0, tuning: noSecondJump);

      // Three steps out: inside a window of 0.1 s, which is six.
      run.run(toGo - 3);
      expect(run.runner.isGrounded, isFalse, reason: 'already landed');

      run.step(holding: _jump);
      expect(run.runner.jumpedThisStep, isFalse,
          reason: 'it jumped in mid-air with no air jump left');

      run.run(8);

      expect(run.runner.body.velocity.y, greaterThan(0.0),
          reason: 'the buffered jump never fired: the runner is going at '
              '${run.runner.body.velocity.y} m/s');
    });

    test('and one pressed far too early is forgotten, not stored', () {
      // Mutation: never decay `_buffer` in `_tickTimers`. A press near the top
      // of a long fall is still waiting when the runner lands, so it bounces on
      // arrival and the player never asked for it.
      final run = _Floor(from: 12.0, tuning: noSecondJump);

      // Past the coyote window first — a press inside it is a *ground* jump,
      // not a buffered one, and would prove nothing about either.
      run.run(20);
      run.step(holding: _jump);
      expect(run.runner.jumpedThisStep, isFalse);

      // Counted, not sampled at the end. Checking "is it at rest afterwards"
      // cannot fail: a jump taken on landing is over long before 400 steps are
      // up, and the runner is back on the floor with no vertical speed either
      // way. That version of this test passed against a buffer that never
      // decayed at all.
      var jumps = 0;
      for (var i = 0; i < 400; i++) {
        run.step();
        if (run.runner.jumpedThisStep) jumps++;
      }

      expect(run.runner.isGrounded, isTrue, reason: 'never landed');
      expect(jumps, 0,
          reason: 'it jumped $jumps times on landing, so a press from the top '
              'of the fall was still waiting');
    });

    test('one press is one jump, even with a double jump in hand', () {
      // **The default tuning here, not `noSecondJump`** — the defect only
      // exists when there is something for a leftover press to spend. Mutation:
      // stop clearing `_buffer` in `_tryJump`. The press survives its own
      // ground jump, the next step finds the runner airborne with an air jump
      // available, and one tap becomes a double jump every time.
      final run = _Floor(from: 1.0);
      run.run(30);
      expect(run.runner.isGrounded, isTrue);

      var jumps = 0;
      run.step(holding: _jump);
      if (run.runner.jumpedThisStep) jumps++;
      for (var i = 0; i < 20; i++) {
        run.step();
        if (run.runner.jumpedThisStep) jumps++;
      }

      expect(jumps, 1,
          reason: 'one press produced $jumps jumps, so the buffer outlived the '
              'jump it paid for');
      expect(run.runner.airJumpsLeft, const RunnerTuning().airJumps,
          reason: 'and the air jump was spent by a press nobody made');
    });

    test('and the window is spent once, not held open by the button', () {
      // Mutation: refill `_buffer` from `held` instead of `pressed`. Holding
      // jump then becomes a standing order — the runner leaves the ground again
      // the instant it touches it, which reads as the floor being made of
      // rubber.
      final toGo = fallOf(3.0);
      final run = _Floor(from: 3.0, tuning: noSecondJump);
      run.run(toGo - 3);

      // Counted rather than timed. A jump takes about forty-five steps to come
      // back down, so "is it on the ground yet" cannot tell one jump from an
      // endless chain of them — which is exactly the defect being looked for.
      var jumps = 0;
      for (var i = 0; i < 400; i++) {
        run.step(holding: _jump);
        if (run.runner.jumpedThisStep) jumps++;
      }

      expect(jumps, 1,
          reason: 'holding the button produced $jumps jumps, so the buffer is '
              'refilled by the button being down rather than by a press');
    });
  });
}
