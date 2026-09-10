/// The primitives a modeller starts from, built as quads.
///
/// **The same six shapes the engine already has, built the other way.** A
/// `Shape` builds what a GPU draws: triangles, with a corner duplicated once
/// per normal meeting there. A modeller needs the surface those triangles came
/// from — four-sided faces, one vertex per corner, and a loop cut that has
/// something to run along. So these hold the same parameters as the engine's
/// shapes, and `toEditMesh` builds the editable version while [drawn] hands
/// back the engine's own for anything that only wants to see it.
///
/// **Sharp edges instead of duplicated points.** Where a `LatheShape` repeats a
/// profile point to break the tangent — a cylinder's rim, so the cap's normal
/// does not bleed into the wall — the editable version welds the two rows into
/// one and marks the ring of edges between them sharp. Both give the same
/// picture; one of them can be dragged.
///
/// **A flat cap is one face.** A band between the axis and a ring at the same
/// height is a disc, and a disc is an n-gon: the twelve triangles a fan would
/// make are twelve faces somebody has to select together. A band between the
/// axis and a ring at a *different* height is a cone's tip or a sphere's pole,
/// and that is a fan, because flattening it would flatten the shape.
///
/// **The texture coordinates are the engine's, corner for corner.** A face of a
/// box runs zero to one in both directions; a lathe runs `u` with the sweep and
/// `v` with arc length along the profile. `VertexLayout.standard` carries a
/// texcoord, so a cube that came out of here without one is a cube that takes
/// no texture in a GLB — which is the whole reason this is not left for later.
library;

import 'dart:math' as math;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';

/// A primitive a document can hold by its parameters rather than by its
/// geometry.
sealed class ParametricShape {
  const ParametricShape();

  /// What to call it.
  String get name;

  /// The engine's shape with the same parameters, for anything that wants the
  /// drawable mesh directly — and for the parity tests, which is how the two
  /// are kept saying the same thing.
  Shape get drawn;

  /// The editable mesh: quads, one vertex per corner, sharp where the engine
  /// duplicates.
  EditMesh toEditMesh();
}

/// A box, centred on the origin.
final class ParametricCuboid extends ParametricShape {
  ParametricCuboid({Vector3? size}) : size = size ?? Vector3(1, 1, 1);

  final Vector3 size;

  @override
  String get name => 'box';

  @override
  Shape get drawn => CuboidShape(size: size);

  /// Per face: the normal, then the U and V axes of its texture. The same
  /// table `CuboidShape` uses, and copied rather than derived because the two
  /// have to agree corner for corner — `cross(u, v)` is the normal for every
  /// entry, which is what makes the shared corner order wind outwards.
  static const List<List<List<double>>> _faces = <List<List<double>>>[
    <List<double>>[
      <double>[1, 0, 0],
      <double>[0, 0, -1],
      <double>[0, 1, 0],
    ],
    <List<double>>[
      <double>[-1, 0, 0],
      <double>[0, 0, 1],
      <double>[0, 1, 0],
    ],
    <List<double>>[
      <double>[0, 1, 0],
      <double>[1, 0, 0],
      <double>[0, 0, -1],
    ],
    <List<double>>[
      <double>[0, -1, 0],
      <double>[1, 0, 0],
      <double>[0, 0, 1],
    ],
    <List<double>>[
      <double>[0, 0, 1],
      <double>[1, 0, 0],
      <double>[0, 1, 0],
    ],
    <List<double>>[
      <double>[0, 0, -1],
      <double>[-1, 0, 0],
      <double>[0, 1, 0],
    ],
  ];

  static const List<List<double>> _corners = <List<double>>[
    <double>[-1, -1],
    <double>[1, -1],
    <double>[1, 1],
    <double>[-1, 1],
  ];

