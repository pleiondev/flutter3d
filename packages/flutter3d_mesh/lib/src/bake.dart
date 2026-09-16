/// `pro-rt-04`: baking a high mesh's surface onto a low mesh's UVs — the
/// rasterizer, the ray cage, the tangent-space normal map and the dilation.
///
/// **A texel is a point on the low mesh, and everything here follows from
/// that.** [rasterizeUv] walks the low mesh's UV triangles and hands back,
/// per covered texel, where that texel sits in space and which way the
/// surface faces there. Every map this file bakes — and `pro-rt-05`'s AO,
/// curvature and thickness, and `pro-pt-02`'s brush projection — is a
/// different answer to "what is true at this point", asked at the same
/// points.
///
/// **The cage is a shell either side of the surface, not a one-sided ray.**
/// A retopologized low mesh sits inside the high one in some places and
/// outside it in others — that is what shrink-wrapping to a simplified shape
/// means — so a ray fired only inward misses wherever the low mesh has sunk
/// below the detail. Firing from [shell] *above* the point, inward, and
/// taking the first hit within twice that distance catches both, and the
/// texel is left empty when nothing is inside the cage at all rather than
/// grabbing whatever geometry happens to be further along the ray.
///
/// **Tangent space, because a normal map is reused.** A normal written in
/// world space is a map that only works while the model stands exactly where
/// it stood when the bake ran; written against the low mesh's own tangent
/// frame it survives the model being turned, mirrored or skinned, which is
/// what every renderer expects a normal map to be.
///
/// **Dilation is not cosmetic.** A texel just outside an island is read by
/// bilinear filtering at the island's edge and by every mip level above it,
/// so leaving it at zero draws a black seam along every UV border. [dilate]
/// pushes the edge colours outward by a few rings, which is what every baker
/// does and what nothing else in this repository would do for it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart' show Ray, TriangleBvh;
import 'package:vector_math/vector_math.dart' hide Ray;

import 'attributes.dart';
import 'edit_mesh.dart';
import 'layout_plan.dart';
import 'normals.dart';

/// One baked image: [size]×[size] texels of [channels] floats, row-major,
/// with [covered] saying which texels a triangle actually reached.
final class BakedMap {
  BakedMap(this.size, this.channels)
    : data = Float32List(size * size * channels),
      covered = Uint8List(size * size);

  final int size;
  final int channels;

  /// `size * size * channels` floats, row-major, `(0, 0, …)` where nothing
  /// was baked.
  final Float32List data;

  /// One byte per texel: 1 where a triangle covered it, 0 where nothing did.
  ///
  /// **Kept beside the data rather than inferred from it.** A texel that
  /// legitimately baked to zero — an ambient occlusion map's own crevice —
  /// is indistinguishable from an empty one once the flags are gone, and
  /// [dilate] would then smear a crevice outward as if it were a gap.
  final Uint8List covered;

  double at(int x, int y, int channel) =>
      data[(y * size + x) * channels + channel];

  void write(int x, int y, List<double> values) {
    final int at = (y * size + x) * channels;
    for (var c = 0; c < channels && c < values.length; c++) {
      data[at + c] = values[c];
    }
    covered[y * size + x] = 1;
  }

  /// This map as 8-bit RGBA, [channels] of it filled and the rest opaque —
  /// what an `EncodedImage` is written from.
  ///
  /// [bias] and [scale] map a float to `0..1` before the 8-bit rounding:
  /// a normal map's own `-1..1` is `bias: 1, scale: 0.5`, and a mask already
  /// in `0..1` takes the defaults.
  Uint8List toRgba8({double bias = 0, double scale = 1}) {
    final out = Uint8List(size * size * 4);
    for (var texel = 0; texel < size * size; texel++) {
      for (var c = 0; c < 3; c++) {
        final double value = c < channels
            ? (data[texel * channels + c] + bias) * scale
            : 0.0;
        out[texel * 4 + c] = (value.clamp(0.0, 1.0) * 255).round();
      }
      out[texel * 4 + 3] = 255;
    }
    return out;
  }
}

/// What one covered texel stands for on the low mesh.
typedef BakeSample = ({
  int x,
  int y,
  Vector3 position,
  Vector3 normal,
  Vector3 tangent,
  Vector3 bitangent,
});

