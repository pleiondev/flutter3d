/// The valley's world and what is drawn of it: the ground, the water over
/// it, the spray off the cliff and what is thrown in.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        BodyPose,
        GameAction,
        GameRandom,
        InputState,
        Snapshot,
        SnapshotFields,
        StateDigest;

import 'fire.dart';
import 'valley.dart';

/// A quarter of a cubic metre a second out of the spring: a stream big
/// enough to fall as a curtain.
const double springRate = 0.25;

/// What the valley's hands ask for, by intent: each read by the step from
/// the run's [InputState], so a run file holds them as it holds a walk.
abstract final class WaterActions {
  /// A stone dropped somewhere over the pond.
  static const GameAction dropStone = GameAction('dropStone');

  /// A stone dropped over the point the step reads from the tunes
  /// [dropX], [dropY] and [dropZ]: a click on the valley.
  static const GameAction dropStoneAt = GameAction('dropStoneAt');

  /// A log put in the stream near the spring.
  static const GameAction dropLog = GameAction('dropLog');

  /// The bonfire lit.
  static const GameAction light = GameAction('light');

  /// A bucket over every burning log.
  static const GameAction douse = GameAction('douse');

  /// The wind down the valley turned on, or off.
  static const GameAction wind = GameAction('wind');

  /// The tunes [dropStoneAt] reads its point from, in metres.
  static const String dropX = 'drop.x', dropY = 'drop.y', dropZ = 'drop.z';

  /// Every action, for a rebind screen or a test.
  static const List<GameAction> all = <GameAction>[
    dropStone,
    dropStoneAt,
    dropLog,
    light,
    douse,
    wind,
  ];
}

/// The valley's simulation, written into its run files: a run recorded on
/// another one is refused rather than replayed wrong, and its pose record
/// plays instead.
///
/// Bump [SimulationVersion.genreVersion] when the step reads its input
/// differently, or the valley's world is built differently.
const SimulationVersion waterSimulation = SimulationVersion(genre: 'water');

/// What a run file names as its level: the valley has no document, so the
/// name is the valley's and the hash is its shape's (see [waterLevelHash]).
const String waterLevel = 'valley';

/// The valley's shape as a run file checks it: a run recorded on a valley
/// of another size, or with another spring, says so rather than parting.
String get waterLevelHash => StateDigest.of(<String, Object?>{
  'cells': valleyCells,
  'cell': valleyCell,
  'spring': <double>[springX, springZ, springRate],
  'pond': <double>[pondX, pondZ],
}).toRadixString(16).padLeft(8, '0');

/// The valley, stepped and drawn.
final class WaterRun {
  WaterRun(
    this._device,
    this.scene,
    this.elements, {
    required ({Vector3 along, Vector3 light}) sun,
    InputState? input,
  }) : input = input ?? InputState() {
    _ground = valleyGround();
    // The ground as the stones meet it: one fixed mesh.
    elements.addGround(<Vector3>[
      for (var j = 0; j < valleyCells; j++)
        for (var i = 0; i < valleyCells; i++)
          Vector3(
            (i + 0.5) * valleyCell,
            _ground[i + j * valleyCells],
            (j + 0.5) * valleyCell,
          ),
    ], _triangles((_, _) => true));
    // The water over it: the pond already at its lip, the stream dry until
    // the spring fills it, and what reaches the map's edge running off.
    water =
        elements.addWater(
            ground: ElementHeightfield.list(
              origin: Vector3.zero(),
              cell: valleyCell,
              nx: valleyCells,
              nz: valleyCells,
              heights: _ground,
            ),
            liquid: Liquid.water(),
            bed: const Bed(roughness: Bed.mountainStream),
            mist: const MistSettings(),
          )
          ..fillBasin(from: Vector3(pondX, 0.0, pondZ), level: 0.05)
          ..addSpring(
            at: Vector3(springX, 0.0, springZ),
            discharge: springRate,
            radius: 0.6,
          );
    for (final side in <GridSide>[
      GridSide.west,
      GridSide.east,
      GridSide.south,
      GridSide.north,
    ]) {
      water.setEdge(side, NativeEdgeFlow.free);
    }
    // The sun the water glints with, as the scene's.
    elements.sun(along: sun.along, light: sun.light);
    _build();
    bonfire = Bonfire(elements, _device);
  }

