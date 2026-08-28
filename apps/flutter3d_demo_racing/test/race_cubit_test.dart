/// Loading, racing, finishing a circuit, and finishing a season.
///
///     flutter test test/race_cubit_test.dart
///
/// **None of this could be tested before.** The season lived in five fields
/// and two `setState` calls inside `_RaceScreenState`, which no test can
/// mount without a device — see `ghost_test.dart` and `season_test.dart` for
/// the scans that stood in for testing it at all. `RaceProgress` needs
/// neither a device nor a window: what it decides is which circuit is next
/// and what to remember, not how to draw one.
library;

import 'package:flutter3d_app/flutter3d_app.dart'; // Storage, from flutter3d_ui
import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/race_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage that keeps everything in a map, the same fake `season_test.dart`
/// and the dungeon's `run_cubit_test.dart` both use.
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

({RaceCubit race, _Storage storage}) _game() {
  final storage = _Storage();
  return (
    storage: storage,
    race: RaceCubit(RaceProgress(season: SeasonProgress(storage: storage))),
  );
}

void main() {
  test('a new season starts loading the first circuit', () {
    final it = _game();

    expect(it.race.state, isA<RaceLoading>());
    expect(it.race.circuit.name, Season.first.name);
  });

  test('ready() says the circuit is up', () {
    final it = _game();

    it.race.ready();

    expect(it.race.state, isA<Racing>());
    expect((it.race.state as Racing).circuit.name, Season.first.name);
  });

  test('failed() says why, whatever was happening before', () {
    final it = _game();
    it.race.ready();

    final error = Exception('no such circuit');
    it.race.failed(error);

    expect(it.race.state, isA<RaceFailed>());
    expect((it.race.state as RaceFailed).error, same(error));
  });

  group('finishing a circuit', () {
    test('with another circuit to come, says which and remembers it', () {
      final it = _game();
      it.race.ready();
      final first = it.race.circuit;

      final next = it.race.finish();

      expect(next, isNotNull);
      expect(
        next!.name,
        isNot(first.name),
        reason: 'the next circuit is a different one',
      );
      final state = it.race.state as RaceOver;
      expect(state.circuit.name, first.name);
      expect(state.next, next);
      expect(state.seasonComplete, isFalse);
      // Written down, not just said: a fresh read of the same storage sees
      // it, the way the next launch would.
      expect(
        SeasonProgress(storage: it.storage).read().name,
        next.name,
        reason: 'the player moved on and nothing remembered it',
      );
    });

    test(
      'at the last circuit, says the season is over and clears the save',
      () {
        final it = _game();
        // Walk to the last circuit the way a season actually would, rather
        // than assuming there are exactly two: `finish` decides and remembers
        // what is next, and `moveOn` — the screen's job, once its pause at the
        // finish line has run out — is what actually leaves for it.
        Circuit? step = it.race.circuit;
        while (Season.after(step!) != null) {
          it.race.ready();
          step = it.race.finish();
          it.race.moveOn(step!);
        }
        it.race.ready();

        final next = it.race.finish();

        expect(next, isNull);
        final state = it.race.state as RaceOver;
        expect(state.seasonComplete, isTrue);
        expect(state.next, isNull);
        expect(
          it.storage.documents,
          isEmpty,
          reason: 'a finished season should not resume mid-way next launch',
        );
      },
    );
  });

  test(
    'moveOn() leaves the circuit that was won and starts loading the next',
    () {
      final it = _game();
      it.race.ready();
      final next = it.race.finish()!;

      it.race.moveOn(next);

      expect(it.race.state, isA<RaceLoading>());
      expect(it.race.circuit.name, next.name);
    },
  );

  test('the notice a screen would show disappears once moveOn is called', () {
    // Not tested through a widget — `_notice` in `main.dart` is a one-line
    // `switch` over exactly this status, and this is the state that switch
    // reads rather than a rendering of it.
    final it = _game();
    it.race.ready();
    final next = it.race.finish()!;
    expect(it.race.state, isA<RaceOver>());

    it.race.moveOn(next);

    expect(
      it.race.state,
      isNot(isA<RaceOver>()),
      reason: 'the finish-line notice should not survive the next load',
    );
  });
}
