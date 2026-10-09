/// The one place that assembles a dive on Wreck Reef: the sea and its
/// current, the floor lit through the surface, the ship, the boat, the
/// finds, the diver and the bags.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_kit/world.dart' show Horizon;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        ActionDeclaration,
        ActionSet,
        AxisAction,
        BodyPose,
        DualAxisAction,
        GameAction,
        InputState,
        Snapshot;
import 'package:vector_math/vector_math.dart';

import 'diver.dart';
import 'finds.dart';
import 'looks.dart';
import 'reef_life.dart';
import 'terrain.dart';
import 'wreck.dart';

/// What the diver does: the way the fins push, from nought to one long;
/// how hard the jacket is [fill]ed and [dump]ed, nought to one; and the
/// [heading] they lie along, radians about y.
typedef ReefControls = ({
  Vector3 swim,
  double fill,
  double dump,
  double heading,
});

/// The dive's rules, as a `.f3drun` names them: a tape recorded under one
/// number is refused by a build whose dive steps differently, and its pose
/// record is shown instead.
const SimulationVersion reefSimulation = SimulationVersion(genre: 'reef');

/// What the diver asks for beyond the four ways to swim, which are
/// [GameAction.moveForward] and its kin: up and down, the jacket filled and
/// dumped, all held; and [act], a bag tied or air blown into one, pressed.
abstract final class ReefActions {
  static const GameAction rise = GameAction('rise');
  static const GameAction sink = GameAction('sink');
  static const GameAction fill = GameAction('fill');
  static const GameAction dump = GameAction('dump');
  static const GameAction act = GameAction('act');

  /// Up through the water, positive: what [rise] less [sink] was.
  static const AxisAction ascend = AxisAction('ascend');

  /// What the dive declares. [ascend] names the button pair a dive recorded
  /// before it was an axis, so such a dive replays rising as it did.
  static const ActionSet set = ActionSet('reef', <ActionDeclaration>[
    ActionDeclaration(GameAction.moveForward, label: 'forward'),
    ActionDeclaration(GameAction.moveBack, label: 'back'),
    ActionDeclaration(GameAction.moveLeft, label: 'left'),
    ActionDeclaration(GameAction.moveRight, label: 'right'),
    ActionDeclaration(DualAxisAction.look),
    ActionDeclaration(ascend, fromButtons: (negative: sink, positive: rise)),
    ActionDeclaration(fill, label: 'fill the jacket'),
    ActionDeclaration(dump, label: 'dump the jacket'),
    ActionDeclaration(act),
  ]);
}

/// Radians the eye turns round the diver for each unit of look the pointer
/// gives: a pixel dragged across.
const double lookPerPixel = 0.006;

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// The current's rate, m³/s, through the sea from west to east: over the
/// four-metre flat, some forty centimetres a second; over the ship, ten.
const double _current = 100.0;

/// How far clear of the reef or the ship the eye is kept, m: past the
/// near plane and past the lumps the drawn rock stands off its solid floor.
const double eyeClearance = 0.5;

/// [eye], or, where something solid stands between [target] and it, pulled
/// in to [eyeClearance] short of it. [cast] says how far along the way from
/// a point, a unit direction, the first solid thing is within a reach, or
/// null. Never pulled in past [target] itself.
Vector3 clearOfSolid(
  Vector3 target,
  Vector3 eye,
  double? Function(Vector3 from, Vector3 along, double reach) cast,
) {
  final way = eye - target;
  final reach = way.length;
  if (reach <= 0.0) return eye;
  final along = way / reach;
  final hit = cast(target, along, reach + eyeClearance);
  if (hit == null) return eye;
  return target + along * math.max(math.min(hit - eyeClearance, reach), 0.0);
}

/// What the sea is: salt water, as clear as pure water.
/// As warm as the air of the world it is poured into.
final Liquid _seawater = Liquid(
  properties: reefSea,
  optics: LiquidOptics.pureWater,
  heat: NativeLiquidHeat.water(),
  atAirTemperature: true,
);

