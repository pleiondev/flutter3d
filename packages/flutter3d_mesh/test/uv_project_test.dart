/// `projectUv` — `pro-uv-03`'s own worked example, a cube's six faces
/// projected without stretch.
///
///     dart test test/uv_project_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The UV-space length of the edge from [half] to its own next corner.
double _uvEdgeLength(EditMesh mesh, int half) =>
    (mesh.uvOf(mesh.nextOf(half)) - mesh.uvOf(half)).length;

/// The world-space length of the same edge, for a caller that wants to
/// compare the two rather than assume a hard-coded number.
double _worldEdgeLength(EditMesh mesh, int half) => (mesh.positionOf(
  mesh.originOf(mesh.nextOf(half)),
)..sub(mesh.positionOf(mesh.originOf(half)))).length;

/// The signed area a face's own UVs enclose, by the shoelace formula —
/// negative would mean the projection folded the face over itself, which a
/// stretch metric alone would not catch.
double _uvArea(EditMesh mesh, int face) {
  var area = 0.0;
  mesh.forEachHalfEdge(face, (int half) {
    final a = mesh.uvOf(half);
    final b = mesh.uvOf(mesh.nextOf(half));
    area += a.x * b.y - b.x * a.y;
  });
  return area / 2;
}

/// `projectUv` is an operation, not a command — `operations.dart`'s own
/// rule that a caller opens the step, not the operation itself — so a test
/// calling it directly has to open one, the way a real command's `apply`
/// would.
void _project(EditMesh mesh, List<int> island, UvProjection mode) {
  mesh.beginStep();
  projectUv(mesh, island, mode);
  mesh.endStep();
}

void main() {
  group('box', () {
    test('every face of a unit cube keeps its own edge lengths', () {
      final mesh = EditMesh.cuboid();
      for (var face = 0; face < 6; face++) {
        _project(mesh, <int>[face], UvProjection.box);
      }

      for (var face = 0; face < 6; face++) {
        var walked = mesh.halfEdgeOf(face);
        for (var i = 0; i < 4; i++) {
          expect(
            _uvEdgeLength(mesh, walked),
            closeTo(1.0, 1e-9),
            reason: 'face $face, corner $i',
          );
          walked = mesh.nextOf(walked);
        }
        expect(
          _uvArea(mesh, face).abs(),
          closeTo(1.0, 1e-9),
          reason: 'face $face',
        );
      }
    });

    test('one call over all six faces at once reads the same as one call '
        'per face — the row\'s own "cube → six islands"', () {
      final oneCall = EditMesh.cuboid();
      _project(oneCall, <int>[0, 1, 2, 3, 4, 5], UvProjection.box);

      final perFace = EditMesh.cuboid();
      for (var face = 0; face < 6; face++) {
        _project(perFace, <int>[face], UvProjection.box);
      }

      // `EditMesh.cuboid()` builds the same half-edges in the same order
      // every time, so the two meshes' half-edge ids line up one to one —
      // box mode reads only [face]'s own normal and its own corners, so
      // grouping six faces into one call or six must answer identically.
      for (var half = 0; half < oneCall.halfEdgeSlotCount; half++) {
        final face = oneCall.faceOf(half);
        if (face == EditMesh.none || !oneCall.isFaceAlive(face)) continue;
        expect(
          oneCall.uvOf(half),
          perFace.uvOf(half),
          reason: 'half-edge $half',
        );
      }
    });

    test('no face reads as mirrored relative to another', () {
      // Mutation: drop the sign flip on the positive-facing axes (always
      // read `p.z`/`p.z`/`p.x` rather than negating it on `n.x >= 0` etc.).
      // +X and −X would then wind oppositely in UV space — one face's UV
      // area positive, the other's negative — which is exactly what makes
      // a texture with any asymmetry (a label, a scratch) look flipped on
      // one side of a crate and not the other. Every one of the six faces
      // should wind the same sense here, because a cube's own faces all
      // wind the same sense in world space to begin with.
      final mesh = EditMesh.cuboid();
      for (var face = 0; face < 6; face++) {
        _project(mesh, <int>[face], UvProjection.box);
      }
      final signs = <double>[
        for (var face = 0; face < 6; face++) _uvArea(mesh, face).sign,
      ];
      expect(signs.toSet(), hasLength(1), reason: '$signs');
    });
  });

  group('planar', () {
    test('a face tilted off every axis still keeps its own edge lengths', () {
      // Mutation: drop the Gram-Schmidt subtraction and normalize the
      // reference vector as-is. A face whose normal is a cardinal axis (the
      // cube's own faces, used everywhere else in this file) already has a
      // reference perpendicular to it, so that mutation is invisible there
      // — this quad's normal has no zero component, which is what actually
      // exercises the subtraction rather than falling through it as a
      // no-op.
      final rotation = Matrix3.rotationX(0.6)..multiply(Matrix3.rotationY(0.4));
      Vector3 corner(double x, double y) =>
          rotation.transformed(Vector3(x, y, 0));
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          corner(-0.5, -0.5),
          corner(0.5, -0.5),
          corner(0.5, 0.5),
          corner(-0.5, 0.5),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
        ],
      );

      _project(mesh, <int>[0], UvProjection.planar);

      var half = mesh.halfEdgeOf(0);
      for (var i = 0; i < 4; i++) {
        expect(
          _uvEdgeLength(mesh, half),
          closeTo(_worldEdgeLength(mesh, half), 1e-6),
          reason: 'corner $i',
        );
        half = mesh.nextOf(half);
      }
    });

    test('a single flat face keeps its own edge lengths too', () {
      final mesh = EditMesh.cuboid();
      _project(mesh, <int>[0], UvProjection.planar);

      var walked = mesh.halfEdgeOf(0);
      for (var i = 0; i < 4; i++) {
        expect(
          _uvEdgeLength(mesh, walked),
          closeTo(1.0, 1e-9),
          reason: 'corner $i',
        );
        walked = mesh.nextOf(walked);
      }
    });

    test('an island bent slightly across its own faces still reads off one '
        'shared plane', () {
      // Two of the cube's own faces, which share no normal at all — the
      // point is that `_projectPlanar` does not refuse or fold, it takes
      // the average and reads every corner off that one plane, so the
      // result is a UV layout with straight, non-overlapping edges rather
      // than an error.
      final mesh = EditMesh.cuboid();
      _project(mesh, <int>[0, 2], UvProjection.planar);

      // Every corner got a real, finite UV — the one thing a caller can
      // rely on regardless of how the two faces happen to sit relative to
      // the shared plane.
      for (final face in <int>[0, 2]) {
        mesh.forEachHalfEdge(face, (int half) {
          final uv = mesh.uvOf(half);
          expect(uv.x.isFinite, isTrue);
          expect(uv.y.isFinite, isTrue);
        });
      }
    });
  });
}