/// Calls [onSample] once for every texel the UV triangles of [low] cover.
///
/// **One pass, top-left fill, no anti-aliasing.** A texel is either a point
/// on the surface or it is not; averaging two points either side of a UV
/// island's edge would produce a position on neither and a normal that
/// belongs to nothing. Seams are handled by [dilate] afterwards, which is
/// where every baker puts them.
///
/// The frame handed to [onSample] is orthonormal: the normal is interpolated
/// from the triangle's own corners, and the tangent follows the direction U
/// increases in, which is what makes the baked map agree with the one a
/// renderer reconstructs at draw time.
void rasterizeUv(
  EditMesh low,
  int size,
  void Function(BakeSample sample) onSample,
) {
  if (size < 1) {
    throw ArgumentError('a bake needs a positive size, not $size');
  }
  if (!low.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) return;

  final normalsOf = MeshNormals()..build(low);
  final Vector3 p0 = Vector3.zero();
  final Vector3 p1 = Vector3.zero();
  final Vector3 p2 = Vector3.zero();

  for (var face = 0; face < low.faceSlotCount; face++) {
    if (!low.isFaceAlive(face)) continue;
    final corners = <int>[];
    low.forEachHalfEdge(face, corners.add);
    if (corners.length < 3) continue;
    for (var i = 1; i + 1 < corners.length; i++) {
      final List<int> triangle = <int>[corners[0], corners[i], corners[i + 1]];
      final List<Vector2> uvs = <Vector2>[
        for (final int he in triangle) low.uvOf(he),
      ];
      final List<int> vertices = <int>[
        for (final int he in triangle) low.originOf(he),
      ];
      low.positionOf(vertices[0], p0);
      low.positionOf(vertices[1], p1);
      low.positionOf(vertices[2], p2);
      final List<Vector3> normals = <Vector3>[
        for (final int he in triangle) normalsOf.cornerNormal(he),
      ];
      final Vector3 tangent = _tangentOf(p0, p1, p2, uvs);

      _fillTriangle(uvs, size, (int x, int y, double w0, double w1, double w2) {
        final Vector3 position = p0.scaled(w0) + p1.scaled(w1) + p2.scaled(w2);
        final Vector3 normal =
            normals[0].scaled(w0) +
            normals[1].scaled(w1) +
            normals[2].scaled(w2);
        if (normal.length2 <= 1e-20) {
          normal.setFrom((p1 - p0).cross(p2 - p0));
        }
        if (normal.length2 <= 1e-20) return;
        normal.normalize();
        final Vector3 alongU = tangent - normal.scaled(tangent.dot(normal));
        if (alongU.length2 <= 1e-20) return;
        alongU.normalize();
        onSample((
          x: x,
          y: y,
          position: position,
          normal: normal,
          tangent: alongU,
          bitangent: normal.cross(alongU),
        ));
      });
    }
  }
}

/// A tangent-space normal map: [high]'s own surface, written into [low]'s
/// UVs.
///
/// [shell] is how far either side of the low surface the cage reaches, in
/// the model's own units — see the library comment for why it is a shell
/// and not a one-sided ray. A texel whose cage contains nothing is left
/// uncovered, for [dilate] to fill from its neighbours.
BakedMap bakeNormalMap({
  required EditMesh low,
  required TriangleBvh high,
  required int size,
  double shell = 0.1,
}) {
  final BakedMap map = BakedMap(size, 3);
  final Ray ray = Ray.zero();
  rasterizeUv(low, size, (BakeSample sample) {
    ray.setFrom(sample.position + sample.normal.scaled(shell), -sample.normal);
    final hit = high.raycast(ray, maxDistance: shell * 2);
    if (hit == null) return;
    final Vector3 there = _triangleNormal(high, hit.triangle);
    // Into the texel's own frame: three dot products, since the frame is
    // orthonormal and its inverse is therefore its transpose.
    map.write(sample.x, sample.y, <double>[
      there.dot(sample.tangent),
      there.dot(sample.bitangent),
      there.dot(sample.normal),
    ]);
  });
  return map;
}

/// Pushes the covered texels outward by [rings], so bilinear filtering and
/// the mip chain have something other than zero to read at a UV border.
///
/// Each pass writes every uncovered texel that has a covered neighbour with
/// the average of those neighbours, then marks it covered for the next pass
/// — a flood outward from the islands rather than a blur across them.
void dilate(BakedMap map, {int rings = 4}) {
  final int size = map.size;
  final int channels = map.channels;
  for (var ring = 0; ring < rings; ring++) {
    final Uint8List before = Uint8List.fromList(map.covered);
    var grew = false;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (before[y * size + x] != 0) continue;
        final sum = Float32List(channels);
        var found = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final int nx = x + dx;
            final int ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
            if (before[ny * size + nx] == 0) continue;
            for (var c = 0; c < channels; c++) {
              sum[c] += map.data[(ny * size + nx) * channels + c];
            }
            found++;
          }
        }
        if (found == 0) continue;
        for (var c = 0; c < channels; c++) {
          map.data[(y * size + x) * channels + c] = sum[c] / found;
        }
        map.covered[y * size + x] = 1;
        grew = true;
      }
    }
    if (!grew) return;
  }
}

