/// Read a probe: a kettle's water as the simulation publishes it, shown
/// from the published state and never from the world.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

void main() => runApp(const MaterialApp(home: ReadAProbe()));

class ReadAProbe extends StatefulWidget {
  const ReadAProbe({super.key});

  @override
  State<ReadAProbe> createState() => _ReadAProbeState();
}

class _ReadAProbeState extends State<ReadAProbe> {
  Flutter3dEngine? engine;

  /// Water warming towards the boil, by the simulated seconds.
  static Quantity water(ProbeSample at) =>
      Quantity(100 - 85 * math.exp(-at.seconds / 60), Unit.celsius);

  void install(Flutter3dEngine engine) {
    final world = engine.loop.world;
    // The probe sits on an entity and is read at the end of every step;
    // what it reads, a sampler answers.
    final probe = Probe(id: 'tea', quantity: 'app.tea', unit: Unit.celsius);
    world.set(world.spawn(), probe);
    engine.loop.probeSamplers.add('app.tea', ProbeSampler.of(water));
    setState(() => this.engine = engine);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Flutter3dView(onCreated: install),
      if (engine case final engine?)
        ProbeBuilder(
          published: engine.published,
          probe: 'tea',
          builder: (context, reading) =>
              Text('${reading?.value.single.toStringAsFixed(1) ?? '…'} °C'),
        ),
    ],
  );
}
