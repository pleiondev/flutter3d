/// A party over a real relay: seated by one code, held to one simulation
/// version, and refused when it is bigger than the game seats.
///
///     dart test test/party_session_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_game_physics/party.dart';
import 'package:flutter3d_net/flutter3d_net.dart' show PartySeat, joinParty;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

const SimulationVersion _game = SimulationVersion(
  genre: 'party_test',
  genreVersion: 3,
);

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start('dart', <String>[
    'run',
    'bin/relay.dart',
    '0',
  ], workingDirectory: '${Directory.current.path}/../flutter3d_net');
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

Future<PartySession<int>> _open(
  Uri base, {
  required SimulationVersion simulation,
  String? code,
  int size = 3,
  int? seats,
}) => PartySession.open<int>(
  relayBase: base,
  simulation: simulation,
  newCode: () => partyCode(math.Random(1)),
  code: code,
  size: size,
  seats: seats,
  // The game this party plays is the slot it was given, staged.
  stage: (PartySeat seat) => seat.slot,
);

void main() {
  late ({Process process, int port}) relay;
  late Uri base;
  setUpAll(() async {
    relay = await _startRelay();
    base = Uri.parse('ws://127.0.0.1:${relay.port}/');
  });
  tearDownAll(() => relay.process.kill());

  test('one code seats every machine in its own slot, at the size the '
      'first asked for', () async {
    final first = await _open(base, simulation: _game, code: 'SEATS');
    final second = await _open(base, simulation: _game, code: 'SEATS', size: 4);
    final third = await _open(base, simulation: _game, code: 'SEATS');
    final all = <PartySession<int>>[first, second, third];
    addTearDown(() async {
      for (final it in all) {
        await it.dispose();
      }
    });
    // Mutation: the size asked for rather than the relay's.
    expect(all.map((it) => it.size), <int>[3, 3, 3]);
    // Mutation: stage handed something other than the seat.
    expect(all.map((it) => it.game).toSet(), <int>{0, 1, 2});
    expect(all.map((it) => it.slot).toList(), all.map((it) => it.game));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(all.every((it) => it.isFull), isTrue);
  });

  test('a machine on another simulation is turned away by the relay', () async {
    final host = await _open(base, simulation: _game, code: 'VERSN');
    addTearDown(host.dispose);
    // Mutation: the session asks without its version, as the party sessions
    // used to. The relay then compares nothing, and the build on other
    // rules is seated in a game that parts at its first contact.
    await expectLater(
      _open(
        base,
        simulation: const SimulationVersion(
          genre: 'party_test',
          genreVersion: 2,
        ),
        code: 'VERSN',
      ),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('simulation'),
        ),
      ),
    );
  });

  test('a party bigger than the game seats is left, not half played', () async {
    // Another client made it for six.
    final maker = await joinParty(base, 'BIGUN', size: 6, simulation: _game);
    addTearDown(maker.socket.close);
    // Mutation: the seat check dropped — a game staged for six.
    await expectLater(
      _open(base, simulation: _game, code: 'BIGUN', seats: 4),
      throwsA(isA<StateError>()),
    );
  });
}
