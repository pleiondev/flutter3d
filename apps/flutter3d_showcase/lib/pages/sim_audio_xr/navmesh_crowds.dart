/// A navigation mesh baked from a small level: a route round a wall pulled
/// tight by the funnel, a jump up onto a ledge the walk cannot reach, the
/// wall broken and only its tiles baked again, and a crowd crossing a
/// circle without touching.
///
/// Quoted by `navmesh_crowds.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Bodies on an open floor stepped by velocity alone, each wanting to walk
/// straight to the far side of the circle it starts on.
final class _Crowd {
  _Crowd(this.count, this.centerX, this.circle) {
    for (var i = 0; i < count; i++) {
      final double a = i * 2.0 * math.pi / count;
      x.add(centerX + circle * math.cos(a));
      z.add(circle * math.sin(a));
      goalX.add(centerX - circle * math.cos(a));
      goalZ.add(-circle * math.sin(a));
    }
  }

  final int count;
  final double centerX, circle;
  final List<double> x = <double>[], z = <double>[];
  final List<double> goalX = <double>[], goalZ = <double>[];
  late final List<double> vx = List<double>.filled(count, 0.0);
  late final List<double> vz = List<double>.filled(count, 0.0);

  static const double radius = 0.35;
  static const double speed = 1.5;
  static const Avoidance _avoidance = Avoidance();

  // #region avoid
  /// One step: every body asks ORCA for the velocity nearest the one it
  /// wants that meets no neighbour within the horizon, all from where they
  /// all were, and only then do they all move.
  void step(double dt) {
    final List<(double, double)> picked = <(double, double)>[
      for (var i = 0; i < count; i++)
        _avoidance.velocity(
          x: x[i],
          z: z[i],
          vx: vx[i],
          vz: vz[i],
          radius: radius,
          maxSpeed: speed,
          prefX: _wish(goalX[i] - x[i], goalZ[i] - z[i]).$1,
          prefZ: _wish(goalX[i] - x[i], goalZ[i] - z[i]).$2,
          neighbors: <AvoidanceNeighbor>[
            for (var j = 0; j < count; j++)
              if (j != i)
                (x: x[j], z: z[j], vx: vx[j], vz: vz[j], radius: radius),
          ],
          dt: dt,
        ),
    ];
    for (final (int i, (double px, double pz)) in picked.indexed) {
      vx[i] = px;
      vz[i] = pz;
      x[i] += px * dt;
      z[i] += pz * dt;
    }
  }
  // #endregion avoid

  /// Straight at the goal, at walking speed, slowing on the last metre.
  static (double, double) _wish(double dx, double dz) {
    final double d = math.sqrt(dx * dx + dz * dz);
    if (d <= speed) return (dx, dz);
    return (dx * speed / d, dz * speed / d);
  }

  /// The nearest any two came, centre to centre.
  double closest() {
    var least = double.infinity;
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final double dx = x[i] - x[j], dz = z[i] - z[j];
        least = math.min(least, math.sqrt(dx * dx + dz * dz));
      }
    }
    return least;
  }
}

final class NavmeshCrowdsDemo extends ShowcaseDemo {
  late NavMesh _mesh;
  late final NavMesh _jumpMesh;
  late NavMeshRoute _route;
  late final NavMeshRoute _jump;
  late _Crowd _crowd;
  late final Scene _scene;
  late final MeshNode _door;
  Renderer? _renderer;

  final List<MeshNode> _people = <MeshNode>[];
  late final MeshNode _walker;

  bool broken = false;
  bool showMesh = true;
  double _along = 0.0;
  double _crowdAge = 0.0;

  static Vector3 get _start => Vector3(-10.0, 0.0, 0.0);
  static Vector3 get _goal => Vector3(-2.0, 0.0, 0.0);
  static Vector3 get _below => Vector3(-9.0, 0.0, 1.5);
  static Vector3 get _onLedge => Vector3(-9.0, 0.9, 5.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 22.0
      ..pitch = 0.85
      ..yaw = 0.0;
    context.orbit.target.setValues(-1.0, 0.0, 0.0);
  }

  // #region level
  /// A floor, a wall across the left half with a middle piece that can be
  /// broken, and a ledge 0.9 m up: higher than a step, lower than a jump.
  static List<Brush> _brushes({required bool broken}) => <Brush>[
    Brush(center: Vector3(0.0, -0.5, 0.0), size: Vector3(24.0, 1.0, 12.0)),
    Brush(center: Vector3(-6.0, 1.5, -2.5), size: Vector3(0.6, 3.0, 3.0)),
    if (!broken)
      Brush(center: Vector3(-6.0, 1.5, 0.0), size: Vector3(0.6, 3.0, 2.0)),
    Brush(center: Vector3(-6.0, 1.5, 2.5), size: Vector3(0.6, 3.0, 3.0)),
    Brush(center: Vector3(-9.0, 0.45, 4.5), size: Vector3(4.0, 0.9, 3.0)),
  ];
  // #endregion level

