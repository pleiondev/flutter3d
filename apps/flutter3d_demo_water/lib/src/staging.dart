/// The valley's world and what is drawn of it: the ground, the water over
/// it, the spray off the cliff and what is thrown in.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'valley.dart';

/// A quarter of a cubic metre a second out of the spring: a stream big
/// enough to fall as a curtain.
const double springRate = 0.25;

/// The most pieces of a falling sheet drawn as ribbon at once, the most
/// drops, and the most clouds of bubbles.
const int drawnSheet = 4000;
const int drawnDrops = 3000;
const int drawnBubbles = 3000;

/// A stone or a log thrown in, and the node that draws it.
final class _Thrown {
  _Thrown(this.body, this.node);

  final NativeBody body;
  final MeshNode node;
}

/// The valley, stepped and drawn.
final class WaterRun {
  WaterRun(this._device, this.scene, this.look) {
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
  }

  final GraphicsDevice _device;
  final Scene scene;

  /// The water's material, `assets_src/water.f3dmat`: its clock and how
  /// rough the wind makes it are set here every frame.
  final Material look;
  final NativeWorld _world = NativeWorld();
  late final NativeWater water;
  late final List<double> _ground;

  /// The water's surface, one vertex a cell.
  late final DeviceMesh _surface;
  late final MeshNode _surfaceNode;
  double _clock = 0.0;
  late final DeviceMesh _sheet;
  late final MeshNode _sheetNode;
  late final InstancedMeshNode _drops, _bubbles;
  late final DeviceMesh _stoneMesh, _logMesh;
  final List<_Thrown> _thrown = <_Thrown>[];
  final math.Random _scatter = math.Random(7);

  /// Whether the wind blows down the valley.
  bool windy = false;

  /// What the water holds and what has run off the map, for the panel.
  ({double held, double lost}) get volume => _world.waterVolume(water);

  /// How many pieces of falling water are in the air, and how many clouds
  /// of bubbles are in the water.
  int sprayInFlight = 0;
  int bubbleClouds = 0;

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
    // The water: its surface written again every frame in place, and
    // drawn by its own material from what each vertex says of it.
    _surface = DeviceMesh.upload(
      _device,
      MeshData(
        layout: VertexLayout.standard,
        vertices: _waterVertices(Float32List(0)),
        indices: Uint32List.fromList(_triangles((_, _) => true)),
      ),
    );
    // Water lets most of the sun through, and a shadow map knows only
    // through or not: none of the water, falling or lying, casts a shadow.
    // A solid shadow of the sheet on the cliff behind it was a dark band.
    _surfaceNode = MeshNode(_surface, look, name: 'water')
      ..castsShadow = false;
    scene.add(_surfaceNode);
    // The falls: the sheet as ribbons, one a face of the lip, through the
    // pieces it threw in the order it threw them; white where it is thick,
    // thinning to clear as continuity thins it. Each quad has its own four
    // vertices, so a frame joins whichever pieces it has.
    _sheet = DeviceMesh.upload(
      _device,
      MeshData(
        layout: VertexLayout.standard,
        vertices: Float32List(drawnSheet * 4 * _stride),
        indices: Uint32List.fromList(<int>[
          for (var q = 0; q < drawnSheet; q++) ...<int>[
            q * 4,
            q * 4 + 1,
            q * 4 + 2,
            q * 4 + 2,
            q * 4 + 1,
            q * 4 + 3,
          ],
        ]),
      ),
    );
    _sheetNode = MeshNode(
      _sheet,
      Material(
        name: 'falls',
        baseColor: Vector4(0.88, 0.93, 1.0, 1.0),
        emissive: Vector3(0.55, 0.60, 0.65),
        roughness: 0.3,
        alphaMode: MaterialAlphaMode.blend,
        doubleSided: true,
      ),
      name: 'falls',
    );
    // What the sheet broke into and what splashed up: small bright drops.
    _drops = InstancedMeshNode(
      DeviceMesh.upload(
        _device,
        const SphereShape(radius: 1.0, segments: 6, rings: 4).build(),
      ),
      Material(
        name: 'drops',
        baseColor: Vector4(0.92, 0.96, 1.0, 0.6),
        emissive: Vector3(0.6, 0.65, 0.7),
        alphaMode: MaterialAlphaMode.blend,
      ),
      capacity: drawnDrops,
      name: 'drops',
    );
    // The bubbles the falls drag down, each cloud drawn as one bead —
    // millimetre bubbles drawn at a size an eye picks out.
    _bubbles = InstancedMeshNode(
      DeviceMesh.upload(
        _device,
        const SphereShape(radius: 0.03, segments: 6, rings: 4).build(),
      ),
      Material(
        name: 'bubbles',
        baseColor: Vector4(0.95, 0.98, 1.0, 0.55),
        emissive: Vector3(0.5, 0.55, 0.6),
        alphaMode: MaterialAlphaMode.blend,
      ),
      capacity: drawnBubbles,
      name: 'bubbles',
    );
    for (final node in <MeshNode>[_sheetNode, _drops, _bubbles]) {
      node.castsShadow = false;
    }
    scene
      ..add(_sheetNode)
      ..add(_drops)
      ..add(_bubbles);
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

