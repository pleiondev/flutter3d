/// More than one circuit, and somewhere to go when a race is won.
///
///     flutter test test/season_test.dart
///
/// **This game had one `const` asset path.** A race could be finished and
/// nothing happened — no next circuit, nothing that remembered having been
/// anywhere, and a car driving round a finished race until the window was
/// closed. The other two games have moved a player from one level to the next
/// since they were written; this is racing catching up, and the second circuit
/// is what makes the difference visible. The season is five now; the chain is
/// the same chain, three links longer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart'; // Storage, from flutter3d_screens
import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

void main() {
  test('the season is a chain of five, and it ends', () {
    // Five by name rather than "more than one": a circuit dropped from the
    // list by accident is a season a player finishes an evening early, and
    // nothing else in the game would say so.
    expect(Season.circuits.map((Circuit c) => c.name).toList(), <String>[
      'ring',
      'gorge',
      'flats',
      'quarry',
      'ridge',
    ], reason: 'the season is raced in this order, easiest to hardest');

    var at = Season.first;
    final seen = <String>[at.name];
    for (var step = 0; step < 20; step++) {
      final next = Season.after(at);
      if (next == null) break;
      at = next;
      seen.add(at.name);
    }

    expect(
      seen,
      Season.circuits.map((Circuit c) => c.name).toList(),
      reason: 'walking the chain does not visit the circuits in order',
    );
    expect(
      Season.after(Season.circuits.last),
      isNull,
      reason: 'the season never ends, so a player never finishes it',
    );
  });

  test('and every circuit is told apart by name and by title', () {
    // The name is the file and the save; the title is what the screen says
    // between circuits. Two circuits sharing either is a player told they
    // are somewhere they are not — or, for the name, a save that resumes on
    // the wrong one.
    final names = Season.circuits.map((Circuit c) => c.name).toSet();
    final titles = Season.circuits.map((Circuit c) => c.title).toSet();

    expect(names.length, Season.circuits.length);
    expect(titles.length, Season.circuits.length);
    for (final circuit in Season.circuits) {
      expect(
        circuit.title.trim(),
        isNotEmpty,
        reason: '${circuit.name} is untitled',
      );
    }
  });

  test('and every circuit in it ships both of its files', () {
    // Mutation: name a circuit the generator does not write. The game would
    // load the first one, win it, and die on a missing asset — which is the
    // moment a player has earned something.
    for (final circuit in Season.circuits) {
      expect(
        File(circuit.track).existsSync(),
        isTrue,
        reason: '${circuit.name} has no track file',
      );
      expect(
        File(circuit.level).existsSync(),
        isTrue,
        reason: '${circuit.name} has no level file',
      );

      final document = TrackDocument.fromJson(
        jsonDecode(File(circuit.track).readAsStringSync())
            as Map<String, Object?>,
      );
      expect(document.track.length, greaterThan(100.0));
      expect(document.level, isNotNull);
    }
  });

  test('and nothing the generator writes is left out of it', () {
    // The other direction, and the one a list beside a directory always gets
    // wrong: a circuit generated, committed and never raced. This repository
    // has just finished paying for 290 lines of exactly that.
    final generated = Directory('assets/tracks')
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where(
          (String name) =>
              name.endsWith('.json') && !name.endsWith('_level.json'),
        )
        .map((String name) => name.substring(0, name.length - 5))
        .toSet();

    expect(generated, Season.circuits.map((Circuit c) => c.name).toSet());
  });

  group('where somebody got to', () {
    test('starts at the beginning and is kept once they move on', () {
      final storage = _Storage();
      final progress = SeasonProgress(storage: storage);
      expect(progress.read().name, Season.first.name);

      progress.reached(Season.circuits[1]);

      expect(
        SeasonProgress(storage: storage).read().name,
        Season.circuits[1].name,
        reason: 'a circuit reached is lost at the window close',
      );
    });

    test('and a finished season starts again rather than sticking', () {
      // The last circuit is not saved as "done", because there is nothing to
      // load when it is. Clearing means the next launch is a season, which is
      // the only other honest answer.
      final storage = _Storage();
      final progress = SeasonProgress(storage: storage)
        ..reached(Season.circuits.last);

      progress.clear();

      expect(progress.read().name, Season.first.name);
    });

    test('and a save naming a circuit this build dropped is not a crash', () {
      // The file outlives the build that wrote it. A name nobody ships any
      // more is a player put back at the start, not a game that will not open.
      final storage = _Storage()..documents['season.json'] = 'nurburgring';

      expect(SeasonProgress(storage: storage).read().name, Season.first.name);
      expect(Season.named('nurburgring'), isNull);
    });
  });

  test('and the game itself moves on when a race is won', () {
    // A scan, for the reason `ghost_test.dart` gives at more length: the move
    // happens in a private method of a widget no test can mount, and every
    // piece below has already been written once in this repository and left
    // uncalled.
    //
    // Split across two files now that the season lives in `RaceProgress`
    // rather than in fields of the widget: what comes next and what is
    // remembered about it are `race_cubit.dart`'s job, and the widget's own
    // job is noticing the finish line at all and not hard-coding a circuit.
    final game = File('lib/main.dart').readAsStringSync();
    final cubit = File('lib/src/race_cubit.dart').readAsStringSync();

    expect(
      cubit,
      contains('Season.after('),
      reason: 'nothing asks what comes next, so nothing ever does',
    );
    expect(
      game,
      contains('finishedThisStep'),
      reason: 'the finish line is crossed and the game does not notice',
    );
    expect(
      cubit,
      contains('season.reached('),
      reason: 'the player moves on and nothing remembers it',
    );
    expect(
      game,
      isNot(contains("'assets/tracks/ring.json'")),
      reason: 'the circuit is still nailed to one file',
    );
  });
}
