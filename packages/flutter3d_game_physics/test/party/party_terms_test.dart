/// What a session asks the relay with: a code, the terms, and the
/// simulation's version, and one side's run kept from what it recorded.
///
///     dart test test/party_terms_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_game_physics/party.dart';
import 'package:flutter3d_net/flutter3d_net.dart' show relayRoom;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

const SimulationVersion _game = SimulationVersion(
  genre: 'party_test',
  genreVersion: 3,
);

void main() {
  test('a code reads unambiguously and is the same for the same dice', () {
    final dice = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final code = partyCode(dice);
      expect(code.length, 5);
      // Mutation: the full alphabet — an `O` read aloud as a nought.
      for (final confusable in <String>['0', 'O', '1', 'I']) {
        expect(code, isNot(contains(confusable)));
      }
    }
    expect(partyCode(math.Random(3)), partyCode(math.Random(3)));
  });

  test('the relay compares one number: the engine and the game', () {
    // Mutation: fold only the game's number in. A new engine that moves a
    // body differently would still meet the old one.
    expect(relayVersionOf(_game), _game.engine * 1000 + 3);
    expect(
      relayVersionOf(_game),
      isNot(
        relayVersionOf(const SimulationVersion(engine: 2, genreVersion: 3)),
      ),
    );
    expect(physicsTerms, startsWith('physics='));
  });

  test('a room is asked for with the simulation, as relayRoom does', () {
    final base = Uri.parse('ws://127.0.0.1:9000/');
    final address = RoomSession.address(
      base,
      'ABCDE',
      simulation: _game,
      terms: 'physics=dart',
    );
    // Mutation: the address built with the terms alone. The relay hears no
    // simulation, and a build on other rules joins a session that parts at
    // its first contact instead of being closed with a reason.
    expect(
      address,
      relayRoom(base, 'ABCDE', terms: 'physics=dart', simulation: _game),
    );
    expect(address.queryParameters['simulation'], _game.describe());
    expect(address.pathSegments, <String>['room', 'ABCDE']);
  });

  test("one side's run carries its start, its level and what it settled", () {
    const start = Snapshot(<String, Object?>{'random': 11, 'x': 1});
    final recording = SideRecording(
      start: start,
      level: 'assets/levels/yard.json',
      levelHash: 'abc',
    );
    final input = InputState();
    for (var step = 0; step < 3; step++) {
      recording
        ..record(input)
        ..settled(step, Snapshot(<String, Object?>{'x': step}));
    }
    final demo = recording.toDemo(buildStamp: 'test');
    expect(demo.level, 'assets/levels/yard.json');
    expect(demo.levelHash, 'abc');
    expect(demo.start.data, start.data);
    // Mutation: the settled states left out of the run — two sides' files
    // then agree whatever they did.
    expect(demo.checkpoints, same(recording.checkpoints));
    expect(demo.tape.steps, 3);
    expect(demo.tape.seed, 11);
  });
}
