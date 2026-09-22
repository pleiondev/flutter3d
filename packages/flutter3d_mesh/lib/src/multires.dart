/// `pro-sc-07`: a base cage, a stack of subdivision levels, and the detail
/// each level carries — [Multires].
///
/// **Detail is a delta in a local basis, and that is the whole idea.** A
/// sculpt stored as world positions is a sculpt that comes apart the moment
/// anybody moves the cage under it: pull an arm and the pores stay where the
/// arm used to be. Stored as an offset along the surface's own tangent,
/// bitangent and normal at that vertex, the same numbers describe the same
/// bump wherever the surface goes, so the cage stays editable after the
/// detail is there — which is the thing multiresolution exists to give and
/// the reason it is not simply "subdivide, then sculpt".
///
/// **The topology of every level is fixed by the base, not by the
/// positions.** `catmullClark` numbers its output from the input's own face,
/// edge and vertex order and nothing else (see `subdivide.dart`), so
/// subdividing the same cage twice gives the same vertex ids however far the
/// cage has been dragged in between. That is what lets a level's deltas be a
/// flat array indexed by vertex: they stay meaningful across an edit to the
/// cage, and only stop meaning anything if the base's *topology* changes,
/// which is what [Multires.rebuilt] is for.
///
/// **Evaluation goes bottom-up and detail composes.** Level `k`'s mesh is
/// the subdivision of level `k - 1`'s *evaluated* mesh — detail already in —
/// with level `k`'s own deltas added on top through the basis of that
/// subdivision. So a bump sculpted at level 3 rides over a bulge sculpted at
/// level 1 rather than replacing it, and sculpting the cage afterwards
/// carries both.
///
/// **Descent is the export half.** An exporter wants the cage plus a
/// displacement map, not six hundred thousand vertices: [displacementMap]
/// walks the finest level, takes each vertex's own displacement *along the
/// normal*, and rasterizes it into the UV space the base already carries —
/// the same UVs subdivision interpolates down, so a texel of the map and a
/// texel of the colour map name the same place on the surface.
///
/// **What this does not attempt.** Dynamic topology — a brush that adds
/// vertices where it needs them — is a different structure and a later row
/// (`B9`/`Б9`, closed 2026-09-09: multiresolution, not dyntopo). Neither is
/// there an analysis pass that takes an arbitrary sculpted mesh apart into
/// per-level detail: [Multires.detailFrom] puts the whole difference on the
/// finest level, which is exactly right for a mesh that was sculpted there
/// and says nothing untrue about one that was not.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'subdivide.dart';

/// A height field over the base mesh's own UVs — what an exporter writes
/// beside the cage instead of the finest mesh.
///
/// [heights] is `size * size` displacements in metres along the surface
/// normal, row-major, `0` where no triangle covered the texel. [lowest] and
/// [highest] are the range actually written, which is what a caller needs to
/// quantize into an 8- or 16-bit image without guessing at a scale.
typedef DisplacementMap = ({
  int size,
  Float32List heights,
  double lowest,
  double highest,
});

/// The tangent, bitangent and normal at every vertex of one level, nine
/// floats per vertex — the frame a level's own deltas are written in.
///
/// Right-handed and orthonormal, so the inverse is the transpose: writing a
/// world offset into the frame is three dot products and reading it back is
/// three scaled adds, with nothing to invert and nothing to go singular.
final class VertexFrames {
  VertexFrames._(this._values, this.vertexSlotCount);

