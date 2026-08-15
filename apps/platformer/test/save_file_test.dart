/// A save is read on launch, written mid-run, and has to say which level it
/// belongs to. All three are what these are about.
library;

import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart' show Snapshot;
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/save_file.dart';

void main() {
  late Directory temporary;
  late SaveFile saves;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('platformer_save');
    saves = SaveFile(directory: temporary);
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
    saves.directory.createSync(recursive: true);
    saves.file.writeAsStringSync('{"run": {"deaths": 3}}');

    expect(saves.read(), isNull);
  });

  test('rubbish on disk starts a new run rather than refusing to launch', () {
    saves.directory.createSync(recursive: true);
    saves.file.writeAsStringSync('{"level": "a.json", "run": ');

    expect(saves.read(), isNull);
  });

  test('a finished run is cleared, and clearing twice is fine', () {
    // Mutation: never clear. The player beats the level, quits, comes back, and
    // is put on the last checkpoint of the level they already finished.
    saves.write('a.json', Snapshot(<String, Object?>{}));
    expect(saves.file.existsSync(), isTrue);

    saves.clear();
    expect(saves.file.existsSync(), isFalse);
    saves.clear();
  });
}
