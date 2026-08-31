import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'track_types.dart';

export 'track_types.dart';

/// A closed circuit: a measured centre line, and everything a lap needs to know
/// that the shape alone does not say.
///
/// ## The road is not a collider
///
/// The obvious way to build a track is to make its surface out of collision
/// geometry and drive on it. This does not: the surface is answered
/// analytically, from the centre line and a width and a camber, and no part of
/// the road is in the collision world at all.
///
/// That is forced, and worth stating so it is not rediscovered. The collision
/// package has axis-aligned boxes, spheres and capsules; a box that never
/// rotates stays axis-aligned, which is exactly what makes the solver simple
/// and exactly what a banked corner is not. A cambered turn approximated by
/// axis-aligned boxes is a staircase, and a car crossing it hits a seam at
/// every step — at a hundred and eighty degrees of arc and four steps a metre
/// that is a vibration, not a road. Answering the surface from the curve gives
/// a road that is smooth everywhere by construction, costs one search per car
/// per step, and is the same number on every machine.
///
/// What stays in the collision world is everything that is genuinely an object:
/// the cars, the scenery, the barriers of a level built from brushes, the
/// volumes lying on the road. Leaving the road itself out of it is what this
/// class is for, and [TrackField] is where the two meet.
///
/// ## Measured in metres
///
/// Every distance here is `s`, metres along the centre line, wrapping at the
/// finish line. Widths, camber, surfaces and barriers are authored per control
/// point or per stretch and read back at any `s`, so a track file and a lap
/// counter never have to agree about segment numbers.
final class TrackSpline {
  TrackSpline({
    required this.centre,
    required List<double> widths,
    required List<double> banks,
    this.shoulder = 4.0,
    List<SurfaceBand> surfaces = const <SurfaceBand>[],
    List<BarrierBand> barriers = const <BarrierBand>[],
    List<double> checkpoints = const <double>[],
    this.grid = const StartGrid(),
  })  : _widths = List<double>.unmodifiable(widths),
        _banks = List<double>.unmodifiable(banks),
        _surfaces = List<SurfaceBand>.unmodifiable(surfaces),
        _barriers = List<BarrierBand>.unmodifiable(barriers),
        checkpoints = List<double>.unmodifiable(checkpoints) {
    if (widths.length != centre.pointCount) {
      throw ArgumentError.value(
        widths.length,
        'widths',
        'needs one per control point (${centre.pointCount})',
      );
    }
    if (banks.length != centre.pointCount) {
      throw ArgumentError.value(
        banks.length,
        'banks',
        'needs one per control point (${centre.pointCount})',
      );
    }
    for (final width in widths) {
      if (!(width > 0.0)) {
        throw ArgumentError.value(width, 'widths', 'must be positive');
      }
    }
    for (var i = 1; i < checkpoints.length; i++) {
      if (checkpoints[i] <= checkpoints[i - 1]) {
        throw ArgumentError.value(
          checkpoints,
          'checkpoints',
          'must be in order around the lap; a lap counter walks them in turn',
        );
      }
    }
    _pointDistances = <double>[
      for (var i = 0; i < centre.pointCount; i++) centre.distanceToPoint(i),
    ];
  }

  /// The centre line, measured in metres.
  final CatmullRom centre;

  final List<double> _widths;
  final List<double> _banks;
  final List<SurfaceBand> _surfaces;
  final List<BarrierBand> _barriers;

  /// How far the ground continues either side of the road before the track
  /// stops describing it and the collision world takes over.
  final double shoulder;

  /// Where each checkpoint is, in order round the lap.
  ///
  /// A lap counts when the finish line is crossed having passed all of these in
  /// turn. Without them a car could drive ten metres, turn round, and cross the
  /// line forwards for a lap a second.
  final List<double> checkpoints;

  final StartGrid grid;

  late final List<double> _pointDistances;

  /// The length of a lap, in metres.
  double get length => centre.length;

  /// The full width of the road at [s] — kerb to kerb, not the half.
  double widthAt(double s) => _betweenPoints(_widths, s);

  /// How far the road is tilted at [s], in radians, positive raising the
  /// positive-`lateral` edge.
  double bankAt(double s) => _betweenPoints(_banks, s);

