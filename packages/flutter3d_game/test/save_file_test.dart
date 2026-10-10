/// A save is read on launch, written mid-run, and has to say which level it
/// belongs to. All three are what these are about.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show SaveMigration, SaveSchema, Snapshot;
import 'package:flutter_test/flutter_test.dart';

void main() async {
  late Directory temporary;
  late FileStorage storage;
  late SaveFile saves;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('platformer_save');
    // A real directory, because what these tests are about is a document that
    // survives a process — see `Storage`, which is what decides where one goes.
    storage = FileStorage(appName: 'platformer', directory: temporary);
    saves = SaveFile(appName: 'test', storage: storage);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('nothing saved is not an error', () async {
    // Mutation: throw, or return an empty snapshot instead of null. The first
    // stops every fresh install from launching; the second restores a run that
    // never happened over the level's own start.
    expect(await saves.read(), isNull);
  });

  test('what is written comes back, level and all', () async {
    final run = Snapshot(<String, Object?>{
      'deaths': 2,
      'lives': 1,
      'elapsed': 41.5,
    });

    expect(await saves.write('assets/levels/first_steps.json', run), isTrue);
    final read = await saves.read();

    expect(read, isNotNull);
    expect(read!.level, 'assets/levels/first_steps.json');
    expect(read.run.data['deaths'], 2);
    expect(read.run.data['elapsed'], 41.5);
  });

  test('a save without a level is refused', () async {
    // Mutation: drop the level check and restore whatever is in the file. A
    // snapshot holds positions in metres, and metres from another level put the
    // runner inside a wall — which reads as the game being broken, not as the
    // save being stale.
    await storage.write('save.json', '{"run": {"deaths": 3}}');

    expect(await saves.read(), isNull);
  });

  test(
    'rubbish on disk starts a new run rather than refusing to launch',
    () async {
      await storage.write('save.json', '{"level": "a.json", "run": ');

      expect(await saves.read(), isNull);
    },
  );

  test(
    'the version reaches the disk, which is where it was not reaching',
    () async {
      // `write` sent `run.data` — the payload without the header `toJson` adds —
      // so the version never left the process and `Snapshot.fromJson` was never
      // called on the way back in. The whole versioning mechanism existed only
      // in a unit test.
      //
      // Mutation: write `run.data` again. This fails on the key, and the two
      // tests below stop meaning anything, because nothing on disk has a version
      // to disagree about.
      await saves.write('a.json', Snapshot(<String, Object?>{'deaths': 3}));

      final written =
          jsonDecode((await storage.read('save.json'))!)
              as Map<String, Object?>;
      final run = written['run']! as Map<String, Object?>;

      expect(run['version'], Snapshot.formatVersion);
      expect(run['deaths'], 3, reason: 'the payload still rides along');
    },
  );

  test('a save from a newer build is refused, and says so', () async {
    // The case the version exists for. Reading it field by field would put the
    // player somewhere a newer build meant something else by — and "starting
    // fresh" with no word discards a run they can still open by going back to
    // the build that wrote it.
    //
    // Mutation: construct with `Snapshot(run)` instead of `Snapshot.fromJson`.
    // The document is read as though it were this build's own and the issue is
    // never raised.
    final said = <String>[];
    final reader = SaveFile(
      appName: 'test',
      storage: storage,
      onIssue: (Issue issue) => said.add(issue.message),
    );
    await storage.write(
      'save.json',
      '{"level": "a.json", "run": {"version": 99, "deaths": 3}}',
    );

    expect(await reader.read(), isNull);
    expect(said.single, contains('newer than this build'));
  });

  test(
    'a save written before the version was stored is still readable',
    () async {
      // Every save on any disk today, because the key was never written. The
      // shape did not change, so refusing it would cost a player a run to fix a
      // bug that was never theirs.
      //
      // Mutation: drop the arm in `SaveRecord.read` that supplies a missing
      // version. This fails, and every existing save becomes a fresh start.
      await storage.write(
        'save.json',
        '{"level": "a.json", "run": {"deaths": 3}}',
      );

      final read = await saves.read();

      expect(read, isNotNull);
      expect(read!.run.data['deaths'], 3);
    },
  );

  test('a save from an older schema is migrated on the way in', () async {
    // A save written before the game split health into hearts. Mutation:
    // construct the reader without passing `schema` through to
    // `SaveRecord.read`, and the hearts come back as nothing while the old
    // field rides along unread.
    await storage.write(
      'save.json',
      '{"level": "a.json", "run": {"version": 1, "health": 30}}',
    );
    final reader = SaveFile(
      appName: 'test',
      storage: storage,
      schema: SaveSchema(<SaveMigration>[
        (run) => run..['hearts'] = (run.remove('health')! as num) ~/ 10,
      ]),
    );

    final read = await reader.readRecord();

    expect(read!.run.data, <String, Object?>{'hearts': 3});
    expect(read.schema, 1);
  });

  test('a save says which schema it was written at', () async {
    // Mutation: write without the schema. Every save then reads as version
    // 0, and the first migration runs again on a run it already changed.
    final writer = SaveFile(
      appName: 'test',
      storage: storage,
      schema: SaveSchema(<SaveMigration>[(run) => run]),
    );
    await writer.write('a.json', Snapshot(<String, Object?>{}), step: 12);

    final written =
        jsonDecode((await storage.read('save.json'))!) as Map<String, Object?>;
    expect(written['schema'], 1);
    expect(written['step'], 12);
    expect(written['digest'], isA<String>());
  });

  test('a finished run is cleared, and clearing twice is fine', () async {
    // Mutation: never clear. The player beats the level, quits, comes back, and
    // is put on the last checkpoint of the level they already finished.
    await saves.write('a.json', Snapshot(<String, Object?>{}));
    expect(await storage.read('save.json'), isNotNull);

    await saves.clear();
    expect(await storage.read('save.json'), isNull);
    await saves.clear();
  });
}
