import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'lathe_shape.dart';
import 'shape.dart';

const double _tau = math.pi * 2.0;

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
