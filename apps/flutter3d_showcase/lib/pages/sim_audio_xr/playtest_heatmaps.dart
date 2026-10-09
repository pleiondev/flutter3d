/// Where a level's players went and where they were lost, read off their
/// tapes rather than off anything their games reported: each run played
/// again through the same simulation, its trail binned into a heatmap, and
/// the heatmap drawn over the level.
///
/// Quoted by `playtest_heatmaps.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

// #region game
/// A walker crossing a yard, steered by the stick. Stepping into the pit
/// loses the run, and the walker stays where it fell — as a player sits on
/// the "you died" screen — until the tape runs out.
final class _Walk extends HeadlessRun {
  _Walk(this.input, this.pit);

  final InputState input;

  /// The pit's corners on the ground, `(minX, minZ, maxX, maxZ)`.
  final (double, double, double, double) pit;
  final Vector3 _at = Vector3.zero();

  @override
  RunOutcome outcome = RunOutcome.playing;

  @override
  void step(double dt) {
    if (outcome.isOver) return;
    _at
      ..x += input.moveAxis.x * 3.0 * dt
      ..z += input.moveAxis.y * 3.0 * dt;
    final (double x0, double z0, double x1, double z1) = pit;
    if (_at.x >= x0 && _at.x < x1 && _at.z >= z0 && _at.z < z1) {
      outcome = RunOutcome.lost;
    }
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{
    'x': _at.x,
    'z': _at.z,
    'outcome': outcome.name,
  });

  @override
  WorldPosition get position => _at.toWorldPosition();

  @override
  WorldPosition get eye => _at.toWorldPosition();

  @override
  void aim(Vector3 out) => out.setValues(1.0, 0.0, 0.0);

  @override
  String get summary => 'at ${_at.x.toStringAsFixed(2)}, ${outcome.name}';

  @override
  Map<String, Object?> get reading => <String, Object?>{'x': _at.x};
}

/// The game, as `resimulate` starts it: the pit is the level's brush made
/// of `pit`, so a level with the pit moved is another level.
final class _WalkGame extends HeadlessGame {
  const _WalkGame();

  @override
  String get name => 'yard';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{};

  @override
  EntityRegistry registry() => EntityRegistry(const <EntityKind>[]);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) {
    final Brush pit = level.brushes.firstWhere((b) => b.material == 'pit');
    final Vector3 half = pit.size * 0.5;
    return _Walk(input, (
      pit.center.x - half.x,
      pit.center.z - half.z,
      pit.center.x + half.x,
      pit.center.z + half.z,
    ));
  }
}

Level _yard() => Level(
  name: 'yard',
  materials: <String, LevelMaterial>{
    'stone': LevelMaterial(),
    'pit': LevelMaterial(),
  },
  brushes: <Brush>[
    Brush(
      center: Vector3(6.5, -0.5, 0.0),
      size: Vector3(15.0, 1.0, 6.0),
      material: 'stone',
    ),
    // One metre square, a cell of the heatmap exactly.
    Brush(
      center: Vector3(5.5, 0.0, -0.5),
      size: Vector3(1.0, 0.1, 1.0),
      material: 'pit',
      solid: false,
    ),
  ],
);
// #endregion game

// #region record
/// One player's tape: six seconds walking across the yard, drifting to one
/// side by however much [seed] says. Written down as a game does — the tape
/// before each step, a checkpoint after it.
Demo _record(Level level, int seed) {
  final input = InputState();
  final run = const _WalkGame().start(level, CollisionWorld(), input);
  final start = run.save();
  // Spread evenly over the yard's width, tape by tape, by the golden ratio.
  final drift = (seed * 0.6180339887) % 1.0 * 0.7 - 0.35;
  final recorder = InputTapeRecorder(seed: seed);
  final trace = DigestTrace(every: 30);
  for (var step = 1; step <= 360; step++) {
    input.setStickAxis(0.75, drift);
    recorder.record(input);
    input.beginStep();
    run.step(1.0 / 60.0);
    trace.observe(step, run.save().toJson());
    input.endStep();
  }
  return Demo(
    level: 'levels/yard.json',
    levelHash: level.digestHex,
    start: start,
    tape: recorder.tape,
    buildStamp: 'showcase',
    checkpoints: trace,
  );
}
// #endregion record

// #region heatmap
/// Every tape played again into [level], and the trails of those that
/// retraced their checkpoints binned into metre cells. A tape that parted
/// from its own checkpoints, or was recorded in another level, gives no
/// trail at all; [refused] counts them.
({Heatmap map, int refused}) _heatmap(Level level, List<Demo> tapes) {
  final trails = <HeatmapTrail>[];
  var refused = 0;
  for (var i = 0; i < tapes.length; i++) {
    switch (resimulate(game: const _WalkGame(), level: level, demo: tapes[i])) {
      case ResimulationRetraced(:final trail, :final outcome, :final steps):
        trails.add(
          HeatmapTrail(
            run: i,
            steps: steps,
            outcome: outcome.name,
            positions: trail,
            endedBadly: outcome == RunOutcome.lost,
          ),
        );
      case _:
        refused++;
    }
  }
  return (
    map: Heatmap.bin(
      trails,
      outcomeNames: <String>[for (final o in RunOutcome.values) o.name],
    ),
    refused: refused,
  );
}
// #endregion heatmap