  /// How much of each column is air, of the bubbles the falls drove into
  /// it, spread over the column's neighbours as a cloud spreads.
  Float64List _airIn(Float32List bubbles, List<double> depth) {
    final air = Float64List(valleyCells * valleyCells);
    for (var o = 0; o < bubbles.length; o += nativeBubbleFloats) {
      final i = (bubbles[o] / valleyCell).floor();
      final j = (bubbles[o + 2] / valleyCell).floor();
      for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
          final (x, z) = (i + di, j + dj);
          if (x < 0 || z < 0 || x >= valleyCells || z >= valleyCells) continue;
          air[x + z * valleyCells] += bubbles[o + 4] / 9.0;
        }
      }
    }
    for (var c = 0; c < air.length; c++) {
      air[c] = depth[c] > 0.004
          ? air[c] / (depth[c] * valleyCell * valleyCell)
          : 0.0;
    }
    return air;
  }

  /// The water's vertices as it stands now, written for its material: the
  /// flow at each in red and green as 0.5 + velocity / 8, the froth in
  /// blue — water is white where it is a few parts in a hundred air,
  /// however fast it runs — and the depth as the first texture coordinate.
  /// Where it is dry the vertex sinks under the ground and is not seen.
  Float32List _waterVertices(Float32List bubbles) {
    final read = _world.readWaterSurface(water);
    final flow = _world.readWaterFlow(water);
    final v = Float32List(valleyCells * valleyCells * _stride);
    final surface = read.surface;
    final air = _airIn(bubbles, read.depth);
    for (var j = 0; j < valleyCells; j++) {
      for (var i = 0; i < valleyCells; i++) {
        final c = i + j * valleyCells;
        final wet = read.depth[c] > 0.004;
        _write(
          v,
          c,
          Vector3(
            (i + 0.5) * valleyCell,
            wet ? surface[c] : _ground[c] - 0.05,
            (j + 0.5) * valleyCell,
          ),
          _normal(surface, i, j),
          Vector4(
            (0.5 + flow[2 * c] / 8.0).clamp(0.0, 1.0),
            (0.5 + flow[2 * c + 1] / 8.0).clamp(0.0, 1.0),
            (air[c] / 0.03).clamp(0.0, 1.0),
            1.0,
          ),
          uv: (read.depth[c], 0.0),
        );
      }
    }
    return v;
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

  final Matrix4 _m = Matrix4.identity();

  /// One frame: the world on by [dt], and what is drawn of it brought up to
  /// date.
  void step(double dt) {
    _world
      ..wind = windy ? Vector3(0.0, 0.0, 6.0) : Vector3.zero()
      ..step(dt);
    final bubbles = _world.readBubbles();
    final vertices = _waterVertices(bubbles).buffer.asByteData();
    _surface.overwriteVertices(_device, 0, vertices);
    _surfaceNode.markBoundsDirty();
    _clock += dt;
    look.parameters['time']![0] = _clock;
    look.parameters['chop']![0] = windy ? 2.0 : 1.0;
    _drawSpray(bubbles);
    for (final t in _thrown) {
      final p = _world.positionOf(t.body);
      final q = _world.orientationOf(t.body);
      t.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(q);
    }
  }

  void _drawSpray(Float32List bubbles) {
    final spray = _world.readSpray(capacity: drawnSheet + drawnDrops);
    sprayInFlight = spray.length ~/ nativeSprayFloats;
    // The drops: what the sheet broke into and what splashed up.
    var drops = 0;
    for (var k = 0; k < sprayInFlight; k++) {
      final o = k * nativeSprayFloats;
      if (spray[o + 9] != nativeSpraySheet && drops < drawnDrops) {
        final d = math.max(spray[o + 7], 0.012);
        _m
          ..setIdentity()
          ..setTranslationRaw(spray[o], spray[o + 1], spray[o + 2])
          ..scaleByDouble(d, d, d, 1.0);
        _drops.setTransform(drops++, _m);
      }
    }
    _drops.count = drops;
    // The sheet is one sheet: what the lip's faces threw in one step is a
    // row across it, and rows follow each other in the order they were
    // thrown. A row starts again where a face's number does not rise, the
    // order the core throws them in. Neighbouring faces of a row are sewn
    // together, and the sheet's two edges stand half a face out.
    final rows = <Map<int, int>>[];
    var last = -1;
    for (var k = 0; k < sprayInFlight; k++) {
      final o = k * nativeSprayFloats;
      if (spray[o + 9] != nativeSpraySheet) continue;
      final face = spray[o + 10].round();
      if (face <= last || rows.isEmpty) rows.add(<int, int>{});
      rows.last[face] = o;
      last = face;
    }
    // The core reuses the slots of what has landed, so the rows do not come
    // out oldest last. A sheet only falls, so how high a row is says how
    // long ago it left the lip: highest first is newest first.
    double height(Map<int, int> row) =>
        row.values.fold(0.0, (sum, o) => sum + spray[o + 1]) / row.length;
    rows.sort((a, b) => height(b).compareTo(height(a)));
    final v = Float32List(drawnSheet * 4 * _stride);
    var quads = 0;
    final up = Vector3(0.0, 1.0, 0.0);
    Vector3 point(int o, double side) {
      final vel = Vector3(spray[o + 3], spray[o + 4], spray[o + 5]);
      final across = vel.cross(up);
      if (across.length2 < 1e-9) across.setValues(1.0, 0.0, 0.0);
      across.normalize();
      return Vector3(spray[o], spray[o + 1], spray[o + 2]) +
          across * (side * spray[o + 7]);
    }

    // Faces side by side on a lip: z faces one apart, x faces a row apart.
    bool beside(int a, int b) => b - a == 1 || b - a == valleyCells + 1;
    void quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, double alpha) {
      if (quads >= drawnSheet) return;
      final normal = (b - a).cross(c - a);
      if (normal.length2 < 1e-12) return;
      normal.normalize();
      final colour = Vector4(1.0, 1.0, 1.0, alpha);
      _write(v, quads * 4, a, normal, colour);
      _write(v, quads * 4 + 1, b, normal, colour);
      _write(v, quads * 4 + 2, c, normal, colour);
      _write(v, quads * 4 + 3, d, normal, colour);
      quads++;
    }

    // Thick water is white; a few millimetres shows through.
    double alphaOf(int o) => (spray[o + 8] / 0.01).clamp(0.25, 0.9);
    for (var r = 0; r + 1 < rows.length; r++) {
      final now = rows[r], next = rows[r + 1];
      final faces = now.keys.where(next.containsKey).toList()..sort();
      for (var i = 0; i < faces.length; i++) {
        final f = faces[i];
        final a = now[f]!, b = next[f]!;
        // Two rows a step apart are a step's fall apart, never a metre.
        final dx = spray[b] - spray[a], dy = spray[b + 1] - spray[a + 1];
        final dz = spray[b + 2] - spray[a + 2];
        if (dx * dx + dy * dy + dz * dz > 1.0) continue;
        final alpha = alphaOf(a);
        final left = i == 0 || !beside(faces[i - 1], f);
        final right = i == faces.length - 1 || !beside(f, faces[i + 1]);
        if (left) {
          quad(
            point(a, -0.5),
            point(a, 0.0),
            point(b, -0.5),
            point(b, 0.0),
            alpha,
          );
        }
        if (right) {
          quad(
            point(a, 0.0),
            point(a, 0.5),
            point(b, 0.0),
            point(b, 0.5),
            alpha,
          );
        }
        if (!right) {
          final g = faces[i + 1];
          // Neighbours on the lip that have drifted a metre apart have torn.
          final dx = spray[now[g]!] - spray[a];
          final dz = spray[now[g]! + 2] - spray[a + 2];
          final dy = spray[now[g]! + 1] - spray[a + 1];
          if (dx * dx + dy * dy + dz * dz > 1.0) continue;
          quad(
            point(a, 0.0),
            point(now[g]!, 0.0),
            point(b, 0.0),
            point(next[g]!, 0.0),
            alpha,
          );
        }
      }
    }
    _sheet.overwriteVertices(_device, 0, v.buffer.asByteData());
    _sheetNode.markBoundsDirty();
    bubbleClouds = bubbles.length ~/ nativeBubbleFloats;
    for (var k = 0; k < math.min(bubbleClouds, drawnBubbles); k++) {
      final o = k * nativeBubbleFloats;
      _m
        ..setIdentity()
        ..setTranslationRaw(bubbles[o], bubbles[o + 1], bubbles[o + 2]);
      _bubbles.setTransform(k, _m);
    }
    _bubbles.count = math.min(bubbleClouds, drawnBubbles);
  }

  void dispose() => _world.dispose();
}
