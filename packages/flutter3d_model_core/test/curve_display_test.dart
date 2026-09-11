/// `anim-06`: `curveSamples`, `tangentHandles`, `valueRange`, `eulerOf` —
/// checked against `KeyTable` fixtures of each interpolation kind, and
/// `eulerOf` against `Quaternion.euler` by round-tripping through the
/// rotation itself, since two different Euler triples can be the same
/// rotation and comparing raw angles would fail for a reason that has
/// nothing to do with a wrong extraction.
///
///     dart test test/curve_display_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('curveSamples', () {
    test('a step track is piecewise-constant between keys', () {
      final table = KeyTable(
        componentCount: 1,
        interpolation: AnimationInterpolation.step,
      )
        ..setKey(0.0, <double>[1.0])
        ..setKey(1.0, <double>[9.0]);

      final samples = curveSamples(table, 0, sampleCount: 11);
      // Every sample strictly before the second key holds the first key's
      // value; nothing in between reads a blend of the two.
      // Mutation: sample through a smooth interpolation instead of
      // `KeyTable.sample` — this would read values climbing from 1.0
      // toward 9.0 instead of holding flat at 1.0 until the jump.
      for (final (time, value) in samples) {
        if (time < 1.0) {
          expect(value, 1.0, reason: 't=$time');
        }
      }
      expect(samples.last.$2, 9.0);
    });

    test('a cubic track matches AnimationTrack.sample exactly', () {
      final table = KeyTable(
        componentCount: 1,
        interpolation: AnimationInterpolation.cubicSpline,
      )
        ..setKey(0.0, <double>[0.0], inTangent: <double>[0.0], outTangent: <double>[3.0])
        ..setKey(1.0, <double>[1.0], inTangent: <double>[0.5], outTangent: <double>[0.0]);

      final track = table.toAnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
      );
      final out = Float32List(1);

      for (final (time, value) in curveSamples(table, 0, sampleCount: 13)) {
        track.sample(time, out);
        // Mutation: reimplement Hermite interpolation locally instead of
        // delegating to `KeyTable.sample` (which itself delegates to
        // `AnimationTrack.sample`) — a hand-rewritten formula that looks
        // right is exactly what this equality is here to catch, not a
        // gross error a looser tolerance would still miss.
        expect(value, closeTo(out[0], 1e-6), reason: 't=$time');
      }
    });

    test('an empty table samples to nothing, not a crash', () {
      final table = KeyTable(componentCount: 1);
      expect(curveSamples(table, 0, sampleCount: 10), isEmpty);
    });
  });

  group('tangentHandles', () {
    test('a cubic key\'s handles sit along its own tangent slope', () {
      final table = KeyTable(
        componentCount: 1,
        interpolation: AnimationInterpolation.cubicSpline,
      )..setKey(2.0, <double>[5.0], inTangent: <double>[1.0], outTangent: <double>[-2.0]);

      final handles = tangentHandles(table, 0, 0, handleLength: 0.5);
      // out: value + outSlope * dt = 5.0 + (-2.0 * 0.5) = 4.0, at t = 2.5.
      // Mutation: swap in/out tangent when building the handle pair — this
      // reads the out handle's value as 5.5 (the *in* slope's own result)
      // instead of 4.0.
      expect(handles.outHandle.x, closeTo(2.5, 1e-9));
      expect(handles.outHandle.y, closeTo(4.0, 1e-9));
      expect(handles.inHandle.x, closeTo(1.5, 1e-9));
      expect(handles.inHandle.y, closeTo(4.5, 1e-9));
    });

    test('a linear table\'s handles collapse onto the key itself', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(1.0, <double>[7.0], inTangent: <double>[99.0], outTangent: <double>[99.0]);
      final handles = tangentHandles(table, 0, 0);
      // Mutation: read tangents through even when `interpolation` is not
      // cubic — this would put the handles far from the key instead of on
      // top of it, since a stray 99.0 tangent is sitting right there
      // waiting to be misread.
      expect(handles.inHandle, Vector2(1.0, 7.0));
      expect(handles.outHandle, Vector2(1.0, 7.0));
    });
  });

  group('valueRange', () {
    test('the min and max across every key', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[3.0])
        ..setKey(1.0, <double>[-2.0])
        ..setKey(2.0, <double>[8.0]);
      final range = valueRange(table, 0);
      expect(range.min, -2.0);
      expect(range.max, 8.0);
    });

    test('an empty table reads a zero range, not an infinite one', () {
      final table = KeyTable(componentCount: 1);
      final range = valueRange(table, 0);
      expect(range.min, 0.0);
      expect(range.max, 0.0);
    });
  });

  group('eulerOf', () {
    test('round-trips through the rotation itself for many angles, away '
        'from the pole', () {
      // Two different Euler triples can mean the same rotation — checked
      // by comparing where `eulerOf`'s own answer, re-encoded, sends a
      // test vector against where the original quaternion sends it, not
      // by comparing the angles themselves.
      final angles = <(double, double, double)>[
        (0.3, 0.5, -0.2),
        (-1.0, 0.1, 0.7),
        (0.0, 0.0, 0.0),
        (1.2, -0.8, 0.4),
        (0.05, -1.3, -0.9),
      ];
      final probe = Vector3(1.0, 2.0, 3.0);

      for (final (yaw, pitch, roll) in angles) {
        final original = Quaternion.euler(yaw, pitch, roll);
        final euler = eulerOf(original);
        // Mutation: swap which extracted component feeds which parameter
        // of `Quaternion.euler` on the way back (e.g. pitch and roll
        // reversed) — this diverges from the original rotation for any
        // angle set that is not symmetric under that swap, which at least
        // one of the five above is.
        final reconstructed = Quaternion.euler(euler.y, euler.x, euler.z);

        final a = original.rotated(probe.clone());
        final b = reconstructed.rotated(probe.clone());
        expect(a.x, closeTo(b.x, 1e-4), reason: '(yaw:$yaw, pitch:$pitch, roll:$roll) x');
        expect(a.y, closeTo(b.y, 1e-4), reason: '(yaw:$yaw, pitch:$pitch, roll:$roll) y');
        expect(a.z, closeTo(b.z, 1e-4), reason: '(yaw:$yaw, pitch:$pitch, roll:$roll) z');
      }
    });

    test('identity reads as zero on every axis', () {
      final euler = eulerOf(Quaternion.identity());
      expect(euler.x, closeTo(0.0, 1e-9));
      expect(euler.y, closeTo(0.0, 1e-9));
      expect(euler.z, closeTo(0.0, 1e-9));
    });

    test('a quarter turn about Y alone reads back as pure yaw', () {
      final q = Quaternion.euler(math.pi / 2, 0.0, 0.0);
      final euler = eulerOf(q);
      expect(euler.y, closeTo(math.pi / 2, 1e-6));
      expect(euler.x, closeTo(0.0, 1e-6));
      expect(euler.z, closeTo(0.0, 1e-6));
    });
  });
}