/// A dive, stepped and drawn.
final class ReefRun {
  ReefRun({
    required GraphicsDevice device,
    required this.scene,
    required this.elements,
    required this.surface,
    required this.floor,
    required this.looks,
    InputState? input,
  }) : _device = device,
       input = input ?? InputState() {
    _floor = floorGrid();
    _buildFloor();
    // The sea going on past what is simulated, so its edge is open water.
    const Horizon(
      size: reefSize,
      floorCell: floorCell,
      surfaceCell: seaCell,
      ground: drawnFloorAt,
    ).addTo(
      device,
      scene,
      floor: underWith(
        floor,
        'far sand',
        Vector4(1.0, 0.97, 0.90, 1.0),
        picture: looks.sand,
        roughness: 0.95,
      ),
      surface: surface.material,
    );
    _sea = elements.addWater(
      ground: ElementHeightfield.list(
        origin: Vector3.zero(),
        cell: seaCell,
        nx: seaCells,
        nz: seaCells,
        heights: _floor,
      ),
      liquid: _seawater,
      bed: const Bed(roughness: Bed.naturalStream),
    );
    // The sea past the reef and the floor under it ripple with the wind
    // over the reef's sea.
    surface.wind = elements.wind.length;
    floor.wind = elements.wind.length;
    _sea.fillBasin(from: start, level: 0.0);
    // The current comes in across the west edge and leaves across the
    // east, where the open sea stands at the reef's level; north and south
    // the reef runs on along the current, and nothing crosses.
    _sea
      ..setEdge(GridSide.west, const NativeEdgeFlow.inflow(discharge: _current))
      ..setEdge(GridSide.east, const NativeEdgeFlow.level(0.0));
    RenderMaterial under(String name, Vector4 color) =>
        floor.under(name, color, roughness: 0.85);
    wreck = Wreck(world, device, scene, floor, looks.wreck);
    ReefLife(
      device,
      scene,
      floor,
      looks.rocks,
      HullRoom(<(MeshData, Matrix4)>[
        for (final piece in looks.wreck.pieces) (piece.data, piece.place),
      ]),
      light: light,
    );
    boat = Boat(world, device, scene, 0.0);
    finds = Finds(world, device, scene, floor, looks);
    diver = Diver(world, device, scene, floor, looks.diver, start);
    final bagMesh = DeviceMesh.upload(
      device,
      const SphereShape(radius: 1.0, segments: 14, rings: 10).build(),
    );
    for (var k = 0; k < 3; k++) {
      final node = MeshNode(
        bagMesh,
        under('bag', Vector4(0.95, 0.55, 0.05, 1.0)),
        name: 'bag',
      )..isVisible = false;
      scene.add(node);
      bags.add(LiftBag(world, node));
    }
    // The finds drawn where the world has them, and taken out with them.
    for (final f in finds.finds) {
      _tracked[f] = elements.track(f.body, look: f.look);
    }
  }

  final Map<Find, TrackedBody> _tracked = <Find, TrackedBody>{};

  final GraphicsDevice _device;
  final Scene scene;

  /// The sea, the finds and the bags as the core has them, drawn and heard;
  /// the run steps the world itself.
  final Elements elements;

  /// Whether to draw less of the sea, for a phone.
  bool get light => identical(elements.quality.liquid, LiquidDetail.light);

  /// The sea's surface, and everything under it.
  final LiquidLook surface;
  final SeabedLook floor;

  /// The models and pictures read before the dive.
  final ReefLooks looks;

  NativeWorld get world => elements.world;
  late final List<double> _floor;
  late final WaterBody _sea;
  NativeShallowLiquid get sea => _sea.native;
  late final Wreck wreck;
  late final Boat boat;

  /// The solid floor, which the eye is kept out of with the ship.
  late final NativeBody _solid;

