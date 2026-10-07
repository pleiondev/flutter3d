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
import 'looks.dart';
import 'props.dart';
import 'terrain.dart';

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// How far up a face of the ground may look, its normal's rise, and still
/// be drawn as a wall: steeper than about forty-five degrees.
const double _steep = 0.7;

/// The same on the volcano, where only the crater's lip, steeper than
/// about sixty-five degrees, is a wall.
const double _lip = 0.42;

/// A little over the plateau's top, m: what lies higher by the volcano is
/// the volcano.
const double _plateau = 8.3;

/// The valley, stepped and drawn.
final class HollowRun {
  HollowRun({
    required GraphicsDevice device,
    required this.scene,
    required Renderer renderer,
    required this.water,
    required this.lava,
    required HollowLooks looks,
    this.light = false,
  }) : _device = device {
    _ground = groundGrid();
    _buildGround(looks);
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
      detail: light ? LiquidDetail.light : LiquidDetail.full,
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
      looks,
    );
    fire = FireView(
      world: world,
      device: device,
      scene: scene,
      renderer: renderer,
      baseWidth: 0.5,
      detail: light ? FireDetail.light : FireDetail.full,
    );
    stones = QuarryStones(world, scene, looks);
    idol = Idol(world, device, scene, looks);
    rafts = Rafts(world, device, scene, hearing, _river, looks);
    trees = Trees(world, scene, fire, looks);
    hearing
      ..listen(_river)
      ..listen(_lava, density: NativeLiquidProperties.moltenBasalt.density)
      ..watch(idol.body, _river);
    village = Village(world, device, scene, fire, looks);
    volcano = Volcano(world, device, scene, _lava, village.huts, looks);
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
      beast: looks.beast,
    );
    _craneAt = craneAt;
  }

  /// The lava's grid: from x = 36 to the east edge, from the north edge
  /// past the cliff.
  static const double _lavaX0 = 32.0;
  static const int _lavaCells = 64;

  final GraphicsDevice _device;
  final Scene scene;

  /// Whether to draw less of the water and the fire, for a phone.
  final bool light;

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
  late final Trees trees;

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

  void _buildGround(HollowLooks looks) {
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
        // Along u, which runs with x: east, bent to lie in the slope. Its
        // fourth number turns the bitangent from −z to +z, the way v runs.
        final tangent = (Vector3(1.0, 0.0, 0.0) - normal * normal.x)
          ..normalize();
        final o = (i + j * n) * _stride;
        // What covers the ground is in the baked picture, which spans the
        // whole valley; the colour of the vertices only shades it, a few
        // per cent lighter or darker from one to the next, the same every
        // run.
        final tuft = (((i * 73856093) ^ (j * 19349663)) & 0xff) / 255.0;
        final shade = 0.95 + 0.1 * tuft;
        vertices
          ..[o] = x
          ..[o + 1] = h
          ..[o + 2] = z
          ..[o + 3] = normal.x
          ..[o + 4] = normal.y
          ..[o + 5] = normal.z
          ..[o + 6] = x / hollowSize
          ..[o + 7] = z / hollowSize
          ..[o + 8] = tangent.x
          ..[o + 9] = tangent.y
          ..[o + 10] = tangent.z
          ..[o + 11] = -1
          ..[o + 12] = shade
          ..[o + 13] = shade
          ..[o + 14] = shade
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
    // A picture seen from above has next to nothing to give a wall: the
    // cliff, the quarry's sides and the crater's lip would wear a few pixels
    // drawn out into streaks. Those faces are drawn apart, their rock laid
    // on from the side.
    Vector3 corner(int k) => Vector3(
      vertices[k * _stride],
      vertices[k * _stride + 1],
      vertices[k * _stride + 2],
    );
    // The volcano's own slopes, above the plateau it stands on: the cliff
    // under it is the plateau's rock, as the rest of the cliff is.
    bool volcanic(int t) {
      final a = corner(indices[t]);
      return a.y > _plateau &&
          Vector2(a.x - volcanoX, a.z - volcanoZ).length < volcanoRadius + 1.0;
    }

    // The cone's flanks keep the picture from above, which suits them; only
    // the crater's lip is steep enough to need the side.
    bool steep(int t) {
      final a = corner(indices[t]);
      final face = (corner(indices[t + 1]) - a).cross(
        corner(indices[t + 2]) - a,
      )..normalize();
      return face.y.abs() < (volcanic(t) ? _lip : _steep);
    }

    final walls = <int>[
      for (var t = 0; t < indices.length; t += 3)
        if (steep(t)) t,
    ];
    final level = <int>[
      for (var t = 0; t < indices.length; t += 3)
        if (!steep(t)) ...indices.sublist(t, t + 3),
    ];

    _addWalls(
      vertices,
      indices,
      <int>[
        for (final t in walls)
          if (!volcanic(t)) t,
      ],
      covered(
        'cliff',
        looks.granite,
        // As the bare rock is in the baked picture where the walls meet it.
        tint: Vector4(0.74, 0.72, 0.68, 1.0),
        repeat: Vector2.all(1.0 / 5.0),
        roughness: 0.95,
      ),
    );
    _addWalls(
      vertices,
      indices,
      <int>[
        for (final t in walls)
          if (volcanic(t)) t,
      ],
      covered(
        'crater',
        looks.basalt,
        tint: Vector4(0.85, 0.8, 0.75, 1.0),
        repeat: Vector2.all(1.0 / 6.0),
        roughness: 0.95,
      ),
    );
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          _device,
          MeshData(
            layout: VertexLayout.standard,
            vertices: vertices,
            indices: Uint32List.fromList(level),
          ),
        ),
        Material(
          name: 'ground',
          lighting: repeating,
          albedo: looks.ground,
          // The baked picture is three centimetres a pixel; the relief of
          // dry earth, repeating every two metres, is what the eye finds in
          // the ground under the car.
          normal: looks.groundRelief,
          normalScale: 0.8,
          roughness: 0.95,
          textureTransforms: <MaterialMap, TextureTransform>{
            MaterialMap.normal: TextureTransform(
              scale: Vector2.all(hollowSize / 2.0),
            ),
          },
        ),
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

  /// The triangles of the ground that start at each of [triangles] in
  /// [indices], drawn in [material] as a mesh of their own: each corner
  /// keeps its place and its normal, so the light runs on across the seam,
  /// but takes its picture from the side the face looks to, along x or
  /// along z, in metres, and upright.
  void _addWalls(
    Float32List ground,
    List<int> indices,
    List<int> triangles,
    Material material,
  ) {
    if (triangles.isEmpty) return;
    final vertices = Float32List(triangles.length * 3 * _stride);
    var o = 0;
    for (final t in triangles) {
      final k = <int>[for (var c = 0; c < 3; c++) indices[t + c] * _stride];
      final a = Vector3(ground[k[0]], ground[k[0] + 1], ground[k[0] + 2]);
      final face =
          (Vector3(ground[k[1]], ground[k[1] + 1], ground[k[1] + 2]) - a).cross(
            Vector3(ground[k[2]], ground[k[2] + 1], ground[k[2] + 2]) - a,
          );
      // Looking east or west, the picture runs along z; else along x.
      final alongZ = face.x.abs() > face.z.abs();
      for (final s in k) {
        for (var f = 0; f < _stride; f++) {
          vertices[o + f] = ground[s + f];
        }
        final x = ground[s], y = ground[s + 1], z = ground[s + 2];
        vertices
          ..[o + 6] = alongZ ? z : x
          ..[o + 7] = -y
          ..[o + 8] = alongZ ? 0.0 : 1.0
          ..[o + 9] = 0.0
          ..[o + 10] = alongZ ? 1.0 : 0.0
          ..[o + 11] = 1.0;
        o += _stride;
      }
    }
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          _device,
          MeshData(
            layout: VertexLayout.standard,
            vertices: vertices,
            indices: Uint32List.fromList(
              List<int>.generate(triangles.length * 3, (k) => k),
            ),
          ),
        ),
        material,
        name: material.name,
      ),
    );
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
    riverView.update(dt);
    lavaView.update(dt);
    fire.update(dt);
    hearing.update(dt);
    water.update(seconds: _clock, eye: eye);
    lava.update(seconds: _clock, eye: eye);
  }

  void dispose() => world.dispose();
}
