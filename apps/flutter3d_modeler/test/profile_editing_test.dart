/// `ProfileCurve`: `ui-13`'s own "чистый Dart" half — points and Bezier
/// segments, flattened to the polyline `AddLathe`/`LatheShape` take.
///
///     dart test test/profile_editing_test.dart
library;

import 'package:flutter3d_modeler/src/profile_editing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A fine, fixed sampling of a quadratic Bezier's own arc length — the
/// "true" length a flattened polyline's chord-length sum is checked
/// against, independent of [ProfileCurve]'s own subdivision.
double _quadraticArcLength(Vector2 p0, Vector2 c, Vector2 p1, {int steps = 20000}) {
  Vector2 at(double t) {
    final u = 1 - t;
    return p0 * (u * u) + c * (2 * u * t) + p1 * (t * t);
  }

  var length = 0.0;
  var previous = at(0.0);
  for (var i = 1; i <= steps; i++) {
    final point = at(i / steps);
    length += (point - previous).length;
    previous = point;
  }
  return length;
}

double _cubicArcLength(
  Vector2 p0,
  Vector2 c1,
  Vector2 c2,
  Vector2 p1, {
  int steps = 20000,
}) {
  Vector2 at(double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        c1 * (3 * u * u * t) +
        c2 * (3 * u * t * t) +
        p1 * (t * t * t);
  }

  var length = 0.0;
  var previous = at(0.0);
  for (var i = 1; i <= steps; i++) {
    final point = at(i / steps);
    length += (point - previous).length;
    previous = point;
  }
  return length;
}

double _chordLength(List<Vector2> polyline) {
  var length = 0.0;
  for (var i = 1; i < polyline.length; i++) {
    length += (polyline[i] - polyline[i - 1]).length;
  }
  return length;
}

void main() {
  test('a curve of only line segments flattens to exactly its own points', () {
    final curve = ProfileCurve(
      points: <ProfilePoint>[
        ProfilePoint(Vector2(0, 0)),
        ProfilePoint(Vector2(1, 2)),
        ProfilePoint(Vector2(1, 4)),
      ],
      segments: const <ProfileSegment>[LineSegment(), LineSegment()],
    );

    expect(curve.toPolyline(), <Vector2>[
      Vector2(0, 0),
      Vector2(1, 2),
      Vector2(1, 4),
    ]);
  });

  test('the constructor refuses a segment count that does not match the '
      'points', () {
    expect(
      () => ProfileCurve(
        points: <ProfilePoint>[
          ProfilePoint(Vector2(0, 0)),
          ProfilePoint(Vector2(1, 1)),
          ProfilePoint(Vector2(2, 2)),
        ],
        segments: const <ProfileSegment>[LineSegment()],
      ),
      throwsArgumentError,
    );
  });

  test('a closed curve wants as many segments as points, not one fewer', () {
    expect(
      () => ProfileCurve(
        points: <ProfilePoint>[
          ProfilePoint(Vector2(0, 0)),
          ProfilePoint(Vector2(1, 1)),
          ProfilePoint(Vector2(2, 0)),
        ],
        segments: const <ProfileSegment>[LineSegment(), LineSegment()],
        closed: true,
      ),
      throwsArgumentError,
    );
  });

  group('a quadratic segment', () {
    final p0 = Vector2(0, 0);
    final control = Vector2(2, 6);
    final p1 = Vector2(4, 0);

    test('the flattened chord length sum is within the flattening '
        'tolerance of the curve\'s own arc length', () {
      const tolerance = 0.01;
      final curve = ProfileCurve(
        points: <ProfilePoint>[ProfilePoint(p0), ProfilePoint(p1)],
        segments: <ProfileSegment>[QuadraticSegment(control)],
      );

      final polyline = curve.toPolyline(tolerance: tolerance);
      final chordLength = _chordLength(polyline);
      final arcLength = _quadraticArcLength(p0, control, p1);

      // A polyline inscribed in a curve is always the shorter of the two —
      // every chord is at most as long as the arc it replaces — so the
      // comparison only needs a one-sided bound.
      expect(chordLength, closeTo(arcLength, arcLength * 0.01));
      expect(chordLength, lessThanOrEqualTo(arcLength));
    });

    test('a tighter tolerance never produces fewer points than a looser one', () {
      final curve = ProfileCurve(
        points: <ProfilePoint>[ProfilePoint(p0), ProfilePoint(p1)],
        segments: <ProfileSegment>[QuadraticSegment(control)],
      );

      final loose = curve.toPolyline(tolerance: 1.0);
      final tight = curve.toPolyline(tolerance: 0.001);

      expect(tight.length, greaterThan(loose.length));
    });

    test('a control point exactly on the line needs no subdivision at all', () {
      final straight = Vector2(2, 0);
      final curve = ProfileCurve(
        points: <ProfilePoint>[ProfilePoint(p0), ProfilePoint(p1)],
        segments: <ProfileSegment>[QuadraticSegment(straight)],
      );

      expect(curve.toPolyline(tolerance: 0.01), <Vector2>[p0, p1]);
    });
  });

  group('a cubic segment', () {
    final p0 = Vector2(0, 0);
    final c1 = Vector2(1, 5);
    final c2 = Vector2(3, -5);
    final p1 = Vector2(4, 0);

    test('the flattened chord length sum is within the flattening '
        'tolerance of the curve\'s own arc length', () {
      const tolerance = 0.01;
      final curve = ProfileCurve(
        points: <ProfilePoint>[ProfilePoint(p0), ProfilePoint(p1)],
        segments: <ProfileSegment>[CubicSegment(c1, c2)],
      );

      final chordLength = _chordLength(curve.toPolyline(tolerance: tolerance));
      final arcLength = _cubicArcLength(p0, c1, c2, p1);

      expect(chordLength, closeTo(arcLength, arcLength * 0.01));
      expect(chordLength, lessThanOrEqualTo(arcLength));
    });
  });

  test('three points, a mix of a line and a quadratic, gives one chord '
      'plus several — the row\'s own worked example', () {
    final curve = ProfileCurve(
      points: <ProfilePoint>[
        ProfilePoint(Vector2(0, 0)),
        ProfilePoint(Vector2(2, 0)),
        ProfilePoint(Vector2(4, 0)),
      ],
      segments: <ProfileSegment>[
        const LineSegment(),
        QuadraticSegment(Vector2(3, 3)),
      ],
    );

    final polyline = curve.toPolyline(tolerance: 0.01);
    // The line segment contributes exactly its own endpoint; the curved
    // one contributes more than one chord, since it is not flat.
    expect(polyline.first, Vector2(0, 0));
    expect(polyline[1], Vector2(2, 0));
    expect(polyline.length, greaterThan(3));

    final arcLength =
        (Vector2(2, 0) - Vector2(0, 0)).length +
        _quadraticArcLength(Vector2(2, 0), Vector2(3, 3), Vector2(4, 0));
    expect(_chordLength(polyline), closeTo(arcLength, arcLength * 0.01));
  });

  test('a closed profile joins the last point back to the first', () {
    final curve = ProfileCurve(
      points: <ProfilePoint>[
        ProfilePoint(Vector2(0, 0)),
        ProfilePoint(Vector2(1, 0)),
        ProfilePoint(Vector2(1, 1)),
      ],
      segments: const <ProfileSegment>[
        LineSegment(),
        LineSegment(),
        LineSegment(),
      ],
      closed: true,
    );

    expect(curve.toPolyline(), <Vector2>[
      Vector2(0, 0),
      Vector2(1, 0),
      Vector2(1, 1),
      Vector2(0, 0),
    ]);
  });
}
