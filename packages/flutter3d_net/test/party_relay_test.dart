/// N14 over real sockets: a party of four on the relay, rolling back into
/// agreement, a spectator played the settled tape, and the relay saying
/// who left.
///
///     dart test test/party_relay_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start('dart', <String>[
    'run',
    'bin/relay.dart',
    '0',
  ], workingDirectory: Directory.current.path);
  final port = Completer<int>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (String line) {
      final match = RegExp(r'relay listening on (\d+)').firstMatch(line);
      if (match != null && !port.isCompleted) {
        port.complete(int.parse(match.group(1)!));
      }
    },
  );
  unawaited(process.stderr.drain<void>());
  return (
    process: process,
    port: await port.future.timeout(const Duration(minutes: 2)),
  );
}

List<int> _step(List<int> at, Map<int, Map<String, Object?>> frames) {
  final next = List<int>.of(at);
  for (final MapEntry(:key, :value) in frames.entries) {
    next[key] += (value['dx'] as int?) ?? 0;
  }
  next[0] += next.last % 3;
  return next;
}

int _input(int slot, int n) => ((n * 7 + slot * 13) % 5) - 2;

void main() {
  test('a party of four rolls back into agreement over the relay, a spectator '
      'watches it, and a machine leaving is said', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');
    final code = 'party-${DateTime.now().microsecondsSinceEpoch}';

    const players = 4;
    final left = <int>[];
    final seats = <PartySeat>[
      for (var i = 0; i < players; i++)
        await joinParty(base, code, size: players, left: left.add),
    ];
    // The relay hands out the slots, in the order the machines came.
    expect(seats.map((s) => s.slot), <int>[0, 1, 2, 3]);
    // A fifth player is turned away; it can watch instead.
    await expectLater(
      joinParty(base, code, timeout: const Duration(seconds: 3)),
      throwsA(anything),
    );

    final settled = List<Map<int, List<int>>>.generate(
      players,
      (_) => <int, List<int>>{},
    );
    final tape = PartyTape<List<int>>(wire: seats[0].wire, encode: (s) => s);
    final machines = <PartyRollback<List<int>>>[];
    for (final seat in seats) {
      var at = List<int>.filled(players, 0);
      var captures = 0;
      machines.add(
        PartyRollback<List<int>>(
          wire: seat.wire,
          players: players,
          captureLocalFrame: () => <String, Object?>{
            'dx': _input(seat.slot, captures++),
          },
          applyAndStep: (frames) => at = _step(at, frames),
          save: () => List<int>.of(at),
          restore: (state) => at = List<int>.of(state),
          onSettled: (step, after, frames) {
            settled[seat.slot][step + 1] = after;
            if (seat.slot == 0) tape.settled(step, after, frames);
          },
          onMessage: seat.slot == 0 ? tape.hear : null,
        ),
      );
    }

    final watching = await joinParty(base, code, watching: true);
    expect(watching.slot, players);
    var watched = <int>[];
    final watcher = PartyTapeWatcher<List<int>>(
      wire: watching.wire,
      decode: (encoded) => List<int>.from(encoded! as List),
      restore: (state) => watched = state,
      applyAndStep: (frames) => watched = _step(watched, frames),
    );

    for (var tick = 0; tick < 240; tick++) {
      for (final machine in machines) {
        machine.advance();
      }
      if (tick > 60) {
        watcher
          ..ask()
          ..advance();
      }
      // Real sockets: let the messages move.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    // Every machine settled the same states, step for step.
    for (var slot = 1; slot < players; slot++) {
      for (final MapEntry(key: step, value: state) in settled[slot].entries) {
        if (settled[0][step] case final List<int> host) {
          expect(state, host, reason: 'slot $slot, step $step');
        }
      }
    }
    expect(watcher.next, isNotNull);
    expect(watched, settled[0][watcher.next!]);

    // One goes; the others are told which.
    await seats[2].socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(left, contains(2));
    for (final seat in seats) {
      await seat.socket.close();
    }
    await watching.socket.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
