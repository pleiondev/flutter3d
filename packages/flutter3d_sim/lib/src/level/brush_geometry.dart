import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'brush_index.dart';
import 'brush_surface.dart';
import 'level.dart';
import 'level_visibility.dart';
import 'lightmap_layout.dart';
import 'surface_builder.dart';

export 'brush_surface.dart';

/// One visible block face: whose it is, which of the six, and its frame —
/// the centre, the outward normal, the two axes across it and the half
/// extents along them. What the geometry emits a quad from and what the
/// lightmap plans a rectangle for, so the two agree about every face.
typedef BrushFace = ({
  int brush,
  int face,
  Vector3 normal,
  Vector3 u,
  Vector3 v,
  double centreX,
  double centreY,
  double centreZ,
  double halfU,
  double halfV,
});

/// Turns a level's brushes into drawable triangles.
///
/// ## UVs come from world space
///
/// A face's texture coordinates are its world position projected onto the two
/// axes of that face, so a texture repeats every metre regardless of how large
/// the brush is. The alternative — stretching one copy of the texture across
/// each face — makes a two-metre wall and a twenty-metre wall look like
/// different materials, and is the single most recognisable sign of a level
/// nobody unwrapped. It also means two brushes meeting in a line have
/// continuous texturing across the seam, for free.
///
/// ## Hidden faces are dropped
///
/// A face whose centre lies inside another solid brush cannot be seen and is
/// not emitted. In a level built by stacking blocks that is a large fraction of
/// them. The test is deliberately conservative — strictly inside, not merely
/// touching — so a face that is merely coplanar with a neighbour survives; a
/// generator that removed those would eventually remove one that was visible,
/// and a hole in a wall is far worse than a triangle nobody sees.
final class BrushGeometry {
  const BrushGeometry({this.cullHiddenFaces = true, this.cellSize = 8.0});

  final bool cullHiddenFaces;

  /// Cell side for the index used to find neighbouring brushes.
  final double cellSize;