  final GraphicsDevice _device;
  final Scene scene;

  /// The water, the fire and what is thrown in, drawn.
  final Elements elements;
  NativeWorld get _world => elements.world;
  late final WaterBody water;
  late final List<double> _ground;
  late final DeviceMesh _stoneMesh, _logMesh;

  /// Where a stone over the pond and a log in the stream fall: seeded, and
  /// saved with the run, so a replay drops them where the run did.
  final GameRandom _scatter = GameRandom(7);

  /// What the hands ask for, read by the step: what the keys and the
  /// pointer write, or a tape.
  final InputState input;

  /// The stones and logs thrown in, in the order they were: their bodies,
  /// and which they are — named by it in the pose record.
  final List<({TrackedBody body, bool stone})> _thrown =
      <({TrackedBody body, bool stone})>[];

  /// The fire laid on the bank.
  late final Bonfire bonfire;

  /// Whether the wind blows down the valley.
  bool windy = false;

  /// What the water holds and what has run off the map, for the panel.
  ({double held, double lost}) get volume => _world.shallowVolume(water.native);

  /// How many pieces of falling water are in the air, and how many clouds
  /// of bubbles are in the water.
  int get sprayInFlight => elements.viewOf(water).sprayInFlight;
  int get bubbleClouds => elements.viewOf(water).bubbleClouds;

  /// The pond's surface above the valley's origin, m.
  double get pondLevel =>
      water.sample(Vector3(pondX, 0.0, pondZ))?.surface ?? 0.0;

  /// The grid's triangles over the cells whose corner (i, j) [keep] says.
  static List<int> _triangles(bool Function(int i, int j) keep) => <int>[
    for (var j = 0; j < valleyCells - 1; j++)
      for (var i = 0; i < valleyCells - 1; i++)
        if (keep(i, j)) ...<int>[
          i + j * valleyCells,
          i + (j + 1) * valleyCells,
          i + 1 + j * valleyCells,
          i + 1 + j * valleyCells,
          i + (j + 1) * valleyCells,
          i + 1 + (j + 1) * valleyCells,
        ],
  ];

  /// Floats a vertex of [VertexLayout.standard] takes: position, normal,
  /// texture coordinate, tangent and colour.
  static const int _stride = 3 + 3 + 2 + 4 + 4;

