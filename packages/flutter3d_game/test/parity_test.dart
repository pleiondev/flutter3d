/// One tape, and the same run wherever it is played.
///
///     flutter test test/parity_test.dart                  # this machine's VM
///     flutter test --platform chrome test/parity_test.dart # a browser
///
/// **This is the measurement the cloud service is not allowed to be built
/// before.** A run is submitted to a server as the inputs that produced it, and
/// the server does not believe the score it was sent — it replays the tape and
/// works the score out itself. That proof is worth nothing unless the server's
/// replay is the same run as the player's, to the last bit, on a different
/// processor and a different operating system and, for a game published to the
/// web, in a browser rather than in the VM at all.
///
/// Whether it is, is not something to assume. Dart's doubles are IEEE 754 and
/// its arithmetic is exact, and so is `sqrt`, which the specification pins to
/// the correctly rounded result. `sin`, `cos`, `atan2`, `pow`, `exp` and `log`
/// are pinned by nothing: on the VM they are the host's libm and in a browser
/// they are whatever that engine ships, and two libms disagreeing in the last
/// place is ordinary rather than exceptional.
///
/// So the file asks three questions, cheapest first, and each one narrows the
/// last:
///
///   1. **Does the instrument read the same everywhere?** A digest that is not
///      itself portable would report a divergence on every browser for ever.
///   2. **Which primitives are portable?** A table of `dart:math` over fixed
///      inputs, one digest apiece, so a failure names the function rather than
///      the run.
///   3. **Does a thousand steps of a body through a room come out the same?**
///      The whole thing: a tape, a collision world, a character controller, the
///      dice, and a query per step through the broadphase.
///
/// The committed numbers were recorded on macOS-arm64. Every other platform
/// compares against them, which is what makes this one file the parity test
/// rather than three of them: `tool/ci.sh` already runs this package under the
/// VM and under Chrome, so a third machine asks the same question of the same
/// bytes without another line being written.
///
/// ## What it answered, the day it was written
///
/// **All forty checkpoints of question 3 are identical between the VM and
/// Chrome**, on the same processor, the same day. Of question 2's ten
/// functions, eight agree and `tan` and `atan` do not — and both of those have
/// a substitute in the same table that is portable and is bit-identical to one
/// of the two native answers.
///
/// So the answer is not "floating point is not portable". It is "two named
/// functions are not, and here is what to call instead". `ARCHITECTURE.md`
/// §9.3, which asserted the broad version of that as a reason not to build a
/// verifying server at all, is rewritten to the measured one.
///
/// **If question 3 ever fails while question 2 passes**, the divergence is in
/// the simulation rather than in the arithmetic — a collection walked in hash
/// order, an integer packed past bit 31 — and [Divergence] names the checkpoint
/// to bisect from. If a row of question 2 gains a new answer on a platform
/// nobody has measured, that function joins `tan` and `atan`: nothing in a step
/// may call it, and the row says so out loud rather than the run failing
/// somewhere downstream of it.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('the instrument', () {
    test('reads the same number on every platform', () {
      // A structure holding one of everything a snapshot may hold. If this
      // number differs between the VM and a browser then nothing below it can
      // be believed, which is why it is the first thing asked.
      expect(StateDigest.of(_shapes), _shapesDigest);
    });

    test('cannot tell 3 from 3.0, because the web cannot', () {
      // Deliberate, and the reason is in `state_digest.dart`: on the web `3`
      // *is* `3.0`, so an instrument that distinguished them would disagree
      // with itself across platforms on every run.
      expect(StateDigest.of(3), StateDigest.of(3.0));
      expect(
        StateDigest.of(<Object?>[1, 2]),
        StateDigest.of(<Object?>[1.0, 2.0]),
      );
    });

    test('does not depend on the order a map was built in', () {
      // The order fields are written in belongs to the code that writes them,
      // not to the state. Two restores that disagree about it are the same
      // world.
      final one = <String, Object?>{'a': 1, 'b': 2, 'c': 3};
      final other = <String, Object?>{'c': 3, 'a': 1, 'b': 2};
      expect(StateDigest.of(one), StateDigest.of(other));
    });

    test('folds negative zero into zero, because dart2js does', () {
      // **Measured, not assumed.** A `-0.0` written as a literal keeps its sign
      // on both platforms; a `-0.0` sitting inside a `const` structure does not
      // survive dart2js's constant canonicalisation, and comes out of a browser
      // as a plain zero. An instrument that told the two apart would report a
      // divergence between the VM and the browser that no simulation caused —
      // which is what this test is here to stop somebody "fixing".
      expect(StateDigest.of(-0.0), StateDigest.of(0.0));
      expect(StateDigest.of(<double>[-0.0]), StateDigest.of(<double>[0.0]));
      expect(
        (-0.0).isNegative,
        isTrue,
        reason: 'the value itself is unchanged',
      );
    });

    test('tells apart the things that are different', () {
      // A digest whose collisions are easy is an instrument that reports
      // agreement it did not find. These are the near-misses worth naming:
      // nesting, emptiness, and a value against the list holding it.
      final numbers = <int>{
        StateDigest.of(null),
        StateDigest.of(false),
        StateDigest.of(0),
        StateDigest.of(''),
        StateDigest.of(<Object?>[]),
        StateDigest.of(<Object?>[<Object?>[]]),
        StateDigest.of(<String, Object?>{}),
        StateDigest.of(<Object?>[1]),
        StateDigest.of(1),
        StateDigest.of(<String, Object?>{'a': 1}),
        StateDigest.of(<String, Object?>{'ab': 1}),
      };
      expect(numbers, hasLength(11));
    });

    test('refuses what a snapshot could not have held', () {
      // Silently skipping an unhashable value is the failure mode that matters:
      // two different worlds would then agree. A `Vector3` reaching this is the
      // realistic mistake, because half the simulation is made of them.
      expect(
        () => StateDigest.of(Vector3.zero()),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => StateDigest.of(<Object?, Object?>{1: 'a'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('a trace', () {
    test('takes a checkpoint every so many steps and no others', () {
      final trace = DigestTrace(every: 25);
      for (var step = 1; step <= 100; step++) {
        trace.observe(step, <String, Object?>{'step': step});
      }
      expect(trace.steps, <int>[25, 50, 75, 100]);
    });

    test('names the first checkpoint two runs disagree at', () {
      final trace = DigestTrace(every: 10);
      for (var step = 1; step <= 40; step++) {
        trace.observe(step, <String, Object?>{'step': step});
      }
      final expected = List<int>.of(trace.digests);
      expect(trace.divergenceFrom(expected), isNull);

      // The third checkpoint, and not the fourth, which also differs.
      expected[2] = ~expected[2] & 0xFFFFFFFF;
      expected[3] = ~expected[3] & 0xFFFFFFFF;
      expect(trace.divergenceFrom(expected)?.step, 30);
    });

    test('counts a run that stopped early as a divergence', () {
      // Not a shorter agreement. A replay that ran out of steps is exactly the
      // symptom of a simulation that took a different branch, and reporting it
      // as "matched as far as it went" is how that gets missed.
      final trace = DigestTrace(every: 10);
      for (var step = 1; step <= 20; step++) {
        trace.observe(step, <String, Object?>{'step': step});
      }
      final short = <int>[trace.digests.first];
      expect(trace.divergenceFrom(short)?.step, 20);
      expect(trace.divergenceFrom(short)?.expected, isNull);
    });
  });

  group('the primitives a step is built from', () {
    // Asked one function at a time so that a failure names the function. The
    // arguments are awkward on purpose: values whose results are near a
    // rounding boundary are where two libms part company, and a table of round
    // numbers would report agreement that means nothing.
    for (final probe in _probes) {
      final claim = probe.portable
          ? '${probe.name} is the same function everywhere'
          : '${probe.name} is one of the two functions it is known to be';
      test(claim, () {
        final digest = StateDigest.of(<double>[
          for (final x in _arguments) probe.of(x),
        ]);
        expect(
          probe.digests,
          contains(digest),
          reason: probe.portable
              ? 'dart:math\'s ${probe.name} gave bits here that no platform has '
                    'given before. Either this platform has its own libm and '
                    'nothing in a step may call ${probe.name} until it is '
                    'replaced, or the recorded number is stale — and which of '
                    'those it is has to be decided before the number is '
                    'updated.'
              : '${probe.name} is already known to differ between the VM and a '
                    'browser and this is a third answer. Nothing may call it '
                    'in a step either way; the row exists so that a new '
                    'platform says so out loud.',
        );
      });
    }

    test('the substitutes give the same answers as what they replace', () {
      // Not bit-identical — that is the whole point, one of the two is wrong
      // somewhere — but the same function to within a rounding or two, so that
      // swapping them is a portability fix and not a physics change.
      //
      // Relative rather than absolute, because `tan` near a right angle is in
      // the tens of quadrillions and an absolute tolerance there would be
      // asking for more than either function promises.
      void agrees(double a, double b) {
        final scale = b.abs() > 1.0 ? b.abs() : 1.0;
        expect((a - b).abs() / scale, lessThan(1e-12));
      }

      for (final x in _arguments) {
        agrees(math.sin(x) / math.cos(x), math.tan(x));
        agrees(math.atan2(x, 1.0), math.atan(x));
      }
    });
  });

  group('a thousand steps of a body through a room', () {
    test('is the same run as the one that was recorded', () {
      final trace = _play(_tape(seed: 20260902, steps: 1000));
      final divergence = trace.divergenceFromHex(_recorded);
      expect(
        divergence,
        isNull,
        reason:
            'the tape played to a different run here than on macOS-arm64: '
            '$divergence. Bisect between that checkpoint and the one before '
            'it; if the primitives group above is green the cause is in the '
            'simulation, not in the arithmetic.',
      );
    });

    test('and playing it twice in one process gives the same run twice', () {
      // The weaker question, and the one that would still be worth asking if
      // the recorded numbers were ever thrown away: a simulation that is not
      // repeatable against itself has a clock or a loose die in it, and the
      // cross-platform question does not arise.
      final tape = _tape(seed: 7, steps: 300);
      expect(_play(tape).digests, _play(tape).digests);
    });

    test('and a different tape is a different run', () {
      // The instrument reports agreement it has not found if the trace is
      // dominated by something the tape cannot move.
      expect(
        _play(_tape(seed: 7, steps: 300)).digests,
        isNot(_play(_tape(seed: 8, steps: 300)).digests),
      );
    });
  });
}

/// One of everything a snapshot may hold, in one value.
const Map<String, Object?> _shapes = <String, Object?>{
  'nothing': null,
  'yes': true,
  'no': false,
  'whole': 3,
  'fraction': 0.1,
  'tiny': 5e-324,
  'huge': 1.7976931348623157e308,
  'negativeZero': -0.0,
  'text': 'a wall, a door, and a monster called Ыдра 🜁',
  'empty': <Object?>[],
  'list': <Object?>[1, 2.5, 'three', null, true],
  'nested': <String, Object?>{
    'at': <double>[1.5, -2.25, 0.125],
    'deeper': <String, Object?>{
      'still': <Object?>[<Object?>[]],
    },
  },
};

/// Recorded on macOS-arm64, 2026-09-02, and matched by Chrome on the same day.
const int _shapesDigest = 3856425528;

/// A function of one number that a step might call, and every answer any
/// platform has been seen to give for it.
///
/// A set rather than a number, because two of these have two answers and
/// pretending otherwise would mean either a permanently red suite or a silent
/// hole. A third answer turning up on a platform nobody has measured is then
/// news rather than noise: the test names the function and says a new one
/// appeared.
final class _Probe {
  const _Probe(this.name, this.of, this.digests, {this.portable = true});

  final String name;
  final double Function(double) of;

  /// Every digest measured. One entry means the function is the same function
  /// everywhere it has been asked.
  final List<int> digests;

  /// Whether a step may call it.
  final bool portable;
}

/// Arguments chosen to land near rounding boundaries rather than on round
/// numbers, and to cover the ranges a simulation actually uses: angles either
/// side of a right angle, small deltas, and one value large enough that
/// argument reduction has work to do.
const List<double> _arguments = <double>[
  0.0,
  1e-8,
  0.1,
  0.3333333333333333,
  0.7071067811865476,
  1.0,
  1.5707963267948966,
  2.0,
  3.141592653589793,
  6.283185307179586,
  12.566370614359172,
  1234.5678901234567,
];

/// Measured on macOS-arm64 under the VM and under Chrome, 2026-09-02.
///
/// `sqrt` is here despite being pinned by the specification to the correctly
/// rounded result, because a row that cannot fail is what tells the others
/// apart from a broken harness.
///
/// **Eight of the ten came back identical and two did not.** `tan` and `atan`
/// are different functions in the two places, in the last bits, which is enough
/// — a simulation is a feedback loop and a last-bit difference is a divergence
/// a few hundred steps later. Both have a portable substitute measured in this
/// same table, and the substitutes are in it for that reason: `tan(x)` is
/// `sin(x) / cos(x)` and `atan(x)` is `atan2(x, 1)`, and all three of `sin`,
/// `cos` and `atan2` agreed.
final List<_Probe> _probes = <_Probe>[
  _Probe('sqrt', (double x) => math.sqrt(x.abs()), <int>[560576848]),
  _Probe('sin', math.sin, <int>[2430477820]),
  _Probe('cos', math.cos, <int>[14733917]),
  _Probe('asin', (double x) => math.asin(x % 1.0), <int>[2942591821]),
  _Probe('atan2', (double x) => math.atan2(x, 1.375), <int>[1492665211]),
  _Probe('exp', (double x) => math.exp(x % 4.0), <int>[1121925872]),
  _Probe('log', (double x) => math.log(x + 1.0), <int>[3036108384]),
  _Probe('pow', (double x) => math.pow(x, 1.5) as double, <int>[1951188195]),

  // The substitutes, measured so that the fix to the two rows below is a
  // change somebody can make without having to re-run this file to find out
  // whether it helped.
  //
  // **Each of them is bit-identical to one platform's native answer**, which
  // is a stronger result than the one being asked for: `sin(x) / cos(x)` is
  // the VM's `tan` exactly, and `atan2(x, 1)` is the browser's `atan` exactly.
  // So swapping is not a compromise between two libms — it is picking one of
  // them and getting it everywhere.
  _Probe('sin over cos', (double x) => math.sin(x) / math.cos(x), <int>[
    3249999797,
  ]),
  _Probe('atan2 against one', (double x) => math.atan2(x, 1.0), <int>[
    4284275088,
  ]),

  // VM first, browser second.
  _Probe('tan', math.tan, <int>[3249999797, 3294569714], portable: false),
  _Probe('atan', math.atan, <int>[1237910714, 4284275088], portable: false),
];

/// The room the run is played in.
///
/// Hand-built rather than loaded, because a browser test has no file system and
/// because a level document read from disk would make this a test of the
/// loader. What it has is what the run needs to touch: a floor to stand on,
/// walls to be stopped by, a lattice of pillars so the broadphase has more than
/// one cell to bin and a sweep has more than one candidate, and a flight of
/// steps so the step-up and the floor snap both run.
CollisionWorld _room() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
    ..addBox(Vector3(0.0, 2.0, -20.0), Vector3(40.0, 6.0, 1.0))
    ..addBox(Vector3(0.0, 2.0, 20.0), Vector3(40.0, 6.0, 1.0))
    ..addBox(Vector3(-20.0, 2.0, 0.0), Vector3(1.0, 6.0, 40.0))
    ..addBox(Vector3(20.0, 2.0, 0.0), Vector3(1.0, 6.0, 40.0));
  for (var x = -3; x <= 3; x++) {
    for (var z = -3; z <= 3; z++) {
      if ((x + z) % 2 == 0) continue;
      world.addBox(Vector3(x * 4.0, 2.0, z * 4.0), Vector3(1.4, 6.0, 1.4));
    }
  }
  for (var i = 0; i < 6; i++) {
    final top = 0.3 * (i + 1);
    world.addBox(
      Vector3(8.0, top / 2.0, -6.0 - i.toDouble()),
      Vector3(6.0, top, 1.0),
    );
  }
  return world;
}

/// A run, generated rather than written down.
///
/// The tape is a thousand frames and would be a thousand lines of literal in
/// this file; it is rolled from a [GameRandom] instead, which is the one
/// generator this repository has already proved gives the same sequence
/// everywhere — `determinism_test.dart` is that proof, and it is the reason
/// this may be done without weakening the question.
InputTape _tape({required int seed, required int steps}) {
  final dice = GameRandom(seed);
  return InputTape(
    seed: seed,
    frames: <InputFrame>[
      for (var i = 0; i < steps; i++)
        InputFrame(
          pressed: dice.nextInt(37) == 0
              ? const <String>['jump']
              : const <String>[],
          stickX: dice.nextDouble() * 2.0 - 1.0,
          stickY: dice.nextDouble() * 2.0 - 1.0,
          lookX: (dice.nextDouble() - 0.5) * 0.09,
        ),
    ],
  );
}

/// Plays [tape] and returns the digest of the world every twenty-five steps.
///
/// The path is the shipped one — an [InputState] written by an
/// [InputTapePlayback], a fixed `dt`, a [CharacterController] against a
/// [CollisionWorld] — rather than a loop that moves a position directly. A
/// parity test of arithmetic nothing calls would be green about nothing.
DigestTrace _play(InputTape tape, {int every = 25}) {
  final world = _room();
  final body = CharacterController(
    world: world,
    position: Vector3(0.0, 1.0, 6.0),
  );
  final dice = GameRandom(tape.seed);
  final playback = InputTapePlayback(tape);
  final input = InputState();
  final trace = DigestTrace(every: every);
  final wish = Vector3.zero();
  final floor = RayHit();
  final down = Vector3(0.0, -1.0, 0.0);
  const dt = 1.0 / 60.0;

  var yaw = 0.0;
  for (var step = 1; step <= tape.frames.length; step++) {
    playback.applyTo(input);

    // The trigonometry a first-person control scheme cannot avoid: a stick is
    // read in the body's frame and the world wants it in its own.
    yaw += input.lookDelta.x;
    final forward = math.cos(yaw);
    final side = math.sin(yaw);
    final move = input.moveAxis;
    wish.setValues(
      move.x * forward + move.y * side,
      0.0,
      move.y * forward - move.x * side,
    );
    final length = wish.length;
    if (length > 1e-6) wish.scale(1.0 / length);

    if (input.pressed(GameAction.jump)) body.requestJump();
    body.step(dt, wishDirection: wish, sprint: dice.nextBool());
    world.update();

    // A query as well as a step, because a query walks the broadphase, and the
    // broadphase packs a cell's three coordinates into one integer — which is
    // the shape of every defect this repository has found that only a browser
    // could see.
    world.raycast(body.position, down, 4.0, floor);

    input.endStep();

    trace.observe(step, <String, Object?>{
      'body': body.save(),
      'dice': dice.state,
      'yaw': yaw,
      'grounded': body.isGrounded,
      'floor': floor.distance,
      'floorNormal': <double>[floor.normal.x, floor.normal.y, floor.normal.z],
    });
  }
  return trace;
}

/// Recorded on macOS-arm64, 2026-09-02: forty checkpoints, one every
/// twenty-five steps of a thousand.
///
/// **Chrome on the same machine reproduced all forty on the day they were
/// written**, which is the first half of the answer the year's plan was waiting
/// for. The second half is Linux, and it is not asked here — `tool/ci.sh` runs
/// this package on the VM and under Chrome, and CI's machines are the third
/// platform. A red row on one of them is the result, not a breakage: it says
/// the cloud service has to carry a checksum per interval and quarantine on a
/// mismatch rather than trusting a whole-run comparison.
const List<String> _recorded = <String>[
  'c520c154',
  '9af8158a',
  'd13b7674',
  '0f9db809',
  '14fc0650',
  'a6dc93da',
  '5100b198',
  '82812341',
  '51e0ec96',
  '3822350d',
  'e44d5e92',
  '084fb3f7',
  'faa42b93',
  '5c64e512',
  '1baccb9c',
  '18c6c624',
  '1679b0f4',
  '25903db7',
  '4f88287b',
  '6cc18752',
  'ec9c7533',
  '1b06238f',
  'eea0d6c4',
  '2989f158',
  '983ac32c',
  '0058789b',
  '3c63d6f6',
  '24d60127',
  '4ed4ca85',
  'a82b54b5',
  '356743f5',
  'd8f4aa2e',
  'f8eca0c6',
  '30f37585',
  '6987d8cb',
  '3a5a8853',
  'acff5788',
  'f7ef3bc0',
  '6aa9f123',
  'b3fd5b9f',
];
