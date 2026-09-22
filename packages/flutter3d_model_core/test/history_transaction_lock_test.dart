/// `mcp-14n`'s own lock: [ModelHistory.whenNotInTransaction], the `await` a
/// caller outside the gesture that opened a transaction takes before running
/// anything against the document.
///
///     dart test test/history_transaction_lock_test.dart
library;

import 'dart:async';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/src/history.dart';
import 'package:flutter3d_model_core/src/project.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelHistory freshHistory() {
  var project = const ModelProject();
  project = project.added(
    (int id) => ModelObject(
      id: id,
      name: 'block',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  return ModelHistory(project);
}

void main() {
  group('ModelHistory.whenNotInTransaction', () {
    test('resolves immediately when nothing is open', () async {
      final history = freshHistory();
      var resolved = false;
      unawaited(history.whenNotInTransaction.then((_) => resolved = true));
      // One microtask turn is enough: nothing was open, so the `async`
      // getter's own `while` loop never ran at all.
      await Future<void>.value();
      expect(resolved, isTrue);
    });

    test('waits for an open transaction, then resolves', () async {
      final history = freshHistory();
      history.beginTransaction();

      var resolved = false;
      final waiting = history.whenNotInTransaction.then((_) => resolved = true);

      await Future<void>.value();
      expect(resolved, isFalse, reason: 'the transaction is still open');

      history.endTransaction();
      await waiting;
      expect(resolved, isTrue);
    });

    test(
      'a transaction that opens again before this resolves is waited out too',
      () async {
        final history = freshHistory();
        history.beginTransaction();

        var resolved = false;
        final waiting = history.whenNotInTransaction.then(
          (_) => resolved = true,
        );

        // Closes the first transaction and immediately opens a second one,
        // both inside the microtask `endTransaction`'s own completion runs —
        // `whenNotInTransaction`'s loop re-reads the flag rather than trusting
        // the one wakeup, which is what this proves.
        history.endTransaction();
        history.beginTransaction();

        await Future<void>.value();
        expect(resolved, isFalse, reason: 'a second transaction is now open');

        history.endTransaction();
        await waiting;
        expect(resolved, isTrue);
      },
    );

    test(
      'several waiters all resolve once the one transaction they are all waiting on closes',
      () async {
        final history = freshHistory();
        history.beginTransaction();

        final order = <int>[];
        final waiters = <Future<void>>[
          for (var i = 0; i < 3; i++)
            history.whenNotInTransaction.then((_) => order.add(i)),
        ];

        history.endTransaction();
        await Future.wait(waiters);
        expect(order.toSet(), <int>{0, 1, 2});
      },
    );

    test('runs in and out of a transaction() body the same way', () async {
      final history = freshHistory();
      late Future<void> waiting;
      var resolved = false;
      history.transaction(() {
        waiting = history.whenNotInTransaction.then((_) => resolved = true);
      });
      // `transaction`'s own `finally` has already called `endTransaction` by
      // the time the body returns, so this is resolved with no further
      // awaiting needed — the ordinary, non-drag case every other command
      // runs through.
      await waiting;
      expect(resolved, isTrue);
    });
  });
}