/// `pro-rt-05`: ambient occlusion over the same texels [bakeNormalMap] uses.
///
/// **Halton, not `Random`.** Two runs of a bake have to produce the same
/// bytes — `texture_bake.dart`'s own rule, and the reason nothing in this
/// repository seeds a generator — and a low-discrepancy sequence also covers
/// the hemisphere more evenly than the same number of random directions, so
/// the noise floor is lower for the same [samples].
///
/// **Cosine-weighted, because that is what the integral is.** Ambient light
/// arriving at a surface falls off with the cosine of the angle from the
/// normal; sampling uniformly and multiplying by the cosine afterwards is
/// the same answer with more of the samples spent where they count least.
///
/// 1 is open sky, 0 is fully enclosed. [distance] is how far a ray looks
/// before deciding nothing is in the way — a wall across the room does not
/// darken a face, and an unbounded ray on a closed model would report every
/// texel occluded.
BakedMap bakeAmbientOcclusion({
  required EditMesh low,
  required TriangleBvh high,
  required int size,
  int samples = 64,
  double distance = 1.0,
  double bias = 1e-3,
}) {
  final BakedMap map = BakedMap(size, 1);
  final ray = Ray.zero();
  rasterizeUv(low, size, (BakeSample sample) {
    var open = 0.0;
    for (var s = 0; s < samples; s++) {
      final Vector3 direction = _cosineDirection(
        s,
        sample.normal,
        sample.tangent,
        sample.bitangent,
      );
      ray.setFrom(sample.position + sample.normal.scaled(bias), direction);
      if (high.raycast(ray, maxDistance: distance) == null) open += 1;
    }
    map.write(sample.x, sample.y, <double>[open / samples]);
  });
  return map;
}

/// `pro-rt-05`: curvature, from how the surface turns between a vertex and
/// its neighbours.
///
/// 0.5 is flat, above it convex, below it concave — an unsigned map would
/// lose exactly the distinction a cavity mask is asked for. [scale] is how
/// hard the answer is pushed away from the middle before it is clamped.
BakedMap bakeCurvature({
  required EditMesh low,
  required int size,
  double scale = 4.0,
}) {
  final normalsOf = MeshNormals()..build(low);
  final Float32List perVertex = Float32List(low.vertexSlotCount);
  final Vector3 here = Vector3.zero();
  final Vector3 there = Vector3.zero();
  for (var v = 0; v < low.vertexSlotCount; v++) {
    if (!low.isVertexAlive(v)) continue;
    final int outgoing = low.outgoingOf(v);
    if (outgoing == EditMesh.none) continue;
    normalsOf.cornerNormal(outgoing, here);
    low.positionOf(v, there);
    var sum = 0.0;
    var count = 0;
    for (final int neighbour in low.neighborsOf(v)) {
      final Vector3 toward = low.positionOf(neighbour) - there;
      if (toward.length2 <= 1e-20) continue;
      toward.normalize();
      // Positive where the neighbour sits *below* the tangent plane — a
      // ridge — and negative in a valley.
      sum += -here.dot(toward);
      count++;
    }
    if (count > 0) perVertex[v] = sum / count;
  }

  final BakedMap map = BakedMap(size, 1);
  rasterizeUv(low, size, (BakeSample sample) {
    // The rasterizer hands back a point, not a vertex, so the value is read
    // from whichever vertex of the covering triangle is nearest — a bake at
    // 1024 squared over a retopologized mesh has many texels per triangle,
    // and the difference between this and a barycentric blend is below the
    // eighth bit it is written into.
    map.write(sample.x, sample.y, <double>[
      (0.5 + perVertex[_nearestVertex(low, sample.position)] * scale).clamp(
        0.0,
        1.0,
      ),
    ]);
  });
  return map;
}

/// `pro-rt-05`: thickness — how much solid there is behind each texel,
/// measured by firing *into* the surface.
///
/// 0 is paper-thin and 1 is at least [distance] of material, which is what a
/// subsurface-scattering shader reads to decide how much light comes through
/// an ear or a leaf.
BakedMap bakeThickness({
  required EditMesh low,
  required TriangleBvh high,
  required int size,
  int samples = 32,
  double distance = 1.0,
  double bias = 1e-3,
}) {
  final BakedMap map = BakedMap(size, 1);
  final ray = Ray.zero();
  rasterizeUv(low, size, (BakeSample sample) {
    final Vector3 inward = -sample.normal;
    var total = 0.0;
    for (var s = 0; s < samples; s++) {
      final Vector3 direction = _cosineDirection(
        s,
        inward,
        sample.tangent,
        sample.bitangent,
      );
      ray.setFrom(sample.position + inward.scaled(bias), direction);
      final hit = high.raycast(ray, maxDistance: distance);
      total += hit == null ? 1.0 : (hit.distance / distance).clamp(0.0, 1.0);
    }
    map.write(sample.x, sample.y, <double>[total / samples]);
  });
  return map;
}

