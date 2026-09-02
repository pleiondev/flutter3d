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
/// the correctly rounded result. The transcendentals are pinned by nothing: on
/// the VM they are the host's libm and in a browser they are whatever that
/// engine ships.
///
/// So the file asks three questions, cheapest first, and each one narrows the
/// last:
///
///   1. **Does the instrument read the same everywhere?** A digest that is not
///      itself portable would report a divergence on every browser for ever.
///   2. **Which primitives are portable?** Twelve `dart:math` functions over
///      twenty thousand arguments apiece, one digest each, so an answer names
///      the function rather than the run.
///   3. **Does a thousand steps of a body through a room come out the same?**
///      The whole thing: a tape, a collision world, a character controller, the
///      dice, and a query per step through the broadphase.
///
/// ## What it answered, and the correction that came with it
///
/// **Question 2: two functions of twelve are portable** — `sqrt` and `pow` —
/// and every transcendental gives different bits in a browser than in the VM,
/// including every combination of them. There is nothing portable to build a
/// substitute out of.
///
/// **Question 3: all forty checkpoints matched anyway.** Those two answers are
/// not in conflict and the gap between them is the useful part. Two libms
/// disagree on a small fraction of arguments; a run reaches the arguments it
/// reaches; a thousand steps of a character controller happened to reach none
/// of the disagreeing ones. `flutter3d_game_racing/test/parity_test.dart` is
/// the counter-example — the same measurement on a car diverges at exactly one
/// checkpoint out of forty — so "a run replays identically" is a thing that is
/// usually true and cannot be relied on.
///
/// **The first version of this file got question 2 wrong**, and the way it did
/// is worth keeping. It sampled twelve hand-picked arguments, concluded that
/// eight of ten functions were portable, and offered `sin(x) / cos(x)` and
/// `atan2(x, 1)` as portable substitutes for the two that were not. All of it
/// was an artefact of the sample size: at twenty thousand arguments the eight
/// are not portable either and neither substitute is. A test of where two
/// implementations agree will report that they agree.
///
/// ## What this means for a verifying server
///
/// Not that it cannot be built — question 3 says a replay usually is exact —
/// but that it cannot trust a whole-run comparison. It has to carry the
/// checkpoints, compare them interval by interval, and treat a mismatch as a
/// quarantine to look at rather than as a player caught cheating. That is the
/// contingency the year's plan wrote down, and it is the one that applies.
///
/// The committed numbers were recorded on macOS-arm64 under the VM and under
/// Chrome. `tool/ci.sh` runs this package on both platforms, so its machines
/// are a third measurement asking the same question of the same bytes; a
/// function gaining a third answer there is a result, not a breakage.
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
    // Asked one function at a time so that a failure names the function rather
    // than the run.
    //
    // **Twenty thousand arguments and not a dozen.** The first version of this
    // group used twelve hand-picked values and reported that eight of the ten
    // functions were portable. That was wrong, and it was wrong in the
    // direction that costs the most: it gave a clean bill of health to `sin`,
    // `cos`, `atan2`, `exp` and `log`, and a substitution built on top of that
    // answer went into the racing physics before a wider sweep took it back
    // out. Two libms agree almost everywhere; a dozen samples is a test of
    // where they agree, and the interesting arguments are the rare ones.
    for (final probe in _probes) {
      final claim = probe.portable
          ? '${probe.name} is the same function everywhere'
          : '${probe.name} is one of the answers it is known to give';
      test(claim, () {
        expect(
          probe.digests,
          contains(
            StateDigest.of(<double>[
              for (var i = 0; i < _sweep; i++) probe.at(i),
            ]),
          ),
          reason: probe.portable
              ? 'dart:math\'s ${probe.name} was the same function on every '
                    'platform measured, and is not on this one. A step may '
                    'call it today; if this is right, a step may not.'
              : '${probe.name} is known to differ between platforms and this '
                    'is an answer no platform has given before. Nothing in a '
                    'step may call it either way — the row is here so a new '
                    'machine says which arithmetic it has, out loud, rather '
                    'than a run failing somewhere downstream of it.',
        );
      });
    }
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

