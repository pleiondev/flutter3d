/// The triangle tree, held to the answer a scan of every triangle gives.
///
/// **The only assertion worth making about an acceleration structure.** A tree
/// that is fast and wrong is worse than the scan it replaced, and every way of
/// being wrong here — a box that does not contain its triangles, a node whose
/// children were sorted after its bounds were taken, a slab test that rejects a
/// ray starting inside the box — shows up as a hit the scan finds and the tree
/// does not. So the scan is the oracle, over a mesh with enough shape to make
/// the split axis change from level to level.
library;

import 'dart:math';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// The nearest triangle [ray] hits, found by asking every one of them.
({int triangle, double distance})? scan(MeshData mesh, Ray ray) {
  final offset = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final stride = mesh.layout.floatsPerVertex;
  Vector3 vertexAt(int index) => Vector3(
    mesh.vertices[index * stride + offset],
    mesh.vertices[index * stride + offset + 1],
    mesh.vertices[index * stride + offset + 2],
  );

  var best = double.infinity;
  var found = -1;
  for (var triangle = 0; triangle * 3 < mesh.indices.length; triangle++) {
    final hit = rayTriangle(
      ray,
      vertexAt(mesh.indices[triangle * 3]),
      vertexAt(mesh.indices[triangle * 3 + 1]),
      vertexAt(mesh.indices[triangle * 3 + 2]),
    );
    if (hit >= 0 && hit < best) {
      best = hit;
      found = triangle;
    }
  }
  return found < 0 ? null : (triangle: found, distance: best);
}

void main() {
  final sphere = const SphereShape(radius: 1, segments: 48, rings: 24).build();
  final cube = CuboidShape().build();

  test('a ray down an axis hits the near face of a cube', () {
    final bvh = TriangleBvh.fromMesh(cube);
    final hit = bvh.raycast(Ray(Vector3(0, 0, 5), Vector3(0, 0, -1)));

    expect(hit, isNotNull);
    expect(hit!.distance, closeTo(4.5, 1e-5));
    expect(hit.point.z, closeTo(0.5, 1e-5));
  });

  test('a thousand rays agree with a scan of every triangle', () {
    final bvh = TriangleBvh.fromMesh(sphere);
    // Seeded, so a failure is the same failure on the machine it is reported
    // from.
    final random = Random(20260909);

    var hits = 0;
    for (var i = 0; i < 1000; i++) {
      // From a shell around the sphere, aimed at a point inside it, so most
      // rays hit and some miss down the side.
      final origin = Vector3(
        random.nextDouble() * 8 - 4,
        random.nextDouble() * 8 - 4,
        random.nextDouble() * 8 - 4,
      );
      final target = Vector3(
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
      );
      final ray = Ray(origin, (target - origin)..normalize());

      final byTree = bvh.raycast(ray);
      final byScan = scan(sphere, ray);

      if (byScan == null) {
        expect(byTree, isNull, reason: 'the tree found a hit nothing is at');
        continue;
      }
      hits++;
      expect(byTree, isNotNull, reason: 'the tree missed a triangle at $ray');
      expect(byTree!.distance, closeTo(byScan.distance, 1e-6));
    }
    // A test where nothing hit would pass every assertion above.
    expect(hits, greaterThan(500));
  });

  test('a ray that starts inside still finds what is in front of it', () {
    final bvh = TriangleBvh.fromMesh(sphere);
    final ray = Ray(Vector3.zero(), Vector3(0, 1, 0));

    final hit = bvh.raycast(ray);
    expect(hit, isNotNull);
    expect(hit!.distance, closeTo(1.0, 0.01));
  });

  test('maxDistance rejects what is further away', () {
    final bvh = TriangleBvh.fromMesh(cube);
    final ray = Ray(Vector3(0, 0, 5), Vector3(0, 0, -1));

    expect(bvh.raycast(ray, maxDistance: 4.0), isNull);
    expect(bvh.raycast(ray, maxDistance: 5.0), isNotNull);
  });

  test('refit follows vertices that moved, without a rebuild', () {
    final bvh = TriangleBvh.fromMesh(cube);
    final nodes = bvh.nodeCount;

    // Sideways, not along the ray. **The direction matters and the first
    // version of this test got it wrong:** moving the cube towards the camera
    // leaves the stale boxes still standing in the ray's path, so the walk
    // reaches the triangles anyway and passes whether `refit` ran or not. Three
    // units along x puts the cube where no old box is, which is the case only a
    // refitted tree can answer.
    for (var i = 0; i < bvh.positions.length; i += 3) {
      bvh.positions[i] += 3.0;
    }
    bvh.refit();

    expect(bvh.nodeCount, nodes, reason: 'a refit is not a rebuild');
    final hit = bvh.raycast(Ray(Vector3(3, 0, 5), Vector3(0, 0, -1)));
    // Mutation: skip the `refit` call and this is null — every box still
    // bounds the cube where it was, and the ray misses all of them.
    expect(hit, isNotNull);
    expect(hit!.distance, closeTo(4.5, 1e-5));
  });

  test('an empty mesh answers nothing rather than throwing', () {
    final empty = MeshBuilder(VertexLayout.standard).build();
    final bvh = TriangleBvh.fromMesh(empty);

    expect(bvh.raycast(Ray(Vector3.zero(), Vector3(0, 0, -1))), isNull);
    expect(
      collectInAabb(bvh, Aabb3.minMax(Vector3.all(-9), Vector3.all(9))),
      isEmpty,
    );
  });

  group('a box query', () {
    test('finds the same triangles a scan of every box finds', () {
      final mesh = const SphereShape(radius: 1, segments: 16, rings: 8).build();
      final bvh = TriangleBvh.fromMesh(mesh);
      // A corner of the sphere's own bounding box, so the answer is a real
      // subset rather than everything or nothing.
      final box = Aabb3.minMax(Vector3(0.2, 0.2, -2), Vector3(2, 2, 2));

      final found = collectInAabb(bvh, box);

      // Mutation: descend only where a node's box is *inside* the query rather
      // than overlapping it, and the tree answers with nothing at all — the
      // root is never inside a box smaller than the mesh.
      expect(found, scanInAabb(bvh, box));
      expect(found, isNotEmpty);
      expect(found.length, lessThan(bvh.indices.length ~/ 3));
    });

    test('a box that holds the whole mesh holds every triangle', () {
      final mesh = CuboidShape().build();
      final bvh = TriangleBvh.fromMesh(mesh);

      expect(
        collectInAabb(bvh, Aabb3.minMax(Vector3.all(-9), Vector3.all(9))),
        hasLength(12),
      );
      // And one beside it holds none.
      expect(
        collectInAabb(bvh, Aabb3.minMax(Vector3.all(8), Vector3.all(9))),
        isEmpty,
      );
    });
  });

  group('a frustum query', () {
    test('finds the same triangles a scan of every box finds', () {
      final mesh = const SphereShape(radius: 1, segments: 16, rings: 8).build();
      final bvh = TriangleBvh.fromMesh(mesh);
      // A slab of space: six planes, four of them cutting the sphere.
      final frustum = Frustum.matrix(
        makeOrthographicMatrix(0.1, 2, -2, 2, -2, 2),
      );

      final found = <int>[];
      bvh.forEachInFrustum(frustum, found.add);
      found.sort();

      final scanned = <int>[];
      final box = Aabb3();
      for (var t = 0; t * 3 < bvh.indices.length; t++) {
        if (frustum.intersectsWithAabb3(boxOfTriangle(bvh, t, box))) {
          scanned.add(t);
        }
      }

      // Mutation: test the node boxes and hand back every triangle of a leaf
      // that overlaps, and this comes back with triangles the scan rejects —
      // a rectangle selection then takes in faces beside the one clicked.
      expect(found, scanned);
      expect(found, isNotEmpty);
      expect(found.length, lessThan(bvh.indices.length ~/ 3));
    });
  });
}

