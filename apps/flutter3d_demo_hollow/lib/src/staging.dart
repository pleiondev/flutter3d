/// The one place that assembles a run of Cobble Hollow: the ground, the
/// river and its lagoon, the volcano's lava, and what is drawn of them.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'car.dart';
import 'crane.dart';
import 'props.dart';
import 'terrain.dart';

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// The valley, stepped and drawn.
final class HollowRun {
  HollowRun({
    required GraphicsDevice device,
    required this.scene,
    required Renderer renderer,
    required this.water,
    required this.lava,
  }) : _device = device {
    _ground = groundGrid();
    _buildGround();
    _river = world.createShallowLiquid(
      nx: hollowCells,
      nz: hollowCells,
      cell: hollowCell,
      origin: Vector3.zero(),
      ground: _ground,
    );
    world
      ..setShallowBed(_river, roughness: 0.035, openEdges: true)
      ..fillShallowLiquid(
        _river,
        x0: lagoonX - lagoonRadius,
        z0: cliffFoot,
        x1: lagoonX + lagoonRadius,
        z1: lagoonZ + lagoonRadius,
        level: 0.6,
      )
      ..setShallowSource(
        _river,
        0,
        x: springX,
        z: springZ,
        radius: 0.8,
        rate: 0.6,
      );
    riverView = LiquidView(
      world: world,
      liquid: _river,
      ground: _ground,
      device: device,
      scene: scene,
      look: water.material,
    );
    // The lava's own grid, over the volcano's south flank.
    final lavaGround = groundGrid(
      x0: _lavaX0,
      z0: 0.0,
      nx: _lavaCells,
      nz: _lavaCells,
    );
    _lava = world.createShallowLiquid(
      nx: _lavaCells,
      nz: _lavaCells,
      cell: hollowCell,
      origin: Vector3(_lavaX0, 0.0, 0.0),
      ground: lavaGround,
    );
    world
      ..setShallowProperties(_lava, NativeLiquidProperties.moltenBasalt)
      ..setShallowBed(_lava, roughness: 0.05);
    lavaView = LiquidView(
      world: world,
      liquid: _lava,
      ground: lavaGround,
      device: device,
      scene: scene,
      look: lava.material,
      detail: LiquidDetail.light,
    );
    car = StoneCar(
      world,
      device,
      scene,
      Vector3(siteX, groundAt(siteX, siteZ - 6) + 1.2, siteZ - 6),
    );
    fire = FireView(
      world: world,
      device: device,
      scene: scene,
      renderer: renderer,
      baseWidth: 0.5,
    );
    stones = QuarryStones(world, device, scene);
    idol = Idol(world, device, scene);
    rafts = Rafts(world, device, scene, hearing, _river);
    hearing
      ..listen(_river)
      ..listen(_lava, density: NativeLiquidProperties.moltenBasalt.density)
      ..watch(idol.body, _river);
    village = Village(world, device, scene, fire);
    volcano = Volcano(world, device, scene, _lava, village.huts);
    // On the quarry's north rim, facing into it.
    final craneAt = Vector3(
      quarryX,
      groundAt(quarryX, quarryZ - quarryHalfZ - 2.2),
      quarryZ - quarryHalfZ - 2.2,
    );
    crane = DinoCrane(
      world,
      device,
      scene,
      at: craneAt,
      facing: -1.5707963267948966,
    );
    _craneAt = craneAt;
  }

  /// The lava's grid: from x = 36 to the east edge, from the north edge
  /// past the cliff.
  static const double _lavaX0 = 32.0;
  static const int _lavaCells = 64;

  final GraphicsDevice _device;
  final Scene scene;

  /// The looks of the river and of the lava.
  final LiquidLook water, lava;

  final NativeWorld world = NativeWorld();
  late final List<double> _ground;
  late final NativeShallowLiquid _river, _lava;
  late final LiquidView riverView, lavaView;
  late final FireView fire;
  late final StoneCar car;
  late final QuarryStones stones;
  late final Idol idol;
  late final Rafts rafts;

  /// What the fires, the falls and the splashes sound like this frame.
  late final PhysicsHearing hearing = PhysicsHearing(world);
  late final Village village;
  late final Volcano volcano;
  late final DinoCrane crane;

  /// Whether the player works the crane rather than drives.
  bool craning = false;

  /// What the last action did, for the panel.
  String said = '';
  double _clock = 0.0;

  late final Vector3 _craneAt;

  /// Whether the car stands near enough the crane to work it.
  bool get nearCrane => (car.position - _craneAt).length < 9.0;

