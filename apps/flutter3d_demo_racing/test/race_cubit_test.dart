/// Loading, racing, finishing a circuit, and finishing a season.
///
///     flutter test test/race_cubit_test.dart
///
/// **None of this could be tested before.** The season lived in five fields
/// and two `setState` calls inside `_RaceScreenState`, which no test can
/// mount without a device — see `ghost_test.dart` and `season_test.dart` for
/// the scans that stood in for testing it at all. `RaceProgress` needs
/// neither a device nor a window: what it decides is which circuit is next,
/// not how to draw one.
library;

import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/race_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

RaceCubit _season() => RaceCubit(RaceProgress());

void main() {
  test('a season starts loading the first circuit, every launch', () {
    // Nothing is saved between launches on purpose. The circuit reached used
    // to be written down, and a player who had once won the first circuit
    // opened the game on the second from then on.
    final race = _season();

    expect(race.state, isA<RaceLoading>());
    expect(race.circuit.name, Season.first.name);
  });

  test('ready() says the circuit is up', () {
    final race = _season();

    race.ready();

    expect(race.state, isA<Racing>());
    expect((race.state as Racing).circuit.name, Season.first.name);
  });

  test('failed() says why, whatever was happening before', () {
    final race = _season();
    race.ready();

    final error = Exception('no such circuit');
    race.failed(error);

    expect(race.state, isA<RaceFailed>());
    expect((race.state as RaceFailed).error, same(error));
  });

  test('and a circuit that would not read says which file it was', () {
    // **The screen showed the thrown object and nothing else.** Every failure
    // that is not the graphics device is a content mistake in one of two
    // generated documents, and "FormatException: Unexpected character" on a
    // black screen names neither the circuit nor the half of it. `asset` is
    // also what `main.dart` switches on to decide between the renderer's own
    // screen and the one that names a file and offers the season again.
    //
    // Mutation: drop the `asset:` argument at the circuit's catch in
    // `_loadCircuit` and this is null — which is the screen with no filename
    // and no way out, and it reads as a device failure besides.
    final race = _season();

    race.failed(Exception('bad json'), asset: 'assets/tracks/ring.json');

    expect((race.state as RaceFailed).asset, 'assets/tracks/ring.json');
    // And the device half stays as it was: nothing to name.
    race.failed(Exception('no device'));
    expect((race.state as RaceFailed).asset, isNull);
  });

  test('startOver() goes back to the first circuit from anywhere', () {
    // **The transition this game did not have.** A completed season is a
    // caption over a race that keeps running, and a circuit that will not read
    // is a screen with nothing on it; neither had a way back, because there is
    // no `restart` here — the other two games get one from `RunSession`, and a
    // season is not one.
    //
    // Mutation: leave `_current` alone in `startOver` and the season restarts
    // on the circuit it was stuck on, which for a broken document reads the
    // same broken document again for ever.
    final race = _season();
    race.ready();
    final second = race.finish()!;
    race.moveOn(second);
    race.failed(Exception('bad json'), asset: second.track);

    race.startOver();

    expect(race.circuit.name, Season.first.name);
    expect(race.state, isA<RaceLoading>());
  });

  group('finishing a circuit', () {
    test('with another circuit to come, says which', () {
      final race = _season();
      race.ready();
      final first = race.circuit;

      final next = race.finish();

      expect(next, isNotNull);
      expect(
        next!.name,
        isNot(first.name),
        reason: 'the next circuit is a different one',
      );
      final state = race.state as RaceOver;
      expect(state.circuit.name, first.name);
      expect(state.next, next);
      expect(state.seasonComplete, isFalse);
    });

    test('at the last circuit, says the season is over', () {
      final race = _season();
      // Walk to the last circuit the way a season actually would, rather
      // than assuming how many there are: `finish` decides what is next, and
      // `moveOn` — the screen's job, once its pause at the finish line has
      // run out — is what actually leaves for it.
      Circuit? step = race.circuit;
      while (Season.after(step!) != null) {
        race.ready();
        step = race.finish();
        race.moveOn(step!);
      }
      race.ready();

      final next = race.finish();

      expect(next, isNull);
      final state = race.state as RaceOver;
      expect(state.seasonComplete, isTrue);
      expect(state.next, isNull);
    });
  });

  test(
    'moveOn() leaves the circuit that was won and starts loading the next',
    () {
      final race = _season();
      race.ready();
      final next = race.finish()!;

      race.moveOn(next);

      expect(race.state, isA<RaceLoading>());
      expect(race.circuit.name, next.name);
    },
  );

  test('the notice a screen would show disappears once moveOn is called', () {
    // Not tested through a widget — `_notice` in `main.dart` is a one-line
    // `switch` over exactly this status, and this is the state that switch
    // reads rather than a rendering of it.
    final race = _season();
    race.ready();
    final next = race.finish()!;
    expect(race.state, isA<RaceOver>());

    race.moveOn(next);

    expect(
      race.state,
      isNot(isA<RaceOver>()),
      reason: 'the finish-line notice should not survive the next load',
    );
  });
}
