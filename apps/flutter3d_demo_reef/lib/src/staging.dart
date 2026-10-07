/// The one place that assembles a dive on Wreck Reef: the sea and its
/// current, the floor lit through the surface, the ship, the boat, the
/// finds, the diver and the bags.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'diver.dart';
import 'finds.dart';
import 'terrain.dart';
import 'wreck.dart';

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// The current's rate, m³/s, through the sea from west to east: over the
/// four-metre flat, some forty centimetres a second; over the ship, ten.
const double _current = 100.0;

/// A dive, stepped and drawn.
final class ReefRun {
  ReefRun({
    required GraphicsDevice device,
    required this.scene,
    required this.surface,
    required this.floor,
  }) : _device = device {
    _floor = floorGrid();
    _buildFloor();
    sea = world.createShallowLiquid(
      nx: seaCells,
      nz: seaCells,
      cell: seaCell,
      origin: Vector3.zero(),
      ground: _floor,
    );
    world
      ..setShallowProperties(sea, NativeLiquidProperties.seawater)
      ..setShallowBed(sea, roughness: 0.03)
      ..fillShallowLiquid(
        sea,
        x0: 0,
        z0: 0,
        x1: reefSize,
        z1: reefSize,
        level: 0.0,
      );
    _setCurrent(0.0);
    seaView = LiquidView(
      world: world,
      liquid: sea,
      ground: _floor,
      device: device,
      scene: scene,
      look: surface.material,
    );
    Material under(String name, Vector4 colour) =>
        floor.under(name, colour, roughness: 0.85);
    Wreck(
      world,
      device,
      scene,
      under('timber', Vector4(0.22, 0.17, 0.12, 1.0)),
    );
    boat = Boat(world, device, scene, 0.0);
    finds = Finds(world, device, scene, under);
    diver = Diver(
      world,
      device,
      scene,
      under('suit', Vector4(0.05, 0.06, 0.08, 1.0)),
      under('gear', Vector4(0.85, 0.65, 0.10, 1.0)),
      start,
    );
    final bagMesh = DeviceMesh.upload(
      device,
      const SphereShape(radius: 1.0, segments: 14, rings: 10).build(),
    );
    for (var k = 0; k < 3; k++) {
      final node = MeshNode(
        bagMesh,
        under('bag', Vector4(0.95, 0.55, 0.05, 1.0)),
        name: 'bag',
      )..visible = false;
      scene.add(node);
      bags.add(LiftBag(world, node));
    }
    hearing
      ..watch(diver.body, sea)
      ..listen(sea, density: NativeLiquidProperties.seawater.density);
    for (final f in finds.finds) {
      hearing.watch(f.body, sea);
    }
  }

  final GraphicsDevice _device;
  final Scene scene;

  /// The sea's surface, and everything under it.
  final LiquidLook surface;
  final SeabedLook floor;

