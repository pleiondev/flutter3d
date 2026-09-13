/// `net-04`'s structural half: given two JSON trees, find the first leaf
/// where they disagree — no genre, no replay, just the recursion
/// `diffRuns` sits on top of.
///
///     dart test test/snapshot_divergence_test.dart
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  group('firstDifferingPath', () {
    test('finds a scalar that differs at the top level', () {
      final result = firstDifferingPath(
        <String, Object?>{'x': 1.0},
        <String, Object?>{'x': 2.0},
      );
      expect(result, isNotNull);
      expect(result!.path, 'x');
      expect(result.a, 1.0);
      expect(result.b, 2.0);
    });

    test('walks into nested maps to the leaf that differs', () {
      final result = firstDifferingPath(
        <String, Object?>{
          'entities': <String, Object?>{
            '7': <String, Object?>{'health': 100, 'x': 3.0},
          },
        },
        <String, Object?>{
          'entities': <String, Object?>{
            '7': <String, Object?>{'health': 40, 'x': 3.0},
          },
        },
      );
      expect(result, isNotNull);
      expect(
        result!.path,
        'entities.7.health',
        reason: 'the path should read like an address into the JSON, '
            'naming the entity a caller would recognise',
      );
      expect(result.a, 100);
      expect(result.b, 40);
    });

    test('reports the earlier key first when several differ', () {
      final result = firstDifferingPath(
        <String, Object?>{'a': 1, 'b': 1},
        <String, Object?>{'a': 2, 'b': 2},
      );
      expect(result!.path, 'a');
    });

    test('walks into lists by index', () {
      final result = firstDifferingPath(
        <String, Object?>{'shots': <Object?>[1, 2, 3]},
        <String, Object?>{'shots': <Object?>[1, 9, 3]},
      );
      expect(result!.path, 'shots[1]');
      expect(result.a, 2);
      expect(result.b, 9);
    });

    test('a list of different lengths names the length itself', () {
      final result = firstDifferingPath(
        <String, Object?>{'shots': <Object?>[1, 2]},
        <String, Object?>{'shots': <Object?>[1, 2, 3]},
      );
      expect(result!.path, 'shots.<length>');
      expect(result.a, 2);
      expect(result.b, 3);
    });

    test('equal trees find nothing', () {
      expect(
        firstDifferingPath(
          <String, Object?>{'x': 1.0, 'nested': <String, Object?>{'y': 2}},
          <String, Object?>{'x': 1.0, 'nested': <String, Object?>{'y': 2}},
        ),
        isNull,
      );
    });
  });

  group('diffRuns', () {
    Map<String, Object?> snap(double x) => <String, Object?>{'x': x};

    test('null when the two digest traces never disagreed', () {
      final a = DigestTrace()..observe(25, snap(1.0));
      final b = DigestTrace()..observe(25, snap(1.0));
      final result = diffRuns(
        a: a,
        b: b,
        snapshotAtA: (_) => snap(1.0),
        snapshotAtB: (_) => snap(1.0),
      );
      expect(result, isNull);
    });

    test(
      'names the checkpoint step from the digests and the field from the '
      'full snapshots handed back for it',
      () {
        final a = DigestTrace()
          ..observe(25, snap(1.0))
          ..observe(50, snap(4.0));
        final b = DigestTrace()
          ..observe(25, snap(1.0))
          ..observe(50, snap(5.0));

        final result = diffRuns(
          a: a,
          b: b,
          snapshotAtA: (step) => step == 50 ? snap(4.0) : snap(1.0),
          snapshotAtB: (step) => step == 50 ? snap(5.0) : snap(1.0),
        );

        expect(result, isNotNull);
        expect(
          result!.step,
          50,
          reason: 'the first checkpoint, at 25, matched — the divergence '
              'should be named at the one that did not',
        );
        expect(result.path, 'x');
        expect(result.expected, 4.0);
        expect(result.found, 5.0);
      },
    );

    test(
      'throws rather than reporting no divergence when the digests '
      'disagreed but the snapshots handed back do not',
      () {
        final a = DigestTrace()..observe(25, snap(1.0));
        final b = DigestTrace()..observe(25, snap(2.0));
        expect(
          () => diffRuns(
            a: a,
            b: b,
            snapshotAtA: (_) => snap(9.0),
            snapshotAtB: (_) => snap(9.0),
          ),
          throwsStateError,
        );
      },
    );
  });
}