  @override
  EditMesh toEditMesh() {
    final half = size * 0.5;
    final builder = EditMeshBuilder();
    // Eight corners rather than twenty-four: the duplicates the engine needs
    // are per normal, and a normal is something the layout plan works out from
    // the flags on the way back out.
    final at = <String, int>{};
    int vertexAt(Vector3 point) => at.putIfAbsent(
      '${point.x},${point.y},${point.z}',
      () => builder.addVertex(point),
    );

    final uvs = <List<Vector2>>[];
    for (final face in _faces) {
      final normal = face[0];
      final uAxis = face[1];
      final vAxis = face[2];
      final loop = <int>[];
      final corners = <Vector2>[];
      for (final corner in _corners) {
        final cu = corner[0];
        final cv = corner[1];
        loop.add(
          vertexAt(
            Vector3(
              (normal[0] + uAxis[0] * cu + vAxis[0] * cv) * half.x,
              (normal[1] + uAxis[1] * cu + vAxis[1] * cv) * half.y,
              (normal[2] + uAxis[2] * cu + vAxis[2] * cv) * half.z,
            ),
          ),
        );
        corners.add(Vector2((cu + 1) * 0.5, (cv + 1) * 0.5));
      }
      builder.addFace(loop);
      uvs.add(corners);
    }

    final mesh = builder.build();
    mesh.beginStep();
    for (var face = 0; face < uvs.length; face++) {
      var corner = 0;
      mesh.forEachHalfEdge(face, (int half) {
        mesh.setUv(half, uvs[face][corner++]);
      });
    }
    mesh
      ..endStep()
      ..clearJournal();
    return mesh;
  }
}

/// A flat sheet in the XZ plane, facing +Y.
final class ParametricPlane extends ParametricShape {
  const ParametricPlane({
    this.width = 1.0,
    this.depth = 1.0,
    this.widthSegments = 1,
    this.depthSegments = 1,
  });

  final double width;
  final double depth;
  final int widthSegments;
  final int depthSegments;

  @override
  String get name => 'plane';

  @override
  Shape get drawn => PlaneShape(
    width: width,
    depth: depth,
    widthSegments: widthSegments,
    depthSegments: depthSegments,
  );

  @override
  EditMesh toEditMesh() {
    if (widthSegments < 1 || depthSegments < 1) {
      throw ArgumentError('a plane needs at least one segment each way');
    }
    final builder = EditMeshBuilder();
    for (var iz = 0; iz <= depthSegments; iz++) {
      for (var ix = 0; ix <= widthSegments; ix++) {
        builder.addVertex(
          Vector3(
            (ix / widthSegments - 0.5) * width,
            0,
            (iz / depthSegments - 0.5) * depth,
          ),
        );
      }
    }
    final stride = widthSegments + 1;
    for (var iz = 0; iz < depthSegments; iz++) {
      for (var ix = 0; ix < widthSegments; ix++) {
        final a = iz * stride + ix;
        // The engine's winding, so the front face is the +Y side.
        builder.addFace(<int>[a, a + stride, a + stride + 1, a + 1]);
      }
    }

    final mesh = builder.build();
    mesh.beginStep();
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      // Flat, so nothing breaks the shading; the smooth flag says so rather
      // than leaving a sheet of quads to guess.
      mesh.setFaceFlag(face, FaceFlags.smooth, on: true);
      mesh.forEachHalfEdge(face, (int half) {
        final at = mesh.positionOf(mesh.originOf(half));
        mesh.setUv(half, Vector2(at.x / width + 0.5, at.z / depth + 0.5));
      });
    }
    mesh
      ..endStep()
      ..clearJournal();
    return mesh;
  }
}

/// A profile swept around the Y axis: the shape the rounded primitives are.
final class ParametricLathe extends ParametricShape {
  const ParametricLathe({
    required this.profile,
    this.segments = 32,
    this.startAngle = 0.0,
    this.sweepAngle = math.pi * 2,
    this.closedProfile = false,
    this.name = 'lathe',
  });

  /// Points in the (radius, height) half-plane, bottom to top.
  final List<Vector2> profile;
  final int segments;
  final double startAngle;
  final double sweepAngle;

  /// Whether the last point joins back to the first, as a torus's does.
  final bool closedProfile;

  @override
  final String name;

  @override
  Shape get drawn => LatheShape(
    profile: profile,
    segments: segments,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    closedProfile: closedProfile,
    name: name,
  );

  @override
  EditMesh toEditMesh() => _lathe(this);
}

/// A ball, as rings of quads with a fan at each pole.
final class ParametricSphere extends ParametricShape {
  const ParametricSphere({
    this.radius = 0.5,
    this.segments = 32,
    this.rings = 16,
  });

