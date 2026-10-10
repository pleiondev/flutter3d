/// A save read by a later build of the game, and two copies of one save that
/// have to become one. Migrations, schema refusals and the conflict rules are
/// what these are about.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

SaveRecord _record(Map<String, Object?> run, {int step = 0, String? level}) =>
    SaveRecord(level: level ?? 'a.json', run: Snapshot(run), step: step);

void main() {
  group('SaveSchema', () {
    // Version 0 kept health as a number; version 1 split it into hearts;
    // version 2 renamed `keys` to `keyRing`.
    final schema = SaveSchema(<SaveMigration>[
      (run) => run..['hearts'] = ((run.remove('health') as num?) ?? 0) ~/ 10,
      (run) => run..['keyRing'] = run.remove('keys'),
    ]);

    test('the version is the number of migrations', () {
      // Mutation: a version kept beside the list. It can be raised without a
      // migration, and the save from the version between is read as current.
      expect(schema.version, 2);
      expect(const SaveSchema().version, 0);
    });

    test('an old run is brought up through every migration in order', () {
      // Mutation: apply only the last migration, or start from 0 whatever the
      // run says. The first loses the hearts, the second divides them again.
      final upgraded = schema.upgrade(<String, Object?>{
        'health': 30,
        'keys': <String>['red'],
      }, 0);

      expect(upgraded, isA<SaveUpgraded>());
      final run = (upgraded as SaveUpgraded).run;
      expect(run, <String, Object?>{
        'hearts': 3,
        'keyRing': <String>['red'],
      });

      final fromOne = schema.upgrade(<String, Object?>{
        'hearts': 2,
        'keys': <String>[],
      }, 1);
      expect((fromOne as SaveUpgraded).run['hearts'], 2);
    });

    test('a run from a newer build is refused, and said to be newer', () {
      // Mutation: read it as current. Its fields mean something this build
      // has never heard of, and the next save overwrites the player's
      // progress with a misreading of it.
      final refused = schema.upgrade(<String, Object?>{}, 3);

      expect(refused, isA<SaveRefused>());
      expect((refused as SaveRefused).newer, isTrue);
      expect(refused.reason, contains('newer'));
    });

    test('a migration that throws is a refusal naming where it failed', () {
      // Mutation: let the throw out. `SaveFile.read` promises never to throw,
      // and a launch that crashes on somebody's save is the worst version of
      // "the save could not be read".
      final broken = SaveSchema(<SaveMigration>[
        (run) => throw StateError('no such field'),
      ]);

      final refused = broken.upgrade(<String, Object?>{}, 0);
      expect(refused, isA<SaveRefused>());
      expect((refused as SaveRefused).newer, isFalse);
      expect(refused.reason, contains('from save schema 0'));
    });

    test('the run handed in is left as it was', () {
      // Mutation: hand the caller's map to the first migration. A failed
      // upgrade then leaves the save it was reading half rewritten.
      final run = <String, Object?>{'health': 30};
      schema.upgrade(run, 0);

      expect(run, <String, Object?>{'health': 30});
    });
  });

  group('SaveRecord', () {
    test('what is written is read back, schema, step and all', () {
      final written = SaveRecord(
        level: 'b.json',
        run: Snapshot(<String, Object?>{'deaths': 2}),
        step: 1200,
        schema: 1,
      );

      final read = SaveRecord.read(
        written.toJson(),
        SaveSchema(<SaveMigration>[(run) => run]),
      );

      expect(read, isA<SaveFound>());
      final record = (read as SaveFound).record;
      expect(record.level, 'b.json');
      expect(record.step, 1200);
      expect(record.run.data, <String, Object?>{'deaths': 2});
      expect(record.digest, written.digest);
      expect(read.upgradedFrom, 1);
    });

    test('a save from before schemas is version 0 and migrated', () {
      // The shape every save on disk had before this: a level and a run, no
      // schema, no step. Mutation: treat a missing schema as current, and the
      // migration a game wrote for its first change never runs on the saves
      // it was written for.
      final read = SaveRecord.read(
        <String, Object?>{
          'level': 'a.json',
          'run': <String, Object?>{'version': 1, 'health': 20},
        },
        SaveSchema(<SaveMigration>[
          (run) => run..['hearts'] = (run.remove('health')! as num) ~/ 10,
        ]),
      );

      final found = read as SaveFound;
      expect(found.upgradedFrom, 0);
      expect(found.record.schema, 1);
      expect(found.record.run.data, <String, Object?>{'hearts': 2});
    });

    test('a snapshot from a newer engine is refused as newer', () {
      final read = SaveRecord.read(<String, Object?>{
        'level': 'a.json',
        'run': <String, Object?>{'version': Snapshot.formatVersion + 1},
      }, const SaveSchema());

      expect(read, isA<SaveNotRead>());
      expect((read as SaveNotRead).newer, isTrue);
    });

    test('the digest is of the run, not of how far it got', () {
      // Mutation: hash the step too. Two copies of one save that counted
      // their steps differently — an older build counted none — would then be
      // a conflict for the player to settle, about nothing.
      final a = _record(<String, Object?>{'x': 1}, step: 10);
      final b = _record(<String, Object?>{'x': 1}, step: 99);
      final c = _record(<String, Object?>{'x': 2}, step: 10);

      expect(a.digest, b.digest);
      expect(a.digest, isNot(c.digest));
      expect(
        _record(<String, Object?>{'x': 1}, level: 'b.json').digest,
        isNot(a.digest),
      );
    });
  });

  group('resolveSaves', () {
    final early = _record(<String, Object?>{'at': 1}, step: 100);
    final late = _record(<String, Object?>{'at': 2}, step: 900);
    final sameStep = _record(<String, Object?>{'at': 3}, step: 900);

    test('one copy, or the same copy twice, is no conflict', () {
      expect(resolveSaves(local: null, remote: null), SaveResolution.inSync);
      expect(
        resolveSaves(local: early, remote: null),
        SaveResolution.keepLocal,
      );
      expect(
        resolveSaves(local: null, remote: early),
        SaveResolution.takeRemote,
      );
      expect(
        resolveSaves(
          local: early,
          remote: _record(<String, Object?>{'at': 1}, step: 5),
        ),
        SaveResolution.inSync,
      );
    });

    test('with no base, the further run wins', () {
      // Mutation: compare in the wrong direction, or by digest order. The
      // player who played on the tablet comes back to the phone's older run.
      expect(
        resolveSaves(local: late, remote: early),
        SaveResolution.keepLocal,
      );
      expect(
        resolveSaves(local: early, remote: late),
        SaveResolution.takeRemote,
      );
    });

    test('when one side is still the base, the other moved and wins', () {
      // A player went back to an earlier checkpoint on the tablet. The phone
      // still holds the run both last agreed on, so the tablet's choice is
      // the newer one even though it is fewer steps in.
      //
      // Mutation: ask the step first. The player's deliberate step back is
      // undone the next time the phone syncs.
      expect(
        resolveSaves(local: late, remote: early, base: late.digest),
        SaveResolution.takeRemote,
      );
      expect(
        resolveSaves(local: early, remote: late, base: late.digest),
        SaveResolution.keepLocal,
      );
    });

    test('two different runs equally far along go to the player', () {
      // Mutation: pick one. Either answer throws away a run somebody played.
      expect(resolveSaves(local: late, remote: sameStep), SaveResolution.ask);
      expect(
        resolveSaves(local: late, remote: sameStep, base: early.digest),
        SaveResolution.ask,
      );
    });
  });
}