  void _build() {
    // The ground: grass on the flat, rock where it is steep, sand by the
    // water's edge.
    final ground = Float32List(valleyCells * valleyCells * _stride);
    for (var j = 0; j < valleyCells; j++) {
      for (var i = 0; i < valleyCells; i++) {
        final c = i + j * valleyCells;
        final normal = _normal(_ground, i, j);
        final steep = 1.0 - normal.y;
        final h = _ground[c];
        final rock = (steep * 3.0).clamp(0.0, 1.0);
        final sand = h < 0.7 && steep < 0.2 ? 0.8 : 0.0;
        final grass = (1.0 - rock - sand).clamp(0.0, 1.0);
        final color =
            Vector3(0.16, 0.30, 0.09) * grass +
            Vector3(0.33, 0.31, 0.29) * rock +
            Vector3(0.48, 0.42, 0.30) * sand;
        _write(
          ground,
          c,
          Vector3((i + 0.5) * valleyCell, h, (j + 0.5) * valleyCell),
          normal,
          Vector4(color.x, color.y, color.z, 1.0),
        );
      }
    }
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          _device,
          MeshData(
            layout: VertexLayout.standard,
            vertices: ground,
            indices: Uint32List.fromList(_triangles((_, _) => true)),
          ),
        ),
        RenderMaterial(name: 'ground', roughness: 0.95),
        name: 'ground',
      ),
    );
    _stoneMesh = DeviceMesh.upload(
      _device,
      CuboidShape(size: Vector3(0.6, 0.4, 0.5)).build(),
    );
    _logMesh = DeviceMesh.upload(
      _device,
      CuboidShape(size: Vector3(1.4, 0.3, 0.3)).build(),
    );
  }

  /// The ground's or the water's normal at cell (i, j), from its
  /// neighbours.
  static Vector3 _normal(List<double> h, int i, int j) {
    double at(int x, int z) =>
        h[x.clamp(0, valleyCells - 1) +
            z.clamp(0, valleyCells - 1) * valleyCells];
    final dx = (at(i + 1, j) - at(i - 1, j)) / (2 * valleyCell);
    final dz = (at(i, j + 1) - at(i, j - 1)) / (2 * valleyCell);
    return Vector3(-dx, 1.0, -dz)..normalize();
  }

  static void _write(
    Float32List v,
    int c,
    Vector3 p,
    Vector3 n,
    Vector4 color, {
    (double, double)? uv,
  }) {
    final o = c * _stride;
    v[o] = p.x;
    v[o + 1] = p.y;
    v[o + 2] = p.z;
    v[o + 3] = n.x;
    v[o + 4] = n.y;
    v[o + 5] = n.z;
    final (u, w) = uv ?? (p.x / valleySize, p.z / valleySize);
    v[o + 6] = u;
    v[o + 7] = w;
    v[o + 8] = 1.0;
    v[o + 9] = 0.0;
    v[o + 10] = 0.0;
    v[o + 11] = 1.0;
    v[o + 12] = color.x;
    v[o + 13] = color.y;
    v[o + 14] = color.z;
    v[o + 15] = color.w;
  }

  /// Where the ray from [origin] along [direction] first meets the ground
  /// or the water, or null when it misses the valley.
  Vector3? hit(Vector3 origin, Vector3 direction) {
    final d = direction.normalized();
    for (var t = 0.0; t < 120.0; t += 0.05) {
      final p = origin + d * t;
      if (p.x < 0 || p.z < 0 || p.x > valleySize || p.z > valleySize) continue;
      final ground = groundAt(p.x, p.z);
      final surface = water.sample(p)?.surface ?? ground;
      if (p.y <= math.max(surface, ground)) return p;
    }
    return null;
  }

  /// A rock of three hundred kilograms dropped from five metres over
  /// [at], or over the pond somewhere when it is null.
  void dropStone([Vector3? at]) {
    final x = at?.x ?? pondX + (_scatter.nextDouble() - 0.5) * 8.0;
    final z = at?.z ?? pondZ + (_scatter.nextDouble() - 0.5) * 6.0;
    final y = (at?.y ?? 0.0) + 5.0;
    // A rock, not a marble: a squat block with its corners worn round, so
    // it settles where it lands instead of rolling about the pond's bowl.
    // Granite, 2600 kg/m³.
    final body = elements.addBody(
      Solid.box(
        Vector3(0.24, 0.14, 0.19),
        material: NativeMaterial.stone(),
        density: 2600.0,
      ).rounded(0.06),
      at: Vector3(x, y, z),
      look: _stoneLook(),
    );
    _thrown.add((body: body, stone: true));
  }

  MeshNode _stoneLook() =>
      _look(_stoneMesh, 'stone', Vector4(0.35, 0.33, 0.31, 1.0), 0.8);

  MeshNode _logLook() =>
      _look(_logMesh, 'log', Vector4(0.42, 0.28, 0.16, 1.0), 0.85);

  /// A node drawing [mesh], put in the scene.
  MeshNode _look(DeviceMesh mesh, String name, Vector4 color, double rough) {
    final node = MeshNode(
      mesh,
      RenderMaterial(name: name, baseColor: _fromSrgb(color), roughness: rough),
      name: name,
    );
    scene.add(node);
    return node;
  }

  /// A log put in the stream near the spring, to ride it over the falls.
  void dropLog() {
    final z = 3.0 + _scatter.nextDouble() * 2.0;
    // Pine, 440 kg/m³.
    final body = elements.addBody(
      Solid.box(
        Vector3(0.7, 0.15, 0.15),
        material: NativeMaterial.wood(),
        density: 440.0,
      ),
      at: Vector3(streamX(z), 7.5, z),
      look: _logLook(),
    );
    _thrown.add((body: body, stone: false));
  }

  /// Where the eye is, for the ripples that fade with distance.
  final Vector3 eye = Vector3.zero();

  /// The valley's step on [loop]: what [input] asks for in `input`, and
  /// the elements — the wind, the world stepped, what is drawn of it brought
  /// up to date — in `elements`.
  ///
  /// **A fixed step now, at the loop's world rate.** The valley was stepped
  /// with each frame's own time; it is stepped in sixtieths whatever the
  /// display. **What the hands do is input now**, read by the step from
  /// [input] as the loop hands it over, so a tape records it and plays it
  /// back: a stone dropped between two steps was something no run file
  /// could hold.
  void install(LoopRegistry loop) {
    loop
      ..addSystem('water.hands', LoopPhase.input, (_) => _hands())
      ..addSystem(
        'water.elements',
        LoopPhase.fields,
        (step) => _elements(step.dt),
      );
  }

  /// One step of [dt], in the order [install] runs it: for a reel, which
  /// steps the valley by its own frames. The latches [input] holds are
  /// spent, as the loop spends them.
  void step(double dt) {
    input.beginStep();
    _hands();
    _elements(dt);
    input.endStep();
  }

  void _hands() {
    if (input.pressed(WaterActions.dropStone)) dropStone();
    if (input.pressed(WaterActions.dropStoneAt)) {
      final tunes = input.tunesThisStep;
      final x = tunes[WaterActions.dropX];
      final y = tunes[WaterActions.dropY];
      final z = tunes[WaterActions.dropZ];
      if (x != null && y != null && z != null) dropStone(Vector3(x, y, z));
    }
    if (input.pressed(WaterActions.dropLog)) dropLog();
    if (input.pressed(WaterActions.light)) bonfire.light();
    if (input.pressed(WaterActions.douse)) bonfire.douse();
    if (input.pressed(WaterActions.wind)) windy = !windy;
  }

  /// The valley's whole state, as a run file starts from and a checkpoint
  /// compares: the physics core's world — the ground, the water on it, every
  /// body and its heat — as the core writes it, the flames held, the wind,
  /// the dice, and which bodies were thrown in.
  ///
  /// **The water is the core's**, in the world's own bytes: the depth and
  /// the flow of every cell. What is drawn of it — the spray's look, the
  /// ripples — is the view's, worked out again from the world each step.
  Snapshot save() => Snapshot(<String, Object?>{
    'world': base64Encode(elements.world.snapshot()),
    'elements': elements.saveElements(),
    'windy': windy,
    'random': _scatter.state,
    'thrown': <Object?>[
      for (final t in _thrown)
        <Object?>[t.stone ? 'stone' : 'log', t.body.native.raw],
    ],
  });

  /// Back to what [save] wrote: the world's bytes, the bodies thrown in
  /// since taken out with their looks, and those the save holds given looks
  /// again.
  ///
  /// The bonfire's logs and the ground are in every save and keep their
  /// bodies; only what was thrown in comes and goes.
  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    for (final t in _thrown) {
      elements.lookOf(t.body)?.removeFromParent();
      elements.remove(t.body);
    }
    _thrown.clear();
    elements.world.restore(base64Decode(data['world']! as String));
    elements.restoreElements(
      data.object('elements') ?? const <String, Object?>{},
    );
    windy = data.flag('windy');
    _scatter.state = data.integer('random', 7);
    for (final row in (data['thrown'] as List<Object?>?) ?? const <Object?>[]) {
      if (row case [final String kind, final int raw]) {
        final stone = kind == 'stone';
        final body = elements.track(
          NativeBody(raw),
          look: stone ? _stoneLook() : _logLook(),
        );
        _thrown.add((body: body, stone: stone));
      }
    }
  }

  /// Where every body that moves is: the bonfire's logs, then each stone
  /// and log thrown in, by the order they were — what a run file's pose
  /// record keeps, for a build that cannot replay its tape.
  List<BodyPose> poses() {
    final world = elements.world;
    return <BodyPose>[
      for (final (i, log) in bonfire.logs.indexed)
        BodyPose(
          'bonfire#$i',
          world.localPositionOf(log.native),
          world.orientationOf(log.native),
        ),
      for (final (i, t) in _thrown.indexed)
        BodyPose(
          '${t.stone ? 'stone' : 'log'}#$i',
          world.localPositionOf(t.body.native),
          world.orientationOf(t.body.native),
        ),
    ];
  }

  void _elements(double dt) {
    elements
      ..wind = windy ? Vector3(0.0, 0.0, 6.0) : Vector3.zero()
      ..update(dt, eye: eye);
  }

  void dispose() => elements.dispose();
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
