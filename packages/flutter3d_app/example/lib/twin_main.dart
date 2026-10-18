/// A digital twin at its smallest: a tank of water standing on a real site,
/// whose air temperature comes from a real source.
///
///     flutter run -d macos -t lib/twin_main.dart
///     flutter run -d chrome -t lib/twin_main.dart \
///         --dart-define=latitude=59.94 --dart-define=longitude=30.31
///
/// **One real source, polled in this file's own code.** `RestPoller` asks
/// Open-Meteo for the current temperature at the site once a minute (it needs
/// no key); each new answer is a measured `ExternalStateInput` fed into the
/// next step the loop runs. An assimilation sets the air to it, and the
/// model warms or cools the water towards the air, so the water is what the
/// twin works out and the air is what it was told.
///
/// **The history is a tape.** Every step's readings are recorded with it,
/// and a `RunTimeline` over the last hour scrubs it: pause, drag the slider
/// back to see the site as it was, and press "Live" to return. Nothing is
/// asked of the network again on the way back; the readings come off the
/// tape at the steps they arrived at.
///
/// **Time is the twin's to scale.** The view's clock is a
/// `TimeSource.scaled`: at 10× ten minutes of the model pass in one, and the
/// fixed step stays a tenth of a second, so a run at 10× is the same run as
/// one at 1×, sooner. The source is still polled once a wall-clock minute.
///
/// Reading the probes and never the world, the panel would read the same
/// with the simulation in an isolate; this one keeps it in the view's loop,
/// because the timeline scrubs that loop.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show RunTimeline;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show RewindBuffer, TimeSource, WorldTiming;

import 'src/twin/open_meteo.dart';
import 'src/twin/rest_poller.dart';
import 'src/twin/site_twin.dart';

/// The site, by `--dart-define=latitude=…` and `longitude=…`; Berlin when
/// neither is given.
final double _latitude = double.parse(
  const String.fromEnvironment('latitude', defaultValue: '52.52'),
);
final double _longitude = double.parse(
  const String.fromEnvironment('longitude', defaultValue: '13.41'),
);

void main() => runApp(const _TwinApp());

class _TwinApp extends StatelessWidget {
  const _TwinApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A twin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6FD6),
        brightness: Brightness.dark,
      ),
    ),
    home: TwinScreen(
      source: RestPoller(
        uri: openMeteoUri(latitude: _latitude, longitude: _longitude),
        read: readOpenMeteo,
      ),
    ),
  );
}

/// The tank on its site, the readings beside it, and the transport under it.
class TwinScreen extends StatefulWidget {
  /// A screen fed by [source], which it starts and disposes.
  const TwinScreen({
    super.key,
    required this.source,
    this.device = const DeviceSettings(),
  });

  /// Where the air's temperature comes from.
  final RestPoller source;

  /// The device the view draws with: its own by default, a test's in a test.
  final DeviceSettings device;

  @override
  State<TwinScreen> createState() => _TwinScreenState();
}

/// The speeds the view's clock offers: simulated seconds per wall-clock
/// second. Thirty is ten steps a frame at 60 Hz, which the loop runs in
/// full; much more and it would drop time and say so.
const List<double> _speeds = <double>[1, 10, 30];

class _TwinScreenState extends State<TwinScreen> {
  /// One source per speed, made once, so a speed chosen again carries on.
  final List<TimeSource> _clocks = <TimeSource>[
    for (final speed in _speeds) TimeSource.scaled(speed),
  ];
  int _speed = 0;

  ({
    Flutter3dEngine engine,
    SiteTwin twin,
    RewindBuffer history,
    RunTimeline timeline,
    RenderMaterial water,
  })?
  _ready;

  void _open(Flutter3dEngine engine) {
    final water = RenderMaterial(
      name: 'water',
      baseColor: _colourOf(SiteTwin.startCelsius),
      roughness: 0.15,
    );
    engine.scene
      ..add(
        MeshNode(
          DeviceMesh.upload(
            engine.device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          RenderMaterial(
            name: 'ground',
            baseColor: LinearColor.fromSrgb(0.32, 0.36, 0.3, 1),
            roughness: 0.9,
          ),
          name: 'ground',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            engine.device,
            const CylinderShape(radiusTop: 0.62, radiusBottom: 0.62).build(),
          ),
          RenderMaterial(
            name: 'tank',
            baseColor: LinearColor.fromSrgb(0.7, 0.72, 0.75, 1),
            metallic: 1,
            roughness: 0.35,
          ),
          name: 'tank',
        )..setPosition(0, 0.5, 0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            engine.device,
            const CylinderShape(
              radiusTop: 0.6,
              radiusBottom: 0.6,
              height: 0.02,
            ).build(),
          ),
          water,
          name: 'water',
        )..setPosition(0, 0.92, 0),
      );
    engine.camera
      ..setPosition(2.4, 2.1, 3.2)
      ..lookAt(Vector3(0, 0.5, 0));