  // #region bake
  /// Quarter-metre cells in tiles of sixteen. A tiled mesh keeps its
  /// outlines within half a cell, which is what lets a tile be baked again
  /// on its own and still meet its neighbours.
  static const NavMeshSettings _config = NavMeshSettings(
    cellSize: 0.25,
    tileSize: 16,
    maxEdgeError: 0.4,
  );

  static NavMesh _bake({required bool broken}) =>
      NavMesh.bake(_brushes(broken: broken), config: _config);
  // #endregion bake

  // #region jumps
  /// A body that leaves the ground at 5 m/s reaches 1.27 m up, under the
  /// Earth's gravity: the page has no world of its own to ask. Baked with
  /// that reach, the mesh keeps links where a gap, a ledge or a drop can be
  /// jumped, and a route given the same reach may take them.
  static const JumpReach _reach = JumpReach(
    jumpSpeed: 5.0,
    gravity: standardGravity,
    runSpeed: 4.0,
  );

  static NavMesh _bakeWithJumps() => NavMesh.bake(
    _brushes(broken: false),
    config: const NavMeshSettings(cellSize: 0.25),
    jumps: _reach,
  );
  // #endregion jumps

  // #region route
  /// A* over the polygons, then the funnel through the edges they share:
  /// a list of corners a body walks straight between.
  NavMeshRoute _routeAcross() => _mesh.route(_start, _goal)!;
  // #endregion route