  /// The frames of every vertex of [mesh], from its own faces.
  ///
  /// **Area-weighted, one pass over the faces.** Walking the fan round each
  /// vertex instead would visit a boundary vertex's neighbours on one side
  /// only (see [EditMesh.neighborsOf]); accumulating from the faces visits
  /// every corner exactly once whatever the vertex looks like. The tangent
  /// is the direction of the first edge leaving the vertex, with whatever
  /// part of it points along the normal taken out — arbitrary, but *fixed by
  /// the topology*, which is the only property a stored delta needs from it.
  factory VertexFrames.of(EditMesh mesh) {
    final int count = mesh.vertexSlotCount;
    final normals = Float32List(count * 3);
    final tangents = Float32List(count * 3);
    final hasTangent = Uint8List(count);

    final a = Vector3.zero();
    final b = Vector3.zero();
    final c = Vector3.zero();
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      final loop = <int>[];
      mesh.forEachVertex(face, loop.add);
      if (loop.length < 3) continue;
      // Newell's normal, which is the area-weighted one for a polygon and
      // does not care whether the quad is planar.
      final faceNormal = Vector3.zero();
      for (var i = 0; i < loop.length; i++) {
        mesh.positionOf(loop[i], a);
        mesh.positionOf(loop[(i + 1) % loop.length], b);
        faceNormal
          ..x += (a.y - b.y) * (a.z + b.z)
          ..y += (a.z - b.z) * (a.x + b.x)
          ..z += (a.x - b.x) * (a.y + b.y);
      }
      for (var i = 0; i < loop.length; i++) {
        final int v = loop[i];
        normals[v * 3] += faceNormal.x;
        normals[v * 3 + 1] += faceNormal.y;
        normals[v * 3 + 2] += faceNormal.z;
        if (hasTangent[v] != 0) continue;
        mesh.positionOf(v, c);
        mesh.positionOf(loop[(i + 1) % loop.length], a);
        a.sub(c);
        if (a.length2 <= 1e-24) continue;
        tangents[v * 3] = a.x;
        tangents[v * 3 + 1] = a.y;
        tangents[v * 3 + 2] = a.z;
        hasTangent[v] = 1;
      }
    }

    final values = Float32List(count * 9);
    final normal = Vector3.zero();
    final tangent = Vector3.zero();
    for (var v = 0; v < count; v++) {
      normal.setValues(normals[v * 3], normals[v * 3 + 1], normals[v * 3 + 2]);
      if (normal.length2 <= 1e-24) {
        normal.setValues(0, 0, 1);
      } else {
        normal.normalize();
      }
      tangent.setValues(
        tangents[v * 3],
        tangents[v * 3 + 1],
        tangents[v * 3 + 2],
      );
      tangent.sub(normal.scaled(tangent.dot(normal)));
      if (tangent.length2 <= 1e-24) {
        // Any direction across the normal will do, and this one is stable:
        // cross with whichever axis the normal leans on least.
        final Vector3 axis = normal.x.abs() < 0.9
            ? Vector3(1, 0, 0)
            : Vector3(0, 1, 0);
        tangent
          ..setFrom(axis.cross(normal))
          ..normalize();
      } else {
        tangent.normalize();
      }
      final Vector3 bitangent = normal.cross(tangent);
      values
        ..[v * 9] = tangent.x
        ..[v * 9 + 1] = tangent.y
        ..[v * 9 + 2] = tangent.z
        ..[v * 9 + 3] = bitangent.x
        ..[v * 9 + 4] = bitangent.y
        ..[v * 9 + 5] = bitangent.z
        ..[v * 9 + 6] = normal.x
        ..[v * 9 + 7] = normal.y
        ..[v * 9 + 8] = normal.z;
    }
    return VertexFrames._(values, count);
  }

  final Float32List _values;
  final int vertexSlotCount;

  /// The unit normal at [vertex].
  Vector3 normalOf(int vertex, [Vector3? out]) => (out ?? Vector3.zero())
    ..setValues(
      _values[vertex * 9 + 6],
      _values[vertex * 9 + 7],
      _values[vertex * 9 + 8],
    );

  /// [world] written into [vertex]'s own frame: `(along tangent, along
  /// bitangent, along normal)`.
  Vector3 into(int vertex, Vector3 world, [Vector3? out]) =>
      (out ?? Vector3.zero())..setValues(
        world.x * _values[vertex * 9] +
            world.y * _values[vertex * 9 + 1] +
            world.z * _values[vertex * 9 + 2],
        world.x * _values[vertex * 9 + 3] +
            world.y * _values[vertex * 9 + 4] +
            world.z * _values[vertex * 9 + 5],
        world.x * _values[vertex * 9 + 6] +
            world.y * _values[vertex * 9 + 7] +
            world.z * _values[vertex * 9 + 8],
      );

  /// [local] read back out of [vertex]'s own frame, into world space.
  Vector3 outOf(int vertex, Vector3 local, [Vector3? out]) =>
      (out ?? Vector3.zero())..setValues(
        local.x * _values[vertex * 9] +
            local.y * _values[vertex * 9 + 3] +
            local.z * _values[vertex * 9 + 6],
        local.x * _values[vertex * 9 + 1] +
            local.y * _values[vertex * 9 + 4] +
            local.z * _values[vertex * 9 + 7],
        local.x * _values[vertex * 9 + 2] +
            local.y * _values[vertex * 9 + 5] +
            local.z * _values[vertex * 9 + 8],
      );
}

