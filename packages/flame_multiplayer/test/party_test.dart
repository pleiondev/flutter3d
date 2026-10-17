/// N14: more than two machines — rollback for a party, a spectator played
/// the settled tape, and an authority with machines predicting under it.
library;

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationVersion;
import 'package:test/test.dart';

/// Where everybody is: one number a slot, and each step's moves coupled so
/// a wrong guess about one machine moves the others too.
List<int> _step(List<int> at, Map<int, Map<String, Object?>> frames) {
  final next = List<int>.of(at);
  for (final MapEntry(:key, :value) in frames.entries) {
    next[key] += (value['dx'] as int?) ?? 0;
  }
  next[0] += next.last % 3;
  return next;
}

/// What machine [slot] presses at its [n]th capture: changing often, so a
/// guess from the last frame is often wrong.
int _input(int slot, int n) => ((n * 7 + slot * 13) % 5) - 2;

/// The game played with every frame known: what every machine should
/// settle on.
List<List<int>> _truth(int players, int steps, int delay) {
  var at = List<int>.filled(players, 0);
  final states = <List<int>>[at];
  for (var s = 0; s < steps; s++) {
    at = _step(at, <int, Map<String, Object?>>{
      for (var p = 0; p < players; p++)
        p: s < delay
            ? const <String, Object?>{}
            : <String, Object?>{'dx': _input(p, s - delay)},
    });
    states.add(at);
  }
  return states;
}

