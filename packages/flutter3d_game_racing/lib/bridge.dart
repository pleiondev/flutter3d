/// The visual half of the genre: a circuit turned into something to draw.
///
/// This is the one file here allowed to see a renderer, and the isolation test
/// names it. Everything else in this package is a simulation and stays testable
/// without a device; the road, however, has to become triangles somewhere, and
/// the rule this repository keeps is that the somewhere is a file that says so.
///
/// The road is built rather than authored, which follows from the road not
/// being collision geometry either — see `TrackSpline`. One curve, a width and
/// a camber describe the surface a car drives on, and the same three describe
/// the surface a player sees. A mesh drawn from a different description than
/// the one being driven on is a mesh whose edges are in the wrong place, and
/// that is the bug this avoids by construction.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'flutter3d_game_racing.dart';

/// How finely the road is cut into rings.
final class RoadMeshSettings {
  const RoadMeshSettings({
    this.sagitta = 0.04,
    this.minStep = 1.5,
    this.maxStep = 8.0,
    this.metresPerTile = 9.0,
    this.barrierHeight = 1.1,
  });

  /// How far the middle of a straight edge may sit from the curve it stands in
  /// for, in metres.
  ///
  /// This is the whole subdivision rule, and it is stated as an error rather
  /// than a step count because that is what it controls: the step needed to
  /// hold a given sagitta is `sqrt(8 · sagitta / curvature)`, so a hairpin gets
  /// short segments and a straight gets long ones without anybody choosing a
  /// number per corner. Four centimetres is well under a kerb.
  final double sagitta;

  /// The shortest and longest a segment may be whatever the maths says.
  ///
  /// The maximum is not about accuracy — a straight is a straight at any step —
  /// but about everything computed per vertex: lighting, fog, and how much of a
  /// crest is between two rings.
  final double minStep;
  final double maxStep;

  /// How many metres of road one repeat of the texture covers.
  final double metresPerTile;

  /// How tall a barrier stands above the road it guards.
  final double barrierHeight;
}

/// The road surface itself, kerb to kerb.
///
/// The texture runs along the road rather than across it: `v` is the distance
/// travelled, in tiles, so a repeating surface repeats down the straight and
/// nothing has to line up between one segment and the next. `u` runs from
/// nought at one edge to one at the other, whatever the road is doing — a
/// corner that narrows keeps its markings at its edges rather than sliding them
/// inwards.
MeshData buildRoadMesh(
  TrackSpline track, {
  RoadMeshSettings settings = const RoadMeshSettings(),
  VertexLayout? layout,
}) =>
    _ribbon(
      track,
      settings,
      layout,
      inner: (double s) => -track.widthAt(s) / 2.0,
      outer: (double s) => track.widthAt(s) / 2.0,
    );

/// The ground either side of the road, out to where the level takes over.
///
/// [side] is `-1` for the left of the track and `1` for the right — the same
/// sign as `lateral` everywhere else.
MeshData buildVergeMesh(
  TrackSpline track, {
  required int side,
  RoadMeshSettings settings = const RoadMeshSettings(),
  VertexLayout? layout,
}) {
  final sign = side < 0 ? -1.0 : 1.0;
  return _ribbon(
    track,
    settings,
    layout,
    inner: (double s) => sign * track.widthAt(s) / 2.0,
    outer: (double s) => sign * (track.widthAt(s) / 2.0 + track.shoulder),
    // A verge that tiles at the road's rate looks like more road. This is
    // ground, and ground is bigger.
    tileScale: 2.5,
  );
}

