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

({RaceCubit race}) _game() => (race: RaceCubit(RaceProgress()));

void main() {
  test('a season starts loading the first circuit, every launch', () {
    // Nothing is saved between launches on purpose. The circuit reached used
    // to be written down, and a player who had once won the first circuit
    // opened the game on the second from then on.
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
    final it = _game();

    it.race.failed(Exception('bad json'), asset: 'assets/tracks/ring.json');

    expect((it.race.state as RaceFailed).asset, 'assets/tracks/ring.json');
    // And the device half stays as it was: nothing to name.
    it.race.failed(Exception('no device'));
    expect((it.race.state as RaceFailed).asset, isNull);
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
    final it = _game();
    it.race.ready();
    final second = it.race.finish()!;
    it.race.moveOn(second);
    it.race.failed(Exception('bad json'), asset: second.track);

    it.race.startOver();

    expect(it.race.circuit.name, Season.first.name);
    expect(it.race.state, isA<RaceLoading>());
  });

  group('finishing a circuit', () {
    test('with another circuit to come, says which', () {
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
    });

    test('at the last circuit, says the season is over', () {
      final it = _game();
      // Walk to the last circuit the way a season actually would, rather
      // than assuming how many there are: `finish` decides what is next, and
      // `moveOn` — the screen's job, once its pause at the finish line has
      // run out — is what actually leaves for it.
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
    });
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