  @override
  Scene build(DemoContext context) {
    _mesh = _bake(broken: false);
    _jumpMesh = _bakeWithJumps();
    _route = _routeAcross();
    _jump = _jumpMesh.route(_below, _onLedge, jumps: _reach)!;
    _crowd = _Crowd(8, 6.0, 4.0);

    MeshNode box(Brush b, Vector4 color, String name) => MeshNode(
      DeviceMesh.upload(context.device, CuboidShape(size: b.size).build()),
      RenderMaterial(name: name, baseColor: _fromSrgb(color)),
      name: name,
    )..setPosition(b.center.x, b.center.y, b.center.z);

    _scene = Scene()
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.8, -0.4)),
      );
    final List<Brush> brushes = _brushes(broken: false);
    for (final (int i, Brush b) in brushes.indexed) {
      final MeshNode node = box(
        b,
        i == 0 ? Vector4(0.36, 0.38, 0.42, 1.0) : Vector4(0.62, 0.58, 0.5, 1.0),
        'brush $i',
      );
      _scene.add(node);
      if (i == 2) _door = node;
    }
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 12).build(),
    );
    _walker = MeshNode(
      ball,
      RenderMaterial(
        name: 'walker',
        baseColor: LinearColor.fromSrgb(0.95, 0.8, 0.2, 1.0),
      ),
      name: 'walker',
    )..setScale(0.35, 0.35, 0.35);
    _scene.add(_walker);
    for (var i = 0; i < _crowd.count; i++) {
      final MeshNode person = MeshNode(
        ball,
        RenderMaterial(
          name: 'person $i',
          baseColor: LinearColor.fromSrgb(
            0.3 + 0.6 * (i % 2),
            0.4 + 0.07 * i,
            0.9 - 0.08 * i,
            1.0,
          ),
        ),
        name: 'person $i',
      )..setScale(_Crowd.radius, _Crowd.radius, _Crowd.radius);
      _people.add(person);
      _scene.add(person);
    }
    _renderer = context.renderer..debugLines = _draw;
    _place();
    return _scene;
  }

  @override
  void dispose() {
    _renderer?.debugLines = null;
  }

  // #region hole
  /// The middle of the wall goes. Only the tiles its box reaches, widened by
  /// the body's erosion, are baked again; the polygons are cut again from
  /// every outline, and the mesh is the one a whole bake would give.
  void _breakWall() {
    _mesh = _mesh.rebake(
      _brushes(broken: true),
      minX: -6.3,
      minZ: -1.0,
      maxX: -5.7,
      maxZ: 1.0,
    );
    _route = _routeAcross();
  }
  // #endregion hole

  void _mendWall() {
    _mesh = _bake(broken: false);
    _route = _routeAcross();
  }

  void _draw(DebugDraw lines) {
    final Vector3 a = Vector3.zero(), b = Vector3.zero();
    if (showMesh) {
      final LinearColor edge = LinearColor.fromSrgb(0.3, 0.85, 0.5);
      for (var p = 0; p < _mesh.polygonCount; p++) {
        final int n = _mesh.polygonVertexCount(p);
        for (var k = 0; k < n; k++) {
          _mesh.vertexAt(_mesh.polygonVertex(p, k), a);
          _mesh.vertexAt(_mesh.polygonVertex(p, (k + 1) % n), b);
          lines.addLine(
            a + Vector3(0.0, 0.03, 0.0),
            b + Vector3(0.0, 0.03, 0.0),
            edge,
          );
        }
      }
    }
    final Vector3 lift = Vector3(0.0, 0.1, 0.0);
    final List<Vector3> path = _route.points;
    for (var i = 0; i + 1 < path.length; i++) {
      lines.addLine(
        path[i] + lift,
        path[i + 1] + lift,
        LinearColor.fromSrgb(1, 0.85, 0.2),
      );
    }
    final List<Vector3> hop = _jump.points;
    for (var i = 0; i + 1 < hop.length; i++) {
      lines.addLine(
        hop[i] + lift,
        hop[i + 1] + lift,
        _jump.jumps.contains(i)
            ? LinearColor.fromSrgb(1.0, 0.35, 0.2)
            : LinearColor.fromSrgb(1.0, 0.6, 0.3),
      );
    }
  }

  /// Where along [_route] the walker is after [distance] metres.
  Vector3 _pointAlong(double distance) {
    var left = distance;
    final List<Vector3> p = _route.points;
    for (var i = 0; i + 1 < p.length; i++) {
      final double leg = p[i].distanceTo(p[i + 1]);
      if (left <= leg) {
        return p[i] + (p[i + 1] - p[i]) * (leg == 0.0 ? 0.0 : left / leg);
      }
      left -= leg;
    }
    return p.last.clone();
  }

  void _place() {
    final Vector3 at = _pointAlong(_along);
    _walker.setPosition(at.x, at.y + 0.35, at.z);
    for (var i = 0; i < _crowd.count; i++) {
      _people[i].setPosition(_crowd.x[i], _Crowd.radius, _crowd.z[i]);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    final double step = math.min(dt, 1 / 30);
    _along += 2.0 * step;
    if (_along > _route.length + 1.0) _along = 0.0;
    _crowd.step(step);
    _crowdAge += step;
    if (_crowdAge > 12.0) {
      _crowd = _Crowd(8, 6.0, 4.0);
      _crowdAge = 0.0;
    }
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Break the wall (rebake its tiles)',
      value: () => broken,
      onChanged: (bool v) {
        broken = v;
        if (v) {
          _breakWall();
          _scene.remove(_door);
        } else {
          _mendWall();
          _scene.add(_door);
        }
        _along = 0.0;
      },
    ),
    ToggleControl(
      'Show the polygons',
      value: () => showMesh,
      onChanged: (bool v) => showMesh = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1 || frame.debugLines < 1) {
      throw StateError('the level or its mesh did not reach the frame');
    }
    // #region check
    // Round the wall: complete, bending past its end, longer than straight.
    final NavMeshRoute round = _bake(broken: false).route(_start, _goal)!;
    if (!round.complete ||
        !round.points.any((Vector3 p) => p.z.abs() > 4.0) ||
        round.length <= _start.distanceTo(_goal) + 1.0) {
      throw StateError('the route does not go round the wall');
    }
    // A hole baked tile by tile is the hole baked whole, and walked through.
    final NavMesh mended = _bake(broken: false);
    final NavMesh holed = mended.rebake(
      _brushes(broken: true),
      minX: -6.3,
      minZ: -1.0,
      maxX: -5.7,
      maxZ: 1.0,
    );
    final NavMesh whole = NavMesh.bake(
      _brushes(broken: true),
      config: _config,
      lattice: mended.lattice,
    );
    if (holed.digest != whole.digest) {
      throw StateError('the rebaked tiles differ from a whole bake');
    }
    if (holed.route(_start, _goal)!.points.length != 2) {
      throw StateError('the route does not take the hole');
    }
    // The ledge is reached by a jump, and not at all on foot.
    if (_jump.jumps.isEmpty || !_jump.complete) {
      throw StateError('no jump onto the ledge');
    }
    if (_jumpMesh.route(_below, _onLedge)!.complete) {
      throw StateError('the ledge should not be walked onto');
    }
    // Eight bodies crossing for ten seconds never come closer than two
    // radii, give or take a centimetre.
    final _Crowd crowd = _Crowd(8, 6.0, 4.0);
    var least = double.infinity;
    for (var i = 0; i < 600; i++) {
      crowd.step(1 / 60);
      least = math.min(least, crowd.closest());
    }
    if (least < 2.0 * _Crowd.radius - 0.01) {
      throw StateError('two of the crowd overlapped: $least m apart');
    }
    // #endregion check
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
