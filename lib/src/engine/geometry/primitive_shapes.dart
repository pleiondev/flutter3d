import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'lathe_shape.dart';
import 'mesh_data.dart';
import 'shape.dart';
import 'vertex_layout.dart';

const double _tau = math.pi * 2.0;

/// Axis-aligned box centred on the origin.
///
/// Uses 24 vertices rather than 8: each face needs its own normal and UV set, and
/// sharing corners would average the normals into something round.
///
/// Named "cuboid" rather than "box" because `flutter/material.dart` exports a
/// `BoxShape` enum, and a clash there would force every app importing both to
/// disambiguate.
class CuboidShape extends Shape {
  CuboidShape({Vector3? size}) : size = size ?? Vector3.all(1.0);

  final Vector3 size;

  @override
  String get name => 'box';

  // Per face: normal, then the U and V axes of the face. cross(u, v) == normal
  // for every entry, which is what makes the shared corner order wind
  // counter-clockwise as seen from outside.
  static const List<List<List<double>>> _faces = <List<List<double>>>[
    [[1, 0, 0], [0, 0, -1], [0, 1, 0]],
    [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    [[0, 1, 0], [1, 0, 0], [0, 0, -1]],
    [[0, -1, 0], [1, 0, 0], [0, 0, 1]],
    [[0, 0, 1], [1, 0, 0], [0, 1, 0]],
    [[0, 0, -1], [-1, 0, 0], [0, 1, 0]],
  ];

  static const List<List<double>> _corners = <List<double>>[
    [-1, -1],
    [1, -1],
    [1, 1],
    [-1, 1],
  ];

  @override
  MeshData build({
    VertexLayout layout = VertexLayout.standard,
  }) {
    final half = size * 0.5;
    final builder =
        MeshBuilder(layout, reserveVertices: 24, reserveIndices: 36);
    final position = Vector3.zero();
    final normal = Vector3.zero();
    final texcoord = Vector2.zero();

    // Each face's UV axes are declared above, so the tangent is exactly the U
    // axis — no need to recover it from UV differences. cross(u, v) is the
    // normal for every entry, which makes cross(normal, tangent) equal the V
    // axis; glTF wants the bitangent to be *minus* dP/dv, so the sign is -1.
    final tangent = Vector4.zero();

    for (final face in _faces) {
      normal.setValues(face[0][0], face[0][1], face[0][2]);
      final uAxis = face[1];
      final vAxis = face[2];
      tangent.setValues(uAxis[0], uAxis[1], uAxis[2], -1.0);
      final base = builder.vertexCount;

      for (final corner in _corners) {
        final cu = corner[0];
        final cv = corner[1];
        position.setValues(
          (normal.x + uAxis[0] * cu + vAxis[0] * cv) * half.x,
          (normal.y + uAxis[1] * cu + vAxis[1] * cv) * half.y,
          (normal.z + uAxis[2] * cu + vAxis[2] * cv) * half.z,
        );
        texcoord.setValues((cu + 1.0) * 0.5, (cv + 1.0) * 0.5);
        builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
          tangent: tangent,
        );
      }

      builder.addQuad(base, base + 1, base + 2, base + 3);
    }

    return builder.build();
  }
}