    final twin = SiteTwin.install(engine.loop, readings: widget.source.take);
    final history = twin.keepHistory(seconds: 3600, keyframeEvery: 300);
    widget.source.start();
    setState(
      () => _ready = (
        engine: engine,
        twin: twin,
        history: history,
        timeline: RunTimeline(rewind: history, loop: engine.loop),
        water: water,
      ),
    );
  }

  @override
  void dispose() {
    widget.source.dispose();
    _ready?.twin.dispose();
    super.dispose();
  }

  /// Blue at nought, red at thirty, as linear colour.
  static LinearColor _colourOf(double celsius) {
    final t = (celsius / 30).clamp(0.0, 1.0);
    return LinearColor.fromSrgb(0.15 + 0.7 * t, 0.35, 0.85 - 0.7 * t, 1);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Flutter3dView(
              device: widget.device,
              time: _clocks[_speed],
              loop: const LoopSettings(
                timing: WorldTiming(stepRate: SiteTwin.stepRate),
              ),
              onCreated: _open,
              // The transport decides whether the loop runs: a paused
              // timeline is one the loop must not step, since a scrub puts
              // the past where the present was.
              onBeforeFrame: (EngineFrame f) =>
                  f.engine.loop.isPaused = ready?.timeline.isPaused ?? false,
              onFrame: (EngineFrame f) {
                final reading = f.engine.published.value.probe(
                  SiteTwin.waterProbe,
                );
                if (reading != null && ready != null) {
                  ready.water.baseColor = _colourOf(reading.value.single);
                }
              },
            ),
          ),
          if (ready != null) ...<Widget>[
            Positioned(
              left: 16,
              top: 16,
              child: _Readings(engine: ready.engine, source: widget.source),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _Transport(
                history: ready.history,
                timeline: ready.timeline,
                speed: _speed,
                onSpeed: (int speed) => setState(() => _speed = speed),
                onChanged: () => setState(() {}),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the probes published, and where the air's reading came from.
class _Readings extends StatelessWidget {
  const _Readings({required this.engine, required this.source});

  final Flutter3dEngine engine;
  final RestPoller source;

  static String _celsius(ProbeReading? reading) =>
      reading == null ? '—' : '${reading.value.single.toStringAsFixed(1)} °C';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProbeBuilder(
              published: engine.published,
              probe: SiteTwin.airProbe,
              builder: (context, reading) => Text(
                'Air, measured: ${_celsius(reading)}',
                style: text.titleMedium,
              ),
            ),
            ProbeBuilder(
              published: engine.published,
              probe: SiteTwin.waterProbe,
              builder: (context, reading) => Text(
                'Water, modelled: ${_celsius(reading)}',
                style: text.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            ProbeBuilder(
              published: engine.published,
              probe: SiteTwin.airProbe,
              builder: (context, _) => Text(switch ((
                source.lastError,
                source.latest?.sourceSeconds,
              )) {
                (final String error, _) => 'Source: $error',
                (_, final double taken) =>
                  'Source: ${source.uri.host}, taken '
                      '${DateTime.fromMillisecondsSinceEpoch((taken * 1000).round(), isUtc: true).toIso8601String().substring(11, 16)} UTC',
                _ => 'Source: ${source.uri.host}, waiting',
              }, style: text.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pause and live, the slider through the history, and the clock's speed.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.history,
    required this.timeline,
    required this.speed,
    required this.onSpeed,
    required this.onChanged,
  });

  final RewindBuffer history;
  final RunTimeline timeline;
  final int speed;
  final ValueChanged<int> onSpeed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    // A scrub to step n replays up to it and publishes what step n − 1
    // left; the oldest keyframe itself is replayed from by nothing, so the
    // slider starts one step after it.
    final present = history.step;
    final oldest = math.min((history.oldestStep ?? present) + 1, present);
    final at = (timeline.scrubbedAt ?? present).clamp(oldest, present);
    final scrubbing = timeline.isPaused && oldest < present;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: () {
                if (timeline.isPaused) {
                  // Back to the present, and on from there.
                  timeline.resume();
                } else {
                  timeline.pause();
                }
                onChanged();
              },
              child: Text(timeline.isPaused ? 'Live' : 'Pause'),
            ),
            Expanded(
              child: Slider(
                min: oldest.toDouble(),
                max: present.toDouble(),
                value: at.toDouble(),
                label: '${((present - at) / SiteTwin.stepRate).round()} s ago',
                divisions: scrubbing ? present - oldest : null,
                onChanged: scrubbing
                    ? (double step) {
                        timeline.scrubTo(step.round());
                        onChanged();
                      }
                    : null,
              ),
            ),
            SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                for (final (i, s) in _speeds.indexed)
                  ButtonSegment<int>(value: i, label: Text('${s.round()}×')),
              ],
              selected: <int>{speed},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> chosen) => onSpeed(chosen.single),
            ),
          ],
        ),
      ),
    );
  }
}
