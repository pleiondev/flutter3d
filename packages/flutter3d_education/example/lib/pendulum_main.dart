/// A laboratory: a pendulum on the accurate profile, with a clock you move.
///
///     flutter run -d macos -t lib/pendulum_main.dart
///
/// **One [Flutter3dView], the simulation placed apart.** The laboratory
/// runs on [SimulationProfile.accurate], in a loop it builds itself in
/// [pendulumSimulation], which the view places in an isolate (in the page
/// on the web) and steps by the view's clock. A laboratory that wants the
/// accurate profile on the view's own loop, inline, says so with
/// `LoopSettings(profile: SimulationProfile.accurate)`; this one builds its
/// own so that it can be placed apart. What the panel shows is what
/// the laboratory's probes published: the angle, and the period measured
/// from the crossings of the vertical beside the one the series gives.
///
/// **Time moves when you move it.** The view's clock is a [ManualTime]:
/// "Step" hands it one fixed step, "Run" a step's worth every frame until
/// pressed again. The fixed step is the loop's, so stepping by hand and
/// running give the same swing.
///
/// A laboratory a server verifies by replaying the student's run stays on
/// the deterministic profile; the accurate one is for showing, and what it
/// ships is poses.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show ManualTime, standardStepRate;

import 'src/pendulum_lab.dart';

void main() => runApp(const _PendulumApp());

class _PendulumApp extends StatelessWidget {
  const _PendulumApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A pendulum',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6FD6),
        brightness: Brightness.dark,
      ),
    ),
    home: const PendulumScreen(),
  );
}

/// The pendulum, the readings over it and the clock under it.
class PendulumScreen extends StatefulWidget {
  /// A screen drawing with [device] and running the laboratory where
  /// [simulation] places it.
  const PendulumScreen({
    super.key,
    this.device = const DeviceSettings(),
    this.simulation = const SimulationPlacement.isolate(
      pendulumSimulation,
      debugName: 'pendulum',
    ),
  });

  /// The device the view draws with: its own by default, a test's in a test.
  final DeviceSettings device;

  /// Where the laboratory runs: in an isolate by default.
  final SimulationPlacement simulation;

  @override
  State<PendulumScreen> createState() => _PendulumScreenState();
}

class _PendulumScreenState extends State<PendulumScreen> {
  final ManualTime _clock = ManualTime();

  /// The fixed step the laboratory's loop runs at, which "Step" hands over.
  static const double _step = 1.0 / standardStepRate;

  /// The pivot, turned by the published angle; the rod and the bob hang
  /// from it.
  final SceneNode _pivot = SceneNode(name: 'pivot');
  Flutter3dEngine? _engine;
  bool _running = false;

  void _open(Flutter3dEngine engine) {
    const length = PendulumLab.length;
    final steel = RenderMaterial(
      name: 'steel',
      baseColor: LinearColor.fromSrgb(0.75, 0.76, 0.78, 1),
      metallic: 1,
      roughness: 0.3,
    );
    engine.scene
      ..add(
        MeshNode(
          DeviceMesh.upload(
            engine.device,
            CuboidShape(size: Vector3(0.6, 0.04, 0.2)).build(),
          ),
          steel,
          name: 'beam',
        )..setPosition(0, length + 0.52, 0),
      )
      ..add(_pivot..setPosition(0, length + 0.5, 0));
    _pivot
      ..add(
        MeshNode(
          DeviceMesh.upload(
            engine.device,
            const CylinderShape(
              radiusTop: 0.006,
              radiusBottom: 0.006,
              height: length,
            ).build(),
          ),
          steel,
          name: 'rod',
        )..setPosition(0, -length / 2, 0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            engine.device,
            const SphereShape(radius: 0.05).build(),
          ),
          RenderMaterial(
            name: 'bob',
            baseColor: LinearColor.fromSrgb(0.85, 0.6, 0.2, 1),
            metallic: 1,
            roughness: 0.25,
          ),
          name: 'bob',
        )..setPosition(0, -length, 0),
      );
    engine.camera
      ..setPosition(0, length * 0.6, 2.6)
      ..lookAt(Vector3(0, length * 0.6, 0));
    setState(() => _engine = engine);
  }

  static String _number(ProbeReading? reading, int digits, String unit) =>
      reading == null
      ? '—'
      : '${reading.value.single.toStringAsFixed(digits)} $unit';

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Flutter3dView(
              device: widget.device,
              time: _clock,
              loop: LoopSettings(simulation: widget.simulation),
              onCreated: _open,
              onBeforeFrame: (_) {
                // Running is the hand on the clock every frame: a step's
                // worth of time, whatever the display's rate.
                if (_running) _clock.advance(_step);
              },
              onFrame: (EngineFrame f) {
                final angle = f.engine.published.value.probe(
                  PendulumLab.angleProbe,
                );
                if (angle != null) {
                  _pivot.setRotationYawPitchRoll(0, 0, angle.value.single);
                }
              },
            ),
          ),
          if (engine != null)
            Positioned(
              left: 16,
              top: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Profile: ${SimulationProfile.accurate}',
                        style: text.bodySmall,
                      ),
                      ProbeBuilder(
                        published: engine.published,
                        probe: PendulumLab.angleProbe,
                        builder: (context, reading) => Text(
                          'Angle: ${_number(reading, 4, 'rad')}',
                          style: text.titleMedium,
                        ),
                      ),
                      ProbeBuilder(
                        published: engine.published,
                        probe: PendulumLab.periodProbe,
                        builder: (context, reading) => Text(
                          'Period, measured: ${_number(reading, 5, 's')}',
                          style: text.titleMedium,
                        ),
                      ),
                      Text(
                        'Period, series: '
                        '${PendulumLab.seriesPeriod().toStringAsFixed(5)} s',
                        style: text.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: _running ? null : () => _clock.advance(_step),
                      child: const Text('Step'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => setState(() => _running = !_running),
                      child: Text(_running ? 'Stop' : 'Run'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