/// A base cage, [levels] subdivisions of it, and the detail each level holds.
///
/// See the library doc comment for what a level's detail is, why it is stored
/// in a local frame, and what descent is for.
final class Multires {
  /// [levels] subdivisions of [base], with no detail on any of them yet.
  Multires(this.base, {this.levels = 1})
    : _deltas = List<Float32List?>.filled(levels + 1, null),
      _frames = List<VertexFrames?>.filled(levels + 1, null),
      _evaluated = List<EditMesh?>.filled(levels + 1, null) {
    if (levels < 1) {
      throw ArgumentError(
        'a multires mesh needs at least one level, not '
        '$levels',
      );
    }
  }

  /// [levels] of detail read off [sculpted] — the finest level's own
  /// difference from the plain subdivision of [base].
  ///
  /// **The whole difference lands on the finest level.** Taking a sculpted
  /// mesh apart into "this much belongs to level 1, this much to level 3" is
  /// an analysis nothing here asks for, and a guess at it would put detail on
  /// a level a person never touched — where the next edit to that level would
  /// then move it. One level, stated, is the honest answer.
  factory Multires.detailFrom(
    EditMesh base,
    EditMesh sculpted, {
    int levels = 1,
  }) {
    final Multires it = Multires(base, levels: levels);
    final EditMesh plain = it._plainAt(levels);
    final VertexFrames frames = it._frames[levels]!;
    final Float32List deltas = it._deltas[levels] ??= Float32List(
      plain.vertexSlotCount * 3,
    );
    final Vector3 was = Vector3.zero();
    final Vector3 now = Vector3.zero();
    final Vector3 local = Vector3.zero();
    for (var v = 0; v < plain.vertexSlotCount; v++) {
      if (!plain.isVertexAlive(v)) continue;
      if (v >= sculpted.vertexSlotCount || !sculpted.isVertexAlive(v)) continue;
      plain.positionOf(v, was);
      sculpted.positionOf(v, now);
      frames.into(v, now..sub(was), local);
      deltas[v * 3] = local.x;
      deltas[v * 3 + 1] = local.y;
      deltas[v * 3 + 2] = local.z;
    }
    it._evaluated[levels] = null;
    return it;
  }

  /// The cage. Editing it and calling [invalidate] moves every level with
  /// it, detail and all — the thing the local frames are for.
  final EditMesh base;

  /// How many times [base] is subdivided. Level `0` is the cage itself.
  final int levels;

  // Per level: the detail, the frames it is written in, and the mesh that
  // comes out. Null until asked for; dropped from a level up when anything
  // under it moves.
  final List<Float32List?> _deltas;
  final List<VertexFrames?> _frames;
  final List<EditMesh?> _evaluated;

  /// Forgets every evaluated level, keeping the detail.
  ///
  /// What to call after editing [base] in place: the deltas are still what
  /// they were — an offset along a surface — and the surface they are offsets
  /// from has moved, which is exactly the case this structure exists for.
  void invalidate() {
    for (var level = 1; level <= levels; level++) {
      _evaluated[level] = null;
      _frames[level] = null;
    }
  }