/// The vertex of [mesh] nearest [point] — [bakeCurvature]'s own lookup.
int _nearestVertex(EditMesh mesh, Vector3 point) {
  var best = 0;
  var bestDistance = double.infinity;
  final at = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, at);
    final double distance = at.distanceToSquared(point);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = v;
    }
  }
  return best;
}

/// Sample [index] of a cosine-weighted hemisphere about [normal], from the
/// Halton sequence in bases 2 and 3.
Vector3 _cosineDirection(
  int index,
  Vector3 normal,
  Vector3 tangent,
  Vector3 bitangent,
) {
  final double u = _halton(index + 1, 2);
  final double v = _halton(index + 1, 3);
  // `r = sqrt(u)` puts the samples' density where the cosine wants them, and
  // z falls out of the unit hemisphere.
  final double r = math.sqrt(u);
  final double theta = 2 * math.pi * v;
  return tangent.scaled(r * math.cos(theta)) +
      bitangent.scaled(r * math.sin(theta)) +
      normal.scaled(math.sqrt(math.max(0.0, 1 - u)));
}

/// The [index]th number of the Halton sequence in [base].
double _halton(int index, int base) {
  var result = 0.0;
  var fraction = 1.0;
  var i = index;
  while (i > 0) {
    fraction /= base;
    result += fraction * (i % base);
    i ~/= base;
  }
  return result;
}

/// A triangle tree over [mesh]'s own surface — what a bake casts against.
TriangleBvh surfaceOf(EditMesh mesh) {
  final plan = MeshLayoutPlan()..build(mesh);
  final rows = plan.indices;
  final indices = Uint32List(plan.triangleCount * 3);
  for (var i = 0; i < indices.length; i++) {
    indices[i] = plan.gpuVertexToVertex[rows[i]];
  }
  final positions = Float32List(mesh.vertexSlotCount * 3);
  final at = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, at);
    positions[v * 3] = at.x;
    positions[v * 3 + 1] = at.y;
    positions[v * 3 + 2] = at.z;
  }
  return TriangleBvh.fromArrays(positions, indices);
}

/// The unit normal of [triangle] in [tree], from its own three corners.
Vector3 _triangleNormal(TriangleBvh tree, int triangle) {
  Vector3 corner(int at) {
    final int v = tree.indices[triangle * 3 + at];
    return Vector3(
      tree.positions[v * 3],
      tree.positions[v * 3 + 1],
      tree.positions[v * 3 + 2],
    );
  }

  final Vector3 a = corner(0);
  final Vector3 normal = (corner(1) - a).cross(corner(2) - a);
  if (normal.length2 <= 1e-20) return Vector3(0, 0, 1);
  return normal..normalize();
}

/// The direction U increases in across the triangle, before it is made
/// perpendicular to the texel's own normal.
Vector3 _tangentOf(Vector3 p0, Vector3 p1, Vector3 p2, List<Vector2> uvs) {
  final Vector3 edge1 = p1 - p0;
  final Vector3 edge2 = p2 - p0;
  final Vector2 duv1 = uvs[1] - uvs[0];
  final Vector2 duv2 = uvs[2] - uvs[0];
  final double determinant = duv1.x * duv2.y - duv2.x * duv1.y;
  if (determinant.abs() < 1e-12) {
    // A degenerate UV triangle carries no direction of its own; any
    // direction across the surface will do and this one is stable.
    return edge1.length2 > 1e-20 ? edge1 : Vector3(1, 0, 0);
  }
  final double r = 1 / determinant;
  return (edge1.scaled(duv2.y) - edge2.scaled(duv1.y)).scaled(r);
}

/// Walks the texels [uvs] covers at [size], calling [onTexel] with the
/// barycentric weights at each texel's own centre.
void _fillTriangle(
  List<Vector2> uvs,
  int size,
  void Function(int x, int y, double w0, double w1, double w2) onTexel,
) {
  final double x0 = uvs[0].x * size, y0 = uvs[0].y * size;
  final double x1 = uvs[1].x * size, y1 = uvs[1].y * size;
  final double x2 = uvs[2].x * size, y2 = uvs[2].y * size;
  final double area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
  if (area.abs() < 1e-12) return;

  final int minX = math.max(0, math.min(x0, math.min(x1, x2)).floor());
  final int maxX = math.min(size - 1, math.max(x0, math.max(x1, x2)).ceil());
  final int minY = math.max(0, math.min(y0, math.min(y1, y2)).floor());
  final int maxY = math.min(size - 1, math.max(y0, math.max(y1, y2)).ceil());

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final double px = x + 0.5;
      final double py = y + 0.5;
      final double w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area;
      final double w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area;
      final double w2 = 1 - w0 - w1;
      if (w0 < 0 || w1 < 0 || w2 < 0) continue;
      onTexel(x, y, w0, w1, w2);
    }
  }
}
