/// How the runner is drawn, without anything drawing it.
///
///     flutter test test/runner_looks_test.dart
///
/// The pose is arithmetic over what the simulation already reports, so it can
/// be tested the way the simulation is: run a body, ask what it should look
/// like, and assert on numbers. That is the whole reason it lives beside
/// `PlatformerLooks` rather than inside `main.dart` — a squash written into the
/// frame loop is a squash nothing can check.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_platformer/src/runner_looks.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

final class _Run {
  _Run() {
    world.add(
      Collider(
        shape: CollisionBox(Vector3(50.0, 0.5, 50.0)),
        position: Vector3(0.0, -0.5, 0.0),
      ),
    );
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: Vector3.zero(),
      random: GameRandom(1),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  final RunnerLooks looks = RunnerLooks();
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
    looks.advance(runner, _dt);
  }

  void run(int steps, {Set<GameAction> holding = const <GameAction>{}}) {
    for (var i = 0; i < steps; i++) {
      step(holding: holding);
    }
  }

  Vector3 get scale => looks.scale;
}

/// How far a scale is from doing nothing.
double _distortion(Vector3 scale) => (scale.y - 1.0).abs();

void main() {
  group('clips', _clipTests);

  test('a body standing still is drawn as itself', () {
    final run = _Run()..run(60);

    expect(run.scale.x, closeTo(1.0, 0.01));
    expect(run.scale.y, closeTo(1.0, 0.01));
  });

  test('a jump stretches it, and a landing squashes it', () {
    // Mutation: give `jumpedThisStep` and `landedThisStep` the same sign. The
    // runner squashes on the way up, which reads as being hit rather than as
    // taking off.
    final run = _Run()..run(30);

    run.step(holding: <GameAction>{GameAction.jump});
    expect(run.scale.y, greaterThan(1.05), reason: 'a jump should stretch');
    expect(run.scale.x, lessThan(1.0), reason: 'and narrow');

    var landed = false;
    for (var i = 0; i < 200 && !landed; i++) {
      run.step();
      landed = run.runner.landedThisStep;
    }
    expect(landed, isTrue);
    expect(run.scale.y, lessThan(0.95), reason: 'a landing should squash');
    expect(run.scale.x, greaterThan(1.0), reason: 'and widen');
  });

  test('it keeps its volume, so a squash is not a shrink', () {
    // Mutation: scale x and z by the same factor as y. The runner gets smaller
    // instead of flatter, which reads as distance rather than as weight.
    final run = _Run()..run(30);
    run.step(holding: <GameAction>{GameAction.jump});

    for (var i = 0; i < 40; i++) {
      final scale = run.scale;
      final volume = scale.x * scale.y * scale.z;
      expect(
        volume,
        closeTo(1.0, 0.02),
        reason: 'the pose changed how big the runner is, not what shape',
      );
      run.step();
    }
  });

  test('a hard landing squashes more than a soft one', () {
    // The reason `landingSpeed` had to exist: without it every landing is the
    // same landing, and a drop from the top of the level looks like a hop.
    //
    // Mutation: ignore `landingSpeed` and use a constant.
    double squashAfterFalling(double from) {
      final run = _Run();
      run.runner.body.teleport(Vector3(0.0, from, 0.0));
      for (var i = 0; i < 400; i++) {
        run.step();
        if (run.runner.landedThisStep) return _distortion(run.scale);
      }
      return 0.0;
    }

    final hop = squashAfterFalling(1.5);
    final drop = squashAfterFalling(25.0);

    expect(hop, greaterThan(0.0));
    expect(
      drop,
      greaterThan(hop * 1.5),
      reason: 'a twenty-five metre fall landed like a hop',
    );
  });

  test('it comes back to standing, and never jumps to get there', () {
    // A pose that snaps back is a pose that pops, and a pop is the one thing a
    // player notices about an animation they were not looking at.
    //
    // Mutation: set `_squash = 0` after a fixed number of steps rather than
    // decaying it.
    final run = _Run()..run(30);
    run.step(holding: <GameAction>{GameAction.jump});

    // Measured from the landing onwards. The events themselves — take-off,
    // touch-down — are *meant* to be instant: a landing squash that eases in
    // has already finished by the time the feet arrive.
    var landed = false;
    for (var i = 0; i < 200 && !landed; i++) {
      run.step();
      landed = run.runner.landedThisStep;
    }
    expect(landed, isTrue);

    var previous = run.scale.y;
    var worstJump = 0.0;
    for (var i = 0; i < 120; i++) {
      run.step();
      final now = run.scale.y;
      final change = (now - previous).abs();
      if (change > worstJump) worstJump = change;
      previous = now;
    }

    expect(worstJump, lessThan(0.06), reason: 'the pose popped');
    expect(run.scale.y, closeTo(1.0, 0.05), reason: 'it never settled');
  });

  test('the recovery is the same at thirty and at a hundred and twenty', () {
    // Frame-rate independence, the same property the camera's lag has and for
    // the same reason.
    //
    // Mutation: `_squash += (0 - _squash) * 0.1` — a per-step constant. The two
    // rates come out different and the game feels different on each monitor.
    double after(double rate, double seconds) {
      final looks = RunnerLooks();
      final run = _Run()..run(30);
      run.step(holding: <GameAction>{GameAction.jump});
      looks.advance(run.runner, 1.0 / rate);
      // One more simulation step, so `jumpedThisStep` is false: the flag stays
      // true until the next one, and advancing the pose against it re-sets the
      // stretch every time. The first draft of this measured the last frame's
      // decay and nothing else.
      run.step();

      final steps = (seconds * rate).round();
      for (var i = 0; i < steps; i++) {
        looks.advance(run.runner, 1.0 / rate);
      }
      return _distortion(looks.scale);
    }

    expect(after(30.0, 0.2), closeTo(after(120.0, 0.2), 0.02));
  });

  test('a double jump turns the runner over once', () {
    // Mutation: leave `_flip` running for ever, or never start it. The first
    // spins the runner for the rest of the level and the second is a double
    // jump that reads exactly like the first one.
    final run = _Run()..run(30);
    run.step(holding: <GameAction>{GameAction.jump});
    run.run(10);
    expect(
      run.looks.spin,
      closeTo(0.0, 0.01),
      reason: 'one jump does not flip',
    );

    run.step();
    run.step(holding: <GameAction>{GameAction.jump});
    expect(
      run.looks.spin.abs(),
      greaterThan(3.0),
      reason: 'the air jump flips',
    );

    run.run(60);
    expect(run.looks.spin, closeTo(0.0, 0.01), reason: 'and it comes back');
  });

  test('running leans it forward and standing still does not', () {
    final run = _Run()..run(30);
    expect(run.looks.lean, closeTo(0.0, 0.02));

    run.run(60, holding: <GameAction>{GameAction.moveForward});
    expect(run.looks.lean, greaterThan(0.1), reason: 'it ran upright');

    run.run(120);
    expect(run.looks.lean, closeTo(0.0, 0.03), reason: 'it stayed leaning');
  });

  test('a crouch is drawn as short as the body actually is', () {
    // **Measured, not tuned.** The number this used to assert was `< 0.8`,
    // against a hand-picked `crouchSquash` that drew the runner at 0.685 while
    // the collider was at 0.5 — a body visibly taller than the gap it had just
    // fitted through. The pose is now read off the body, so the claim can be
    // the exact one.
    //
    // Mutation: put the eyeballed constant back. The drawn height stops
    // matching the collider and this says by how much.
    final run = _Run()..run(30);
    run.run(20, holding: <GameAction>{PlatformerActions.dropThrough});

    expect(run.runner.isCrouching, isTrue);
    final wanted =
        run.runner.body.halfExtents.y / run.runner.standingHalfHeight;
    expect(
      run.scale.y,
      closeTo(wanted, 0.02),
      reason: 'drawn at ${run.scale.y} while the body is at $wanted',
    );
  });

  test('and standing up is not a decay', () {
    // Mutation: fold the crouch into `_squash`, which decays. Standing up then
    // takes a quarter of a second during which the collider is already tall and
    // the picture is not — so the runner walks under a ledge they cannot fit
    // under, on the one frame anybody would screenshot.
    final run = _Run()..run(30);
    run.run(20, holding: <GameAction>{PlatformerActions.dropThrough});
    expect(run.scale.y, lessThan(0.7));

    run.step();
    expect(run.runner.isCrouching, isFalse);
    expect(
      run.scale.y,
      closeTo(1.0, 0.02),
      reason: 'one step after standing up it is still drawn crouched',
    );
  });

  group('feet on the floor', () {
    // The arithmetic a crouch breaks if nobody does it. Pure, so tested
    // directly: the model's feet must land on the body's feet in both shapes,
    // and the body's *centre* is what moves between them.
    const modelFloor = 0.0;

    test('standing, the model sits on the body\'s feet', () {
      final looks = RunnerLooks();
      expect(
        looks.drawnHeight(bodyY: 0.9, halfHeight: 0.9, modelFloor: modelFloor),
        closeTo(0.0, 1e-9),
      );
    });

    test('crouching, it does not sink into the floor', () {
      // Mutation: place the node at a fixed drop from the body's centre, which
      // is what this used to do. The centre falls by 0.45 when the body halves,
      // so the penguin spends every crouch buried to the knees.
      final run = _Run()..run(30);
      final stood = run.runner.body.position.y - run.runner.body.halfExtents.y;

      run.run(20, holding: <GameAction>{PlatformerActions.dropThrough});
      expect(run.runner.isCrouching, isTrue);

      final feet = run.looks.drawnHeight(
        bodyY: run.runner.body.position.y,
        halfHeight: run.runner.body.halfExtents.y,
        modelFloor: modelFloor,
      );
      expect(
        feet,
        closeTo(stood, 0.02),
        reason:
            'the crouched model is drawn ${stood - feet} m into the '
            'floor it is standing on',
      );
    });

    test(
      'and a model whose own origin is not its feet is offset by that much',
      () {
        // `localBounds.min.y` is not zero for every asset, and an asset that
        // carries its own offset must not be drawn floating.
        final looks = RunnerLooks();
        expect(
          looks.drawnHeight(bodyY: 0.9, halfHeight: 0.9, modelFloor: -0.2),
          closeTo(0.2, 1e-9),
          reason:
              'a model whose lowest point is 0.2 below its origin is placed '
              '0.2 higher, so that point lands on the floor',
        );
      },
    );
  });
}