  /// [eye], or, where the reef or the ship stands between [target] and it,
  /// pulled in along the way to it to stand a hand's breadth clear of what
  /// is in the way: the eye of a diver's shoulder, which does not look
  /// from inside a wall or a hull.
  Vector3 clearView(Vector3 target, Vector3 eye) => clearOfSolid(
    target,
    eye,
    (from, along, reach) => world
        .rayCastAll(from, along, reach)
        .where((hit) => hit.body == _solid || wreck.bodies.contains(hit.body))
        .firstOrNull
        ?.at,
  );
  late final Finds finds;
  late final Diver diver;
  final List<LiftBag> bags = <LiftBag>[];
  PhysicsHearing get hearing => elements.hearing!;

  /// What the last action did, for the panel.
  String said = '';
  double _clock = 0.0;

  /// Where a dive starts: in the water beside the boat.
  Vector3 get start => Vector3(boatX + 1.0, -1.2, boatZ + 2.5);

  /// The sea's surface over the diver.
  double get level =>
      world.sampleShallow(sea, diver.position.x, diver.position.z)?.surface ??
      0.0;

  /// How many finds are in the boat.
  int get raised => finds.finds.where((f) => f.aboard).length;

  /// Where the eye is, for the ripples and the water's colour.
  final Vector3 eye = Vector3.zero();

  /// The action key: a bag onto the nearest find; or, near one already
  /// tied, air into it.
  void act() {
    final at = diver.position;
    final tied = bags.where((b) => b.inUse).toList();
    for (final b in tied) {
      final p = b.position;
      if (p != null && (p - at).length < 2.5) {
        final litres = 20.0 * squeezeAt(world, diver.depthUnder(level));
        if (diver.air <= litres) {
          said = 'Not enough air in the tank to spare.';
          return;
        }
        diver.air -= litres;
        b.fill(litres);
        said = 'Twenty litres into the bag on the ${b.lifting!.name}.';
        return;
      }
    }
    final find = finds.nearest(at);
    if (find == null) {
      said = 'Nothing near enough to tie a bag to.';
      return;
    }
    if (bags.any((b) => b.lifting == find)) {
      said = 'The ${find.name} has a bag on it: swim up to the bag to fill it.';
      return;
    }
    final free = bags.where((b) => !b.inUse);
    if (free.isEmpty) {
      said = 'All three bags are out.';
      return;
    }
    free.first.tie(find);
    // What it weighs in the water: its weight less the water it displaces
    // holds up; a litre of air at the surface lifts a kilogram.
    final (:volume, water: _) = world.submergedOf(find.body);
    final weight = world.massOf(find.body) - reefSea.density * volume;
    said =
        'A bag on the ${find.name}, ${weight.round()} kg in the water: '
        'E by the bag to blow air in.';
  }

