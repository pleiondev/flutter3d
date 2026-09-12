/// How much a UV mapping distorts world distance — Sander's own L2 metric.
///
/// **`pro-uv-04`, and the number `pro-uv-05`'s packer will read.** A packer
/// choosing how much room to give an island needs a number for "how much
/// this island's own texture is already stretched", and Sander, Snyder,
/// Gortler and Hoppe's own signal-to-noise metric — root-mean-square
/// singular value of the per-triangle Jacobian from UV to world space,
/// weighted by world-space area across the island — is the standard answer.
library;

import 'dart:math' as math;

import 'edit_mesh.dart';

/// The root-mean-square stretch of [island]'s current UV mapping.
///
/// **1.0 is a perfect isometry.** A parameterization that scales world
/// distance by exactly one in every direction, everywhere in the island —
/// the shape [projectUv]'s `box` mode gives an axis-aligned face, which is
/// why that is what the row's own worked example measures. Above one is
/// stretched — texture detail spread thinner than the surface it covers;
/// below one is compressed — texture detail wasted on less surface than it
/// could cover. The metric does not say which: a mapping scaled to half
/// size in both directions and one scaled to double in only one read the
/// same number, because both move every singular value the same distance
/// from one. A caller that needs to tell those apart reads the singular
/// values themselves, which this does not expose.
///
/// **Faces are read as a triangle fan from their own first corner** — right
/// for the convex faces [projectUv] and every primitive in this package
/// produce. A concave n-gon wants the same ear clipping `triangulateFaces`
/// falls back from a fan for (see `triangulate.dart`'s own reasoning); this
/// does not do that, so a concave island's own answer is only as good as a
/// fan's triangulation of it.
///
/// A degenerate triangle — collinear in UV space, so the parameterization
/// has no inverse there — contributes nothing rather than dividing by zero;
/// an island entirely of these answers 0.0, which is not a stretch value any
/// real mapping produces and is therefore a caller's signal that nothing
/// here was measurable.
double stretchOf(EditMesh mesh, List<int> island) {
  var weightedSquareSum = 0.0;
  var totalArea = 0.0;

  for (final face in island) {
    final corners = <int>[];
    mesh.forEachHalfEdge(face, corners.add);
    if (corners.length < 3) continue;

    final q0 = mesh.positionOf(mesh.originOf(corners[0]));
    final uv0 = mesh.uvOf(corners[0]);

    // A fan from the first corner: triangles (0, i, i+1) for i = 1..n-2.
    for (var i = 1; i + 1 < corners.length; i++) {
      final q1 = mesh.positionOf(mesh.originOf(corners[i]));
      final q2 = mesh.positionOf(mesh.originOf(corners[i + 1]));
      final uv1 = mesh.uvOf(corners[i]);
      final uv2 = mesh.uvOf(corners[i + 1]);

      // Twice the triangle's own UV-space area — its sign carries the
      // winding the two partial-derivative vectors below depend on, and a
      // zero means the three UVs are collinear: no plane to speak of.
      final twiceUvArea =
          (uv1.x - uv0.x) * (uv2.y - uv0.y) - (uv2.x - uv0.x) * (uv1.y - uv0.y);
      if (twiceUvArea == 0) continue;

      // The world-space vectors a unit step in s and in t would move a
      // point by, solved from the three corners the way an affine map
      // over one triangle always can be — Sander et al.'s own Ss, St.
      final ss =
          (q0 * (uv1.y - uv2.y) + q1 * (uv2.y - uv0.y) + q2 * (uv0.y - uv1.y))
            ..scale(1 / twiceUvArea);
      final st =
          (q0 * (uv2.x - uv1.x) + q1 * (uv0.x - uv2.x) + q2 * (uv1.x - uv0.x))
            ..scale(1 / twiceUvArea);

      // Γ² + γ² of the Jacobian is its trace, |Ss|² + |St|², whatever its
      // off-diagonal term is — the L2 (RMS) stretch never needs the full
      // singular value decomposition, only its sum.
      final l2Squared = (ss.length2 + st.length2) / 2;

      final area3d = (q1 - q0).cross(q2 - q0).length / 2;
      weightedSquareSum += l2Squared * area3d;
      totalArea += area3d;
    }
  }

  if (totalArea == 0) return 0.0;
  return math.sqrt(weightedSquareSum / totalArea);
}