/// Which clip plays, and whether the model has it.
///
/// The state machine is a pure function, so it is tested as one — and the last
/// test is the one that matters most: a clip name this game asks for that the
/// *file* does not contain is a silent no-op, because `crossFadeToNamed`
/// returns false and nothing looks at it.
void _clipTests() {
  test('standing still is idle, and moving is not', () {
    final run = _Run()..run(30);
    expect(RunnerClips.forRunner(run.runner), RunnerClips.idle);

    run.run(60, holding: <GameAction>{GameAction.moveForward});
    expect(RunnerClips.forRunner(run.runner), RunnerClips.run);
  });

  test(
    'the air has two clips, and which one depends on the way you are going',
    () {
      // Mutation: use one clip for both. A jump and a fall look identical, which
      // is the difference between reading a jump and watching a shape rise.
      final run = _Run()..run(30);
      run.step(holding: <GameAction>{GameAction.jump});
      expect(RunnerClips.forRunner(run.runner), RunnerClips.jump);

      for (var i = 0; i < 60; i++) {
        run.step();
        if (run.runner.body.velocity.y < -1.0) break;
      }
      expect(RunnerClips.forRunner(run.runner), RunnerClips.falling);
    },
  );

  test('crouching ducks, and being in the air beats being crouched', () {
    final run = _Run()..run(30);
    run.run(10, holding: <GameAction>{PlatformerActions.dropThrough});
    expect(RunnerClips.forRunner(run.runner), RunnerClips.duck);
  });

  test('a dead runner plays one thing and nothing else', () {
    // Mutation: put the death case anywhere but first. A body that dies while
    // running keeps running.
    final run = _Run()..run(30);
    run.runner.health.damage(1000.0);
    expect(RunnerClips.forRunner(run.runner), RunnerClips.death);
  });

  test('a run clip is played faster the faster the body moves', () {
    // The sliding-feet problem, which is the most noticeable flaw a
    // well-animated character can have.
    //
    // Mutation: return 1.0 always.
    expect(
      RunnerClips.rateFor(RunnerClips.run, 9.0),
      greaterThan(RunnerClips.rateFor(RunnerClips.run, 4.0)),
    );
    expect(RunnerClips.rateFor(RunnerClips.idle, 9.0), 1.0);
  });

  test('the rigged model has every clip this game asks for', () async {
    // **The one that cannot be reasoned about, only checked.** A name that is
    // not in the file makes `crossFadeToNamed` return false, and nothing looks
    // at the answer: the runner would simply keep playing whatever it was.
    //
    // Against `hero.glb`, which the game does *not* load: the penguin is shipped
    // instead. The names are still worth guarding — the clip machinery is wired
    // and the moment that model renders it is what plays — and asserting them
    // against the penguin would assert nothing, because the penguin has no clips
    // at all.
    //
    // **Read from the engine's fixtures**, because that is where the rig lives
    // now: it used to sit in this game's `assets/models/`, which is declared
    // whole, so 424 KB of a model nothing drew went into every download.
    final document = await decodeModel(
      const ModelLoadRequest(
        source: FileAssetSource(
          '../../packages/flutter3d/test/fixtures/hero.glb',
        ),
      ),
    );

    final names = document.animations.map((AnimationClip c) => c.name).toSet();
    for (final wanted in RunnerClips.all) {
      expect(names, contains(wanted), reason: 'the model has no "$wanted"');
    }
  });
}