/// The walls, where the track says there are walls.
///
/// Built as separate strips rather than one long one, because a barrier that
/// runs half the lap has a beginning and an end and the geometry has to as
/// well — the alternative is a wall closing across the road at the point the
/// band stops.
List<MeshData> buildBarrierMeshes(
  TrackSpline track, {
  required int side,
  RoadMeshSettings settings = const RoadMeshSettings(),
  VertexLayout? layout,
}) {
  // The standard layout, not a leaner one. The engine's shaders read a
  // tangent and a vertex colour whether or not a mesh has anything to say
  // about them, and a road built with the eight-float layout crashes the
  // shadow pass reading past the end of its vertices.
  final chosen = layout ?? VertexLayout.standard;
  final left = side < 0;
  final sign = left ? -1.0 : 1.0;
  final meshes = <MeshData>[];

  // One builder per run of barrier. Nulled between runs rather than reset,
  // because "there is no wall here" and "there is a wall of no length" are
  // different things and only one of them should produce a mesh.
  MeshBuilder? current;
  var previousTop = -1;
  var previousBottom = -1;

  void close() {
    final builder = current;
    if (builder != null && builder.indexCount > 0) meshes.add(builder.build());
    current = null;
    previousTop = -1;
    previousBottom = -1;
  }

  final frame = TrackFrame();
  final foot = Vector3.zero();
  final head = Vector3.zero();
  final normal = Vector3.zero();

  for (final s in _stations(track, settings)) {
    if (!track.barrierAt(s, left: left)) {
      close();
      continue;
    }

    final builder = current ??= MeshBuilder(chosen);
    track.frameAt(s, frame);

    final lateral = sign * track.widthAt(s) / 2.0;
    foot
      ..setFrom(frame.position)
      ..addScaled(frame.right, lateral);
    head
      ..setFrom(foot)
      ..addScaled(frame.up, settings.barrierHeight);

    // Facing the road, so the side a car sees is the side that is lit.
    normal
      ..setFrom(frame.right)
      ..scale(-sign);

    final v = s / settings.metresPerTile;
    final bottom = builder.addVertex(
      position: foot,
      normal: normal,
      texcoord: Vector2(v, 1.0),
    );
    final top = builder.addVertex(
      position: head,
      normal: normal,
      texcoord: Vector2(v, 0.0),
    );

    if (previousBottom >= 0) {
      if (left) {
        builder.addQuad(previousBottom, bottom, top, previousTop);
      } else {
        builder.addQuad(previousBottom, previousTop, top, bottom);
      }
    }
    previousBottom = bottom;
    previousTop = top;
  }
  close();
  return meshes;
}

/// The lap as a flat outline, for a map in the corner of the screen.
///
/// Returned in world XZ and left unscaled: what a map is drawn at is the map's
/// business, and a helper that decided it would have to know how big the corner
/// of the screen was.
List<Vector2> trackOutline(TrackSpline track, {double step = 12.0}) {
  final points = <Vector2>[];
  final at = Vector3.zero();
  for (var s = 0.0; s < track.length; s += step) {
    track.centreAt(s, at);
    points.add(Vector2(at.x, at.z));
  }
  return points;
}

/// The distances round the lap that a ring of vertices is put at.
///
/// Closed: the last station is a repeat of the first, so that the seam is a
/// join like any other rather than a gap at the finish line.
Iterable<double> _stations(TrackSpline track, RoadMeshSettings settings) sync* {
  var s = 0.0;
  while (s < track.length) {
    yield s;
    final bend = track.centre.curvatureAt(s).abs();
    final wanted = bend < 1e-6
        ? settings.maxStep
        : math.sqrt(8.0 * settings.sagitta / bend);
    s += wanted.clamp(settings.minStep, settings.maxStep);
  }
  yield track.length;
}

MeshData _ribbon(
  TrackSpline track,
  RoadMeshSettings settings,
  VertexLayout? layout, {
  required double Function(double s) inner,
  required double Function(double s) outer,
  double tileScale = 1.0,
}) {
  final builder = MeshBuilder(layout ?? VertexLayout.standard);
  final frame = TrackFrame();
  final left = Vector3.zero();
  final right = Vector3.zero();

  var previousLeft = -1;
  var previousRight = -1;

  for (final s in _stations(track, settings)) {
    track.frameAt(s, frame);

    // Always emitted in increasing `lateral` order, whichever way round the
    // caller described the strip.
    //
    // **This is what makes the surface face upwards**, and getting it wrong is
    // invisible in every check that reads positions: the road was built with
    // its two edges in the order it happened to think of them, which wound its
    // triangles clockwise from above, and back-face culling removed the entire
    // road from the picture. The verge on the other side of the track was
    // described the other way round and so was drawn — which is why what
    // reached the screen was a circuit with grass down one side and a hole
    // where the tarmac should be.
    final low = math.min(inner(s), outer(s));
    final high = math.max(inner(s), outer(s));

    left
      ..setFrom(frame.position)
      ..addScaled(frame.right, low);
    right
      ..setFrom(frame.position)
      ..addScaled(frame.right, high);

    final v = s / (settings.metresPerTile * tileScale);
    final a = builder.addVertex(
      position: left,
      normal: frame.up,
      texcoord: Vector2(0.0, v),
    );
    final b = builder.addVertex(
      position: right,
      normal: frame.up,
      texcoord: Vector2(1.0, v),
    );

    if (previousLeft >= 0) {
      // Wound so that the geometric normal comes out along the road's up.
      builder.addQuad(previousLeft, a, b, previousRight);
    }
    previousLeft = a;
    previousRight = b;
  }

  return builder.build();
}
