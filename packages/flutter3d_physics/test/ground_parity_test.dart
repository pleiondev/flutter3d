/// A body walking over sampled ground, and whether it walks the same way
/// everywhere.
///
///     dart test test/ground_parity_test.dart
///     dart test --platform chrome test/ground_parity_test.dart
///
/// **New arithmetic in a step has to be asked this question before it is
/// believed.** A replay is only evidence if the same tape produces the same run
/// on a verifying server as on the player's machine, and `CollisionHeightfield`
/// put a good deal of new arithmetic inside a step: a cross product per
/// triangle, a square root to normalise it, a floor-and-clamp per axis to find
/// a cell, and a walk over parts whose *order* is decided by two nested loops
/// over integers. Every one of those is a place two platforms could part
/// company.
///
/// ## What was predicted, and why it was still worth measuring
///
/// Nothing here calls a transcendental — `sqrt` is the one function of
/// `dart:math` the specification pins, and the structure rule `a step asks no
/// machine for an answer` is what keeps it that way — so the prediction was
/// that this matches. A prediction is not a measurement, and this one had three
/// ways to be wrong that have nothing to do with `dart:math`:
///
///  * **`Float32List`.** The samples are stored as single-precision floats and
///    read back as doubles. The rounding on the way in is IEEE and the same
///    everywhere; the way a browser *stores* a typed array is not obviously the
///    same thing, and this file is where that stops being an assumption.
///  * **`floor` and `clamp` on the cell index.** Which cell a coordinate falls
///    in is an integer, and an `int` in a browser is a `double` — the trap that
///    has cost this repository three defects, all of them invisible outside a
///    browser, and all of them in code that looked like arithmetic.
///  * **The order the parts come back in.** Two nested loops over cells, and
///    the nearest contact wins by a strict `<`. Two parts at exactly the same
///    distance — which is what a body standing on a join *is* — are separated
///    by the order they were walked, and nothing else.
///
/// ## What is digested, and why not `StateDigest`
///
/// The instrument the rest of the repository uses lives in `flutter3d_sim`,
/// which depends on this package: reaching for it here would make a circle out
/// of a line. So the fold is written out below — the same FNV-1a over the bytes
/// of doubles, with the same halved multiply, and for the same reason: a
/// 32-by-32 multiply is the one operation a browser gets silently wrong.
library;

import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a walk over sampled ground', () {
    test('is the walk that was recorded, wherever it is walked', () {
      final trace = _walk(steps: 600);
      final divergence = _divergence(trace, _recorded);
      expect(
        divergence,
        isNull,
        reason:
            'the same tape produced a different walk here: $divergence. '
            'Nothing in `flutter3d_physics` calls a function whose answer '
            'belongs to the machine, so look at what decides an order or an '
            'integer: the cell index the ground is read by, the two loops that '
            'hand back the triangles near a body, the broadphase\'s cells.',
      );
    });

    test('and walking it twice in one process walks it the same way', () {
      // The weaker question, and the one that would still be worth asking if
      // the recorded numbers were thrown away: a step that disagrees with
      // itself has a clock or an identity hash in it, and the cross-platform
      // question does not arise.
      expect(_walk(steps: 600), _walk(steps: 600));
    });

    test('and over the whole trace the body goes somewhere and stays on the '
        'ground', () {
      // Without this the file could be recording that a body which never moved
      // failed to move on both platforms, which is true and worth nothing.
      final world = _world();
      final walker = _walker(world);
      final crates = _crates(world);
      final was = walker.position.clone();
      var travelled = 0.0;
      var airborne = 0;

      for (var step = 1; step <= 600; step++) {
        _stepAll(walker, crates, step);
        travelled += walker.position.distanceTo(was);
        was.setFrom(walker.position);
        if (!walker.isGrounded) airborne++;
      }

      // The ground it covered, not where it ended up: the walk is a square, so
      // it comes back to where it started and a displacement would report that
      // as having gone nowhere.
      expect(
        travelled,
        greaterThan(30.0),
        reason: 'the body never went anywhere',
      );
      expect(
        walker.position.y,
        greaterThan(-2.0),
        reason: 'the body fell through the ground',
      );
      expect(
        airborne,
        lessThan(200),
        reason:
            'the body spent most of the trace in the air, so the ground '
            'contact this file is measuring is barely in it',
      );
      expect(
        crates.bodies.every((body) => body.position.y > -2.0),
        isTrue,
        reason: 'a crate fell through the ground',
      );
    });
  });
}

const double _dt = 1.0 / 60.0;

/// Ground with a pattern in it rather than a hill, so the walk crosses joins,
/// climbs, descends and turns corners inside six hundred steps.
///
/// The heights come out of the integers of the grid — a remainder of a product,
/// which is exact on both platforms while the numbers stay under 2^53 — rather
/// than out of a generator, because the one generator this repository has
/// proved portable lives in `flutter3d_sim` and this package is underneath it.
CollisionWorld _world() {
  const n = 33;
  final heights = Float32List(n * n);
  for (var row = 0; row < n; row++) {
    for (var column = 0; column < n; column++) {
      // Gentle on purpose, and it was tuned by measuring: a rougher field at
      // six metres a second launches the body off every ridge, and a trace of
      // something mostly airborne is a trace with very little ground contact
      // in it. A quarter of a metre of rise per metre travelled at the very
      // worst, which is a fourteen-degree slope.
      heights[row * n + column] =
          0.03 * ((column * 5 + row * 3) % 7) +
          0.02 * ((column * 3 + row * 11) % 5);
    }
  }
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionHeightfield(
          columns: n,
          rows: n,
          cellSize: 1.0,
          heights: heights,
        ),
        position: Vector3.zero(),
      ),
    );
  world.update();
  return world;
}

