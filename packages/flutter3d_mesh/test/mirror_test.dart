/// Reflecting a mesh across a plane through the origin, and welding the seam.
///
///     dart test test/mirror_test.dart
///
/// Two shapes carry the acceptance: a box nowhere near the plane, which
/// mirrors into two disjoint boxes with double the volume and nothing to
/// weld, and a box with one face sitting exactly on the plane, which mirrors
/// into a single longer box once the seam is welded — the seam itself stays
/// as a real, un-simplified ring of vertices down the middle rather than
/// vanishing, since nothing here simplifies coplanar geometry.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The eight corners of a box, in the order the six quads below name them.
List<Vector3> boxPoints(Vector3 low, Vector3 high) => <Vector3>[
  Vector3(low.x, low.y, low.z),
  Vector3(high.x, low.y, low.z),
  Vector3(high.x, high.y, low.z),
  Vector3(low.x, high.y, low.z),
  Vector3(low.x, low.y, high.z),
  Vector3(high.x, low.y, high.z),
  Vector3(high.x, high.y, high.z),
  Vector3(low.x, high.y, high.z),
];

List<List<int>> boxFaces() => <List<int>>[
  <int>[4, 5, 6, 7],
  <int>[1, 0, 3, 2],
  <int>[5, 1, 2, 6],
  <int>[0, 4, 7, 3],
  <int>[3, 7, 6, 2],
  <int>[0, 1, 5, 4],
];

EditMesh box(Vector3 low, Vector3 high) =>
    EditMesh.fromFaces(boxPoints(low, high), boxFaces());

void main() {
  group('mirror', () {
    test('a box nowhere near the plane doubles into two disjoint boxes', () {
      final base = box(Vector3(2, -0.5, -0.5), Vector3(3, 0.5, 0.5));
      final result = mirror(base, normal: Vector3(1, 0, 0));
      result.validate();

      // Mutation: reuse the kept copy's vertices for the mirrored one instead
      // of adding a fresh set — the count stops moving with the mirror at
      // all, staying at 8 instead of the two boxes' 16.
      expect(result.vertexCount, 16);
      expect(result.faceCount, 12);
      // The two boxes never touch, so nothing here is welded and the total
      // volume is exactly twice the one box's own.
      // Mutation: forget to reverse the mirrored copy's winding — its own
      // faces would then draw inward, and its contribution to the total
      // subtracts rather than adds, landing near zero instead of doubling.
      expect(result.signedVolume, closeTo(base.signedVolume * 2, 1e-9));
    });

    test('a box with one face on the plane welds into one longer box', () {
      // A unit cube from x=0 to x=1: one whole face sits exactly on the
      // mirror plane at x=0.
      final base = box(Vector3(0, -0.5, -0.5), Vector3(1, 0.5, 0.5));
      final result = mirror(
        base,
        normal: Vector3(1, 0, 0),
        mergeDistance: 1e-6,
      );
      result.validate();

      // 8 + 8 vertices, minus the 4 pairs exactly on the plane that weld.
      // The seam itself is not simplified away — it stays as a real ring
      // of 4 vertices down the middle of what is otherwise a flat wall,
      // since nothing here dissolves coplanar geometry.
      //
      // Mutation: skip `mergeByDistance` when `mergeDistance` is given —
      // the count stays 16 and the plane's own doubled, inside-out face
      // is never dropped either.
      expect(result.vertexCount, 12);
      // The doubled face sitting exactly on the plane — one from each
      // copy, coincident and wound oppositely — is the "wall seen from
      // both sides" case `mergeByDistance` already drops on its own; the
      // other five faces of each box survive on both sides, for eleven,
      // less those two, for ten.
      expect(result.faceCount, 10);
      // Two unit cubes end to end is a 2x1x1 box.
      expect(result.signedVolume, closeTo(2.0, 1e-9));
    });

    test('bisect is refused rather than silently mirroring the whole mesh', () {
      expect(
        () => mirror(
          box(Vector3.zero(), Vector3(1, 1, 1)),
          normal: Vector3(1, 0, 0),
          bisect: true,
        ),
        throwsUnimplementedError,
      );
    });

    test('the normal need not already be unit length', () {
      final base = box(Vector3(2, -0.5, -0.5), Vector3(3, 0.5, 0.5));
      final withUnit = mirror(base, normal: Vector3(1, 0, 0));
      final withLong = mirror(base, normal: Vector3(5, 0, 0));

      expect(withLong.vertexCount, withUnit.vertexCount);
      expect(withLong.signedVolume, closeTo(withUnit.signedVolume, 1e-9));
    });

    test('each face keeps its own material slot on both sides', () {
      final base = box(Vector3(2, -0.5, -0.5), Vector3(3, 0.5, 0.5));
      base.beginStep();
      for (var f = 0; f < base.faceSlotCount; f++) {
        base.setMaterialSlot(f, 3);
      }
      base.endStep();

      final result = mirror(base, normal: Vector3(1, 0, 0));

      for (var f = 0; f < result.faceSlotCount; f++) {
        expect(result.materialSlotOf(f), 3);
      }
    });
  });
}
