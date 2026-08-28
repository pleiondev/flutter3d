/// A save is read on launch, written mid-run, and has to say which level it
/// belongs to. All three are what these are about.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart' show Snapshot;
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late FileStorage storage;
  late SaveFile saves;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('platformer_save');
    // A real directory, because what these tests are about is a document that
    // survives a process — see `Storage`, which is what decides where one goes.
    storage = FileStorage(appName: 'platformer', directory: temporary);
    saves = SaveFile(appName: 'test', storage: storage);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('nothing saved is not an error', () {
    // Mutation: throw, or return an empty snapshot instead of null. The first
    // stops every fresh install from launching; the second restores a run that
    // never happened over the level's own start.
    expect(saves.read(), isNull);
  });

  test('what is written comes back, level and all', () {
    final run = Snapshot(<String, Object?>{
      'deaths': 2,
      'lives': 1,
      'elapsed': 41.5,
    });

    expect(saves.write('assets/levels/first_steps.json', run), isTrue);
    final read = saves.read();

    expect(read, isNotNull);
    expect(read!.level, 'assets/levels/first_steps.json');
    expect(read.run.data['deaths'], 2);
    expect(read.run.data['elapsed'], 41.5);
  });

  test('a save without a level is refused', () {
    // Mutation: drop the level check and restore whatever is in the file. A
    // snapshot holds positions in metres, and metres from another level put the
    // runner inside a wall — which reads as the game being broken, not as the
    // save being stale.
    storage.write('save.json', '{"run": {"deaths": 3}}');

    expect(saves.read(), isNull);
  });

  test('rubbish on disk starts a new run rather than refusing to launch', () {
    storage.write('save.json', '{"level": "a.json", "run": ');

    expect(saves.read(), isNull);
  });

  test('the version reaches the disk, which is where it was not reaching', () {
    // `write` sent `run.data` — the payload without the header `toJson` adds —
    // so the version never left the process and `Snapshot.fromJson` was never
    // called on the way back in. The whole versioning mechanism existed only
    // in a unit test.
    //
    // Mutation: write `run.data` again. This fails on the key, and the two
    // tests below stop meaning anything, because nothing on disk has a version
    // to disagree about.
    saves.write('a.json', Snapshot(<String, Object?>{'deaths': 3}));

    final written =
        jsonDecode(storage.read('save.json')!) as Map<String, Object?>;
    final run = written['run']! as Map<String, Object?>;

    expect(run['version'], Snapshot.formatVersion);
    expect(run['deaths'], 3, reason: 'the payload still rides along');
  });

  test('a save from a newer build is refused, and says so', () {
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
      onIssue: said.add,
    );
    storage.write(
      'save.json',
      '{"level": "a.json", "run": {"version": 99, "deaths": 3}}',
    );

    expect(reader.read(), isNull);
    expect(said.single, contains('newer than this build'));
  });

  test('a save written before the version was stored is still readable', () {
    // Every save on any disk today, because the key was never written. The
    // shape did not change, so refusing it would cost a player a run to fix a
    // bug that was never theirs.
    //
    // Mutation: drop the `containsKey('version')` arm in `read`. This fails,
    // and every existing save becomes a fresh start.
    storage.write('save.json', '{"level": "a.json", "run": {"deaths": 3}}');

    final read = saves.read();

    expect(read, isNotNull);
    expect(read!.run.data['deaths'], 3);
  });

  test('a finished run is cleared, and clearing twice is fine', () {
    // Mutation: never clear. The player beats the level, quits, comes back, and
    // is put on the last checkpoint of the level they already finished.
    saves.write('a.json', Snapshot(<String, Object?>{}));
    expect(storage.read('save.json'), isNotNull);

    saves.clear();
    expect(storage.read('save.json'), isNull);
    saves.clear();
  });
}
