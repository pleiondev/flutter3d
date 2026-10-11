/// Probes: declared in the simulation, read after the publish phase,
/// published to the view, traced for the run file.
///
///     dart test test/probe_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A plate that warms by a kelvin a step.
void _warm(LoopContext context) {
  final world = context.world;
  for (final entity
      in world.query().having<MaterialStateComponent>().entities.toList()) {
    final state = world.get<MaterialStateComponent>(entity)!.state;
    world.set<MaterialStateComponent>(
      entity,
      MaterialStateComponent(
        state.withQuantity(
          MaterialState.temperatureId,
          Quantity(state.temperature + 1, Unit.kelvin),
        ),
      ),
    );
  }
}

(EngineLoop, Entity) _plate(Probe probe) {
  final loop = EngineLoop(input: InputState());
  final plate = loop.world.spawn();
  loop.world
    ..set<MaterialStateComponent>(
      plate,
      MaterialStateComponent(MaterialState.at(temperature: 300)),
    )
    ..set<Probe>(plate, probe);
  loop.addSystem('test.warm', LoopPhase.fields, _warm);
  return (loop, plate);
}

void main() {
  test('a probe on a body reads its material state after the step', () {
    final (loop, _) = _plate(
      Probe(
        id: 'plate.t',
        quantity: MaterialState.temperatureId,
        unit: Unit.celsius,
      ),
    );
    loop.runSteps(2);
    final reading = loop.published.probe('plate.t')!;
    expect(reading.step, 2);
    // 302 K in degrees Celsius: read in the probe's unit.
    expect(reading.value.single, closeTo(28.85, 1e-9));
    expect(reading.unit, Unit.celsius);
    expect(reading.kind, ReadingKind.simulated);
  });

  test('a derived expression is published instead, compiled once', () {
    final probe = Probe(
      id: 'plate.rise',
      quantity: MaterialState.temperatureId,
      unit: Unit.kelvin,
      derived: 'x - 300 [K] + t * 0 [K/s]',
    );
    final (loop, _) = _plate(probe);
    loop.runSteps(3);
    expect(loop.probeReadings.single.value.single, closeTo(3, 1e-12));
    expect(identical(probe.compiled, probe.compiled), isTrue);
  });

  test('a derived expression that does not read is refused, naming the '
      'probe', () {
    expect(
      () => Probe.fromJson(<String, Object?>{
        'id': 'p',
        'quantity': 'f3d.temperature',
        'unit': 'K',
        'derived': 'x +',
      }),
      throwsA(
        isA<PluginFormatException>().having(
          (e) => e.message,
          'message',
          contains('"p"'),
        ),
      ),
    );
  });

  test('a sampler reads a quantity at a point', () {
    final loop = EngineLoop(input: InputState());
    loop.probeSamplers.add(
      'test.depth',
      ProbeSampler.of(
        (sample) => switch (sample.probe.region) {
          ProbePoint(:final at) => Quantity(-at.y, Unit.meter),
          _ => null,
        },
      ),
    );
    final buoy = loop.world.spawn();
    loop.world.set<Probe>(
      buoy,
      Probe(
        id: 'buoy',
        quantity: 'test.depth',
        unit: Unit.meter,
        region: const ProbePoint(WorldPosition(0, -4, 0)),
      ),
    );
    loop.runSteps(1);
    expect(loop.probeReadings.single.value, <double>[4]);
  });

  test(
    'the codec round-trips every region, and keeps one it does not know',
    () {
      for (final region in <ProbeRegion>[
        const ProbeBody(),
        const ProbePoint(WorldPosition(1, 2, 3)),
        const ProbeSection(
          origin: WorldPosition(0, 1, 0),
          normal: WorldPosition(0, 0, 1),
        ),
        ProbeRegion.fromJson(<String, Object?>{'kind': 'volume', 'size': 2}),
      ]) {
        final probe = Probe(
          id: 'p',
          quantity: 'f3d.temperature',
          unit: Unit.kelvin,
          region: region,
          derived: 'x * 2',
        );
        final back = Probe.codec.decode(Probe.codec.encode(probe), 1)!;
        expect(back.toJson(), probe.toJson());
      }
    },
  );

  test('a probe leaves the world as the step left it', () {
    final (probed, plate) = _plate(
      Probe(id: 't', quantity: MaterialState.temperatureId, unit: Unit.kelvin),
    );
    final (bare, other) = _plate(
      Probe(id: 't', quantity: MaterialState.temperatureId, unit: Unit.kelvin),
    );
    bare.world.remove<Probe>(other);
    probed.runSteps(5);
    bare.runSteps(5);
    expect(
      probed.world.get<MaterialStateComponent>(plate)!.state.temperature,
      bare.world.get<MaterialStateComponent>(other)!.state.temperature,
    );
  });

  test('a trace keeps every step\'s readings in step order', () {
    final (loop, _) = _plate(
      Probe(id: 't', quantity: MaterialState.temperatureId, unit: Unit.kelvin),
    );
    final trace = ProbeTrace()..record(loop);
    loop.runSteps(3);
    expect(trace.readings.map((r) => r.step), <int>[1, 2, 3]);
    expect(trace.readings.last.value.single, 303);
  });
}
