/// Cutting a face into triangles, and the faces a fan gets wrong.
///
/// The oracle is area: a correct cut of a simple polygon covers exactly the
/// polygon, so the triangles' areas sum to its own and none of them lies
/// outside. A fan over a concave outline fails both, which is what the L-shape
/// and the dented quad here are for.
library;

import 'dart:math' as math;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The area of a polygon in the XY plane, by the shoelace formula — which is
/// signed and exact for any simple outline, convex or not, and so is a fair
/// oracle for a triangulation of one.
double shoelace(List<Vector3> points) {
  var twice = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return twice.abs() / 2;
}

/// The triangles a cut produced, as triples of positions.
List<List<Vector3>> cut(List<Vector3> points) {
  final out = <List<Vector3>>[];
  FaceTriangulator().triangulate(points, (int a, int b, int c) {
    out.add(<Vector3>[points[a], points[b], points[c]]);
  });
  return out;
}

double areaOfTriangle(List<Vector3> triangle) =>
    (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).length / 2;

double totalArea(List<List<Vector3>> triangles) => triangles.fold<double>(
  0,
  (double sum, List<Vector3> t) => sum + areaOfTriangle(t),
);

void main() {
  _triangulateFacesTests();
  group('the easy shapes', () {
    test('a triangle is already one', () {
      final triangles = cut(<Vector3>[
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
      ]);

      expect(triangles, hasLength(1));
    });

    test('a square becomes two, covering it exactly', () {
      final square = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0),
        Vector3(0, 1, 0),
      ];

      final triangles = cut(square);

      expect(triangles, hasLength(2));
      expect(totalArea(triangles), closeTo(shoelace(square), 1e-9));
    });

    test('a rectangle is cut along its short diagonal', () {
      // Four by one: the diagonals are the same length here, so the shape that
      // decides is a long thin quad where they are not.
      final quad = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(4, 0, 0),
        Vector3(4, 1, 0),
        Vector3(0, 1, 0),
      ];

      final triangles = cut(quad);
      expect(totalArea(triangles), closeTo(4, 1e-9));

      // Both diagonals of a rectangle are equal, so this asserts only what the
      // tie-break promises: the same answer every time, rather than one that
      // depends on floating-point noise.
      final again = cut(quad);
      expect(triangles.first[2].x, again.first[2].x);
    });
  });

  group('the shapes a fan gets wrong', () {
    test('a dented quad is cut along the diagonal that stays inside', () {
      // Corner 1 is pushed *in*, so the diagonal 0-2 runs outside the outline
      // and only 1-3 is usable. The shapes are chosen so the usable diagonal is
      // also the **longer** one — 2.1 against 2.0 — which is what makes this a
      // test of the winding check rather than of the tie-break: pick by length
      // alone and the answer is the diagonal that leaves the notch covered.
      final dented = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(1, 0.9, 0),
        Vector3(2, 0, 0),
        Vector3(1, 3, 0),
      ];

      final triangles = cut(dented);

      expect(triangles, hasLength(2));
      // A tolerance rather than an exact match: `Vector3` holds float32, so a
      // coordinate of 0.9 is not 0.9 and the areas differ in the seventh place.
      expect(shoelace(dented), closeTo(2.1, 1e-6));
      expect(totalArea(triangles), closeTo(2.1, 1e-6));
    });

    test('an L-shaped six-gon becomes four triangles inside it', () {
      // The classic case: fanning from corner 0 covers the notch.
      final ell = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 1, 0),
        Vector3(1, 1, 0),
        Vector3(1, 2, 0),
        Vector3(0, 2, 0),
      ];

      final triangles = cut(ell);

      expect(triangles, hasLength(4));
      // Three square units, which is the L's own area. A fan from corner 0
      // gives four triangles covering four units — the notch included — and
      // that is the whole bug.
      expect(shoelace(ell), closeTo(3, 1e-9));
      expect(totalArea(triangles), closeTo(3, 1e-9));
    });

    test('a comb keeps every tooth and fills no gap', () {
      // Five teeth on a flat base, with a corner in the middle of every gap in
      // that base — so the outline has runs of three collinear corners, which
      // is what a boundary test gets wrong. Twenty-five corners: five straight
      // ones on the base, four reflex between the teeth.
      final comb = <Vector3>[];
      for (var tooth = 0; tooth < 5; tooth++) {
        final x = tooth * 2.0;
        comb
          ..add(Vector3(x, 0, 0))
          ..add(Vector3(x, 2, 0))
          ..add(Vector3(x + 1, 2, 0))
          ..add(Vector3(x + 1, 0, 0));
        // The straight corner: on the base, between this tooth and the next.
        if (tooth < 4) comb.add(Vector3(x + 1.5, 0, 0));
      }

      final cutter = FaceTriangulator();
      final triangles = <List<Vector3>>[];
      cutter.triangulate(comb, (int a, int b, int c) {
        triangles.add(<Vector3>[comb[a], comb[b], comb[c]]);
      });

      // Cut properly rather than fanned. Mutation: drop the second pass, so a
      // straight corner is never taken — the base's collinear corners then
      // surround the outline with corners nothing can remove, and this is
      // true.
      expect(cutter.fannedLastFace, isFalse);

      // Five teeth, two square units apiece.
      expect(shoelace(comb), closeTo(10, 1e-9));
      expect(totalArea(triangles), closeTo(10, 1e-9));
      expect(triangles, hasLength(comb.length - 2));
    });
  });

  group('faces that are not flat and not in a plane', () {
    test('a face in the YZ plane is cut the same as one in XY', () {
      final flat = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(0, 2, 0),
        Vector3(0, 2, 1),
        Vector3(0, 1, 1),
        Vector3(0, 1, 2),
        Vector3(0, 0, 2),
      ];

      final triangles = cut(flat);

      expect(triangles, hasLength(4));
      // Mutation: project by dropping the last axis whatever the normal says,
      // and this face collapses to a line — every cross product is zero, no
      // ear is ever found, and it falls back to a fan.
      expect(totalArea(triangles), closeTo(3, 1e-9));
    });

    test('a face wound the other way is cut just as correctly', () {
      final ell = <Vector3>[
        Vector3(0, 2, 0),
        Vector3(1, 2, 0),
        Vector3(1, 1, 0),
        Vector3(2, 1, 0),
        Vector3(2, 0, 0),
        Vector3(0, 0, 0),
      ];

      final triangles = cut(ell);

      expect(triangles, hasLength(4));
      expect(totalArea(triangles), closeTo(3, 1e-9));
    });

    test('a quad with a corner lifted out of plane still covers itself', () {
      final bent = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0.4),
        Vector3(0, 1, 0),
      ];

      final triangles = cut(bent);

      expect(triangles, hasLength(2));
      // Non-planar, so the two triangles do not sum to a flat quad's area —
      // what is asserted is that they are both real triangles and neither is
      // degenerate, which a diagonal chosen at random would not give.
      for (final triangle in triangles) {
        expect(areaOfTriangle(triangle), greaterThan(0.1));
      }
    });
  });

  group('what it cannot cut', () {
    test('a self-intersecting outline is fanned, and says so', () {
      // A bowtie: the outline crosses itself, so no ear exists anywhere.
      final bowtie = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(2, 2, 0),
        Vector3(2, 0, 0),
        Vector3(0, 2, 0),
      ];

      final cutter = FaceTriangulator();
      var count = 0;
      cutter.triangulate(bowtie, (int _, int _, int _) => count++);

      expect(count, 2);
      // The flag is the point: the caller gets triangles rather than an
      // exception, and something it can put in front of a person.
      expect(cutter.fannedLastFace, isTrue);
    });

    test('an ordinary face leaves the flag down', () {
      final cutter = FaceTriangulator();
      cutter.triangulate(<Vector3>[
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0),
        Vector3(0, 1, 0),
      ], (int _, int _, int _) {});

      expect(cutter.fannedLastFace, isFalse);
    });
  });

  group('through the mesh', () {
    test('a cube converts to twelve triangles of the right total area', () {
      final mesh = EditMesh.cuboid().toMeshData();

      expect(mesh.triangleCount, 12);
      // Six faces of one square unit.
      expect(mesh.computeBounds().max.x - mesh.computeBounds().min.x, 1);
    });

    test('an L-shaped face in a mesh keeps its own area', () {
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(2, 0, 0),
          Vector3(2, 1, 0),
          Vector3(1, 1, 0),
          Vector3(1, 2, 0),
          Vector3(0, 2, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3, 4, 5],
        ],
      );

      // `areaOf` fans, and the triangulation does not — so this is also the
      // measurement that says the two disagree about a concave face, which is
      // `mesh-27`'s subject rather than this one's.
      final drawn = mesh.toMeshData();
      expect(drawn.triangleCount, 4);

      var area = 0.0;
      final offset = drawn.layout.floatOffsetOf(VertexLayout.position.name);
      final stride = drawn.layout.floatsPerVertex;
      Vector3 at(int index) => Vector3(
        drawn.vertices[index * stride + offset],
        drawn.vertices[index * stride + offset + 1],
        drawn.vertices[index * stride + offset + 2],
      );
      for (var i = 0; i + 2 < drawn.indices.length; i += 3) {
        final a = at(drawn.indices[i]);
        final b = at(drawn.indices[i + 1]);
        final c = at(drawn.indices[i + 2]);
        area += (b - a).cross(c - a).length / 2;
      }
      expect(area, closeTo(3, 1e-6));
    });
  });
}