  /// The one action key: at the water, fill the barrel; at a burning hut,
  /// empty it over it.
  void act() {
    final p = car.position;
    if (idol.carried) {
      if (Vector2(p.x - villageX, p.z - villageZ).length < 6.0) {
        idol.setDown();
        said = 'The idol is home.';
        return;
      }
    } else if (!idol.home && idol.lift(car.body, car.deck, p)) {
      said = 'The idol is on the car: bring it to the village.';
      return;
    }
    final here = world.sampleShallow(_river, p.x, p.z);
    if (here != null && here.depth > 0.3) {
      car.water = StoneCar.barrelHolds;
      said = 'The barrel is full.';
      return;
    }
    if (car.water >= 25.0 && village.douse(p, kilograms: car.water)) {
      car.water = 0.0;
      said = 'Water over the hut.';
      return;
    }
    said = car.water <= 0.0
        ? 'Drive into the river or the lagoon to fill the barrel.'
        : 'Nothing burning near enough.';
  }

  /// Where the eye is, for the ripples that fade with distance.
  final Vector3 eye = Vector3.zero();

  /// The lagoon's surface over the origin, m.
  double get lagoonLevel =>
      world.sampleShallow(_river, lagoonX, lagoonZ)?.surface ?? 0.0;

  void _buildGround() {
    final n = hollowCells;
    final vertices = Float32List(n * n * _stride);
    double at(int i, int j) =>
        _ground[i.clamp(0, n - 1) + j.clamp(0, n - 1) * n];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final x = (i + 0.5) * hollowCell, z = (j + 0.5) * hollowCell;
        final h = at(i, j);
        final normal = Vector3(
          -(at(i + 1, j) - at(i - 1, j)) / (2 * hollowCell),
          1.0,
          -(at(i, j + 1) - at(i, j - 1)) / (2 * hollowCell),
        )..normalize();
        final o = (i + j * n) * _stride;
        final colour = _colourAt(x, z, h, normal.y);
        vertices
          ..[o] = x
          ..[o + 1] = h
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
        Material(name: 'ground', roughness: 0.95),
        name: 'ground',
      ),
    );
    final floor = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setMesh(
      floor,
      world.createMesh(<Vector3>[
        for (var j = 0; j < n; j++)
          for (var i = 0; i < n; i++)
            Vector3((i + 0.5) * hollowCell, at(i, j), (j + 0.5) * hollowCell),
      ], indices),
    );
  }

  /// What the ground is at (x, z): grass on the level, bare rock where it
  /// is steep or quarried, dark basalt on the volcano, sand by the water,
  /// trodden earth where the village and the builder stand.
  static Vector3 _colourAt(double x, double z, double h, double up) {
    final steep = ((1.0 - up) * 4.0).clamp(0.0, 1.0);
    final grass = Vector3(0.20, 0.32, 0.11);
    final rock = Vector3(0.40, 0.38, 0.35);
    final basalt = Vector3(0.12, 0.11, 0.11);
    final sand = Vector3(0.62, 0.55, 0.40);
    final earth = Vector3(0.36, 0.28, 0.19);
    final dv = Vector3(x - volcanoX, 0, z - volcanoZ).length / volcanoRadius;
    final dl = Vector3(x - lagoonX, 0, z - lagoonZ).length / lagoonRadius;
    final dq = Vector3(
      (x - quarryX) / quarryHalfX,
      0,
      (z - quarryZ) / quarryHalfZ,
    ).length;
    final dvill = Vector3(x - villageX, 0, z - villageZ).length / 8;
    final dsite = Vector3(x - siteX, 0, z - siteZ).length / 4;
    var c = grass + (rock - grass) * steep;
    if (dl < 1.25) c = c + (sand - c) * ((1.25 - dl) * 2).clamp(0.0, 1.0);
    if (dq < 1.1) c = c + (rock - c) * ((1.1 - dq) * 4).clamp(0.0, 1.0);
    if (dv < 1.0) c = c + (basalt - c) * ((1.0 - dv) * 3).clamp(0.0, 1.0);
    final trodden = 1.0 - (dvill < dsite ? dvill : dsite);
    if (trodden > 0) c = c + (earth - c) * (trodden * 1.5).clamp(0.0, 0.8);
    return c;
  }

  /// One frame: the world on by [dt], and what is drawn of it.
  void step(double dt) {
    world.step(dt);
    _clock += dt;
    car.update();
    stones.update();
    idol.update();
    rafts.update(dt);
    crane.update();
    volcano.update(dt);
    riverView.update();
    lavaView.update();
    fire.update(dt);
    hearing.update(dt);
    water.update(seconds: _clock, eye: eye);
    lava.update(seconds: _clock, eye: eye);
  }

  void dispose() => world.dispose();
}