  void _buildFloor() {
    // What is drawn stands on the solid floor by the reef's relief, finer
    // than the solid one, and is shaded by its own slopes.
    final n = light ? floorCells : drawnCells;
    final cell = reefSize / n;
    final vertices = Float32List(n * n * _stride);
    final drawn = <double>[
      for (var j = 0; j < n; j++)
        for (var i = 0; i < n; i++)
          drawnFloorAt((i + 0.5) * cell, (j + 0.5) * cell),
    ];
    double g(int i, int j) => drawn[i.clamp(0, n - 1) + j.clamp(0, n - 1) * n];
    final rocky = Float32List(n * n);
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final x = (i + 0.5) * cell, z = (j + 0.5) * cell;
        final normal = Vector3(
          -(g(i + 1, j) - g(i - 1, j)) / (2 * cell),
          1.0,
          -(g(i, j + 1) - g(i, j - 1)) / (2 * cell),
        )..normalize();
        // The rock's relief is read along the picture's own axes: u runs
        // with z, so the tangent is the way along z laid in the slope; v
        // runs down the wall, and the engine's bitangent is the way v
        // falls (`material_maps.glsl`: green up the picture), which from
        // this normal and tangent is a fourth number of −1.
        final tangent = (Vector3(0.0, 0.0, 1.0) - normal * normal.z)
          ..normalize();
        rocky[i + j * n] = rockinessAt(x, z);
        var head = 0.0;
        for (final (cx, cz, r, _) in coralHeads) {
          final d = math.sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)) / r;
          head = math.max(head, (1.4 - d * 1.2).clamp(0.0, 1.0));
        }
        final speck = (((i * 73856093) ^ (j * 19349663)) & 0xff) / 255.0;
        // The pictures carry the grain; the vertices only the slow change
        // across the reef — sand a shade paler on the plain than in the
        // hollows of the flat, the rock's crust warmer on the heads.
        final tone = 0.92 + 0.12 * speck;
        final o = (i + j * n) * _stride;
        vertices
          ..[o] = x
          ..[o + 1] = g(i, j)
          ..[o + 2] = z
          ..[o + 3] = normal.x
          ..[o + 4] = normal.y
          ..[o + 5] = normal.z
          // Across along z, and down the wall by the distance travelled
          // over it rather than across it, so the rock's picture is not
          // stretched where the wall falls away.
          ..[o + 6] = z / 3
          ..[o + 7] = (x - g(i, j)) / 3
          ..[o + 8] = tangent.x
          ..[o + 9] = tangent.y
          ..[o + 10] = tangent.z
          ..[o + 11] = -1
          ..[o + 12] = tone * (1.0 + 0.10 * head)
          ..[o + 13] = tone
          ..[o + 14] = tone * (1.0 - 0.06 * head)
          ..[o + 15] = 1;
      }
    }
    final sand = <int>[];
    final rock = <int>[];
    for (var j = 0; j < n - 1; j++) {
      for (var i = 0; i < n - 1; i++) {
        final a = i + j * n, b = i + (j + 1) * n;
        for (final triangle in <List<int>>[
          <int>[a, b, a + 1],
          <int>[a + 1, b, b + 1],
        ]) {
          final most = triangle.map((v) => rocky[v]).reduce(math.max);
          final least = triangle.map((v) => rocky[v]).reduce(math.min);
          if (least < 0.8) sand.addAll(triangle);
          if (most > 0.2) rock.addAll(triangle);
        }
      }
    }
    // The reef laid over the sand a couple of centimetres up, cut where the
    // vertex's share of rock times the rock's own height, in its picture's
    // alpha, falls below a half: from a share of one the whole of it shows,
    // and as the share falls the sand fills the rock's crevices first and
    // covers its crests last, so the reef gives out into the sand along its
    // own shapes rather than along the edges of triangles. Sand does not
    // lie on a slope much steeper than its own, so down the wall the share
    // is raised until no crevice is deep enough to hold any.
    final reef = Float32List.fromList(vertices);
    for (var v = 0; v < n * n; v++) {
      // The first fifth of rockiness is the sand's own hummocks, and drawn
      // as rock it would speckle the plain.
      final t = ((rocky[v] - 0.2) / 0.6).clamp(0.0, 1.0);
      final steep = ((1.0 - vertices[v * _stride + 4]) * 5.0).clamp(0.0, 1.0);
      reef
        ..[v * _stride + 1] += 0.02
        ..[v * _stride + 15] =
            (0.45 + 0.55 * t * t * (3.0 - 2.0 * t)) * (1.0 + 2.0 * steep);
    }
    // Two meshes, the sand in its picture and the reef in its own, each in
    // the floor's material, so each is lit through the same surface by the
    // same caustics.
    for (final (name, data, part, picture, relief)
        in <(String, Float32List, List<int>, TextureHandle, TextureHandle?)>[
          ('sand', vertices, sand, looks.sand, null),
          ('reef', reef, rock, looks.reefRock, looks.reefRelief),
        ]) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            _device,
            MeshData(
              layout: VertexLayout.standard,
              vertices: data,
              indices: Uint32List.fromList(part),
            ),
          ),
          underWith(
            floor,
            name,
            name == 'sand'
                ? Vector4(1.0, 0.97, 0.90, 1.0)
                : Vector4(1.15, 1.0, 1.05, 1.0),
            picture: picture,
            relief: relief,
            roughness: 0.95,
            alphaMode: name == 'sand'
                ? MaterialAlphaMode.opaque
                : MaterialAlphaMode.mask,
          ),
          name: 'floor $name',
        ),
      );
    }
    // The solid floor, the smooth one, at its own coarser spacing.
    const s = floorCells;
    _solid = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setMesh(
      _solid,
      world.createMesh(
        <Vector3>[
          for (var j = 0; j < s; j++)
            for (var i = 0; i < s; i++)
              Vector3(
                (i + 0.5) * floorCell,
                floorAt((i + 0.5) * floorCell, (j + 0.5) * floorCell),
                (j + 0.5) * floorCell,
              ),
        ],
        <int>[
          for (var j = 0; j < s - 1; j++)
            for (var i = 0; i < s - 1; i++) ...<int>[
              i + j * s,
              i + (j + 1) * s,
              i + 1 + j * s,
              i + 1 + j * s,
              i + (j + 1) * s,
              i + 1 + (j + 1) * s,
            ],
        ],
      ),
    );
  }

  /// What the player asks for: the window's keys and pointer write it, a
  /// tape writes it on a replay, and the step alone reads it.
  final InputState input;

  /// Which way the eye looks round the diver, radians about y: the way the
  /// keys swim relative to. **The simulation's**, because it decides where
  /// the fins push: the pointer turns it through [input]'s look, and it
  /// drifts round behind a swimming diver in the step.
  double eyeYaw = math.pi;

  /// Seconds since the pointer last turned the eye, stepped.
  double _sinceLook = 10.0;

  /// How fast the diver turns at most, radians a second, and how quickly
  /// the eye swings round behind them while they swim and nobody is
  /// turning it.
  static const double _turnRate = 2.2, _follow = 1.2;

  /// [controls] read off [input], at the top of a step: the keys say where
  /// the diver means to go, turned by where the eye looks; the diver turns
  /// towards it no faster than a body in water turns, and the fins push the
  /// way they face, less the further the diver still has to turn.
  void _steer(double dt) {
    final i = input;
    if (i.pressed(ReefActions.act)) act();
    final look = i.lookDelta.x;
    if (look != 0.0) {
      _sinceLook = 0.0;
      eyeYaw -= look * lookPerPixel;
    } else {
      _sinceLook += dt;
    }
    double axis(GameAction plus, GameAction minus) =>
        (i.held(plus) ? 1.0 : 0.0) - (i.held(minus) ? 1.0 : 0.0);
    final ahead = axis(GameAction.moveForward, GameAction.moveBack);
    final side = axis(GameAction.moveRight, GameAction.moveLeft);
    // An axis now, on Space and C as a composite; a dive recorded when it
    // was two buttons is upgraded by [ReefActions.set].
    final rise = i.axis(ReefActions.ascend);
    var heading = controls.heading;
    // Forward is away from the eye, level; the eye looks along −(yaw).
    final eye = Portable.sinCos(eyeYaw);
    final forward = Vector3(-eye.cos, 0.0, eye.sin);
    final right = Vector3(-forward.z, 0.0, forward.x);
    final wanted = forward * ahead + right * side;
    var push = 0.0;
    if (wanted.length2 > 0.0) {
      final target = Portable.atan2(-wanted.z, wanted.x);
      final turn = _wrap(target - heading);
      // Eased in as the turn closes, so the diver settles on the new way
      // rather than stopping on it.
      final rate = math.min(_turnRate, 3.0 * turn.abs() + 0.4);
      heading = _wrap(heading + turn.clamp(-rate * dt, rate * dt));
      push = math.max(Portable.cos(_wrap(target - heading)), 0.0);
      // The eye drifts round behind a swimming diver.
      if (_sinceLook > 1.5 && ahead > 0.0) {
        final behind = _wrap(heading + math.pi - eyeYaw);
        eyeYaw += behind * math.min(_follow * dt, 1.0);
      }
    }
    final fins = Portable.sinCos(heading);
    final facing = Vector3(fins.cos, 0.0, -fins.sin);
    final swim =
        facing * (push * math.min(wanted.length, 1.0)) +
        Vector3(0.0, rise, 0.0);
    controls = (
      swim: swim.length > 1.0 ? swim.normalized() : swim,
      fill: i.held(ReefActions.fill) ? 1.0 : 0.0,
      dump: i.held(ReefActions.dump) ? 1.0 : 0.0,
      heading: heading,
    );
  }

  /// [angle] brought into (−π, π].
  static double _wrap(double angle) {
    var a = angle % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    return a;
  }

  /// What the diver does: the way the fins push, [ReefControls.swim], how
  /// hard the jacket is filled and dumped, and which way they lie. Read off
  /// [input] at the top of every step, or handed in by a reel's [step].
  ReefControls controls = (
    swim: Vector3.zero(),
    fill: 0.0,
    dump: 0.0,
    heading: 0.0,
  );

  /// The dive's step, phase by phase, on [loop]: [controls] read off
  /// [input] in `input`, the diver's fins and the core's world in `physics`, the elements — the sea's events read, its
  /// water drawn and heard — in `elements`, the bags, the finds and the air
  /// in `rules`, and the boat, the diver and the light through the surface
  /// drawn once a frame, in `animate`.
  ///
  /// **A fixed step now, at the loop's world rate.** The dive was stepped
  /// with each frame's own time; it is stepped in sixtieths whatever the
  /// display.
  void install(LoopRegistry loop) {
    loop
      ..addSystem('reef.controls', LoopPhase.input, (step) => _steer(step.dt))
      ..addSystem('reef.world', LoopPhase.physics, (step) => _move(step.dt))
      ..addSystem(
        'reef.elements',
        LoopPhase.fields,
        (step) => elements.update(step.dt, eye: eye),
      )
      ..addSystem('reef.dive', LoopPhase.rules, (step) => _rules(step.dt))
      ..addSystem('reef.show', LoopPhase.animate, (_) => show());
  }

  /// One step of [dt] and what is drawn of it, in the order [install] runs
  /// them, the diver doing as [swim], [fill], [dump] and [heading] say: for
  /// a reel, which steps the dive by its own frames.
  void step(
    double dt, {
    required Vector3 swim,
    required double fill,
    required double dump,
    required double heading,
  }) {
    controls = (swim: swim, fill: fill, dump: dump, heading: heading);
    _move(dt);
    elements.update(dt, eye: eye);
    _rules(dt);
    show();
  }

  void _move(double dt) {
    final c = controls;
    diver.step(dt, level: level, swim: c.swim, fill: c.fill, dump: c.dump);
    world.step(dt);
  }

  void _rules(double dt) {
    _clock += dt;
    for (final b in bags) {
      b.update(level);
    }
    for (final f in finds.finds) {
      if (f.aboard) continue;
      final p = world.localPositionOf(f.body);
      // Up at the surface on its bag, the boat weighs anchor and motors
      // round to it; alongside, it is hauled in.
      final bag = bags.where((b) => b.lifting == f).firstOrNull;
      final floating = bag?.position;
      final up = floating != null && floating.y > level - 0.6;
      f.surfaced = up ? f.surfaced + dt : 0.0;
      if (!boat.alongside(p)) {
        if (up) {
          if (f.surfaced < dt * 1.5) {
            said = 'The ${f.name} is up: the boat is coming round for it.';
          }
          boat.motorTo(floating);
        }
        continue;
      }
      boat.stop();
      // Hauled over the side: the bag cut free and folded.
      for (final b in bags) {
        if (b.lifting == f) b.untie();
      }
      f.aboard = true;
      elements.remove(_tracked.remove(f)!);
      scene.remove(f.look);
      said = 'The ${f.name} is in the boat.';
    }
    if (diver.air <= 0.0) {
      diver.restart(start);
      said = 'Out of air: hauled up into the boat. Watch the gauge.';
    }
  }

  /// The boat and the diver drawn where the world has them, and the light
  /// through the surface and on the floor.
  void show() {
    boat.update();
    diver.update(controls.heading);
    surface.update(seconds: _clock, eye: eye);
    floor.update(seconds: _clock, eye: eye, level: 0.0);
  }

  // ------------------------------------------------------------- saving

  /// The dive as it stands after a step: the core's world with the sea and
  /// every body in it, and what only this side keeps — the diver's air, the
  /// bags and what they lift, the finds aboard, the boat's anchor, where the
  /// eye looks round the diver and which way they lie.
  Snapshot save() => Snapshot(<String, Object?>{
    'world': base64Encode(world.snapshot()),
    'elements': elements.saveElements(),
    'said': said,
    'clock': _clock,
    'eyeYaw': eyeYaw,
    'sinceLook': _sinceLook,
    'heading': controls.heading,
    'diver': diver.save(),
    'boat': boat.save(),
    'finds': <Object?>[for (final f in finds.finds) f.save()],
    'bags': <Object?>[for (final b in bags) b.save(finds.finds)],
  });

  /// Puts the dive back as [save] wrote it. Throws a [FormatException] for
  /// a snapshot that is not one of this reef's.
  void restore(Snapshot snapshot) {
    final d = snapshot.data;
    if (d case {
      'world': final String bytes,
      'elements': final Map<String, Object?> saved,
      'said': final String said,
      'clock': final num clock,
      'eyeYaw': final num eyeYaw,
      'sinceLook': final num sinceLook,
      'heading': final num heading,
      'finds': final List<Object?> found,
      'bags': final List<Object?> lifting,
    }) {
      world.restore(base64Decode(bytes));
      // The events of the world that was left are not this one's.
      world.readEvents();
      elements.restoreElements(saved);
      this.said = said;
      _clock = clock.toDouble();
      this.eyeYaw = eyeYaw.toDouble();
      _sinceLook = sinceLook.toDouble();
      controls = (
        swim: Vector3.zero(),
        fill: 0.0,
        dump: 0.0,
        heading: heading.toDouble(),
      );
      diver.restore(d['diver']);
      boat.restore(d['boat']);
      for (var k = 0; k < finds.finds.length && k < found.length; k++) {
        final f = finds.finds[k]..restore(found[k]);
        // A find hauled aboard is out of the world and the scene; one that
        // was not is back in both.
        final tracked = _tracked[f];
        if (f.aboard && tracked != null) {
          elements.remove(_tracked.remove(f)!);
          scene.remove(f.look);
        } else if (!f.aboard && tracked == null) {
          _tracked[f] = elements.track(f.body, look: f.look);
          scene.add(f.look);
        }
      }
      for (var k = 0; k < bags.length && k < lifting.length; k++) {
        bags[k].restore(lifting[k], finds.finds);
      }
      show();
      return;
    }
    throw const FormatException('not a snapshot of Wreck Reef');
  }

  /// Where the dive's moving bodies are, for the pose record a `.f3drun`
  /// carries beside its tape: the diver, the boat, the finds still in the
  /// sea and the bags in use.
  Iterable<BodyPose> poses() sync* {
    BodyPose pose(String name, NativeBody body) =>
        BodyPose(name, world.localPositionOf(body), world.orientationOf(body));
    yield pose('diver', diver.body);
    yield pose('boat', boat.body);
    for (final f in finds.finds) {
      if (!f.aboard) yield pose(f.name, f.body);
    }
    for (var k = 0; k < bags.length; k++) {
      final body = bags[k].body;
      if (body != null) yield pose('bag#$k', body);
    }
  }

  void dispose() {
    elements.dispose();
    world.dispose();
  }
}