  /// Fills [out] with the road's frame of reference at [s].
  void frameAt(double s, TrackFrame out) {
    centre
      ..sampleAt(s, out.position)
      ..tangentAt(s, out.forward);

    // right = worldUp x forward, which for a road running along +z comes out
    // along +x. Written out because two of its three components are zero.
    var rx = out.forward.z;
    var rz = -out.forward.x;
    final flat = math.sqrt(rx * rx + rz * rz);
    if (flat < 1e-6) {
      // The centre line is pointing straight up or down. This format cannot
      // describe a loop, so rather than divide by nothing, keep a usable frame
      // and let the shape be wrong somewhere nobody can drive.
      rx = 1.0;
      rz = 0.0;
    } else {
      rx /= flat;
      rz /= flat;
    }

    // up = forward x right, which is already a unit vector: forward is one, and
    // right is a unit vector in the horizontal plane perpendicular to it.
    final ux = out.forward.y * rz;
    final uy = out.forward.z * rx - out.forward.x * rz;
    final uz = -out.forward.y * rx;

    final bank = bankAt(s);
    if (bank == 0.0) {
      out.right.setValues(rx, 0.0, rz);
      out.up.setValues(ux, uy, uz);
      return;
    }

    // Rotate the pair about the direction of travel. Both stay perpendicular to
    // it, so the road stays a flat ribbon and only its tilt changes.
    final cosine = math.cos(bank);
    final sine = math.sin(bank);
    out.right.setValues(
      rx * cosine + ux * sine,
      uy * sine,
      rz * cosine + uz * sine,
    );
    out.up.setValues(
      ux * cosine - rx * sine,
      uy * cosine,
      uz * cosine - rz * sine,
    );
  }

  /// Fills [out] with the point on the road surface [lateral] metres to the
  /// side of the centre line at [s].
  void surfacePoint(double s, double lateral, Vector3 out) {
    frameAt(s, _scratch);
    out
      ..setFrom(_scratch.position)
      ..addScaled(_scratch.right, lateral);
  }

  /// Fills [out] with the point on the centre line at [s]. Where a car goes
  /// back to when it is put back on the track.
  void centreAt(double s, Vector3 out) => centre.sampleAt(s, out);

  /// What the ground is called at this point on the track, or null where the
  /// file has not said.
  String? surfaceAt(double s, double lateral) {
    final wrapped = centre.wrap(s);
    final onRoad = lateral.abs() <= widthAt(wrapped) / 2.0;
    for (final band in _surfaces) {
      if (band.covers(wrapped)) return onRoad ? band.centre : band.shoulder;
    }
    return null;
  }

  /// Whether there is a wall down one side of the track at [s].
  bool barrierAt(double s, {required bool left}) {
    final wrapped = centre.wrap(s);
    for (final band in _barriers) {
      if (!band.covers(wrapped)) continue;
      if (left ? band.left : band.right) return true;
    }
    return false;
  }

  /// Where car [index] starts, and which way it faces.
  ///
  /// Numbered from the front: nought is pole. Rows go backwards from
  /// [StartGrid.s], which is why that is usually negative — a grid in front of
  /// the finish line would give the whole field a free lap.
  void startSlot(int index, Vector3 outPosition, Vector3 outForward) {
    final row = index ~/ grid.columns;
    final column = index % grid.columns;
    final lateral = (column - (grid.columns - 1) / 2.0) * grid.columnGap;

    frameAt(grid.s - row * grid.rowGap, _scratch);
    outPosition
      ..setFrom(_scratch.position)
      ..addScaled(_scratch.right, lateral);
    outForward.setFrom(_scratch.forward);
  }

  /// Reads a value authored per control point at any distance between them.
  double _betweenPoints(List<double> values, double s) {
    final wrapped = centre.wrap(s);

    var low = 0;
    var high = _pointDistances.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_pointDistances[middle] <= wrapped) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    final last = low == _pointDistances.length - 1;
    final fromS = _pointDistances[low];
    final toS = last ? centre.length : _pointDistances[low + 1];
    final next = last ? (centre.closed ? 0 : low) : low + 1;

    final span = toS - fromS;
    if (span <= 1e-9) return values[low];

    final t = ((wrapped - fromS) / span).clamp(0.0, 1.0);
    // Smoothstep rather than a straight line. A width or a camber that changed
    // linearly would be continuous but its slope would not be, and the crease
    // that leaves at every control point is visible in the road edge and
    // audible in the suspension.
    final blend = t * t * (3.0 - 2.0 * t);
    return values[low] + (values[next] - values[low]) * blend;
  }

  final TrackFrame _scratch = TrackFrame();
}