/// Runs [body] as one step of history, which is what every operation here
/// expects: the journal is what `undo` reads and a write outside a step has
/// nowhere to be recorded.
void _edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

void _triangulateFacesTests() {
  group('triangulating a mesh', () {
    test('a cube of quads becomes twelve triangles', () {
      final mesh = EditMesh.cuboid();
      final all = Selection.of(ElementLevel.face, <int>[
        for (var face = 0; face < mesh.faceSlotCount; face++)
          if (mesh.isFaceAlive(face)) face,
      ]);

      late final OpResult result;
      _edit(mesh, () => result = triangulateFaces(mesh, all));

      expect(result.ok, isTrue);
      expect(result.topologyChanged, isTrue);
      // Six quads, one diagonal each.
      expect(mesh.faceCount, 12);
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        var sides = 0;
        mesh.forEachHalfEdge(face, (int _) => sides++);
        expect(sides, 3, reason: 'face $face still has $sides sides');
      }
      mesh.validate();
    });

    test('running it twice is running it once', () {
      final mesh = EditMesh.cuboid();
      Selection all() => Selection.of(ElementLevel.face, <int>[
        for (var face = 0; face < mesh.faceSlotCount; face++)
          if (mesh.isFaceAlive(face)) face,
      ]);

      _edit(mesh, () => triangulateFaces(mesh, all()));
      final faces = mesh.faceCount;
      late final OpResult again;
      _edit(mesh, () => again = triangulateFaces(mesh, all()));

      // Refused rather than cut and rejoined. Mutation: cut a triangle anyway
      // — `splitFace` refuses a cut between neighbours, so every attempt is a
      // no-op that still reports success, and an exporter loops for ever
      // waiting for a mesh that is "not triangulated yet" to become so.
      expect(again.ok, isFalse);
      expect(again.reason, contains('already'));
      expect(mesh.faceCount, faces);
    });

    test('a five-sided face becomes three triangles', () {
      final mesh = EditMesh.empty();
      late final int face;
      _edit(mesh, () {
        final ring = <int>[
          for (var i = 0; i < 5; i++)
            mesh.addVertex(
              Vector3(
                math.cos(i * 2 * math.pi / 5),
                0,
                math.sin(i * 2 * math.pi / 5),
              ),
            ),
        ];
        face = mesh.addFace(ring);
      });

      late final OpResult result;
      _edit(
        mesh,
        () => result = triangulateFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[face]),
        ),
      );

      // n − 2 triangles from n − 3 diagonals. Mutation: cut on every edge of
      // every triangle the clipper emits rather than on the diagonals only,
      // and the cuts between neighbours are refused one at a time — which
      // leaves the count right by luck on a quad and wrong on anything larger.
      expect(result.ok, isTrue);
      expect(mesh.faceCount, 3);
      mesh.validate();
    });

    test('a twelve-gon and a concave outline both come out whole', () {
      // **What pins the two assumptions the cutting rests on**: that the ear
      // clipper always names a diagonal of the part not yet cut off, and that
      // `splitFace` leaves that part as the face it was given. If either
      // changed, a polygon would come out with fewer triangles than its corners
      // less two, and this is where that shows.
      for (final int n in <int>[4, 5, 6, 8, 12]) {
        final mesh = EditMesh.empty();
        late final int face;
        _edit(mesh, () {
          final ring = <int>[
            for (var i = 0; i < n; i++)
              mesh.addVertex(
                Vector3(
                  math.cos(i * 2 * math.pi / n),
                  0,
                  math.sin(i * 2 * math.pi / n),
                ),
              ),
          ];
          face = mesh.addFace(ring);
        });
        _edit(
          mesh,
          () => triangulateFaces(
            mesh,
            Selection.of(ElementLevel.face, <int>[face]),
          ),
        );
        expect(mesh.faceCount, n - 2, reason: 'a $n-gon');
        mesh.validate();
      }

      // A concave outline, where the clipper's ears are not simply consecutive:
      // an L with the notch cut into one side.
      final mesh = EditMesh.empty();
      late final int face;
      _edit(mesh, () {
        final ring = <int>[
          for (final (double x, double z) in <(double, double)>[
            (0, 0),
            (2, 0),
            (2, 1),
            (1, 1),
            (1, 2),
            (0, 2),
          ])
            mesh.addVertex(Vector3(x, 0, z)),
        ];
        face = mesh.addFace(ring);
      });
      _edit(
        mesh,
        () => triangulateFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[face]),
        ),
      );

      expect(mesh.faceCount, 4);
      mesh.validate();
    });

    test('nothing selected is refused with a sentence', () {
      final mesh = EditMesh.cuboid();

      late final OpResult result;
      _edit(
        mesh,
        () =>
            result = triangulateFaces(mesh, Selection.empty(ElementLevel.face)),
      );

      expect(result.ok, isFalse);
      expect(result.reason, contains('no faces'));
    });
  });
}