  final double radius;
  final int segments;
  final int rings;

  @override
  String get name => 'sphere';

  @override
  Shape get drawn =>
      SphereShape(radius: radius, segments: segments, rings: rings);

  @override
  EditMesh toEditMesh() => _lathe(
    ParametricLathe(
      profile: <Vector2>[
        for (var k = 0; k <= rings; k++)
          () {
            final phi = -math.pi / 2 + math.pi * (k / rings);
            return Vector2(radius * math.cos(phi), radius * math.sin(phi));
          }(),
      ],
      segments: segments,
      name: name,
    ),
  );
}

/// A cylinder or a truncated cone, with flat caps as single faces.
final class ParametricCylinder extends ParametricShape {
  const ParametricCylinder({
    this.radiusTop = 0.5,
    this.radiusBottom = 0.5,
    this.height = 1.0,
    this.segments = 32,
    this.capped = true,
  });

  final double radiusTop;
  final double radiusBottom;
  final double height;
  final int segments;
  final bool capped;

  @override
  String get name =>
      radiusTop == 0.0 || radiusBottom == 0.0 ? 'cone' : 'cylinder';

  @override
  Shape get drawn => CylinderShape(
    radiusTop: radiusTop,
    radiusBottom: radiusBottom,
    height: height,
    segments: segments,
    capped: capped,
  );

  @override
  EditMesh toEditMesh() {
    final half = height * 0.5;
    return _lathe(
      ParametricLathe(
        profile: <Vector2>[
          if (capped && radiusBottom > 0) ...<Vector2>[
            Vector2(0, -half),
            Vector2(radiusBottom, -half),
          ],
          // Repeated, which is what the engine does to break the tangent — and
          // what becomes a sharp ring here.
          Vector2(radiusBottom, -half),
          Vector2(radiusTop, half),
          if (capped && radiusTop > 0) ...<Vector2>[
            Vector2(radiusTop, half),
            Vector2(0, half),
          ],
        ],
        segments: segments,
        name: name,
      ),
    );
  }
}

/// A ring, closed both ways round.
final class ParametricTorus extends ParametricShape {
  const ParametricTorus({
    this.radius = 0.35,
    this.tubeRadius = 0.15,
    this.segments = 48,
    this.tubeSegments = 24,
  });

  final double radius;
  final double tubeRadius;
  final int segments;
  final int tubeSegments;

  @override
  String get name => 'torus';

  @override
  Shape get drawn => TorusShape(
    radius: radius,
    tubeRadius: tubeRadius,
    segments: segments,
    tubeSegments: tubeSegments,
  );

  @override
  EditMesh toEditMesh() => _lathe(
    ParametricLathe(
      profile: <Vector2>[
        for (var k = 0; k < tubeSegments; k++)
          () {
            final phi = math.pi * 2 * (k / tubeSegments);
            return Vector2(
              radius + tubeRadius * math.cos(phi),
              tubeRadius * math.sin(phi),
            );
          }(),
      ],
      segments: segments,
      closedProfile: true,
      name: name,
    ),
  );
}

/// One run of profile rows that stand in the same place.
final class _Band {
  _Band(this.at, this.lowV, this.highV);

  /// Where the row is, in the (radius, height) half-plane.
  final Vector2 at;

  /// The texture coordinate the band *below* this row ends at, and the one the
  /// band above it starts at.
  ///
  /// The same number everywhere except at the seam of a closed profile, where
  /// the tube comes back to where it started and the arc length has run all
  /// the way to one — which is exactly the place a torus needs two.
  final double lowV;
  final double highV;

  bool get onAxis => at.x == 0;
}

