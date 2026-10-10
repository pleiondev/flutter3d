/// A published state as plain values, and back: what crosses an isolate's
/// port or a socket.
///
///     dart test test/published_wire_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

void main() {
  final state = PublishedState(
    step: 12,
    seconds: 0.2,
    origin: const WorldPosition(1000.5, 0, -3),
    components: <String, Map<Entity, Object?>>{
      'body': <Entity, Object?>{
        const Entity.of(3, 1): <String, Object?>{
          'at': <double>[1, 2, 3],
        },
      },
    },
    positions: <Entity, WorldPosition>{
      const Entity.of(3, 1): const WorldPosition(1001.5, 2, 0),
    },
    events: <PublishedEvent>[
      PublishedEvent(
        name: OriginShifted.eventName,
        version: 1,
        data: OriginShifted.codec.encode(
          const OriginShifted(
            from: WorldPosition.origin,
            to: WorldPosition(1000.5, 0, -3),
          ),
        ),
        step: 11,
        sequence: 0,
        resimulated: false,
      ),
    ],
    simulation: const SimulationVersion(genre: 'platformer', genreVersion: 2),
  );

  test('reads back what it wrote, through JSON too', () {
    // Mutation: write an entity as its index alone — the generation is
    // lost, and a recycled entity reads as the one that died.
    final read = PublishedState.fromWire(
      jsonDecode(jsonEncode(state.toWire())),
    );
    expect(read.step, 12);
    expect(read.seconds, 0.2);
    expect(read.origin, const WorldPosition(1000.5, 0, -3));
    expect(read.components['body']?.keys, <Entity>[const Entity.of(3, 1)]);
    expect(
      read.positionOf(const Entity.of(3, 1)),
      const WorldPosition(1001.5, 2, 0),
    );
    expect(read.simulation, state.simulation);
    final event = read.events.single;
    expect(
      (event.name, event.step, event.sequence, event.resimulated),
      (OriginShifted.eventName, 11, 0, false),
    );
    expect(
      event.decode(OriginShifted.codec)?.to,
      const WorldPosition(1000.5, 0, -3),
    );
  });

  test('refuses what is not one, with a sentence', () {
    // Mutation: answer an empty state for a broken one — the view draws
    // nothing and no one hears why.
    expect(
      () => PublishedState.fromWire(<String, Object?>{'step': 'twelve'}),
      throwsA(isA<PluginFormatException>()),
    );
    final wire = state.toWire()
      ..['positions'] = <Object?>[
        <Object?>[1],
      ];
    expect(
      () => PublishedState.fromWire(wire),
      throwsA(isA<PluginFormatException>()),
    );
  });
}