/// The triangles the tree says are in [box].
List<int> collectInAabb(TriangleBvh bvh, Aabb3 box) {
  final found = <int>[];
  bvh.forEachInAabb(box, found.add);
  return found..sort();
}

/// The same question asked of every triangle in turn.
List<int> scanInAabb(TriangleBvh bvh, Aabb3 box) {
  final found = <int>[];
  final into = Aabb3();
  for (var triangle = 0; triangle * 3 < bvh.indices.length; triangle++) {
    final bounds = boxOfTriangle(bvh, triangle, into);
    if (bounds.min.x <= box.max.x &&
        bounds.max.x >= box.min.x &&
        bounds.min.y <= box.max.y &&
        bounds.max.y >= box.min.y &&
        bounds.min.z <= box.max.z &&
        bounds.max.z >= box.min.z) {
      found.add(triangle);
    }
  }
  return found;
}

/// The box round one triangle of [bvh].
Aabb3 boxOfTriangle(TriangleBvh bvh, int triangle, Aabb3 into) {
  final base = triangle * 3;
  Vector3 at(int corner) => Vector3(
    bvh.positions[bvh.indices[base + corner] * 3],
    bvh.positions[bvh.indices[base + corner] * 3 + 1],
    bvh.positions[bvh.indices[base + corner] * 3 + 2],
  );
  final a = at(0);
  final b = at(1);
  final c = at(2);
  into.min.setFrom(a);
  into.max.setFrom(a);
  Vector3.min(into.min, b, into.min);
  Vector3.max(into.max, b, into.max);
  Vector3.min(into.min, c, into.min);
  Vector3.max(into.max, c, into.max);
  return into;
}