/// A function a step might call, and every answer any platform has been seen
/// to give for it over the sweep below.
///
/// A set rather than a number, because most of these have two answers already.
/// A third turning up on a machine nobody has measured is then news rather than
/// noise: the test names the function and says a new one appeared.
final class _Probe {
  const _Probe(this.name, this.at, this.digests, {this.portable = false});

  final String name;

  /// The function at the *i*th argument of the sweep.
  final double Function(int i) at;

  /// Every digest measured. One entry means the function came back the same on
  /// every platform asked.
  final List<int> digests;

  /// Whether a step may call it.
  final bool portable;
}

/// How many arguments each function is asked about.
///
/// Twenty thousand rather than twelve, for the reason the group above gives,
/// and not two hundred thousand: at twenty thousand every divergence that the
/// larger sweep found is already found, and the file costs a second and a half
/// on the VM instead of fifteen.
const int _sweep = 20000;

/// The arguments, rolled rather than written out.
///
/// Four magnitudes in rotation — inside the unit circle, a couple of turns
/// either way, a thousand, and a ten-thousandth — because the places two libms
/// part company are spread over the range rather than clustered anywhere a
/// person would think to look. [GameRandom] is the generator for the reason the
/// tape below uses it: it is the one this repository has proved gives the same
/// sequence everywhere, so the *arguments* are identical on both platforms even
/// when the answers are not.
List<double> _sweepArguments(int seed) {
  final dice = GameRandom(seed);
  return <double>[
    for (var i = 0; i < _sweep; i++)
      switch (i % 4) {
        0 => dice.nextDouble() * 2.0 - 1.0,
        1 => (dice.nextDouble() * 2.0 - 1.0) * math.pi * 2.0,
        2 => (dice.nextDouble() * 2.0 - 1.0) * 1000.0,
        _ => (dice.nextDouble() * 2.0 - 1.0) * 1e-4,
      },
  ];
}

final List<double> _a = _sweepArguments(1);
final List<double> _b = _sweepArguments(2);

/// Measured on macOS-arm64 under the VM and under Chrome, 2026-09-02.
///
/// **Two functions out of twelve are the same function in both places**, and
/// they are the two the specification pins rather than the two anybody would
/// have guessed: `sqrt`, which IEEE 754 requires to be correctly rounded, and
/// `pow` at the one exponent asked about here. Every transcendental differs —
/// `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log` — and so
/// does every combination of them, which is why there is no substitute row in
/// this table any more. There is nothing portable to build one out of.
///
/// The VM's answer is first in each pair and the browser's second.
final List<_Probe> _probes = <_Probe>[
  _Probe('sqrt', (int i) => math.sqrt(_a[i].abs()), <int>[
    3731598178,
  ], portable: true),
  _Probe('pow', (int i) => math.pow(_a[i].abs(), 1.5) as double, <int>[
    1010605104,
  ], portable: true),

  _Probe('sin', (int i) => math.sin(_a[i]), <int>[1529023637, 2189972239]),
  _Probe('cos', (int i) => math.cos(_a[i]), <int>[278506023, 346840732]),
  _Probe('tan', (int i) => math.tan(_a[i]), <int>[1991664472, 706737394]),
  _Probe('asin', (int i) => math.asin(_a[i].abs() % 1.0), <int>[
    1169059466,
    3965097627,
  ]),
  _Probe('acos', (int i) => math.acos(_a[i].abs() % 1.0), <int>[
    1074980516,
    2412058023,
  ]),
  _Probe('atan', (int i) => math.atan(_a[i]), <int>[2151501439, 711472516]),
  _Probe('atan2', (int i) => math.atan2(_a[i], _b[i]), <int>[
    4076892957,
    386132713,
  ]),
  _Probe('exp', (int i) => math.exp(_a[i] % 4.0), <int>[1225667539, 184235517]),
  _Probe('log', (int i) => math.log(_a[i].abs() + 1e-3), <int>[
    3156546821,
    2348571721,
  ]),
  _Probe('sin over cos', (int i) => math.sin(_a[i]) / math.cos(_a[i]), <int>[
    3918902778,
    2137336336,
  ]),
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
