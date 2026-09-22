/// `pro-pt-02`: [projectBrush] — which texels of a texture a brush on the
/// surface reaches, and how strongly.
///
/// **The brush is a ball in space, not a circle in the texture.** A circle
/// drawn in UV space paints across every seam it crosses and stops at every
/// island edge, which is exactly backwards: a UV layout is a cut-up of the
/// surface, so two texels far apart in the layout can be neighbours on the
/// model and two that touch in the layout can be on opposite sides of it.
/// Measuring the distance in three dimensions is what makes a stroke across
/// a seam paint both islands and what keeps it off the island it happens to
/// be beside.
///
/// **Only the faces the brush can reach are rasterized.** A dab over a
/// 1024² texture would otherwise walk a million texels to write a few
/// thousand, sixty times a second; the tree answers which triangles are
/// inside the brush's own box first, and `rasterizeUv` walks those faces
/// alone.
///
/// **Spans rather than texels, because that is how a texture is written.**
/// A run along one row is one `setRange` into the tile behind it; a list of
/// loose texels is a bounds check and a multiply per texel, and the row's
/// own consumer (`pro-pt-03`'s stroke command) writes rows.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:vector_math/vector_math.dart' hide Ray;

import 'bake.dart';
import 'edit_mesh.dart';
import 'layout_plan.dart';
import 'sculpt_brush.dart' show BrushFalloff, shapeFalloff;

/// A run of texels along one row of a texture, with the brush's own weight
/// at each of them.
///
/// [x0] and [x1] are inclusive, and [weights] is `x1 - x0 + 1` long.
typedef UvSpan = ({int y, int x0, int x1, Float32List weights});

/// Which texels of a [size]×[size] texture the brush reaches, and how hard.
///
/// [surface] must be a tree over [mesh] itself — the brush is measured
/// against the surface it is painting, not against a different one.
/// [radius] is in the model's own units; [falloff] shapes the weight from 1
/// at the centre to 0 at the edge.
List<UvSpan> projectBrush({
  required EditMesh mesh,
  required TriangleBvh surface,
  required Vector3 centre,
  required double radius,
  required int size,
  BrushFalloff falloff = BrushFalloff.smooth,
}) {
  if (radius <= 0) return const <UvSpan>[];

  // The faces whose triangles are inside the brush's own box. A box rather
  // than a ball because that is the query the tree has; the ball is enforced
  // per texel below, which is where it has to be anyway.
  final plan = MeshLayoutPlan()..build(mesh);
  final faces = <int>{};
  surface.forEachInAabb(
    Aabb3.centerAndHalfExtents(centre, Vector3.all(radius)),
    (int triangle) {
      if (triangle < plan.triangleCount) {
        faces.add(plan.triangleToFace[triangle]);
      }
    },
  );
  if (faces.isEmpty) return const <UvSpan>[];

  // Gathered per row first: the rasterizer visits triangles in whatever
  // order the faces come in, and a span is a run of neighbouring texels.
  final rows = <int, Map<int, double>>{};
  rasterizeUv(mesh, size, (BakeSample sample) {
    final double distance = sample.position.distanceTo(centre);
    if (distance > radius) return;
    final double weight = shapeFalloff(falloff, 1 - distance / radius);
    if (weight <= 0) return;
    final Map<int, double> row = rows.putIfAbsent(
      sample.y,
      () => <int, double>{},
    );
    // A texel covered twice — two triangles of one face, or two faces
    // sharing it — keeps whichever reading is stronger rather than adding
    // them, since both are the same point on the surface and adding would
    // double the brush along every triangle edge.
    final double? already = row[sample.x];
    if (already == null || weight > already) row[sample.x] = weight;
  }, faces: faces);

  final spans = <UvSpan>[];
  for (final MapEntry<int, Map<int, double>> row in rows.entries) {
    final List<int> xs = row.value.keys.toList()..sort();
    var start = 0;
    while (start < xs.length) {
      var end = start;
      while (end + 1 < xs.length && xs[end + 1] == xs[end] + 1) {
        end++;
      }
      final weights = Float32List(xs[end] - xs[start] + 1);
      for (var i = 0; i < weights.length; i++) {
        weights[i] = row.value[xs[start] + i]!;
      }
      spans.add((y: row.key, x0: xs[start], x1: xs[end], weights: weights));
      start = end + 1;
    }
  }
  spans.sort((UvSpan a, UvSpan b) {
    final int byRow = a.y.compareTo(b.y);
    return byRow != 0 ? byRow : a.x0.compareTo(b.x0);
  });
  return spans;
}

/// How many texels [spans] name together — what a caller reports and a test
/// counts.
int texelsIn(List<UvSpan> spans) {
  var total = 0;
  for (final UvSpan span in spans) {
    total += span.x1 - span.x0 + 1;
  }
  return total;
}