  /// The mesh at [level], detail and all. Level `0` is [base] itself.
  EditMesh meshAt(int level) {
    _check(level);
    if (level == 0) return base;
    final EditMesh? kept = _evaluated[level];
    if (kept != null) return kept;

    final EditMesh mesh = _plainAt(level);
    final VertexFrames frames = _frames[level]!;
    final Float32List? deltas = _deltas[level];
    if (deltas != null) {
      final Vector3 at = Vector3.zero();
      final Vector3 local = Vector3.zero();
      final Vector3 world = Vector3.zero();
      mesh.beginStep();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        local.setValues(deltas[v * 3], deltas[v * 3 + 1], deltas[v * 3 + 2]);
        if (local.length2 == 0) continue;
        frames.outOf(v, local, world);
        mesh.moveVertex(v, mesh.positionOf(v, at)..add(world));
      }
      mesh.endStep();
      // The subdivision is this structure's own working copy: nobody else
      // holds it, and a journal on it would only be a second, unreachable
      // way back to a mesh `meshAt` can rebuild from the cage anyway.
      mesh.clearJournal();
    }
    return _evaluated[level] = mesh;
  }

  /// The finest mesh — what a viewport draws and a brush sculpts.
  EditMesh get finest => meshAt(levels);

  /// Moves [vertex] of [level] by [by], recording it as detail at that level.
  ///
  /// **The offset is world-space and what is kept is not.** A brush hands
  /// over a direction in the space the model is in; this writes it into the
  /// frame that vertex has on the plain subdivision, so it survives the cage
  /// moving underneath it. Level `0` has no frames of its own — it is the
  /// cage — so a move there edits [base] directly.
  void displace(int level, int vertex, Vector3 by) {
    _check(level);
    if (level == 0) {
      base.beginStep();
      base.moveVertex(vertex, base.positionOf(vertex)..add(by));
      base.endStep();
      invalidate();
      return;
    }
    _plainAt(level);
    final Vector3 local = _frames[level]!.into(vertex, by);
    final Float32List deltas = _deltasAt(level);
    deltas[vertex * 3] += local.x;
    deltas[vertex * 3 + 1] += local.y;
    deltas[vertex * 3 + 2] += local.z;
    for (var above = level; above <= levels; above++) {
      _evaluated[above] = null;
      if (above > level) _frames[above] = null;
    }
  }

  /// What [vertex] of [level] is displaced by, in world space as the surface
  /// stands now.
  Vector3 displacementOf(int level, int vertex) {
    _check(level);
    if (level == 0) return Vector3.zero();
    _plainAt(level);
    final Float32List? deltas = _deltas[level];
    if (deltas == null) return Vector3.zero();
    return _frames[level]!.outOf(
      vertex,
      Vector3(
        deltas[vertex * 3],
        deltas[vertex * 3 + 1],
        deltas[vertex * 3 + 2],
      ),
    );
  }

  /// This detail, carried onto [cage] — a base with the same topology and
  /// different positions, or a different cage entirely.
  ///
  /// **A new object rather than a setter, because the deltas only travel
  /// where the numbering does.** Level `k`'s detail is indexed by level `k`'s
  /// own vertex ids, and those follow the cage's face, edge and vertex order;
  /// a cage with the same topology keeps them all, and one with different
  /// topology keeps whichever ids happen to exist, which is a thing to ask
  /// for on purpose rather than to have happen on assignment.
  Multires rebuilt(EditMesh cage) {
    final Multires it = Multires(cage, levels: levels);
    for (var level = 1; level <= levels; level++) {
      final Float32List? deltas = _deltas[level];
      if (deltas == null) continue;
      final Float32List into = it._deltasAt(level);
      final int shared = math.min(deltas.length, into.length);
      into.setRange(0, shared, deltas);
    }
    return it;
  }

  /// The finest level's own displacement, along the normal, rasterized into
  /// the UVs the base carries — `pro-sc-07`'s "descent for export".
  ///
  /// **Along the normal only, and the rest is dropped on purpose.** A
  /// displacement map is a height field: a renderer pushes a surface point
  /// out along its own normal by what the texel says, and has nowhere to put
  /// a sideways component. Keeping one would produce a map that only agrees
  /// with the sculpt in a renderer that does not exist.
  ///
  /// Texels no triangle covers stay at zero — no surface, no height — and
  /// [DisplacementMap.lowest]/[DisplacementMap.highest] name the range that
  /// was written, so a caller quantizing to eight bits has the scale rather
  /// than a guess at it.
  DisplacementMap displacementMap({int size = 512}) {
    if (size < 1) {
      throw ArgumentError(
        'a displacement map needs a positive size, not $size',
      );
    }
    final EditMesh mesh = finest;
    final Float32List heights = Float32List(size * size);
    if (!mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
      return (size: size, heights: heights, lowest: 0.0, highest: 0.0);
    }

    final Float32List? deltas = _deltas[levels];
    // The frame's third component *is* the one along the normal, which is
    // why the deltas are stored in that order rather than any other: a
    // height map is this number and nothing else.
    double heightAt(int vertex) =>
        deltas == null ? 0.0 : deltas[vertex * 3 + 2];

    var lowest = 0.0;
    var highest = 0.0;
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      final corners = <int>[];
      mesh.forEachHalfEdge(face, corners.add);
      if (corners.length < 3) continue;
      // A fan, the same triangulation every exporter in this package uses for
      // a convex quad.
      for (var i = 1; i + 1 < corners.length; i++) {
        final range = _rasterizeTriangle(mesh, heights, size, <int>[
          corners[0],
          corners[i],
          corners[i + 1],
        ], heightAt);
        lowest = math.min(lowest, range.$1);
        highest = math.max(highest, range.$2);
      }
    }
    return (size: size, heights: heights, lowest: lowest, highest: highest);
  }

  // ------------------------------------------------------------- machinery

  void _check(int level) {
    if (level < 0 || level > levels) {
      throw RangeError.range(level, 0, levels, 'level');
    }
  }

  Float32List _deltasAt(int level) =>
      _deltas[level] ??= Float32List(_plainAt(level).vertexSlotCount * 3);

  /// The subdivision of level `level - 1`'s evaluated mesh, with no detail of
  /// its own applied, and its frames — built and kept in [_frames] because
  /// every delta at this level is written in them.
  EditMesh _plainAt(int level) {
    final VertexFrames? kept = _frames[level];
    final EditMesh? done = _evaluated[level];
    if (kept != null && done != null) {
      // Already evaluated: the plain mesh is gone, but nothing asks for it
      // once the frames are in hand — `_deltasAt` needs a vertex count and
      // the evaluated mesh has the same one.
      return done;
    }
    final EditMesh plain = catmullClark(meshAt(level - 1));
    _frames[level] = VertexFrames.of(plain);
    return plain;
  }
}

