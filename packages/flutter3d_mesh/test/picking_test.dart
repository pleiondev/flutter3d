/// Finding what a ray meets, and turning that into what somebody meant.
///
/// The oracle for the tree is the scan it replaces: ten thousand rays at a
/// sphere have to give the same face every time, because every way a tree can
/// be wrong — a box that does not contain its triangles, a refit that was not
/// run, a triangle mapped to the wrong face — shows up as a ray the scan hits
/// and the tree does not.
library;

import 'dart:math' as math;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// A mesh, its plan and a tree over it, which is what a viewport holds.
({EditMesh mesh, MeshLayoutPlan plan, MeshBvh bvh, MeshPicker picker}) staged(
  EditMesh mesh,
) {
  final plan = MeshLayoutPlan()..build(mesh);
  final bvh = MeshBvh(mesh, plan);
  return (mesh: mesh, plan: plan, bvh: bvh, picker: MeshPicker(mesh, bvh));
}

/// The nearest face [ray] hits, found by asking every triangle of the plan.
int scanForFace(EditMesh mesh, MeshLayoutPlan plan, Ray ray) {
  final at = Vector3.zero();
  Vector3 corner(int row) =>
      mesh.positionOf(plan.gpuVertexToVertex[row], at).clone();

  var best = double.infinity;
  var found = EditMesh.none;
  for (var triangle = 0; triangle < plan.triangleCount; triangle++) {
    final hit = rayTriangle(
      ray,
      corner(plan.indices[triangle * 3]),
      corner(plan.indices[triangle * 3 + 1]),
      corner(plan.indices[triangle * 3 + 2]),
    );
    if (hit >= 0 && hit < best) {
      best = hit;
      found = plan.triangleToFace[triangle];
    }
  }
  return found;
}

