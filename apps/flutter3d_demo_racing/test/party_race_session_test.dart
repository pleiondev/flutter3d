/// The racing game's door onto the relay's parties: three machines given
/// three cars by one code, each hearing the other two, and a party bigger
/// than a grid refused.
///
///     flutter test test/party_race_session_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/net_race_session.dart';
import 'package:flutter3d_demo_racing/src/party_race_session.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _throttle = GameAction('throttle');

TrackDocument _ring() => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/ring.json').readAsStringSync())
      as Map<String, Object?>,
);

CollisionWorld _worldFor(TrackDocument document) {
  final world = CollisionWorld();
  document.level?.addTo(world);
  return world;
}

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start(
    'dart',
    <String>['run', 'bin/relay.dart', '0'],
    workingDirectory: '${Directory.current.path}/../../packages/flutter3d_net',
  );
  final portFound = Completer<int>();
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final match = RegExp(
          r'flutter3d_net relay listening on (\d+)',
        ).firstMatch(line);
        if (match != null && !portFound.isCompleted) {
          portFound.complete(int.parse(match.group(1)!));
        }
      });
  final port = await portFound.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      process.kill();
      throw StateError('the relay never printed the port it bound to');
    },
  );
  await subscription.cancel();
  return (process: process, port: port);
}

Future<PartyRaceSession> _open(
  Uri base, {
  String? code,
  required int size,
  required InputState input,
  bool find = false,
  String circuit = 'assets/tracks/ring.json',
}) {
  final document = _ring();
  return PartyRaceSession.open(
    relayBase: base,
    document: document,
    world: _worldFor(document),
    input: input,
    code: code,
    size: size,
    find: find,
    circuit: circuit,
  );
}

void main() {
  test('one code seats three machines in three cars, and each hears the '
      'other two', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');

    final inputs = List<InputState>.generate(3, (_) => InputState());
    final first = await _open(base, size: 3, input: inputs[0]);
    // The later two ask for four; the party is what its maker asked for.
    final second = await _open(
      base,
      code: first.code,
      size: 4,
      input: inputs[1],
    );
    final third = await _open(
      base,
      code: first.code,
      size: 4,
      input: inputs[2],
    );
    final all = <PartyRaceSession>[first, second, third];
    addTearDown(() async {
      for (final it in all) {
        await it.dispose();
      }
    });

    // Mutation: the size asked for rather than the relay's, or a fixed car.
    expect(all.map((it) => it.size), <int>[3, 3, 3]);
    expect(all.map((it) => it.localCarIndex).toSet(), <int>{0, 1, 2});
    expect(all.map((it) => it.race.cars), <int>[3, 3, 3]);

    for (var step = 0; step < 240; step++) {
      for (final (index, it) in all.indexed) {
        inputs[index].setActionValue(_throttle, 1.0);
        it.advance();
        inputs[index].endStep();
      }
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    expect(all.map((it) => it.heard), <int>[2, 2, 2]);
  });

  test('a party bigger than the grid is refused, not half raced', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');

    // Another client made it for six, on the same simulation: a maker on
    // none would be refused for its version, and this would pass for that.
    final maker = await joinParty(
      base,
      'BIGUN',
      size: 6,
      terms: NetRaceSession.terms,
      simulation: racingSimulationVersion,
    );
    addTearDown(maker.socket.close);
    // Mutation: the size check dropped — a race staged for six cars.
    await expectLater(
      _open(base, code: 'BIGUN', size: 4, input: InputState()),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('seats'),
        ),
      ),
    );
  });

  test('a party asks with the racing simulation, so another build is turned '
      'away', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');

    final host = await _open(base, code: 'RULES', size: 3, input: InputState());
    addTearDown(host.dispose);
    // Mutation: open the party with no simulation version, as it once was.
    // A build on the old rules made the party and this one was seated in it.
    await expectLater(
      joinParty(
        base,
        'RULES',
        terms: NetRaceSession.terms,
        simulation: SimulationVersion(
          genre: racingSimulationVersion.genre,
          genreVersion: racingSimulationVersion.genreVersion + 1,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('Find a race seats strangers on one circuit together, says when the '
      'grid is full, and keeps circuits apart', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');

    final first = await _open(base, size: 3, find: true, input: InputState());
    final stranger = await _open(
      base,
      size: 3,
      find: true,
      circuit: 'assets/tracks/gorge.json',
      input: InputState(),
    );
    final second = await _open(base, size: 3, find: true, input: InputState());
    expect(first.full, isFalse);
    final third = await _open(base, size: 3, find: true, input: InputState());
    final all = <PartyRaceSession>[first, second, third, stranger];
    addTearDown(() async {
      for (final it in all) {
        await it.dispose();
      }
    });

    // Mutation: the circuit left out of the ask — the gorge's
    // driver takes the ring's second car.
    expect(<String>{first.code, second.code, third.code}, hasLength(1));
    expect(stranger.code, isNot(first.code));
    expect(
      <int>{first.localCarIndex, second.localCarIndex, third.localCarIndex},
      <int>{0, 1, 2},
    );
    // Mutation: the relay's word that the grid is full not kept.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      <bool>[first.full, second.full, third.full],
      <bool>[true, true, true],
    );
    expect(stranger.full, isFalse);
  });
}