/// Fills the triangle [corners] (half-edges of [mesh], each carrying a UV and
/// a vertex) into [heights], and answers the lowest and highest it wrote.
(double, double) _rasterizeTriangle(
  EditMesh mesh,
  Float32List heights,
  int size,
  List<int> corners,
  double Function(int vertex) heightAt,
) {
  final uvs = <Vector2>[for (final int he in corners) mesh.uvOf(he)];
  final values = <double>[
    for (final int he in corners) heightAt(mesh.originOf(he)),
  ];

  final double x0 = uvs[0].x * size, y0 = uvs[0].y * size;
  final double x1 = uvs[1].x * size, y1 = uvs[1].y * size;
  final double x2 = uvs[2].x * size, y2 = uvs[2].y * size;
  final double area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
  if (area.abs() < 1e-12) return (0, 0);

  final int minX = math.max(0, math.min(x0, math.min(x1, x2)).floor());
  final int maxX = math.min(size - 1, math.max(x0, math.max(x1, x2)).ceil());
  final int minY = math.max(0, math.min(y0, math.min(y1, y2)).floor());
  final int maxY = math.min(size - 1, math.max(y0, math.max(y1, y2)).ceil());

  var lowest = 0.0;
  var highest = 0.0;
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final double px = x + 0.5;
      final double py = y + 0.5;
      final double w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area;
      final double w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area;
      final double w2 = 1 - w0 - w1;
      if (w0 < 0 || w1 < 0 || w2 < 0) continue;
      final double height = values[0] * w0 + values[1] * w1 + values[2] * w2;
      heights[y * size + x] = height;
      lowest = math.min(lowest, height);
      highest = math.max(highest, height);
    }
  }
  return (lowest, highest);
}
