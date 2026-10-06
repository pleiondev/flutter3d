/// The valley's world and what is drawn of it: the ground, the water over
/// it, the spray off the cliff and what is thrown in.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'fire.dart';
import 'valley.dart';

/// A quarter of a cubic metre a second out of the spring: a stream big
/// enough to fall as a curtain.
const double springRate = 0.25;

/// A stone or a log thrown in, and the node that draws it.
final class _Thrown {
  _Thrown(this.body, this.node);

  final NativeBody body;
  final MeshNode node;
}

/// The valley, stepped and drawn.
final class WaterRun {
  WaterRun(this._device, this.scene, this.look, Renderer renderer) {
    _ground = valleyGround();
    // The ground as the stones meet it: one fixed mesh body.
    final floor = _world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    _world.setMesh(
      floor,
      _world.createMesh(<Vector3>[
        for (var j = 0; j < valleyCells; j++)
          for (var i = 0; i < valleyCells; i++)
            Vector3(
              (i + 0.5) * valleyCell,
              _ground[i + j * valleyCells],
              (j + 0.5) * valleyCell,
            ),
      ], _triangles((_, _) => true)),
    );
    // The water over it: the pond already at its lip, the stream dry until
    // the spring fills it.
    water = _world.createWater(
      nx: valleyCells,
      nz: valleyCells,
      cell: valleyCell,
      origin: Vector3.zero(),
      ground: _ground,
    );
    _world
      ..setWaterBed(water, roughness: 0.035, openEdges: true)
      ..fillWater(
        water,
        x0: pondX - pondRadius,
        z0: cliffFoot,
        x1: pondX + pondRadius,
        z1: pondZ + pondRadius,
        level: 0.05,
      )
      ..setWaterSource(
        water,
        0,
        x: springX,
        z: springZ,
        radius: 0.6,
        rate: springRate,
      );
    _build();
    waterView = WaterView(
      world: _world,
      water: water,
      ground: _ground,
      device: _device,
      scene: scene,
      look: look.material,
    );
    fireView = FireView(
      world: _world,
      device: _device,
      scene: scene,
      renderer: renderer,
      baseWidth: 0.3,
    );
    bonfire = Bonfire(_world, _device, scene, fireView);
  }

  final GraphicsDevice _device;
  final Scene scene;

  /// The water's material: its clock and how rough the wind makes it are
  /// set here every frame.
  final WaterLook look;
  final NativeWorld _world = NativeWorld();
  late final NativeWater water;
  late final List<double> _ground;

  /// The water and the fires, drawn.
  late final WaterView waterView;
  late final FireView fireView;
  double _clock = 0.0;
  late final DeviceMesh _stoneMesh, _logMesh;
  final List<_Thrown> _thrown = <_Thrown>[];
  final math.Random _scatter = math.Random(7);

  /// The fire laid on the bank.
  late final Bonfire bonfire;

  /// Whether the wind blows down the valley.
  bool windy = false;

  /// What the water holds and what has run off the map, for the panel.
  ({double held, double lost}) get volume => _world.waterVolume(water);

  /// How many pieces of falling water are in the air, and how many clouds
  /// of bubbles are in the water.
  int get sprayInFlight => waterView.sprayInFlight;
  int get bubbleClouds => waterView.bubbleClouds;

  /// The pond's surface above the valley's origin, m.
  double get pondLevel =>
      _world.sampleWater(water, pondX, pondZ)?.surface ?? 0.0;

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
        final colour =
            Vector3(0.16, 0.30, 0.09) * grass +
            Vector3(0.33, 0.31, 0.29) * rock +
            Vector3(0.48, 0.42, 0.30) * sand;
        _write(
          ground,
          c,
          Vector3((i + 0.5) * valleyCell, h, (j + 0.5) * valleyCell),
          normal,
          Vector4(colour.x, colour.y, colour.z, 1.0),
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
        Material(name: 'ground', roughness: 0.95),
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
    Vector4 colour, {
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
    v[o + 12] = colour.x;
    v[o + 13] = colour.y;
    v[o + 14] = colour.z;
    v[o + 15] = colour.w;
  }

  /// Where the ray from [origin] along [direction] first meets the ground
  /// or the water, or null when it misses the valley.
  Vector3? hit(Vector3 origin, Vector3 direction) {
    final d = direction.normalized();
    for (var t = 0.0; t < 120.0; t += 0.05) {
      final p = origin + d * t;
      if (p.x < 0 || p.z < 0 || p.x > valleySize || p.z > valleySize) continue;
      final ground = groundAt(p.x, p.z);
      final surface = _world.sampleWater(water, p.x, p.z)?.surface ?? ground;
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
    final body = _world.addBody(
      position: Vector3(x, y, z),
      mass: 2600.0 * 0.6 * 0.4 * 0.5,
    );
    _world
      ..setShape(body, NativeShape.box(Vector3(0.24, 0.14, 0.19)))
      ..setRounding(body, 0.06);
    final node = MeshNode(
      _stoneMesh,
      Material(
        name: 'stone',
        baseColor: Vector4(0.35, 0.33, 0.31, 1.0),
        roughness: 0.8,
      ),
      name: 'stone',
    );
    scene.add(node);
    _thrown.add(_Thrown(body, node));
  }

  /// A log put in the stream near the spring, to ride it over the falls.
  void dropLog() {
    final z = 3.0 + _scatter.nextDouble() * 2.0;
    final body = _world.addBody(
      position: Vector3(streamX(z), 7.5, z),
      mass: 55.0,
    );
    _world.setShape(body, NativeShape.box(Vector3(0.7, 0.15, 0.15)));
    final node = MeshNode(
      _logMesh,
      Material(
        name: 'log',
        baseColor: Vector4(0.42, 0.28, 0.16, 1.0),
        roughness: 0.85,
      ),
      name: 'log',
    );
    scene.add(node);
    _thrown.add(_Thrown(body, node));
  }

  /// Where the eye is, for the ripples that fade with distance.
  final Vector3 eye = Vector3.zero();

  /// One frame: the world on by [dt], and what is drawn of it brought up to
  /// date.
  void step(double dt) {
    final wind = windy ? Vector3(0.0, 0.0, 6.0) : Vector3.zero();
    _world
      ..wind = wind
      ..step(dt);
    bonfire.step();
    fireView.update(dt);
    waterView.update();
    _clock += dt;
    look
      ..update(seconds: _clock, eye: eye)
      ..chop = windy ? 1.6 : 1.0;
    for (final t in _thrown) {
      final p = _world.positionOf(t.body);
      final q = _world.orientationOf(t.body);
      t.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(q);
    }
  }

  void dispose() => _world.dispose();
}