  final NativeWorld world = NativeWorld();
  late final List<double> _floor;
  late final NativeShallowLiquid sea;
  late final LiquidView seaView;
  late final Boat boat;
  late final Finds finds;
  late final Diver diver;
  final List<LiftBag> bags = <LiftBag>[];
  late final PhysicsHearing hearing = PhysicsHearing(world);

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
        final litres = 20.0 * pressureAt(diver.depthUnder(level));
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
    said = 'A bag on the ${find.name}: E by the bag to blow air in.';
  }

  void _buildFloor() {
    const n = floorCells;
    final vertices = Float32List(n * n * _stride);
    double at(int i, int j) => floorAt(
      (i.clamp(0, n - 1) + 0.5) * floorCell,
      (j.clamp(0, n - 1) + 0.5) * floorCell,
    );
    final heights = <double>[
      for (var j = 0; j < n; j++)
        for (var i = 0; i < n; i++) at(i, j),
    ];
    double h(int i, int j) =>
        heights[i.clamp(0, n - 1) + j.clamp(0, n - 1) * n];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final x = (i + 0.5) * floorCell, z = (j + 0.5) * floorCell;
        final y = h(i, j);
        final normal = Vector3(
          -(h(i + 1, j) - h(i - 1, j)) / (2 * floorCell),
          1.0,
          -(h(i, j + 1) - h(i, j - 1)) / (2 * floorCell),
        )..normalize();
        // Sand on the plain and the flat, coral rock where it is steep or
        // raised, a few per cent lighter or darker vertex to vertex.
        final steep = ((1.0 - normal.y) * 5.0).clamp(0.0, 1.0);
        final sand = Vector3(0.78, 0.72, 0.58);
        final rock = Vector3(0.45, 0.38, 0.40);
        final speck = (((i * 73856093) ^ (j * 19349663)) & 0xff) / 255.0;
        final colour = (sand + (rock - sand) * steep) * (0.9 + 0.2 * speck);
        final o = (i + j * n) * _stride;
        vertices
          ..[o] = x
          ..[o + 1] = y
          ..[o + 2] = z
          ..[o + 3] = normal.x
          ..[o + 4] = normal.y
          ..[o + 5] = normal.z
          ..[o + 6] = x / 4
          ..[o + 7] = z / 4
          ..[o + 8] = 1
          ..[o + 11] = 1
          ..[o + 12] = colour.x
          ..[o + 13] = colour.y
          ..[o + 14] = colour.z
          ..[o + 15] = 1;
      }
    }
    final indices = <int>[
      for (var j = 0; j < n - 1; j++)
        for (var i = 0; i < n - 1; i++) ...<int>[
          i + j * n,
          i + (j + 1) * n,
          i + 1 + j * n,
          i + 1 + j * n,
          i + (j + 1) * n,
          i + 1 + (j + 1) * n,
        ],
    ];
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          _device,
          MeshData(
            layout: VertexLayout.standard,
            vertices: vertices,
            indices: Uint32List.fromList(indices),
          ),
        ),
        floor.material,
        name: 'floor',
      ),
    );
    final solid = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setMesh(
      solid,
      world.createMesh(<Vector3>[
        for (var j = 0; j < n; j++)
          for (var i = 0; i < n; i++)
            Vector3((i + 0.5) * floorCell, h(i, j), (j + 0.5) * floorCell),
      ], indices),
    );
  }

  /// One frame: the diver's hands and fins as [swim], [fill] and [dump]
  /// say, the world on by [dt], and what is drawn of it.
  void step(
    double dt, {
    required Vector3 swim,
    required double fill,
    required double dump,
    required double heading,
  }) {
    if (_clock < _rising) {
      final t = _clock / _rising;
      _setCurrent(t * t * (3.0 - 2.0 * t));
    }
    final surfaceHere = level;
    diver.step(dt, level: surfaceHere, swim: swim, fill: fill, dump: dump);
    world.step(dt);
    _clock += dt;
    for (final b in bags) {
      b.update(level);
    }
    for (final f in finds.finds) {
      if (f.aboard) continue;
      final p = world.positionOf(f.body);
      // Up at the surface on its bag, it waits for the boat to motor round
      // and gaff it; alongside the boat it is simply hauled in.
      final bag = bags.where((b) => b.lifting == f).firstOrNull;
      final floating = bag?.position;
      final up = floating != null && floating.y > level - 0.6;
      f.surfaced = up ? f.surfaced + dt : 0.0;
      if (f.surfaced < _pickUp && !boat.alongside(p)) {
        if (up && f.surfaced < dt * 1.5) {
          said = 'The ${f.name} is up: the boat is coming round for it.';
        }
        continue;
      }
      // Hauled over the side: the bag cut free and folded.
      for (final b in bags) {
        if (b.lifting == f) b.untie();
      }
      f.aboard = true;
      hearing.forget(f.body);
      world.removeBody(f.body);
      scene.remove(f.look);
      said = 'The ${f.name} is in the boat.';
    }
    if (diver.air <= 0.0) {
      diver.restart(start);
      said = 'Out of air: hauled up into the boat. Watch the gauge.';
    }
    finds.update();
    boat.update();
    diver.update(heading);
    seaView.update();
    hearing.update(dt);
    surface.update(seconds: _clock, eye: eye);
    floor.update(seconds: _clock, eye: eye, level: 0.0);
  }

  /// The current at [share] of its full rate: springs along the west edge
  /// and drains of the same rate along the east, so water runs across while
  /// the sea keeps its level.
  void _setCurrent(double share) {
    for (var k = 0; k < 8; k++) {
      final z = 4.0 + k * 8.0;
      final rate = share * _current / 8;
      world
        ..setShallowSource(sea, k, x: 2.5, z: z, radius: 3.0, rate: rate)
        ..setShallowSource(
          sea,
          8 + k,
          x: reefSize - 2.5,
          z: z,
          radius: 3.0,
          rate: -rate,
        );
    }
  }

  /// How long a find waits at the surface for the boat, s.
  static const double _pickUp = 4.0;

  /// How long the current takes to rise to its full rate, s: as a tide's
  /// stream rises, not all at once — which would set the whole sea rocking
  /// from end to end.
  static const double _rising = 90.0;

  void dispose() => world.dispose();
}
