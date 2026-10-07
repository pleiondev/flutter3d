/// The sea past the part of it that is simulated: the floor going on from
/// the reef's edge and falling away into deep water, and the surface going
/// on to the horizon, so a diver at the edge sees open sea fading into
/// blue rather than the end of the world.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'terrain.dart';

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// How far out each ring of the far floor and the far surface lies past
/// the simulated square, m: close together at the edge, where the eye is
/// near, and kilometres apart where water hides everything anyway.
const List<double> _rings = <double>[
  0,
  2,
  5,
  10,
  18,
  30,
  50,
  85,
  140,
  240,
  420,
  800,
  1500,
];

/// How deep the open sea's floor lies far from the reef, m.
const double _farDepth = 34.0;

/// The points round the edge of the square from [lo] to [hi], every [step]
/// metres, and the way out from each: straight out from the middle, so the
/// rings never cross.
List<(Vector3, Vector3)> _edge(double lo, double hi, double step) {
  final middle = Vector3((lo + hi) / 2, 0, (lo + hi) / 2);
  final points = <Vector3>[];
  final n = ((hi - lo) / step).round();
  for (var k = 0; k < n; k++) {
    points.add(Vector3(lo + k * step, 0, lo));
  }
  for (var k = 0; k < n; k++) {
    points.add(Vector3(hi, 0, lo + k * step));
  }
  for (var k = 0; k < n; k++) {
    points.add(Vector3(hi - k * step, 0, hi));
  }
  for (var k = 0; k < n; k++) {
    points.add(Vector3(lo, 0, hi - k * step));
  }
  return <(Vector3, Vector3)>[
    for (final p in points)
      (
        p,
        (p - middle)
          ..y = 0
          ..normalize(),
      ),
  ];
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// A ring band mesh round the square: [heightAt] gives each vertex's
/// height from where the edge point it grew from is and how far out it is;
/// [paint] writes the rest of the vertex.
MeshData _bands(
  List<(Vector3, Vector3)> edge,
  double Function(Vector3 edgePoint, Vector3 at, double out) heightAt,
  void Function(Float32List v, int o, Vector3 at, double out) paint,
) {
  final m = edge.length, rings = _rings.length;
  final vertices = Float32List(m * rings * _stride);
  for (var r = 0; r < rings; r++) {
    for (var k = 0; k < m; k++) {
      final (p, out) = edge[k];
      final at = p + out * _rings[r];
      at.y = heightAt(p, at, _rings[r]);
      final o = (k + r * m) * _stride;
      vertices
        ..[o] = at.x
        ..[o + 1] = at.y
        ..[o + 2] = at.z
        ..[o + 8] = 1
        ..[o + 11] = 1;
      paint(vertices, o, at, _rings[r]);
    }
  }
  // Normals from the band's own slopes: along the ring and out across it.
  Vector3 vertex(int k, int r) {
    final o = ((k % m) + r * m) * _stride;
    return Vector3(vertices[o], vertices[o + 1], vertices[o + 2]);
  }

  for (var r = 0; r < rings; r++) {
    for (var k = 0; k < m; k++) {
      final along = vertex(k + 1, r) - vertex(k + m - 1, r);
      final across =
          vertex(k, math.min(r + 1, rings - 1)) - vertex(k, math.max(r - 1, 0));
      final normal = across.cross(along)..normalize();
      if (normal.y < 0) normal.negate();
      final o = (k + r * m) * _stride;
      vertices
        ..[o + 3] = normal.x
        ..[o + 4] = normal.y
        ..[o + 5] = normal.z;
    }
  }
  final indices = <int>[
    for (var r = 0; r < rings - 1; r++)
      for (var k = 0; k < m; k++) ...<int>[
        k + r * m,
        (k + 1) % m + r * m,
        k + (r + 1) * m,
        (k + 1) % m + r * m,
        (k + 1) % m + (r + 1) * m,
        k + (r + 1) * m,
      ],
  ];
  return MeshData(
    layout: VertexLayout.standard,
    vertices: vertices,
    indices: Uint32List.fromList(indices),
  );
}

/// The far floor and the far surface, added to [scene]: the floor in
/// [floor]'s material, going on from the drawn reef's own edge and sinking
/// to the open sea's depth over a few hundred metres; the surface in
/// [surface]'s, level and as deep as the floor under it is.
void addHorizon(
  GraphicsDevice device,
  Scene scene, {
  required Material floor,
  required Material surface,
}) {
  // The drawn floor's outermost vertices stand at its cells' middles.
  final floorEdge = _edge(
    0.5 * floorCell,
    reefSize - 0.5 * floorCell,
    floorCell,
  );
  double floorHeight(Vector3 p, Vector3 at, double out) {
    final start = drawnFloorAt(p.x, p.z);
    // A slow swell in the far floor, so the deep is not one flat bowl.
    final swell = 2.5 * math.sin(at.x * 0.021 + 1.3) * math.cos(at.z * 0.017);
    return start + (-_farDepth + swell - start) * _smooth(4, 320, out);
  }

  final floorData = _bands(floorEdge, floorHeight, (v, o, at, out) {
    v
      ..[o + 6] = at.z / 3
      ..[o + 7] = at.x / 3
      ..[o + 12] = 1
      ..[o + 13] = 1
      ..[o + 14] = 1
      ..[o + 15] = 1;
  });
  scene.add(
    MeshNode(DeviceMesh.upload(device, floorData), floor, name: 'far floor'),
  );

  // The simulated surface's outermost vertices stand at its cells' middles.
  final seaEdge = _edge(0.5 * seaCell, reefSize - 0.5 * seaCell, seaCell);
  final seaData = _bands(seaEdge, (p, at, out) => 0.0, (v, o, at, out) {
    final under = floorHeight(
      Vector3(
        at.x.clamp(0.5 * floorCell, reefSize - 0.5 * floorCell),
        0,
        at.z.clamp(0.5 * floorCell, reefSize - 0.5 * floorCell),
      ),
      at,
      out,
    );
    v
      // The look reads its first texture coordinate as the depth.
      ..[o + 6] = math.max(-under, 0.5)
      ..[o + 7] = 0
      // Still water, no froth: the flow's two halves at a half, no air.
      ..[o + 12] = 0.5
      ..[o + 13] = 0.5
      ..[o + 14] = 0
      ..[o + 15] = 1;
  });
  scene.add(
    MeshNode(DeviceMesh.upload(device, seaData), surface, name: 'far sea'),
  );
}