/// Builds the editable mesh of a surface of revolution.
EditMesh _lathe(ParametricLathe spec) {
  if (spec.profile.length < 2) {
    throw ArgumentError('a revolution profile needs at least two points');
  }
  var widest = 0.0;
  for (final point in spec.profile) {
    if (point.x < 0) {
      throw ArgumentError('a profile radius must be at least zero');
    }
    if (point.x > widest) widest = point.x;
  }
  // The engine's rule, so a row that trigonometry left at 6e-17 is on the axis
  // here too — otherwise a pole comes out as a ring of hairs.
  final axisEpsilon = widest * 1e-6;
  final rows = <Vector2>[
    for (final point in spec.profile)
      point.x <= axisEpsilon ? Vector2(0, point.y) : point,
  ];
  if (spec.closedProfile) rows.add(rows.first);
  final vs = _arcLength(rows);

  // Rows standing in the same place become one, and the ring between them
  // becomes sharp.
  final bands = <_Band>[];
  final sharpBelow = <bool>[];
  for (var j = 0; j < rows.length; j++) {
    if (bands.isNotEmpty && _samePlace(rows[j], bands.last.at)) {
      // Nothing to carry over: two rows in the same place are no distance
      // apart, so the arc length has not moved and both sides of the ring
      // already read the same `v` — which is what the engine writes too.
      sharpBelow[bands.length - 1] = true;
      continue;
    }
    bands.add(_Band(rows[j], vs[j], vs[j]));
    sharpBelow.add(false);
  }
  // A closed profile ends where it started, so the last band and the first are
  // one ring — and that is not a hard edge, it is the tube closing.
  final closed =
      spec.closedProfile &&
      bands.length > 2 &&
      _samePlace(bands.first.at, bands.last.at);
  if (closed) {
    bands[0] = _Band(bands.first.at, bands.last.lowV, bands.first.highV);
    bands.removeLast();
    sharpBelow.removeLast();
  }

  final rings = closed ? bands.length : bands.length - 1;
  // A ring joins back to itself only when the sweep goes all the way round.
  // Welding the seam of a half-swept lathe would close a tube that is meant to
  // be a strip — the shape would gain a wall nobody asked for and lose its rim.
  final wholeTurn = (spec.sweepAngle.abs() - math.pi * 2).abs() < 1e-9;
  final columns = wholeTurn ? spec.segments : spec.segments + 1;

  /// Whether a band on the axis is the apex of a fan. One that is not is the
  /// middle of a flat disc, and a disc is an n-gon with no middle — putting a
  /// vertex there anyway would leave a cylinder with two points no face
  /// reaches, which is exactly what `MeshChecks` calls an isolated vertex.
  final axisUsed = List<bool>.filled(bands.length, false);
  for (var band = 0; band < rings; band++) {
    final low = bands[band];
    final high = bands[(band + 1) % bands.length];
    if (low.onAxis && high.onAxis) continue;
    if (low.at.y == high.at.y && (low.onAxis || high.onAxis)) continue;
    if (low.onAxis) axisUsed[band] = true;
    if (high.onAxis) axisUsed[(band + 1) % bands.length] = true;
  }

  final builder = EditMeshBuilder();
  // Where each band's ring of vertices starts, or the single vertex it is.
  final ringAt = <int>[];
  for (var index = 0; index < bands.length; index++) {
    final band = bands[index];
    if (band.onAxis && !axisUsed[index]) {
      ringAt.add(EditMesh.none);
      continue;
    }
    ringAt.add(builder.vertexCount);
    if (band.onAxis) {
      builder.addVertex(Vector3(0, band.at.y, 0));
      continue;
    }
    for (var i = 0; i < columns; i++) {
      final angle = spec.startAngle + spec.sweepAngle * (i / spec.segments);
      builder.addVertex(
        Vector3(
          band.at.x * math.cos(angle),
          band.at.y,
          band.at.x * math.sin(angle),
        ),
      );
    }
  }

  int vertexAt(int band, int column) => bands[band].onAxis
      ? ringAt[band]
      : ringAt[band] + (wholeTurn ? column % spec.segments : column);

  // Faces, and what each corner's texture coordinate is. The corners are
  // written down as the faces are built, because a welded seam means the two
  // sides of it carry different `u` for the same vertex.
  final corners = <List<Vector2>>[];
  final sharpFaces = <List<bool>>[];

  void quad(List<int> loop, List<Vector2> uvs, List<bool> sharp) {
    builder.addFace(loop);
    corners.add(uvs);
    sharpFaces.add(sharp);
  }

  double uAt(int column) => column / spec.segments;

  for (var band = 0; band < rings; band++) {
    final low = bands[band];
    final high = bands[(band + 1) % bands.length];
    if (low.onAxis && high.onAxis) continue;
    final hard = sharpBelow[(band + 1) % bands.length];

    // A flat disc between the axis and a ring is one face; a cone's tip or a
    // sphere's pole is a fan, because a disc there would flatten the shape.
    if (low.onAxis && low.at.y == high.at.y) {
      quad(
        <int>[for (var i = 0; i < spec.segments; i++) vertexAt(band + 1, i)],
        <Vector2>[
          for (var i = 0; i < spec.segments; i++) Vector2(uAt(i), high.lowV),
        ],
        <bool>[for (var i = 0; i < spec.segments; i++) hard],
      );
      continue;
    }
    if (high.onAxis && low.at.y == high.at.y) {
      quad(
        <int>[for (var i = spec.segments - 1; i >= 0; i--) vertexAt(band, i)],
        <Vector2>[
          for (var i = spec.segments - 1; i >= 0; i--)
            Vector2(uAt(i), low.highV),
        ],
        <bool>[for (var i = 0; i < spec.segments; i++) hard],
      );
      continue;
    }

    for (var i = 0; i < spec.segments; i++) {
      final loop = <int>[];
      final uvs = <Vector2>[];
      final sharp = <bool>[];
      void corner(int atBand, int column, double v) {
        loop.add(vertexAt(atBand, column));
        uvs.add(Vector2(uAt(column), v));
      }

      // A half-edge runs from its own corner to the next, so the flag for a
      // ring of edges goes on the corner the ring *leaves* — which is not the
      // corner standing on it.
      if (low.onAxis) {
        // A fan triangle: along the ring, then up to the apex and back.
        corner(band + 1, i, high.lowV);
        corner(band + 1, i + 1, high.lowV);
        corner(band, i, low.highV);
        sharp
          ..add(hard)
          ..add(false)
          ..add(false);
      } else if (high.onAxis) {
        corner(band, i, low.highV);
        corner(band + 1, i, high.lowV);
        corner(band, i + 1, low.highV);
        sharp
          ..add(false)
          ..add(false)
          ..add(sharpBelow[band]);
      } else {
        corner(band, i, low.highV);
        corner((band + 1) % bands.length, i, high.lowV);
        corner((band + 1) % bands.length, i + 1, high.lowV);
        corner(band, i + 1, low.highV);
        sharp
          ..add(false)
          ..add(hard)
          ..add(false)
          ..add(sharpBelow[band]);
      }
      // The far side of a welded seam runs to one rather than back to zero,
      // which is what a per-corner texture coordinate is for. A lathe that
      // does not go all the way round has no seam and needs none of this.
      if (wholeTurn) {
        for (var at = 0; at < loop.length; at++) {
          if (uvs[at].x == 0 && at > 0 && uvs[at - 1].x > 0.5) {
            uvs[at] = Vector2(1, uvs[at].y);
          }
        }
      }
      quad(loop, uvs, sharp);
    }
  }

  final mesh = builder.build();
  mesh.beginStep();
  for (var face = 0; face < corners.length; face++) {
    // Round, unless a ring says otherwise — which is the whole difference
    // between this and a box.
    mesh.setFaceFlag(face, FaceFlags.smooth, on: true);
    var at = 0;
    mesh.forEachHalfEdge(face, (int half) {
      final index = at++;
      mesh.setUv(half, corners[face][index]);
      if (sharpFaces[face][index]) {
        mesh.setEdgeFlag(half, EdgeFlags.sharp, on: true);
      }
    });
  }
  mesh
    ..endStep()
    ..clearJournal();
  return mesh;
}

bool _samePlace(Vector2 a, Vector2 b) => a.x == b.x && a.y == b.y;

/// Normalised cumulative arc length along the profile — the engine's own `v`.
List<double> _arcLength(List<Vector2> rows) {
  final lengths = List<double>.filled(rows.length, 0);
  var total = 0.0;
  for (var j = 1; j < rows.length; j++) {
    total += (rows[j] - rows[j - 1]).length;
    lengths[j] = total;
  }
  if (total == 0) {
    for (var j = 0; j < rows.length; j++) {
      lengths[j] = rows.length == 1 ? 0 : j / (rows.length - 1);
    }
    return lengths;
  }
  for (var j = 0; j < rows.length; j++) {
    lengths[j] /= total;
  }
  return lengths;
}
