/// Observing an authoritative simulation: the tape to a build that replays
/// it, poses to one that cannot or to a simulation that promises no bits,
/// and each observer only the probes it asked for.
///
///     dart test test/observer_test.dart
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A tank the plant's sensor fills, read by two probes.
final class _Tank {
  const _Tank(this.level);

  final double level;

  static final ComponentCodec<_Tank> codec = ComponentCodec<_Tank>.of(
    id: 'test.tank',
    encode: (tank) => tank.level,
    decode: (context) {
      final data = context.data;
      return data is num ? _Tank(data.toDouble()) : null;
    },
  );
}

const String _depth = 'test.depth';

EngineLoop _plant({
  SimulationProfile profile = SimulationProfile.deterministic,
}) {
  final loop = EngineLoop(input: InputState(), profile: profile);
  loop.world.components.register<_Tank>(_Tank.codec, published: true);
  final tank = loop.world.spawn();
  loop.world
    ..set<_Tank>(tank, const _Tank(0))
    ..set<WorldPosition>(tank, const WorldPosition(1, 2, 3));
  for (final id in <String>['tank.level', 'tank.half']) {
    loop.world.set<Probe>(
      loop.world.spawn(),
      Probe(
        id: id,
        quantity: _depth,
        unit: Unit.meter,
        region: const ProbePoint(WorldPosition.origin),
        derived: id == 'tank.half' ? 'x / 2' : null,
      ),
    );
  }
  loop.probeSamplers.add(
    _depth,
    ProbeSampler.of((sample) {
      final tanks = sample.world.query().having<_Tank>().entities;
      return Quantity(sample.world.get<_Tank>(tanks.first)!.level, Unit.meter);
    }),
  );
  loop.addAssimilation(
    'test.fill',
    Assimilation.of((context) {
      for (final reading in context.from('sensor')) {
        final tank = context.world.query().having<_Tank>().entities.first;
        context.world.set<_Tank>(tank, _Tank(reading.quantity.value));
      }
    }),
  );
  return loop;
}

/// Runs [steps] steps of [loop] fed a rising level, handing each to [feed].
void _run(EngineLoop loop, ObserverFeed feed, LoopbackParty party, int steps) {
  final recorder = InputTapeRecorder(seed: 0);
  loop.recorders.add(recorder);
  var fed = 0.0;
  final feeding = loop.onStepInput((input) {
    fed += 0.25;
    input.feedExternal(
      ExternalStateInput.quantity('sensor', Quantity(fed, Unit.meter)),
    );
  });
  for (var i = 0; i < steps; i++) {
    loop.runSteps(1);
    feed.stepped(recorder.tape.frames.last, loop.published);
    party.step();
  }
  feeding.cancel();
  loop.recorders.remove(recorder);
}

void main() {
  test('an observer on the same simulation is sent the tape and replays '
      'the telemetry to the same state', () {
    final party = LoopbackParty(3);
    final plant = _plant();
    final feed = ObserverFeed(
      wire: party.wire(0),
      simulation: plant.simulationVersion,
      capture: plant.capture,
    );
    _run(plant, feed, party, 2);

    final copy = _plant();
    final readings = <List<ProbeReading>>[];
    final observer = SimulationObserver(
      wire: party.wire(1),
      simulation: copy.simulationVersion,
      filter: const ObserverFilter(probes: <String>{'tank.half'}),
      restore: (restore) => copy.rewindTo(restore.step, state: restore.start),
      replay: (input) {
        copy.playback = InputTapePlayback.tape(
          InputTape(seed: 0, frames: <InputFrame>[input]),
        );
        copy.runSteps(1);
      },
      readings: readings.add,
    )..join();
    party
      ..step()
      ..step();
    expect(observer.mode, ObserverMode.tape);
    _run(plant, feed, party, 3);
    party.step();
    expect(copy.capture().toJson(), plant.capture().toJson());
    expect(copy.probeReadings, plant.probeReadings);
    // Its filter: only the probe it asked for.
    expect(readings.last.map((r) => r.probe), <String>['tank.half']);
    expect(readings.last.single.value.single, closeTo(0.75 / 2, 1e-12));
  });

  test('an accurate simulation sends poses, each observer its own probes', () {
    final party = LoopbackParty(3);
    final plant = _plant(profile: SimulationProfile.accurate);
    final feed = ObserverFeed(
      wire: party.wire(0),
      simulation: plant.simulationVersion,
      capture: plant.capture,
    );
    _run(plant, feed, party, 1);
    final shown = <int, List<PublishedState>>{1: [], 2: []};
    final watchers = <SimulationObserver>[
      for (final (slot, probes) in <(int, Set<String>?)>[
        (1, <String>{'tank.level'}),
        (2, null),
      ])
        SimulationObserver(
          wire: party.wire(slot),
          // The same build: a tape would replay, but its profile promises
          // no bits, so poses it is.
          simulation: plant.simulationVersion,
          filter: ObserverFilter(probes: probes),
          show: shown[slot]!.add,
        )..join(),
    ];
    party
      ..step()
      ..step();
    _run(plant, feed, party, 2);
    party.step();
    expect(watchers.map((w) => w.mode), everyElement(ObserverMode.poses));
    final first = shown[1]!.last;
    expect(first.positions.values.single, const WorldPosition(1, 2, 3));
    expect(first.probes.map((p) => p.probe), <String>['tank.level']);
    expect(shown[2]!.last.probes.map((p) => p.probe), <String>[
      'tank.level',
      'tank.half',
    ]);
    expect(first.simulation.profile, SimulationProfile.accurate);
  });

  test('a build on another simulation is sent poses, not a tape it would '
      'refuse', () {
    final party = LoopbackParty(2);
    final plant = _plant();
    final feed = ObserverFeed(
      wire: party.wire(0),
      simulation: plant.simulationVersion,
      capture: plant.capture,
    );
    final observer = SimulationObserver(
      wire: party.wire(1),
      simulation: const SimulationVersion(genre: 'racing'),
    )..join();
    party.step();
    _run(plant, feed, party, 1);
    expect(observer.mode, ObserverMode.poses);
    expect(feed.observers, <int>[1]);
  });
}