void main() {
  group('the tree over a mesh', () {
    test('a ray at the top of a box finds the top of the box', () {
      final it = staged(EditMesh.cuboid());

      final hit = it.bvh.raycast(Ray(Vector3(0, 0, 5), Vector3(0, 0, -1)))!;

      // Face 0 is the +Z quad, cut into two triangles — and what comes back is
      // the face. Mutation: hand back the triangle number, and a person
      // clicking a quad selects half of it.
      expect(hit.face, 0);
      expect(hit.distance, closeTo(4.5, 1e-5));
      expect(hit.point.z, closeTo(0.5, 1e-5));
    });

    test('ten thousand rays agree with a scan of every triangle', () {
      final (mesh, _) = importMeshData(
        const SphereShape(radius: 1, segments: 16, rings: 8).build(),
      );
      final it = staged(mesh);
      final random = math.Random(1234);

      var hits = 0;
      for (var i = 0; i < 10000; i++) {
        final from = Vector3(
          random.nextDouble() * 6 - 3,
          random.nextDouble() * 6 - 3,
          random.nextDouble() * 6 - 3,
        );
        final towards = Vector3(
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
        );
        final ray = Ray(from, (towards - from)..normalize());
        final tree = it.bvh.raycast(ray)?.face ?? EditMesh.none;
        if (tree != EditMesh.none) hits++;
        expect(tree, scanForFace(mesh, it.plan, ray), reason: 'ray $i');
      }
      // And enough of them hit for the agreement to mean something.
      expect(hits, greaterThan(2000));
    });

    test('a refit follows the vertices and keeps the tree', () {
      final it = staged(EditMesh.cuboid());
      final ray = Ray(Vector3(3, 0, 5), Vector3(0, 0, -1));
      expect(it.bvh.raycast(ray), isNull);

      edit(it.mesh, () {
        translateSelection(
          it.mesh,
          Selection.of(ElementLevel.vertex, <int>[
            for (var v = 0; v < it.mesh.vertexSlotCount; v++) v,
          ]),
          by: Vector3(3, 0, 0),
        );
      });
      it.bvh.refit(it.mesh);

      // Mutation: leave the tree alone after a drag, and every box still bounds
      // the box where it was — the ray misses a mesh it goes straight through.
      final hit = it.bvh.raycast(ray);
      expect(hit, isNotNull);
      expect(hit!.face, 0);
      expect(hit.distance, closeTo(4.5, 1e-5));
    });

    test('a rebuild is what an extrusion needs', () {
      final it = staged(EditMesh.cuboid());
      expect(it.bvh.triangleCount, 12);

      edit(it.mesh, () {
        extrudeFaces(
          it.mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 1,
        );
      });
      // A refit alone cannot see faces that did not exist when the tree was
      // built, which is exactly what `OpResult.topologyChanged` is there to
      // say — so the plan is rebuilt and the tree with it.
      it.plan.build(it.mesh);
      it.bvh.rebuild(it.mesh, it.plan);

      expect(it.bvh.triangleCount, 20);
      final hit = it.bvh.raycast(Ray(Vector3(0, 0, 5), Vector3(0, 0, -1)))!;
      expect(hit.face, 0);
      expect(hit.distance, closeTo(3.5, 1e-5));
    });

    test('a box and a frustum answer in faces', () {
      final it = staged(EditMesh.cuboid());

      final whole = it.bvh.facesInAabb(
        Aabb3.minMax(Vector3.all(-9), Vector3.all(9)),
      );
      expect(whole.length, 6);
      expect(whole.level, ElementLevel.face);

      // A corner of the box, which four of its six faces reach into.
      final corner = it.bvh.facesInAabb(
        Aabb3.minMax(Vector3(0.4, 0.4, 0.4), Vector3(9, 9, 9)),
      );
      expect(corner.length, 3);

      // A box round the whole cube takes all six.
      expect(
        it.bvh
            .facesInFrustum(
              Frustum.matrix(makeOrthographicMatrix(-9, 9, -9, 9, -9, 9)),
            )
            .length,
        6,
      );
      // One that stops just short of the top face takes five: the other five
      // straddle the cut, and being conservative is what the tree promises.
      expect(
        it.bvh
            .facesInFrustum(
              Frustum.matrix(makeOrthographicMatrix(-9, 9, -9, 9, 0.01, 18)),
            )
            .length,
        5,
      );
    });
  });

  group('picking a face', () {
    test('a click in the middle of a face selects that face', () {
      final it = staged(EditMesh.cuboid());

      expect(it.picker.faceAt(Ray(Vector3(0, 0, 5), Vector3(0, 0, -1))), 0);
      expect(it.picker.faceAt(Ray(Vector3(5, 0, 0), Vector3(-1, 0, 0))), 2);
      // And a click past the model selects nothing rather than the nearest
      // thing to where it landed.
      expect(
        it.picker.faceAt(Ray(Vector3(9, 9, 5), Vector3(0, 0, -1))),
        EditMesh.none,
      );
    });

    test('a maximum distance stops the ray short', () {
      final it = staged(EditMesh.cuboid());

      expect(
        it.picker.faceAt(
          Ray(Vector3(0, 0, 5), Vector3(0, 0, -1)),
          maxDistance: 1,
        ),
        EditMesh.none,
      );
    });
  });

  group('picking a vertex', () {
    test('the nearest corner within the radius, and none outside it', () {
      final it = staged(EditMesh.cuboid());
      // Aimed at the corner (0.5, 0.5, 0.5), which is vertex 6.
      final ray = Ray(Vector3(0.5, 0.5, 5), Vector3(0, 0, -1));

      expect(it.picker.vertexNear(ray, radius: 0.1), 6);
      // Aimed a quarter of a unit off it, with a radius too small to reach.
      expect(
        it.picker.vertexNear(
          Ray(Vector3(0.25, 0.5, 5), Vector3(0, 0, -1)),
          radius: 0.1,
        ),
        EditMesh.none,
      );
    });

    test('the one in front, not the one closest to the line', () {
      final it = staged(EditMesh.cuboid());
      // Down the corner of the box: vertex 6 at z = 0.5 and vertex 2 at
      // z = −0.5 are both on the line.
      final ray = Ray(Vector3(0.5, 0.5, 5), Vector3(0, 0, -1));

      // Mutation: order by distance to the line rather than along it, and the
      // two are tied — so which of them a click selects depends on the order
      // the arrays happen to hold them in.
      expect(it.picker.vertexNear(ray, radius: 0.1), 6);
    });

    test('with visibleOnly, what the surface hides is not offered', () {
      // A wall with a vertex behind it, and the wall's own corners far enough
      // out that nothing but the hidden one is within reach of the line.
      final it = staged(
        EditMesh.fromFaces(
          <Vector3>[
            Vector3(-3, -3, 1),
            Vector3(3, -3, 1),
            Vector3(3, 3, 1),
            Vector3(-3, 3, 1),
            Vector3(0, 0, -1),
            Vector3(1, 0, -1),
            Vector3(0, 1, -1),
          ],
          <List<int>>[
            <int>[0, 1, 2, 3],
            <int>[4, 5, 6],
          ],
        ),
      );
      final ray = Ray(Vector3(0, 0, 5), Vector3(0, 0, -1));

      // Looking through: the vertex behind the wall is the only one near the
      // line, and a person box-selecting through a model means to reach it.
      expect(it.picker.vertexNear(ray, radius: 0.5), 4);

      // Mutation: ignore `visibleOnly`, and a click on the front of a model
      // grabs a vertex on the far side of it that nobody can see.
      expect(
        it.picker.vertexNear(ray, radius: 0.5, visibleOnly: true),
        EditMesh.none,
      );
    });
  });

  group('picking an edge', () {
    test('the edge the ray runs nearest to', () {
      final it = staged(EditMesh.cuboid());
      // Aimed at the middle of the edge between (0.5, −0.5, 0.5) and
      // (0.5, 0.5, 0.5), which runs up the right of the top face.
      final found = it.picker.edgeNear(
        Ray(Vector3(0.5, 0, 5), Vector3(0, 0, -1)),
        radius: 0.1,
      );

      expect(found, isNot(EditMesh.none));
      final from = it.mesh.positionOf(it.mesh.originOf(found));
      final to = it.mesh.positionOf(it.mesh.originOf(it.mesh.nextOf(found)));
      // Mutation: measure to the nearer end of the segment rather than to the
      // segment, and an edge pointed at across its middle is never the nearest
      // one — a click halfway along an edge picks whatever is at a corner.
      expect(from.x, closeTo(0.5, 1e-6));
      expect(to.x, closeTo(0.5, 1e-6));
      expect(from.z, closeTo(0.5, 1e-6));
      expect(to.z, closeTo(0.5, 1e-6));
    });

    test('nothing within the radius is nothing', () {
      final it = staged(EditMesh.cuboid());

      expect(
        it.picker.edgeNear(
          Ray(Vector3(0, 0, 5), Vector3(0, 0, -1)),
          radius: 0.1,
        ),
        EditMesh.none,
      );
    });
  });

  group('a rectangle drag', () {
    test('a box round half a cube takes four corners', () {
      final it = staged(EditMesh.cuboid());
      // Everything from z = −1 to z = 0: the four corners of the −Z face.
      final frustum = Frustum.matrix(
        makeOrthographicMatrix(-2, 2, -2, 2, 0.01, 1),
      );

      final corners = it.picker.inFrustum(frustum, ElementLevel.vertex);
      expect(corners.ids, <int>[0, 1, 2, 3]);

      // At face level it is the one face all of whose corners are in — not the
      // four that reach into the box with one corner each. Mutation: take
      // every face touching a selected vertex, and a rectangle drag round one
      // side of a model selects five.
      expect(it.picker.inFrustum(frustum, ElementLevel.face).ids, <int>[1]);
      expect(it.picker.inFrustum(frustum, ElementLevel.edge).length, 4);
    });

    test('a box round nothing takes nothing', () {
      final it = staged(EditMesh.cuboid());

      expect(
        it.picker
            .inFrustum(
              Frustum.matrix(makeOrthographicMatrix(-2, 2, -2, 2, 9, 18)),
              ElementLevel.vertex,
            )
            .isEmpty,
        isTrue,
      );
    });
  });
}