CharacterController _walker(CollisionWorld world) =>
    CharacterController(world: world, position: Vector3(-2.0, 2.0, -2.0));

/// Four crates, so the solver's own path over the ground is in the trace too.
Dynamics _crates(CollisionWorld world) {
  final dynamics = Dynamics(world: world);
  for (var i = 0; i < 4; i++) {
    dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.35)),
        position: Vector3(-4.0 + i * 1.7, 4.0 + i * 0.6, -3.0 + i * 1.3),
        friction: 0.5,
      ),
    );
  }
  return dynamics;
}

/// One step of everything, with the walker steered on a square so the trace
/// covers every direction the ground can lean.
void _stepAll(CharacterController walker, Dynamics crates, int step) {
  final leg = (step ~/ 100) % 4;
  final wish = switch (leg) {
    0 => Vector3(1.0, 0.0, 0.0),
    1 => Vector3(0.0, 0.0, 1.0),
    2 => Vector3(-1.0, 0.0, 0.0),
    _ => Vector3(0.0, 0.0, -1.0),
  };
  if (step % 199 == 0) walker.requestJump();
  walker.step(_dt, wishDirection: wish);
  crates.step(_dt);
  crates.world.update();
}

/// The digest of the whole scene every fifteen steps.
List<String> _walk({required int steps, int every = 15}) {
  final world = _world();
  final walker = _walker(world);
  final crates = _crates(world);
  final trace = <String>[];

  for (var step = 1; step <= steps; step++) {
    _stepAll(walker, crates, step);
    if (step % every != 0) continue;
    final digest = _Digest()
      ..vector(walker.position)
      ..vector(walker.velocity)
      ..vector(walker.groundNormal)
      ..flag(walker.isGrounded);
    for (final body in crates.bodies) {
      digest
        ..vector(body.position)
        ..vector(body.velocity);
    }
    trace.add(digest.hex);
  }
  return trace;
}

/// Where two traces of the same tape parted company, or null.
String? _divergence(List<String> found, List<String> expected) {
  final shared = found.length < expected.length
      ? found.length
      : expected.length;
  for (var i = 0; i < shared; i++) {
    if (found[i] != expected[i]) {
      return 'checkpoint $i (step ${(i + 1) * 15}): '
          'expected ${expected[i]}, found ${found[i]}';
    }
  }
  if (found.length == expected.length) return null;
  return 'the trace is ${found.length} checkpoints and the expectation is '
      '${expected.length}';
}

/// FNV-1a over the bytes of doubles. See the head of this file for why it is
/// here rather than imported, and `StateDigest` in `flutter3d_sim` for the
/// argument behind every line of it.
final class _Digest {
  int _hash = 0x811C9DC5;

  static const int _prime = 16777619;
  static const int _wrap = 4294967296;
  static final ByteData _scratch = ByteData(8);

  String get hex => _hash.toRadixString(16).padLeft(8, '0');

  void vector(Vector3 value) {
    number(value.x);
    number(value.y);
    number(value.z);
  }

  void flag(bool value) => _byte(value ? 1 : 0);

  void number(double value) {
    // Negative zero folded into zero, and a NaN written as one fixed pattern:
    // both are differences two platforms produce without a simulation having
    // caused them.
    if (value.isNaN) {
      _byte(0x7F);
      _byte(0xF8);
      for (var i = 0; i < 6; i++) {
        _byte(0);
      }
      return;
    }
    _scratch.setFloat64(0, value == 0 ? 0.0 : value);
    for (var i = 0; i < 8; i++) {
      _byte(_scratch.getUint8(i));
    }
  }

  void _byte(int byte) {
    final mixed = _hash ^ (byte % 256);
    final low = mixed % 65536;
    final high = (mixed ~/ 65536) % 65536;
    _hash =
        ((low * _prime) % _wrap + ((high * _prime) % 65536) * 65536) % _wrap;
  }
}

/// Recorded on macOS-arm64 under the VM, 2026-09-08, and matched by Chrome.
///
/// Forty checkpoints and forty different numbers: the walk is still moving at
/// the end of it, which is what a trace has to be doing to be able to fail. A
/// second half that repeats is a second half that cannot.
const List<String> _recorded = <String>[
  '5a7bd0fc',
  '22edc7eb',
  '038a1da2',
  '006eaf85',
  '7f71d670',
  '563b371f',
  'f8b5532b',
  '2d6e4b75',
  '5fe91720',
  '28091345',
  '498e04f0',
  '62f504fb',
  '3ef3baa7',
  '9f148623',
  '5a5138d8',
  'd0b56ec2',
  '953736e3',
  '8454f74f',
  'bfd8a1ce',
  '77a1d70d',
  'c5a55bab',
  '3ff17482',
  'b23bc540',
  '768632f4',
  'e16248fd',
  'd1f3e2d2',
  '84efd6d9',
  '27e214ed',
  '971583a4',
  '77c39293',
  'c171a40b',
  '18303b7f',
  '8754355d',
  '57e3e0ba',
  '980232d1',
  '0b4acf4d',
  'e41e861c',
  '4603175f',
  '8d107574',
  '34a49542',
];
