/// More than one circuit, and somewhere to go when a race is won.
///
///     flutter test test/season_test.dart
///
/// **This game had one `const` asset path.** A race could be finished and
/// nothing happened — no next circuit, nothing that remembered having been
/// anywhere, and a car driving round a finished race until the window was
/// closed. The other two games have moved a player from one level to the next
/// since they were written; this is racing catching up, and the second circuit
/// is what makes the difference visible.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/race_cubit.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the season is a chain, and it ends', () {
    expect(
      Season.circuits.length,
      greaterThan(1),
      reason: 'a season of one circuit is the game that had no chain',
    );

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

  test('and nothing about where somebody got to outlives the window', () {
    // The circuit reached used to be saved and read back at the next launch,
    // and the effect was a game that opened on the second circuit for anyone
    // who had ever won the first. A season is one sitting; the only thing
    // kept between launches is the best lap, and that is the ghost's file.
    final race = RaceProgress();

    expect(race.current.name, Season.first.name);
    expect(
      Season.circuits.map((Circuit c) => c.name),
      isNot(contains('season')),
      reason: 'no circuit may be named after the file this used to be',
    );
  });

  test('and the game itself moves on when a race is won', () {
    // A scan, for the reason `ghost_test.dart` gives at more length: the move
    // happens in a private method of a widget no test can mount, and every
    // piece below has already been written once in this repository and left
    // uncalled.
    //
    // Split across two files now that the season lives in `RaceProgress`
    // rather than in fields of the widget: what comes next is
    // `race_cubit.dart`'s job, and the widget's own job is noticing the
    // finish line at all and not hard-coding a circuit.
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
      isNot(contains('storage')),
      reason:
          'the circuit reached is being saved again, and the next launch '
          'will open on it rather than on the first',
    );
    expect(
      game,
      isNot(contains("'assets/tracks/ring.json'")),
      reason: 'the circuit is still nailed to one file',
    );
  });
}
