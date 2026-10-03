/// Where an orthographic camera's near shadow cascades go — `P7`.
///
/// Split out of the shadow pass because it is geometry with no device in it:
/// which part of the world an orthographic view can see, cut into slabs along
/// its axis, and the sphere round each slab. A test can ask it directly.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// One near cascade of an orthographic view: the depth along the view axis
/// where it ends, and the sphere its map is fitted to.
typedef OrthographicCascade = ({double end, Vector3 centre, double radius});

/// The [slabs] near cascades for an orthographic [viewProjection].
///
/// **Split evenly by depth, and fitted to what the view can see.** The split a
/// perspective camera gets runs from a metre in front of the eye, half way to
/// logarithmic, because through that lens a texel on screen covers more world
/// the further away it is. Through an orthographic lens every metre of depth
/// gets the same texels on screen, and the eye is only where the camera was
/// put along its axis — often tens of metres back, so the perspective split
/// spent the near cascades on air and dropped everything into the last and
/// softest one. Here the depths that matter are the ones where the view box
/// meets the casters' bounds, [boundsMin] to [boundsMax]; that range, capped
/// at [reach] metres past its start, is cut into [slabs] equal slabs, and each
/// slab's sphere is fitted to the corners of its own share of the box and the
/// bounds. An isometric camera over a long floor gets strips across the
/// screen, each a fraction of the level wide.
///
/// Depth is measured as the shaders measure it — `ViewDepth` in `color.glsl`:
/// along [forward] from [eye]. [viewProjection] is in the engine's own
/// convention, depth nought to one; the view box is read off its rows, so a
/// projection with an offset or a tilt is handled the same as a centred one.
///
/// The slab ends and every radius are rounded onto a grid of their own size,
/// so that a camera panning by less than a step, or a caster that moves,
/// leaves the maps' texels where they were — see [_quantum].
///
/// When the view sees none of the bounds, the slabs are cut from the view box
/// alone: nothing in it casts, and any fit is as good as another.
List<OrthographicCascade> orthographicCascades({
  required Matrix4 viewProjection,
  required Vector3 eye,
  required Vector3 forward,
  required Vector3 boundsMin,
  required Vector3 boundsMax,
  required int slabs,
  required double reach,
}) {
  final view = _viewBox(viewProjection);
  final bounds = <_HalfSpace>[
    (normal: Vector3(1.0, 0.0, 0.0), offset: -boundsMin.x),
    (normal: Vector3(-1.0, 0.0, 0.0), offset: boundsMax.x),
    (normal: Vector3(0.0, 1.0, 0.0), offset: -boundsMin.y),
    (normal: Vector3(0.0, -1.0, 0.0), offset: boundsMax.y),
    (normal: Vector3(0.0, 0.0, 1.0), offset: -boundsMin.z),
    (normal: Vector3(0.0, 0.0, -1.0), offset: boundsMax.z),
  ];
  double depthOf(Vector3 point) => (point - eye).dot(forward);

  final seen = _corners(<_HalfSpace>[...view, ...bounds]);
  final volume = seen.isEmpty ? view : <_HalfSpace>[...view, ...bounds];
  final corners = seen.isEmpty ? _corners(view) : seen;
  final depths = corners.map(depthOf);
  final start = depths.fold(double.infinity, math.min);
  final far = depths.fold(double.negativeInfinity, math.max);
  // A sliver at least, so a view that meets the bounds in a plane still has
  // slabs with an inside.
  final end = math.max(math.min(far, start + reach), start + 1e-3);
  // Both ends on a grid, so a pan or a caster that moves a little leaves the
  // slabs where they were — see [_quantum].
  final step = _quantum(end - start);
  final from = (start / step).floorToDouble() * step;
  final to = (end / step).ceilToDouble() * step;

  return <OrthographicCascade>[
    for (var i = 0; i < slabs; i++)
      _fit(
        volume,
        eye: eye,
        forward: forward,
        from: from + (to - from) * i / slabs,
        to: from + (to - from) * (i + 1) / slabs,
      ),
  ];
}

/// A step for rounding a length of about [length]: a sixteenth of the power of
/// two at or above it.
///
/// **Rounded, because the fit moves with everything.** The corners a slab is
/// fitted to are where the view box meets the casters' bounds, so they slide
/// with every pan of the camera and every caster that rises or falls — a
/// character jumping is enough. The shadow pass snaps each map to whole
/// texels of its radius, and a radius that changes every frame is a texel
/// grid that rescales every frame: shadow edges crawl, and the scroll that
/// keeps a still tile from being redrawn refuses a map whose scale changed.
/// On steps a sixteenth of the length's power of two the radius and the slab
/// ends stay put until the fit has moved by a whole step, and a radius
/// rounded up wastes at most an eighth of the map.
double _quantum(double length) =>
    math.pow(2.0, (math.log(math.max(length, 1e-3)) / math.ln2).ceil()) / 16.0;

