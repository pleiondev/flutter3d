/// Comparing two meshes that agree on nothing but their triangles — `gfx-82n`.
///
/// A mesh that has been through an edgebreaker encoder keeps its surface and
/// loses its bookkeeping: the faces are in the order the encoder's walk left
/// them, the vertices in the order a second walk reaches them, and each face
/// may start at a different one of its three corners. Counts are no help
/// either — the encoder welds what it can and the original may not have.
///
/// What survives is the bag of triangles, each a cycle of three corners with
/// everything a corner carries. This matches one bag against another.
library;

import 'dart:typed_data';

/// The triangles of [expected] that have no partner in [actual], by index.
///
/// Both lists hold `tolerance.length` floats per corner, three corners per
/// triangle — already de-indexed, so that two meshes indexed differently are
/// compared on what they draw. A partner is a triangle not yet taken by
/// another, equal in every float to within that float's own [tolerance] — a
/// position and a normal are quantised to different grids and one number for
/// both would be too loose for one of them — under one of the three rotations
/// that keep its winding. Quadratic, and honest about it: the alternative is a
/// spatial hash whose cell edges are exactly where quantised values land.
List<int> unmatchedTriangles(
  Float32List expected,
  Float32List actual,
  List<double> tolerance,
) {
  final stride = tolerance.length;
  final size = stride * 3;
  final taken = List<bool>.filled(actual.length ~/ size, false);

  bool matches(int e, int a, int rotation) {
    for (var corner = 0; corner < 3; corner++) {
      final from = e * size + corner * stride;
      final to = a * size + ((corner + rotation) % 3) * stride;
      for (var i = 0; i < stride; i++) {
        if ((expected[from + i] - actual[to + i]).abs() > tolerance[i]) {
          return false;
        }
      }
    }
    return true;
  }

  int partnerOf(int e) {
    for (var a = 0; a < taken.length; a++) {
      if (taken[a]) continue;
      for (var rotation = 0; rotation < 3; rotation++) {
        if (matches(e, a, rotation)) return a;
      }
    }
    return -1;
  }

  // A loop and not a collection: claiming a partner is a side effect, and each
  // claim changes what the next triangle may match.
  final unmatched = <int>[];
  for (var e = 0; e < expected.length ~/ size; e++) {
    final partner = partnerOf(e);
    if (partner < 0) {
      unmatched.add(e);
    } else {
      taken[partner] = true;
    }
  }
  return unmatched;
}