  /// The six faces, as an outward normal and the two axes across it.
  ///
  /// `cross(u, v) == normal`, which is what makes the corner order below wind
  /// counter-clockwise seen from outside. Get one of these wrong and the face
  /// is culled as a back face, which looks like a hole rather than like a
  /// winding error.
  static final List<(Vector3, Vector3, Vector3)>
  faceAxes = <(Vector3, Vector3, Vector3)>[
    (Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
    (Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)),
    (Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0)),
    (Vector3(0.0, -1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)),
    (Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)),
    (Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)),
  ];

  /// One surface per material actually used, per answer about shadows — and,
  /// given [visibility], per visibility cell as well.
  ///
  /// **A batch is the smallest thing a frame can leave out**, so a level
  /// whose walls are three batches is a level that draws all its walls from
  /// everywhere. With a table, each face joins the batch of the cell its
  /// centre falls in: a room's walls become that room's batches, and a frame
  /// in the next room draws none of them. The cost is draw calls — a batch
  /// per material per cell rather than per material — which is the price of
  /// having something to skip. Without a table the batching is what it was,
  /// which keeps every recorded picture where it is.
  ///
  /// With [lightmap], every vertex also carries its second texture
  /// coordinate — the face's place in the atlas — and [BrushSurface.lightmapUvs]
  /// is filled; without one it is null and the batches are what they were.
  List<BrushSurface> build(
    Level level, {
    LevelVisibility? visibility,
    LightmapLayout? lightmap,
  }) {
    final builders = <String, SurfaceBuilder>{};

    // Keyed by material and by the shadow answer, because a batch is the
    // smallest thing that can be taken out of the shadow pass — and by the
    // cell, when there is a table to say which cell a face is in. A level
    // with no fences and no table produces exactly the batches it always did.
    SurfaceBuilder builderFor(Brush brush, double x, double y, double z) {
      final slot = visibility == null ? -1 : visibility.slotOf(x, y, z);
      final key = '${brush.material}|${brush.castsShadow ? 1 : 0}|$slot';
      return builders.putIfAbsent(
        key,
        () => SurfaceBuilder(
          brush.material,
          castsShadow: brush.castsShadow,
          lightmapped: lightmap != null,
        ),
      );
    }

    for (final face in blockFaces(level)) {
      final brush = level.brushes[face.brush];
      _emitFace(
        face,
        level.materialFor(brush),
        builderFor(brush, face.centreX, face.centreY, face.centreZ),
        lightmap,
      );
    }
    for (final brush in level.brushes) {
      final ramp = brush.ramp;
      if (ramp == null) continue;
      final centre = brush.centre;
      _emitRamp(
        brush,
        ramp,
        level.materialFor(brush),
        builderFor(brush, centre.x, centre.y, centre.z),
        lightmap,
      );
    }

    return <BrushSurface>[
      for (final builder in builders.values)
        if (builder.isNotEmpty) builder.finish(),
    ];
  }

  /// Every block face the level draws, in brush order and then face order.
  ///
  /// The same rules [build] draws by — a ramp keeps two of its six, a face
  /// whose centre is inside another solid brush is not there — stated once,
  /// so the lightmap's planner and the geometry cannot disagree about which
  /// faces exist.
  Iterable<BrushFace> blockFaces(Level level) sync* {
    final index = BrushIndex(level, cellSize);
    for (var b = 0; b < level.brushes.length; b++) {
      final brush = level.brushes[b];
      final half = brush.halfExtents;
      final ramp = brush.ramp;
      for (var f = 0; f < faceAxes.length; f++) {
        final (normal, u, v) = faceAxes[f];
        // A ramp keeps two of the block's six faces — the floor and the wall
        // at the top of the climb — loses the one at the thin end entirely,
        // and trades the other three for a slope and two triangles.
        if (ramp != null && !rampKeeps(ramp, normal)) continue;
        // Distance from the centre to this face, along its own normal.
        final offset =
            normal.x.abs() * half.x +
            normal.y.abs() * half.y +
            normal.z.abs() * half.z;
        final centreX = brush.centre.x + normal.x * offset;
        final centreY = brush.centre.y + normal.y * offset;
        final centreZ = brush.centre.z + normal.z * offset;
        if (cullHiddenFaces &&
            index.containsPoint(centreX, centreY, centreZ, brush)) {
          continue;
        }
        yield (
          brush: b,
          face: f,
          normal: normal,
          u: u,
          v: v,
          centreX: centreX,
          centreY: centreY,
          centreZ: centreZ,
          // Half the face, measured along its own two axes.
          halfU: u.x.abs() * half.x + u.y.abs() * half.y + u.z.abs() * half.z,
          halfV: v.x.abs() * half.x + v.y.abs() * half.y + v.z.abs() * half.z,
        );
      }
    }
  }

  void _emitFace(
    BrushFace face,
    LevelMaterial material,
    SurfaceBuilder out,
    LightmapLayout? lightmap,
  ) {
    final scale = material.texelsPerMetre;
    final normal = face.normal;
    final u = face.u;
    final v = face.v;
    final centreX = face.centreX;
    final centreY = face.centreY;
    final centreZ = face.centreZ;
    final halfU = face.halfU;
    final halfV = face.halfV;
    final placed = lightmap?.faceOf(face.brush, face.face);

    final first = out.vertexCount;
    for (final (su, sv) in const <(double, double)>[
      (-1.0, -1.0),
      (1.0, -1.0),
      (1.0, 1.0),
      (-1.0, 1.0),
    ]) {
      final x = centreX + u.x * halfU * su + v.x * halfV * sv;
      final y = centreY + u.y * halfU * su + v.y * halfV * sv;
      final z = centreZ + u.z * halfU * su + v.z * halfV * sv;
      final (lu, lv) = switch ((lightmap, placed)) {
        (final layout?, final at?) => layout.uvAt(at, su, sv),
        (final layout?, null) => layout.neutralUv,
        _ => (0.0, 0.0),
      };

      out.addVertex(
        x,
        y,
        z,
        normal.x,
        normal.y,
        normal.z,
        u.x,
        u.y,
        u.z,
        // World position projected onto the face's axes: continuous across
        // the seam between two brushes, and independent of face size.
        (x * u.x + y * u.y + z * u.z) * scale,
        (x * v.x + y * v.y + z * v.z) * scale,
        lightmapU: lu,
        lightmapV: lv,
      );
    }

    out.addQuad(first);
  }

  /// Whether a ramp keeps the block face pointing along [normal].
  ///
  /// Two of the six: the floor, and the wall at the top of the climb. The face
  /// at the thin end is gone entirely — that is the corner being cut — and the
  /// two sides and the top are replaced by triangles and a slope.
  static bool rampKeeps(WedgeUphill uphill, Vector3 normal) {
    if (normal.y != 0.0) return normal.y < 0.0;
    return normal.x == uphill.x && normal.z == uphill.z;
  }

  /// The slope and the two triangles under it.
  ///
  /// None of them is planned in a lightmap — a wedge is not a box face — so
  /// with a layout their vertices point at its reserved texel.
  void _emitRamp(
    Brush brush,
    WedgeUphill uphill,
    LevelMaterial material,
    SurfaceBuilder out,
    LightmapLayout? lightmap,
  ) {
    final half = brush.halfExtents;
    final centre = brush.centre;
    final scale = material.texelsPerMetre;
    final axis = uphill.axis;
    final side = axis == 0 ? 2 : 0;
    final (lightmapU, lightmapV) = lightmap?.neutralUv ?? (0.0, 0.0);

    // The slope is a rectangle centred on the brush's own centre, because the
    // cut runs corner to corner. Its two axes are the side of the brush and the
    // line straight up the hill, and `cross(u, v) == normal` holds by
    // construction — which is what winds the corners the right way round.
    final normal = CollisionWedge(half, uphill: uphill).slopeNormal;
    final u = Vector3.zero()..[side] = 1.0;
    final v = normal.cross(u);
    final halfU = half[side];
    final halfV = math.sqrt(half[axis] * half[axis] + half.y * half.y);

    final first = out.vertexCount;
    for (final (su, sv) in const <(double, double)>[
      (-1.0, -1.0),
      (1.0, -1.0),
      (1.0, 1.0),
      (-1.0, 1.0),
    ]) {
      final x = centre.x + u.x * halfU * su + v.x * halfV * sv;
      final y = centre.y + u.y * halfU * su + v.y * halfV * sv;
      final z = centre.z + u.z * halfU * su + v.z * halfV * sv;
      out.addVertex(
        x,
        y,
        z,
        normal.x,
        normal.y,
        normal.z,
        u.x,
        u.y,
        u.z,
        (x * u.x + y * u.y + z * u.z) * scale,
        (x * v.x + y * v.y + z * v.z) * scale,
        lightmapU: lightmapU,
        lightmapV: lightmapV,
      );
    }
    out.addQuad(first);

    // The two ends, which are right-angled triangles: along the floor from the
    // thin edge to the tall end, and up the tall end to the top of the slope.
    final thin = centre[axis] - uphill.sign * half[axis];
    final tall = centre[axis] + uphill.sign * half[axis];
    final bottom = centre.y - half.y;
    final top = centre.y + half.y;

    for (final outward in <double>[-1.0, 1.0]) {
      final faceNormal = Vector3.zero()..[side] = outward;
      final at = centre[side] + outward * half[side];
      final corners = <Vector3>[
        _at(axis, side, thin, bottom, at),
        _at(axis, side, tall, bottom, at),
        _at(axis, side, tall, top, at),
      ];
      // Wound from the geometry rather than from four cases worked out by
      // hand: a face wound the wrong way is culled as a back face, which looks
      // like a hole and not like a mistake.
      final winding = (corners[1] - corners[0]).cross(corners[2] - corners[0]);
      if (winding.dot(faceNormal) < 0.0) {
        final swap = corners[1];
        corners[1] = corners[2];
        corners[2] = swap;
      }

      // The face's own axes, so the texture runs along the level rather than
      // along the triangle. Any pair perpendicular to the normal will do; the
      // world projection makes the choice invisible across a seam.
      final faceU = Vector3.zero()..[axis] = 1.0;
      final faceV = faceNormal.cross(faceU);
      final base = out.vertexCount;
      for (final corner in corners) {
        out.addVertex(
          corner.x,
          corner.y,
          corner.z,
          faceNormal.x,
          faceNormal.y,
          faceNormal.z,
          faceU.x,
          faceU.y,
          faceU.z,
          corner.dot(faceU) * scale,
          corner.dot(faceV) * scale,
          lightmapU: lightmapU,
          lightmapV: lightmapV,
        );
      }
      out.addTriangle(base);
    }
  }

  /// A point given as a coordinate along the climb, a height, and the side.
  static Vector3 _at(
    int axis,
    int side,
    double along,
    double height,
    double across,
  ) {
    final point = Vector3(0.0, height, 0.0);
    point[axis] = along;
    point[side] = across;
    return point;
  }
}