void main() {
  test('four machines, late and lossy, settle every step on the truth', () {
    const players = 4;
    const delay = 2;
    final party = LoopbackParty(players, delaySteps: 3, lossRate: 0.1, seed: 5);
    final settled = List<Map<int, List<int>>>.generate(
      players,
      (_) => <int, List<int>>{},
    );
    final machines = <RollbackSession<List<int>>>[];
    for (var slot = 0; slot < players; slot++) {
      var at = List<int>.filled(players, 0);
      var captures = 0;
      machines.add(
        RollbackSession<List<int>>(
          wire: party.wire(slot),
          players: players,
          inputDelay: delay,
          maxRollbackFrames: 12,
          captureLocalFrame: () => <String, Object?>{
            'dx': _input(slot, captures++),
          },
          applyAndStep: (step) => at = _step(at, step.frames),
          save: () => List<int>.of(at),
          restore: (state) => at = List<int>.of(state),
          onSettled: (s) => settled[slot][s.step + 1] = s.after,
        ),
      );
    }
    for (var tick = 0; tick < 300; tick++) {
      for (final machine in machines) {
        machine.advance();
      }
      party.tick();
    }
    final truth = _truth(players, 300, delay);
    // Mutation: a correction that runs the steps since on the old guess,
    // or that forgets the slot's other steps — the machines part.
    for (var slot = 0; slot < players; slot++) {
      expect(machines[slot].droppedCorrections, 0, reason: 'slot $slot');
      expect(settled[slot], isNotEmpty);
      for (final MapEntry(key: step, value: state) in settled[slot].entries) {
        expect(state, truth[step], reason: 'slot $slot, step $step');
      }
    }
    // And the guesses were wrong often enough for that to mean something.
    expect(
      machines.map((m) => m.stepsRerun).reduce((a, b) => a + b),
      greaterThan(100),
    );
  });

  test(
    'a spectator arriving late is sent the state and plays on to the truth',
    () {
      const players = 3;
      const delay = 1;
      // Slot three watches.
      final party = LoopbackParty(players + 1, delaySteps: 2, seed: 9);
      final tape = PartyTape<List<int>>(
        wire: party.wire(0),
        encode: (state) => state,
      );
      final machines = <RollbackSession<List<int>>>[];
      for (var slot = 0; slot < players; slot++) {
        var at = List<int>.filled(players, 0);
        var captures = 0;
        machines.add(
          RollbackSession<List<int>>(
            wire: slot == 0 ? party.wire(0) : party.wire(slot),
            players: players,
            inputDelay: delay,
            captureLocalFrame: () => <String, Object?>{
              'dx': _input(slot, captures++),
            },
            applyAndStep: (step) => at = _step(at, step.frames),
            save: () => List<int>.of(at),
            restore: (state) => at = List<int>.of(state),
            onSettled: slot == 0 ? tape.settled : null,
            onMessage: slot == 0 ? tape.hear : null,
          ),
        );
      }
      var watched = <int>[];
      final watcher = PartyTapeWatcher<List<int>>(
        wire: party.wire(players),
        decode: (encoded) => List<int>.of(encoded! as List<int>),
        restore: (state) => watched = state,
        applyAndStep: (frames) => watched = _step(watched, frames),
      );
      for (var tick = 0; tick < 200; tick++) {
        for (final machine in machines) {
          machine.advance();
        }
        // It turns up a quarter of the way through, and watches.
        if (tick >= 50) {
          watcher
            ..ask()
            ..advance();
        }
        party.tick();
      }
      final truth = _truth(players, 200, delay);
      // Mutation: a host that sends the steps but not the state to start
      // them from — the spectator plays from nothing.
      expect(watcher.next, isNotNull);
      expect(watcher.next, greaterThan(100));
      expect(watched, truth[watcher.next!]);
    },
  );

  test('under an authority, every machine ends where the authority is', () {
    const players = 4;
    final party = LoopbackParty(
      players,
      delaySteps: 2,
      lossRate: 0.15,
      seed: 3,
    );
    var server = List<int>.filled(players, 0);
    final authority = AuthorityServer<List<int>>(
      wire: party.wire(0),
      players: players,
      applyAndStep: (frames) => server = _step(server, frames),
      save: () => List<int>.of(server),
      encode: (state) => state,
    );
    final views = List<List<int>>.generate(
      players,
      (_) => List<int>.filled(players, 0),
    );
    var pressing = true;
    final clients = <PredictingClient<List<int>>>[
      for (var slot = 1; slot < players; slot++)
        () {
          var captures = 0;
          return PredictingClient<List<int>>(
            wire: party.wire(slot),
            captureLocalFrame: () => <String, Object?>{
              'dx': pressing ? _input(slot, captures++) : 0,
            },
            predict: (frame) => views[slot] = _step(
              views[slot],
              <int, Map<String, Object?>>{slot: frame},
            ),
            restore: (state) => views[slot] = List<int>.of(state),
            decode: (encoded) => List<int>.of(encoded! as List<int>),
          );
        }(),
    ];
    for (var tick = 0; tick < 240; tick++) {
      if (tick == 180) pressing = false;
      for (final client in clients) {
        client.advance();
      }
      authority.advance();
      party.tick();
    }
    // Mutation: a client that takes the state and does not run its own
    // unacknowledged hands again on it — or runs the acknowledged too.
    expect(
      clients.map((c) => c.replayed).reduce((a, b) => a + b),
      greaterThan(0),
    );
    for (var slot = 1; slot < players; slot++) {
      expect(views[slot], server, reason: 'slot $slot');
    }
    // The acknowledgements keep up: what is still waiting is no more than
    // the round trip and a snapshot's interval hold — a client that kept
    // what the authority had run would pile up every frame it ever sent.
    expect(clients.map((c) => c.unacknowledged), everyElement(lessThan(12)));
  });

  group('the hello before the party', () {
    // The other build's hello: the next protocol major.
    const ahead = WireHello(
      simulation: SimulationVersion.engineOnly,
      protocolMajor: WireHello.currentProtocolMajor + 1,
    );

    test('an authority runs no hands from a machine that said no hello, or '
        'one it cannot play with, and each side says why', () {
      final party = LoopbackParty(3);
      final ran = <int, int>{};
      final authority = AuthorityServer<int>(
        wire: party.wire(0),
        players: 3,
        applyAndStep: (frames) {
          for (final MapEntry(:key, :value) in frames.entries) {
            if (value['dx'] case final int dx) ran[key] = (ran[key] ?? 0) + dx;
          }
        },
        save: () => 0,
        encode: (s) => s,
        snapshotEvery: 1,
      );
      final other = PredictingClient<int>(
        wire: party.wire(1),
        captureLocalFrame: () => const <String, Object?>{'dx': 1},
        predict: (_) {},
        restore: (_) {},
        decode: (e) => e! as int,
        hello: ahead,
      );
      for (var tick = 0; tick < 20; tick++) {
        other.advance();
        // Slot two sends hands the way a build from before the hello did:
        // under the key, with no hello. Mutation: queue hands before a
        // hello is heard, and these run.
        party
            .wire(2)
            .send(
              PeerSend(
                message: const <String, Object?>{
                  'f3d': 'party',
                  'event': 'inputs',
                  'inputs': <String, Object?>{
                    '0': <String, Object?>{'dx': 5},
                  },
                },
                reliable: false,
              ),
            );
        authority.advance();
        party.tick();
      }
      // Mutation: the hello not compared — the next major's hands run.
      expect(ran, isEmpty);
      expect(
        authority.refusals[1],
        contains('update this game to protocol ${ahead.protocolMajor}'),
      );
      expect(authority.refusals.containsKey(2), isFalse);
      // The client reads the authority's hello off its state and refuses it
      // in its own words.
      expect(
        other.refusal,
        contains('update the other game to protocol ${ahead.protocolMajor}'),
      );
    });

    test('a spectator on another protocol is told so and sent no tape, and a '
        'party\'s messages never reach the game as its own', () {
      final party = LoopbackParty(3);
      final tape = PartyTape<int>(wire: party.wire(0), encode: (s) => s);
      final heardByGame = <Map<String, Object?>>[];
      party.wire(0).listenFrom((heard) {
        tape.hear(heard);
        if (heard.message['f3d'] == null) heardByGame.add(heard.message);
      });
      var restored = false;
      final watcher = PartyTapeWatcher<int>(
        wire: party.wire(1),
        decode: (e) => e! as int,
        restore: (_) => restored = true,
        applyAndStep: (_) {},
        hello: ahead,
      );
      final welcome = PartyTapeWatcher<int>(
        wire: party.wire(2),
        decode: (e) => e! as int,
        restore: (_) => restored = true,
        applyAndStep: (_) {},
      );
      for (var step = 0; step < 6; step++) {
        tape.settled(
          SettledStep<int>(
            step: step,
            after: step,
            frames: const <int, Map<String, Object?>>{},
          ),
        );
        watcher.ask();
        party.tick();
      }
      expect(watcher.refusal, contains('protocol ${ahead.protocolMajor}'));
      expect(watcher.next, isNull);
      expect(restored, isFalse);
      expect(tape.refusals.keys, <int>[1]);
      // A spectator on this build is let in once it asks.
      welcome.ask();
      // One tick for the ask to arrive, one for the answer.
      party
        ..tick()
        ..tick();
      expect(welcome.refusal, isNull);
      expect(welcome.next, 6);
      // Mutation: the ask back as a bare `{"watching": true}` — a game's
      // own message would then start the tape.
      expect(heardByGame, isEmpty);
    });
  });
}
