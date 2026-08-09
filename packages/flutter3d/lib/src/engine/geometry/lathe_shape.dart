import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'mesh_data.dart';
import 'shape.dart';
import 'vertex_layout.dart';

const double _tau = math.pi * 2.0;

/// A surface of revolution: a profile polyline swept around the Y axis.
///
/// This is the generator the rounded primitives are built from, which is why it
/// is a class rather than a function — [SphereShape], [CylinderShape],
/// [TorusShape] and friends hold one of these and expose friendlier parameters.
///
/// [profile] lives in the (radius, height) half-plane: `x` is the distance from
/// the Y axis and must be >= 0, `y` is the position along it.
///
/// Orientation follows the profile direction, consistently for both normals and
/// winding: a profile ordered bottom-to-top yields outward normals and
/// counter-clockwise front faces. Reverse the profile to get an inside-out
/// surface (useful for skyboxes) without touching any other flag.
///
/// Normals are derived analytically from the profile tangent rather than by
/// averaging face normals, which keeps cones and poles exact. Repeating a profile
/// point produces a hard edge: the duplicated pair has a zero-length delta on one
/// side, so each copy falls back to its own one-sided tangent. That is how
/// [CylinderShape] gets crisp rims where the caps meet the wall.
///
/// UVs use `u = angle / sweepAngle` and `v = normalized arc length` along the
/// profile. Arc length, rather than point index, keeps texels from bunching up
/// where the profile is finely subdivided.
///
/// Derived normals come from chords, which is exact for straight profile segments
/// but first-order wrong at the ends of a curved profile: at a sphere pole built
/// from 16 rings the error is about 5.6 degrees. Pass [profileNormals] when the
/// profile has a known analytic normal, as [SphereShape] and [CapsuleShape] do.
class LatheShape extends Shape {
  const LatheShape({
    required this.profile,
    this.segments = 32,
    this.startAngle = 0.0,
    this.sweepAngle = _tau,
    this.closedProfile = false,
    this.profileNormals,
    this.name = 'lathe',
  });

  final List<Vector2> profile;
  final int segments;
  final double startAngle;
  final double sweepAngle;

  /// Whether the profile's last point connects back to its first.
  final bool closedProfile;

  /// Optional exact normals, one `(radial, axial)` vector per profile point.
  final List<Vector2>? profileNormals;

  @override
  final String name;

  @override
  MeshData build({
    VertexLayout layout = VertexLayout.standard,
  }) {
    final normals = profileNormals;
    if (profile.length < 2) {
      throw ArgumentError('A revolution profile needs at least 2 points.');
    }
    if (segments < 3) {
      throw ArgumentError('segments must be >= 3, got $segments.');
    }
    if (normals != null && normals.length != profile.length) {
      throw ArgumentError(
        'profileNormals has ${normals.length} entries but profile has '
        '${profile.length}.',
      );
    }

    var maxRadius = 0.0;
    for (final point in profile) {
      if (point.x < 0.0) {
        throw ArgumentError(
          'Profile radius must be >= 0, got ${point.x}. The profile lives in '
          'the half-plane on one side of the axis.',
        );
      }
      if (point.x > maxRadius) maxRadius = point.x;
    }

    // Rows exactly on the axis need exact zeros: they are what marks the
    // degenerate triangles to drop, and trigonometry rarely lands on zero
    // (`cos(-pi/2)` is 6.1e-17). Snapping relative to the profile size keeps this
    // scale-invariant and also closes the micro-gap such a row would leave.
    final axisEpsilon = maxRadius * 1e-6;
    final snapped = <Vector2>[
      for (final point in profile)
        point.x <= axisEpsilon ? Vector2(0.0, point.y) : point,
    ];

    // Closing the profile means repeating the first point as an extra row, so the
    // seam gets its own UV column while sharing the first row's normal.
    final rows = <Vector2>[
      ...snapped,
      if (closedProfile) snapped.first,
    ];
    final rowCount = rows.length;

    final planeNormals = normals == null
        ? _profileNormals(rows)
        : <Vector2>[
            for (final n in normals) n.normalized(),
            if (closedProfile) normals.first.normalized(),
          ];
    final vCoords = _arcLengthParameters(rows);

    final columnCount = segments + 1;
    final builder = MeshBuilder(
      layout,
      reserveVertices: columnCount * rowCount,
      reserveIndices: segments * (rowCount - 1) * 6,
    );

    final position = Vector3.zero();
    final normal = Vector3.zero();
    final texcoord = Vector2.zero();
    final tangent = Vector4.zero();

    // The tangent of a surface of revolution is known in closed form, so there
    // is no reason to derive it from UV differences the way a general mesh has
    // to. U runs with the sweep angle, and dP/du is the circumferential
    // direction whatever the profile does.
    //
    // The bitangent sign follows: dP/dv works out to minus cross(normal,
    // tangent), and glTF's bitangent is minus dP/dv, so w is +1 — flipping with
    // a negative sweep, because then U runs the other way.
    final sweepSign = sweepAngle < 0.0 ? -1.0 : 1.0;
    final bitangentSign = sweepSign;

    for (var i = 0; i < columnCount; i++) {
      final t = i / segments;
      final angle = startAngle + sweepAngle * t;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      tangent.setValues(
        -sinA * sweepSign,
        0.0,
        cosA * sweepSign,
        bitangentSign,
      );

      for (var j = 0; j < rowCount; j++) {
        final radius = rows[j].x;
        final planeNormal = planeNormals[j];

        position.setValues(radius * cosA, rows[j].y, radius * sinA);
        normal.setValues(
          planeNormal.x * cosA,
          planeNormal.y,
          planeNormal.x * sinA,
        );
        // A degenerate profile can still yield a zero normal; leave it rather
        // than emit NaN.
        if (normal.length2 > 0.0) normal.normalize();
        texcoord.setValues(t, vCoords[j]);

        builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
          tangent: tangent,
        );
      }
    }