/// [length] rounded up to its [_quantum].
double _roundUp(double length) {
  final step = _quantum(length);
  return (length / step).ceilToDouble() * step;
}

/// `normal · p + offset ≥ 0` for every point p inside.
typedef _HalfSpace = ({Vector3 normal, double offset});

/// The six half-spaces of an orthographic view box, from its matrix's rows:
/// clip x and y between −w and w, z between nought and w.
List<_HalfSpace> _viewBox(Matrix4 m) {
  _HalfSpace row(double sx, double sy, double sz, double sw) {
    // Row r of the matrix is (m[r], m[r + 4], m[r + 8], m[r + 12]).
    final s = m.storage;
    double at(int column) =>
        sx * s[column * 4] +
        sy * s[column * 4 + 1] +
        sz * s[column * 4 + 2] +
        sw * s[column * 4 + 3];
    return (normal: Vector3(at(0), at(1), at(2)), offset: at(3));
  }

  return <_HalfSpace>[
    row(1.0, 0.0, 0.0, 1.0),
    row(-1.0, 0.0, 0.0, 1.0),
    row(0.0, 1.0, 0.0, 1.0),
    row(0.0, -1.0, 0.0, 1.0),
    row(0.0, 0.0, 1.0, 0.0),
    row(0.0, 0.0, -1.0, 1.0),
  ];
}

/// The slab of [volume] between depths [from] and [to], as a sphere.
OrthographicCascade _fit(
  List<_HalfSpace> volume, {
  required Vector3 eye,
  required Vector3 forward,
  required double from,
  required double to,
}) {
  final corners = _corners(<_HalfSpace>[
    ...volume,
    (normal: forward, offset: -(from + eye.dot(forward))),
    (normal: -forward, offset: to + eye.dot(forward)),
  ]);
  if (corners.isEmpty) {
    // Only a degenerate box gets here; a point on the axis is still a sphere
    // the shader can fall through.
    return (
      end: to,
      centre: eye + forward.scaled((from + to) * 0.5),
      radius: math.max((to - from) * 0.5, 1e-3),
    );
  }
  final low = corners.fold(Vector3.all(double.infinity), (a, b) {
    Vector3.min(a, b, a);
    return a;
  });
  final high = corners.fold(Vector3.all(double.negativeInfinity), (a, b) {
    Vector3.max(a, b, a);
    return a;
  });
  final centre = (low + high)..scale(0.5);
  final radius = corners.fold(
    0.0,
    (r, corner) => math.max(r, corner.distanceTo(centre)),
  );
  return (end: to, centre: centre, radius: _roundUp(math.max(radius, 1e-3)));
}

/// The corners of the convex volume [planes] bound: every point where three
/// of them meet that lies inside the rest.
///
/// **Every triple rather than a clipped polygon.** Fourteen planes are 364
/// triples, a few microseconds once a frame, and there is no face list to keep
/// consistent as each plane cuts — the bookkeeping that loses a corner where
/// two cutting planes meet inside the box.
List<Vector3> _corners(List<_HalfSpace> planes) {
  final scale = planes.fold(1.0, (s, p) => math.max(s, p.offset.abs()));
  final tolerance = 1e-6 * scale;
  final found = <Vector3>[];
  for (var i = 0; i < planes.length; i++) {
    for (var j = i + 1; j < planes.length; j++) {
      for (var k = j + 1; k < planes.length; k++) {
        final point = _meet(planes[i], planes[j], planes[k]);
        if (point == null) continue;
        if (planes.every(
          (p) => p.normal.dot(point) + p.offset >= -tolerance * p.normal.length,
        )) {
          found.add(point);
        }
      }
    }
  }
  return found;
}

/// Where three planes meet, or null when two of them are parallel.
Vector3? _meet(_HalfSpace a, _HalfSpace b, _HalfSpace c) {
  final bc = b.normal.cross(c.normal);
  final determinant = a.normal.dot(bc);
  final size = a.normal.length * b.normal.length * c.normal.length;
  if (determinant.abs() <= 1e-9 * size) return null;
  // Cramer's rule for n·p = −offset, in its vector form.
  final ca = c.normal.cross(a.normal);
  final ab = a.normal.cross(b.normal);
  return (bc.scaled(-a.offset) + ca.scaled(-b.offset) + ab.scaled(-c.offset))
    ..scale(1.0 / determinant);
}