final class PlaytestHeatmapsDemo extends ShowcaseDemo {
  double tapes = 16;

  late final Level _level;
  late Heatmap _map;
  late int _refused;
  final Map<(int, int), MeshNode> _tiles = <(int, int), MeshNode>{};
  final List<MeshNode> _deaths = <MeshNode>[];

  static const int _most = 32;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 17.0
      ..pitch = 0.95
      ..yaw = 0.0;
    context.orbit.target.setValues(6.5, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _level = _yard();
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.5 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.2 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.2, -1.0, -0.3)),
      );
    for (final Brush brush in _level.brushes) {
      final bool pit = brush.material == 'pit';
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: brush.size).build(),
          ),
          RenderMaterial(
            name: brush.material,
            baseColor: pit
                ? LinearColor.fromSrgb(0.05, 0.05, 0.06, 1.0)
                : LinearColor.fromSrgb(0.3, 0.32, 0.34, 1.0),
          ),
          name: brush.material,
        )..setPositionFrom(brush.center),
      );
    }
    // One flat tile a cell over the yard, coloured by the heatmap.
    final DeviceMesh tile = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.92, 0.04, 0.92)).build(),
    );
    for (var x = -1; x < 14; x++) {
      for (var z = -3; z < 3; z++) {
        final node = MeshNode(
          tile,
          RenderMaterial(name: 'cell $x,$z', lighting: LightingModel.unlit),
          name: 'cell $x,$z',
        )..setPosition(x + 0.5, 0.08, z + 0.5);
        _tiles[(x, z)] = node;
        scene.add(node);
      }
    }
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 12, rings: 6, radius: 0.12).build(),
    );
    for (var i = 0; i < _most; i++) {
      final node = MeshNode(
        ball,
        RenderMaterial(
          name: 'death',
          baseColor: LinearColor.fromSrgb(1.0, 0.15, 0.1, 1.0),
        ),
        name: 'death $i',
      );
      _deaths.add(node);
      scene.add(node);
    }
    _measure();
    return scene;
  }

  void _measure() {
    final List<Demo> recorded = <Demo>[
      for (var seed = 1; seed <= tapes.round(); seed++) _record(_level, seed),
    ];
    final (:map, :refused) = _heatmap(_level, recorded);
    _map = map;
    _refused = refused;
    _draw();
  }

  // #region draw
  /// Each cell from cold to hot by how many samples landed in it, against
  /// the hottest; a cell nobody walked through is not drawn. A red ball
  /// where each run was lost.
  void _draw() {
    final int hottest = _hottest(_map).samples;
    for (final MeshNode node in _tiles.values) {
      node.isVisible = false;
    }
    for (final HeatmapCell cell in _map.cells) {
      final MeshNode? node = _tiles[(cell.x, cell.z)];
      if (node == null) continue;
      final double t = cell.samples / hottest;
      node
        ..isVisible = true
        ..material.baseColor = LinearColor.fromSrgb(
          (t * 2.0).clamp(0.0, 1.0),
          (1.0 - (t - 0.5).abs() * 2.0).clamp(0.15, 1.0),
          (1.0 - t * 2.0).clamp(0.0, 1.0),
          1.0,
        );
    }
    for (var i = 0; i < _deaths.length; i++) {
      final bool shown = i < _map.ends.length;
      _deaths[i].isVisible = shown;
      if (shown) {
        _deaths[i].setPosition(_map.ends[i].x, 0.25, _map.ends[i].z);
      }
    }
  }
  // #endregion draw

  static HeatmapCell _hottest(Heatmap map) => map.cells.reduce(
    (HeatmapCell a, HeatmapCell b) => b.samples > a.samples ? b : a,
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Tapes (${_map.outcomes['lost']} lost, $_refused refused)',
      min: 4,
      max: _most.toDouble(),
      divisions: _most - 4,
      value: () => tapes,
      onChanged: (double v) {
        tapes = v;
        _measure();
      },
      format: (double v) => v.round().toString(),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Every tape retraced its own checkpoints, and some were lost.
    if (_refused != 0 || _map.runs != tapes.round()) {
      throw StateError('$_refused of the tapes did not replay');
    }
    if (_map.ends.length < 3) {
      throw StateError('only ${_map.ends.length} runs were lost in the pit');
    }
    // The hottest cell is the one every run was lost in: a player who fell
    // stays there, sample after sample.
    final HeatmapCell hottest = _hottest(_map);
    for (final HeatmapEnd end in _map.ends) {
      if ((end.x.floor(), end.z.floor()) != (hottest.x, hottest.z)) {
        throw StateError(
          'run ${end.run} was lost at (${end.x}, ${end.z}), and the hottest '
          'cell is (${hottest.x}, ${hottest.z})',
        );
      }
    }
    // The same tapes in a yard with the pit moved are another level's runs.
    final Level moved = Level.fromJson(_yard().toJson())
      ..brushes.last.center.x += 1.0;
    if (resimulate(
          game: const _WalkGame(),
          level: moved,
          demo: _record(_level, 1),
        )
        is! ResimulationLevelChanged) {
      throw StateError('a tape replayed into a level it was not recorded in');
    }
    // #endregion check
    if (frame.drawCalls < 3) throw StateError('the heatmap was not drawn');
  }
}