/// Subdivided plane in the XZ plane, normal pointing at +Y.
class PlaneShape extends Shape {
  const PlaneShape({
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
  MeshData build({
    VertexLayout layout = VertexLayout.standard,
  }) {
    if (widthSegments < 1 || depthSegments < 1) {
      throw ArgumentError('Plane segment counts must be >= 1.');
    }

    final builder = MeshBuilder(
      layout,
      reserveVertices: (widthSegments + 1) * (depthSegments + 1),
      reserveIndices: widthSegments * depthSegments * 6,
    );
    final normal = Vector3(0.0, 1.0, 0.0);
    final position = Vector3.zero();
    final texcoord = Vector2.zero();
    // U runs along +X and V along +Z, so cross(normal, +X) is -Z, which is
    // already minus dP/dv — the sign is positive.
    final tangent = Vector4(1.0, 0.0, 0.0, 1.0);

    for (var iz = 0; iz <= depthSegments; iz++) {
      final tz = iz / depthSegments;
      for (var ix = 0; ix <= widthSegments; ix++) {
        final tx = ix / widthSegments;
        position.setValues((tx - 0.5) * width, 0.0, (tz - 0.5) * depth);
        texcoord.setValues(tx, tz);
        builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
          tangent: tangent,
        );
      }
    }

    final rowStride = widthSegments + 1;
    for (var iz = 0; iz < depthSegments; iz++) {
      for (var ix = 0; ix < widthSegments; ix++) {
        final a = iz * rowStride + ix;
        final b = a + 1;
        final c = a + rowStride + 1;
        final d = a + rowStride;
        // Winding chosen so the front face is the +Y side.
        builder.addQuad(a, d, c, b);
      }
    }

    return builder.build();
  }
}

/// UV sphere, a revolved meridian arc.
///
/// [rings] counts the segments from pole to pole, so the pole rows land exactly
/// on the axis and [LatheShape] drops the degenerate triangles there.
class SphereShape extends DerivedShape {
  const SphereShape({
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
  Shape get delegate {
    if (rings < 2) throw ArgumentError('rings must be >= 2, got $rings.');

    final profile = <Vector2>[];
    final normals = <Vector2>[];
    for (var k = 0; k <= rings; k++) {
      final phi = -math.pi / 2.0 + math.pi * (k / rings);
      final cosPhi = math.cos(phi);
      final sinPhi = math.sin(phi);
      profile.add(Vector2(radius * cosPhi, radius * sinPhi));
      // A sphere normal is radial by definition, so supply it instead of letting
      // chords approximate it.
      normals.add(Vector2(cosPhi, sinPhi));
    }

    return LatheShape(
      profile: profile,
      profileNormals: normals,
      segments: segments,
      name: name,
    );
  }
}

/// Cylinder or truncated cone, centred on the origin, axis along Y.
///
/// Caps are part of the profile rather than separate meshes, so the rim stays a
/// single watertight surface, and the repeated rim points give it a hard edge.
class CylinderShape extends DerivedShape {
  const CylinderShape({
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
  String get name => radiusTop == 0.0 || radiusBottom == 0.0 ? 'cone' : 'cylinder';

  @override
  Shape get delegate {
    if (radiusTop <= 0.0 && radiusBottom <= 0.0) {
      throw ArgumentError('At least one of the cylinder radii must be > 0.');
    }

    final halfHeight = height * 0.5;
    final profile = <Vector2>[];

    if (capped && radiusBottom > 0.0) {
      profile.add(Vector2(0.0, -halfHeight));
      profile.add(Vector2(radiusBottom, -halfHeight));
    }
    // Repeated rim point: breaks the tangent so the cap normal does not bleed
    // into the wall.
    profile.add(Vector2(radiusBottom, -halfHeight));
    profile.add(Vector2(radiusTop, halfHeight));
    if (capped && radiusTop > 0.0) {
      profile.add(Vector2(radiusTop, halfHeight));
      profile.add(Vector2(0.0, halfHeight));
    }

    return LatheShape(profile: profile, segments: segments, name: name);
  }
}

/// Cone with the apex at +Y: a cylinder whose top radius is zero.
class ConeShape extends DerivedShape {
  const ConeShape({
    this.radius = 0.5,
    this.height = 1.0,
    this.segments = 32,
    this.capped = true,
  });

  final double radius;
  final double height;
  final int segments;
  final bool capped;

  @override
  String get name => 'cone';

  @override
  Shape get delegate => CylinderShape(
        radiusTop: 0.0,
        radiusBottom: radius,
        height: height,
        segments: segments,
        capped: capped,
      );
}

/// Torus: a closed circular profile revolved around Y.
class TorusShape extends DerivedShape {
  const TorusShape({
    this.radius = 0.35,
    this.tubeRadius = 0.15,
    this.segments = 48,
    this.tubeSegments = 24,
  });

  /// Distance from the origin to the tube centre.
  final double radius;

  /// The tube's own radius.
  final double tubeRadius;

  final int segments;
  final int tubeSegments;

  @override
  String get name => 'torus';

  @override
  Shape get delegate {
    if (tubeSegments < 3) {
      throw ArgumentError('tubeSegments must be >= 3, got $tubeSegments.');
    }

    final profile = <Vector2>[];
    for (var k = 0; k < tubeSegments; k++) {
      final phi = _tau * (k / tubeSegments);
      profile.add(
        Vector2(
          radius + tubeRadius * math.cos(phi),
          tubeRadius * math.sin(phi),
        ),
      );
    }

    return LatheShape(
      profile: profile,
      segments: segments,
      closedProfile: true,
      name: name,
    );
  }
}

/// Capsule: a cylinder of [height] closed by two hemispheres of [radius].
///
/// The profile has no repeated points, so the hemisphere-to-wall junction stays
/// smooth.
class CapsuleShape extends DerivedShape {
  const CapsuleShape({
    this.radius = 0.3,
    this.height = 0.5,
    this.segments = 32,
    this.rings = 8,
  });

  final double radius;
  final double height;
  final int segments;
  final int rings;

  @override
  String get name => 'capsule';

  @override
  Shape get delegate {
    if (rings < 1) throw ArgumentError('rings must be >= 1, got $rings.');

    final halfHeight = height * 0.5;
    final profile = <Vector2>[];
    final normals = <Vector2>[];

    void addHemisphereRow(double phi, double centreY) {
      final cosPhi = math.cos(phi);
      final sinPhi = math.sin(phi);
      profile.add(Vector2(radius * cosPhi, centreY + radius * sinPhi));
      // Normals are radial about the corresponding hemisphere centre, which is
      // also correct along the cylindrical middle where phi is 0.
      normals.add(Vector2(cosPhi, sinPhi));
    }

    for (var k = 0; k <= rings; k++) {
      addHemisphereRow(
        -math.pi / 2.0 + (math.pi / 2.0) * (k / rings),
        -halfHeight,
      );
    }
    for (var k = 0; k <= rings; k++) {
      addHemisphereRow((math.pi / 2.0) * (k / rings), halfHeight);
    }

    return LatheShape(
      profile: profile,
      profileNormals: normals,
      segments: segments,
      name: name,
    );
  }
}

/// Flat annulus in the XZ plane facing +Y. An [innerRadius] of 0 gives a disc.
///
/// The profile runs outer-to-inner: profile direction sets both the normal and
/// the winding, so reversing it is all that is needed to face the surface the
/// other way.
class DiscShape extends DerivedShape {
  const DiscShape({
    this.radius = 0.5,
    this.innerRadius = 0.0,
    this.segments = 32,
  });

  final double radius;
  final double innerRadius;
  final int segments;

  @override
  String get name => innerRadius > 0.0 ? 'annulus' : 'disc';

  @override
  Shape get delegate {
    if (innerRadius < 0.0 || innerRadius >= radius) {
      throw ArgumentError('Expected 0 <= innerRadius < radius.');
    }
    return LatheShape(
      profile: <Vector2>[Vector2(radius, 0.0), Vector2(innerRadius, 0.0)],
      segments: segments,
      name: name,
    );
  }
}