    int indexAt(int column, int row) => column * rowCount + row;

    for (var i = 0; i < segments; i++) {
      for (var j = 0; j < rowCount - 1; j++) {
        final a = indexAt(i, j);
        final b = indexAt(i + 1, j);
        final c = indexAt(i + 1, j + 1);
        final d = indexAt(i, j + 1);

        // On the axis a whole quad edge collapses to a point. Those triangles
        // have zero area, so skip them instead of shipping degenerate geometry
        // to the rasterizer: at a sphere pole that is a full ring of them.
        final bottomOnAxis = rows[j].x == 0.0;
        final topOnAxis = rows[j + 1].x == 0.0;
        if (bottomOnAxis && topOnAxis) continue;

        if (!bottomOnAxis) builder.addTriangle(a, d, b);
        if (!topOnAxis) builder.addTriangle(b, d, c);
      }
    }

    return builder.build();
  }

  /// Per-row normals in the (radial, axial) plane.
  ///
  /// The normal is the profile tangent rotated by -90 degrees, which for a
  /// bottom-to-top profile points away from the axis.
  List<Vector2> _profileNormals(List<Vector2> rows) {
    final count = rows.length;
    final result = List<Vector2>.generate(count, (_) => Vector2(1.0, 0.0));

    for (var j = 0; j < count; j++) {
      Vector2? backward;
      if (j > 0) {
        backward = rows[j] - rows[j - 1];
      } else if (closedProfile) {
        // rows already ends with a copy of rows[0], so the real predecessor of
        // row 0 is two from the end.
        backward = rows[0] - rows[count - 2];
      }

      Vector2? forward;
      if (j < count - 1) {
        forward = rows[j + 1] - rows[j];
      } else if (closedProfile) {
        forward = rows[1] - rows[j];
      }

      // A zero-length delta marks a repeated point, i.e. a requested hard edge.
      if (backward != null && backward.length2 == 0.0) backward = null;
      if (forward != null && forward.length2 == 0.0) forward = null;

      Vector2 tangent;
      if (backward != null && forward != null) {
        tangent = backward.normalized() + forward.normalized();
        if (tangent.length2 == 0.0) {
          // The profile doubles back on itself; pick one side.
          tangent = forward.normalized();
        } else {
          tangent.normalize();
        }
      } else if (forward != null) {
        tangent = forward.normalized();
      } else if (backward != null) {
        tangent = backward.normalized();
      } else {
        tangent = Vector2(0.0, 1.0);
      }

      result[j] = Vector2(tangent.y, -tangent.x);
    }

    return result;
  }

  /// Normalized cumulative arc length along the profile, used as the V coordinate.
  List<double> _arcLengthParameters(List<Vector2> rows) {
    final count = rows.length;
    final lengths = List<double>.filled(count, 0.0);
    var total = 0.0;

    for (var j = 1; j < count; j++) {
      total += (rows[j] - rows[j - 1]).length;
      lengths[j] = total;
    }

    if (total == 0.0) {
      // Fully degenerate profile: fall back to index parametrization so UVs stay
      // finite.
      for (var j = 0; j < count; j++) {
        lengths[j] = count == 1 ? 0.0 : j / (count - 1);
      }
      return lengths;
    }

    for (var j = 0; j < count; j++) {
      lengths[j] /= total;
    }
    return lengths;
  }
}
