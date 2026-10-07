/// The one place that assembles a dive on Wreck Reef: the sea and its
/// current, the floor lit through the surface, the ship, the boat, the
/// finds, the diver and the bags.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'diver.dart';
import 'finds.dart';
import 'looks.dart';
import 'reef_life.dart';
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
    required this.looks,
    this.light = false,
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
      detail: light ? LiquidDetail.light : LiquidDetail.full,
    );
    Material under(String name, Vector4 colour) =>
        floor.under(name, colour, roughness: 0.85);
    Wreck(world, device, scene, floor, looks.wreck);
    ReefLife(device, scene, floor, looks.rocks, light: light);
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

  /// Whether to draw less of the sea, for a phone.
  final bool light;

  /// The sea's surface, and everything under it.
  final LiquidLook surface;
  final SeabedLook floor;

  /// The models and pictures read before the dive.
  final ReefLooks looks;

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
    // What is drawn stands on the solid floor by the reef's relief, and is
    // shaded by its own slopes.
    final drawn = <double>[
      for (var j = 0; j < n; j++)
        for (var i = 0; i < n; i++)
          heights[i + j * n] +
              reliefAt((i + 0.5) * floorCell, (j + 0.5) * floorCell),
    ];
    double g(int i, int j) => drawn[i.clamp(0, n - 1) + j.clamp(0, n - 1) * n];
    final rocky = Float32List(n * n);
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final x = (i + 0.5) * floorCell, z = (j + 0.5) * floorCell;
        final normal = Vector3(
          -(g(i + 1, j) - g(i - 1, j)) / (2 * floorCell),
          1.0,
          -(g(i, j + 1) - g(i, j - 1)) / (2 * floorCell),
        )..normalize();
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
          ..[o + 8] = 1
          ..[o + 11] = 1
          ..[o + 12] = tone * (1.0 + 0.10 * head)
          ..[o + 13] = tone
          ..[o + 14] = tone * (1.0 - 0.06 * head)
          ..[o + 15] = 1;
      }
    }
    final indices = <int>[];
    final sand = <int>[];
    final rock = <int>[];
    for (var j = 0; j < n - 1; j++) {
      for (var i = 0; i < n - 1; i++) {
        final a = i + j * n, b = i + (j + 1) * n;
        for (final triangle in <List<int>>[
          <int>[a, b, a + 1],
          <int>[a + 1, b, b + 1],
        ]) {
          indices.addAll(triangle);
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
    for (final (name, data, part, picture)
        in <(String, Float32List, List<int>, TextureHandle)>[
          ('sand', vertices, sand, looks.sand),
          ('reef', reef, rock, looks.reefRock),
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
            roughness: 0.95,
            alphaMode: name == 'sand'
                ? MaterialAlphaMode.opaque
                : MaterialAlphaMode.mask,
          ),
          name: 'floor $name',
        ),
      );
    }
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
