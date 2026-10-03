import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The volume a closed mesh encloses: the divergence theorem, tetrahedra
/// from the origin to every face.
double _enclosed(MeshData mesh) {
  final v = mesh.vertices;
  final f = mesh.layout.floatsPerVertex;
  Vector3 at(int i) => Vector3(v[i * f], v[i * f + 1], v[i * f + 2]);
  var six = 0.0;
  for (var t = 0; t < mesh.indices.length; t += 3) {
    final a = at(mesh.indices[t]);
    final b = at(mesh.indices[t + 1]);
    final c = at(mesh.indices[t + 2]);
    six += a.dot(b.cross(c));
  }
  return six / 6;
}

LiquidBody _body(VesselShape shape, double volume, {Matrix3? turn}) {
  final body = LiquidBody(
    shape: shape,
    medium: FluidMedium.water,
    volume: volume,
    modes: 2,
  );
  body
    ..place(turn ?? Matrix3.identity(), Vector3.zero())
    ..step(1e-4, gravity: Vector3(0, -9.81, 0))
    ..surface.calm();
  return body;
}

MeshVessel _box(Vector3 size) {
  final x = size.x, y = size.y, z = size.z;
  final p = <Vector3>[
    for (final yy in [0.0, y])
      for (final (xx, zz) in [(0.0, 0.0), (x, 0.0), (x, z), (0.0, z)])
        Vector3(xx, yy, zz),
  ];
  const quads = <List<int>>[
    [0, 1, 2, 3],
    [4, 7, 6, 5],
    [0, 4, 5, 1],
    [1, 5, 6, 2],
    [2, 6, 7, 3],
    [3, 7, 4, 0],
  ];
  return MeshVessel(
    positions: p,
    indices: [
      for (final q in quads) ...[q[0], q[1], q[2], q[0], q[2], q[3]],
    ],
    rim: [p[4], p[5], p[6], p[7]],
  );
}

void main() {
  final tube = RevolvedVessel([
    Vector2(0, 0),
    Vector2(0.008, 0),
    Vector2(0.008, 0.1),
  ]);

  test('the liquid drawn holds the volume it has, upright and tipped', () {
    // Mutation: lift only the cap by the surface and not the wall's edge,
    // and the meniscus opens a gap the volume leaks through.
    for (final tilt in [0.0, 0.5, 1.2]) {
      final volume = math.pi * 0.008 * 0.008 * 0.04;
      final body = _body(tube, volume, turn: Matrix3.rotationX(tilt));
      final meshes = liquidMeshes(body);
      expect(meshes, hasLength(1));
      expect(
        _enclosed(meshes.single.mesh),
        closeTo(volume, volume * 0.02),
        reason: 'tilt $tilt',
      );
    }
  });

  test('so does liquid in a vessel that is any mesh', () {
    final box = _box(Vector3(0.04, 0.05, 0.03));
    final body = _body(box, 2e-5, turn: Matrix3.rotationZ(0.4));
    expect(
      _enclosed(liquidMeshes(body).single.mesh),
      closeTo(2e-5, 2e-5 * 0.01),
    );
  });

  test('oil on water is two meshes, each its own volume', () {
    final body = _body(tube, 8e-6)..pour(4e-6, medium: FluidMedium.oil);
    body
      ..place(Matrix3.identity(), Vector3.zero())
      ..step(1e-4, gravity: Vector3(0, -9.81, 0))
      ..surface.calm();
    final meshes = liquidMeshes(body);
    expect(meshes.map((m) => m.layer.medium.name), ['water', 'oil']);
    expect(_enclosed(meshes[0].mesh), closeTo(8e-6, 8e-6 * 0.02));
    expect(_enclosed(meshes[1].mesh), closeTo(4e-6, 4e-6 * 0.02));
  });

  test('a stream and particles draw what is there', () {
    final jet = Jet(medium: FluidMedium.water, breakupGrowth: 1e9);
    for (var i = 0; i < 20; i++) {
      jet
        ..emit(
          flow: 1e-6,
          dt: 1e-3,
          point: Vector3.zero(),
          velocity: Vector3(0.2, 0, 0),
          width: 1e-3,
          across: Vector3(0, 0, 1),
        )
        ..step(1e-3, gravity: Vector3(0, -9.81, 0));
    }
    expect(jetMesh(jet).triangleCount, greaterThan(0));
    final dots = particleMesh([Vector3.zero(), Vector3(1, 0, 0)], 0.001);
    // Two spheres of forty-two points.
    expect(dots.vertexCount, 84);
    expect(_enclosed(dots), greaterThan(0));
  });

  test('a puddle is drawn as a cap of its radius and height', () {
    final cap = capMesh([Vector3(0.1, 0, 0)], [0.02], [0.001]);
    final ys = [for (var i = 0; i < cap.vertexCount; i++) cap.positionAt(i).y];
    // Its top as high as asked, its rim on the bench.
    expect(ys.reduce(math.max), closeTo(0.001, 1e-7));
    expect(ys.reduce(math.min), closeTo(0.0, 1e-7));
    var widest = 0.0;
    for (var i = 0; i < cap.vertexCount; i++) {
      final p = cap.positionAt(i);
      widest = math.max(widest, math.sqrt(math.pow(p.x - 0.1, 2) + p.z * p.z));
    }
    expect(widest, closeTo(0.02, 1e-7));
  });

  test('a tipped tube keeps its liquid inside its glass, meniscus and all', () {
    // Mutation: lift the surface along up with the meniscus of the radius,
    // as for a tube standing, and the long sides of a tipped tube's liquid
    // stand out through the glass.
    final tube = RevolvedVessel([
      for (var i = 0; i <= 8; i++)
        Vector2(
          0.0075 * math.sin(i / 8 * math.pi / 2),
          0.0005 + 0.0075 * (1 - math.cos(i / 8 * math.pi / 2)),
        ),
      Vector2(0.0075, 0.09),
    ]);
    final body = _body(tube, 6e-6, turn: Matrix3.rotationX(1.2));
    for (final layer in liquidMeshes(body)) {
      final mesh = layer.mesh;
      final stride = mesh.layout.floatsPerVertex;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final p = Vector3(
          mesh.vertices[i * stride],
          mesh.vertices[i * stride + 1],
          mesh.vertices[i * stride + 2],
        );
        final at = tube.wallDistance(p);
        if (at != null) expect(at.distance, lessThan(2e-5), reason: '$p');
      }
    }
  });
}
