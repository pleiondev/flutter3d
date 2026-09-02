import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';
import 'tolerances.dart';

/// A smooth curve through a list of control points, measured in metres.
///
/// The measurement is the whole point. A cubic spline is naturally parameterised
/// by a unitless number that runs one unit per segment, and that number moves at
/// a different speed everywhere along the curve: where the control points are
/// ten metres apart a step of `0.1` covers a metre, and where the next ones are
/// eighty metres apart the same step covers eight. Everything that wants a curve
/// for something other than drawing it wants metres instead — how far along a
/// track a car has got, how far ahead of itself a driver should aim, how many
/// times a road texture repeats, where the grid slots sit. So this measures the
/// curve once at construction and takes `s` in metres everywhere afterwards.
///
/// A [closed] curve loops back to its first point, and then `s` wraps instead of
/// clamping. That is deliberate: a lap counter that has to special-case the seam
/// is a lap counter that will miscount at the seam, and the seam is the finish
/// line — the one place on a track where being wrong is worst.
///
/// Points are copied at construction. A caller that keeps and mutates the list
/// it passed would otherwise silently invalidate the arc-length table, and the
/// symptom would be a curve that reports distances for a shape it no longer has.
final class CatmullRom {
  CatmullRom(
    List<Vector3> points, {
    this.closed = true,
    this.tension = 0.5,
    int samplesPerSegment = 16,
  }) : _samplesPerSegment = samplesPerSegment,
       _points = [for (final point in points) point.clone()] {
    final minimum = closed ? 3 : 2;
    if (_points.length < minimum) {
      throw ArgumentError.value(
        points.length,
        'points',
        closed
            ? 'a closed curve needs at least three points'
            : 'an open curve needs at least two points',
      );
    }
    if (samplesPerSegment < 2) {
      throw ArgumentError.value(
        samplesPerSegment,
        'samplesPerSegment',
        'must be at least two',
      );
    }
    _measure();
  }

  /// Whether the last point joins back to the first.
  final bool closed;

  final List<Vector3> _points;

  /// How hard the curve pulls towards each control point. The classical
  /// Catmull-Rom value is `0.5`; lower slackens the curve towards straight lines
  /// between the points, higher overshoots them.
  final double tension;

  /// How finely the curve is measured, per segment.
  ///
  /// This is the accuracy of every distance this class reports: the arc length
  /// is the sum of this many chords per segment, so it always slightly
  /// *underestimates* a curved segment, and doubling this roughly quarters that
  /// error. Sixteen holds a well-behaved track segment to under a tenth of a
  /// percent, which is far below the width of the car.
  final int _samplesPerSegment;

  /// Positions of every measured sample, flattened. Kept because the nearest
  /// point searches scan it directly instead of re-evaluating the polynomial.
  late final Float64List _samples;

  /// Distance along the curve at each sample, so it is monotonically increasing
  /// and can be binary searched.
  late final Float64List _distances;

  late final double _length;

  /// The distance all the way round, in metres.
  double get length => _length;

  /// How many cubic pieces the curve is made of.
  int get segmentCount => closed ? _points.length : _points.length - 1;

  /// The number of control points the curve was built from.
  int get pointCount => _points.length;

  /// How far along the curve control point [index] sits, in metres.
  ///
  /// The bridge between the two ways a track is described. Widths, camber,
  /// surfaces and barriers are authored *per control point*, because that is
  /// where a person editing a track puts them; everything that reads a track
  /// asks in metres. Without this the two would have to be matched by eye.
  double distanceToPoint(int index) {
    final wrapped = closed
        ? index % _points.length
        : index.clamp(0, _points.length - 1);
    return _distances[wrapped * _samplesPerSegment];
  }

  /// Brings [s] into range: wrapped for a [closed] curve, clamped for an open
  /// one.
  ///
  /// Worth calling directly whenever two distances are compared — the difference
  /// between `-2.0` and `398.0` on a four hundred metre lap is two metres, and
  /// code that has not wrapped first will read it as most of a lap.
  double wrap(double s) {
    if (!closed) return s.clamp(0.0, _length);
    if (_length <= 0.0) return 0.0;
    // Dart's `%` on a positive divisor never returns a negative result, which is
    // why going backwards past the start needs no special case here.
    return s % _length;
  }

  /// Writes the point [s] metres along the curve into [out].
  void sampleAt(double s, Vector3 out) => _evaluate(_toU(s), out);

  /// Writes the unit direction of travel at [s] into [out].
  void tangentAt(double s, Vector3 out) {
    final u = _toU(s);
    _derivative(u, out);
    var scale = out.length;
    if (scale < Tolerance.divisor) {
      // Coincident control points can flatten the derivative to nothing. Step a
      // hair along the curve rather than inventing a direction, so that a
      // duplicated point in the track file is a wobble and not a car facing
      // north for one step.
      _derivative(u + 1e-4, out);
      scale = out.length;
      if (scale < Tolerance.divisor) {
        out.setValues(0.0, 0.0, 1.0);
        return;
      }
    }
    out.scale(1.0 / scale);
  }

  /// How sharply the curve bends at [s], in radians per metre.
  ///
  /// The reciprocal is the radius of the turn, which is what a driver actually
  /// wants: the fastest a car can hold a corner is `sqrt(lateralGrip / kappa)`,
  /// so this is the number an AI brakes against and a road mesh subdivides by.
  /// A straight reports zero.
  double curvatureAt(double s) {
    final u = _toU(s);
    _derivative(u, _first);
    _secondDerivative(u, _second);

    final speed = _first.length;
    if (speed < Tolerance.divisor) return 0.0;

    // Written out rather than through `cross`, which allocates a vector: an AI
    // asks this several times per car per step.
    final cx = _first.y * _second.z - _first.z * _second.y;
    final cy = _first.z * _second.x - _first.x * _second.z;
    final cz = _first.x * _second.y - _first.y * _second.x;

    return math.sqrt(cx * cx + cy * cy + cz * cz) / (speed * speed * speed);
  }

  /// The distance along the curve of the point nearest [point], searched only
  /// within [window] metres either side of [nearS].
  ///
  /// The window is not an optimisation, it is the correctness fix. A track
  /// passes close to itself all the time — a hairpin folded back beside the
  /// straight that feeds it, an overpass, a figure of eight — and at those places
  /// the globally nearest point on the curve is half a lap from where the car
  /// actually is. One frame of that and the car has apparently finished the lap,
  /// or is driving the wrong way, or both. Anchoring the search to the answer
  /// from the previous step keeps it on the branch the car is really on.
  ///
  /// Use [closestSGlobal] when there is no previous answer to anchor to: a
  /// spawn, a respawn, a car dropped in by an editor.
  double closestS(
    Vector3 point, {
    required double nearS,
    double window = 30.0,
  }) {
    if (_length <= 0.0) return 0.0;
    if (window <= 0.0) return wrap(nearS);
    if (closed && window * 2.0 >= _length) return closestSGlobal(point);

    final from = closed ? nearS - window : (nearS - window).clamp(0.0, _length);
    final to = closed ? nearS + window : (nearS + window).clamp(0.0, _length);
    return _refine(point, _nearestSampleBetween(point, from, to));
  }

  /// The distance along the curve of the nearest point anywhere on it.
  double closestSGlobal(Vector3 point) {
    if (_length <= 0.0) return 0.0;
    return _refine(point, _nearestSampleIn(point, 0, _sampleCount - 1));
  }

  // --- measurement -----------------------------------------------------------

  int get _sampleCount => segmentCount * _samplesPerSegment + 1;

  void _measure() {
    final count = _sampleCount;
    _samples = Float64List(count * 3);
    _distances = Float64List(count);

    final point = Vector3.zero();
    var total = 0.0;
    var previousX = 0.0;
    var previousY = 0.0;
    var previousZ = 0.0;

    for (var i = 0; i < count; i++) {
      _evaluate(i / _samplesPerSegment, point);
      if (i > 0) {
        final dx = point.x - previousX;
        final dy = point.y - previousY;
        final dz = point.z - previousZ;
        total += math.sqrt(dx * dx + dy * dy + dz * dz);
      }
      _distances[i] = total;
      _samples[i * 3] = point.x;
      _samples[i * 3 + 1] = point.y;
      _samples[i * 3 + 2] = point.z;
      previousX = point.x;
      previousY = point.y;
      previousZ = point.z;
    }
    _length = total;
  }

  /// Metres to the internal parameter, by binary search of the measured table.
  double _toU(double s) {
    if (_length <= 0.0) return 0.0;
    final target = wrap(s);

    var low = 0;
    var high = _distances.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_distances[middle] <= target) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    if (low >= _distances.length - 1) return segmentCount.toDouble();

    final span = _distances[low + 1] - _distances[low];
    final fraction = span > 1e-12 ? (target - _distances[low]) / span : 0.0;
    return (low + fraction) / _samplesPerSegment;
  }

  /// The internal parameter back to metres.
  double _toS(double u) {
    final scaled = _wrapU(u) * _samplesPerSegment;
    final index = scaled.floor();
    if (index >= _distances.length - 1) return _length;
    if (index < 0) return 0.0;
    final fraction = scaled - index;
    return _distances[index] +
        (_distances[index + 1] - _distances[index]) * fraction;
  }

  double _wrapU(double u) {
    final segments = segmentCount.toDouble();
    if (!closed) return u.clamp(0.0, segments);
    return u % segments;
  }

  // --- nearest point ---------------------------------------------------------

  /// Index of the measured sample nearest [point] within an inclusive range,
  /// which may run past the end of a closed curve and wrap.
  int _nearestSampleIn(Vector3 point, int from, int to) {
    var bestIndex = from;
    var bestDistance = double.infinity;
    // The last sample of a closed curve is the first one again, so the wrapping
    // stride skips it; counting it twice would be harmless but wasteful.
    final period = closed ? _sampleCount - 1 : _sampleCount;
    for (var i = from; i <= to; i++) {
      var index = i;
      if (closed) {
        index = i % period;
      } else if (index < 0 || index >= _sampleCount) {
        continue;
      }
      final dx = _samples[index * 3] - point.x;
      final dy = _samples[index * 3 + 1] - point.y;
      final dz = _samples[index * 3 + 2] - point.z;
      final distance = dx * dx + dy * dy + dz * dz;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Same, over a range given in metres.
  int _nearestSampleBetween(Vector3 point, double fromS, double toS) {
    final from = (_toU(fromS) * _samplesPerSegment).floor();
    var to = (_toU(toS) * _samplesPerSegment).ceil();
    if (closed && toS > fromS) {
      // `_toU` wrapped both ends, so a window crossing the seam comes back with
      // its end before its start. Unwrap it by walking forwards from the start
      // instead, which is what the caller meant.
      if (to < from) to += _sampleCount - 1;
    }
    return _nearestSampleIn(point, from, to);
  }

  /// Narrows the answer from the nearest measured sample to the nearest point on
  /// the curve itself, by ternary search between its neighbours.
  double _refine(Vector3 point, int sampleIndex) {
    final centre = sampleIndex / _samplesPerSegment;
    final step = 1.0 / _samplesPerSegment;
    var low = centre - step;
    var high = centre + step;
    if (!closed) {
      low = low.clamp(0.0, segmentCount.toDouble());
      high = high.clamp(0.0, segmentCount.toDouble());
    }

    // Twenty rounds shrink the interval to about six parts in a hundred thousand
    // of a segment, which on any real track is well under a millimetre.
    for (var i = 0; i < 20; i++) {
      final third = (high - low) / 3.0;
      final a = low + third;
      final b = high - third;
      if (_distanceSquaredAtU(a, point) <= _distanceSquaredAtU(b, point)) {
        high = b;
      } else {
        low = a;
      }
    }
    return _toS((low + high) / 2.0);
  }

  double _distanceSquaredAtU(double u, Vector3 point) {
    _evaluate(u, _probe);
    final dx = _probe.x - point.x;
    final dy = _probe.y - point.y;
    final dz = _probe.z - point.z;
    return dx * dx + dy * dy + dz * dz;
  }

  // --- the polynomial --------------------------------------------------------

  /// The control point [index] with the ends handled: wrapped on a closed curve,
  /// held on an open one so that the first and last segments still have the two
  /// neighbours the formula needs.
  Vector3 _controlPoint(int index) {
    // Dart's `%` on a positive divisor is never negative, so the point before
    // the first one is the last one without any arithmetic to get wrong.
    if (closed) return _points[index % _points.length];
    return _points[index.clamp(0, _points.length - 1)];
  }

  /// Splits the internal parameter into which segment and how far into it.
  (int, double) _segmentAt(double u) {
    final wrapped = _wrapU(u);
    var index = wrapped.floor();
    if (index >= segmentCount) index = segmentCount - 1;
    if (index < 0) index = 0;
    return (index, wrapped - index);
  }

  void _evaluate(double u, Vector3 out) {
    final (index, t) = _segmentAt(u);
    final p0 = _controlPoint(index - 1);
    final p1 = _controlPoint(index);
    final p2 = _controlPoint(index + 1);
    final p3 = _controlPoint(index + 2);

    final t2 = t * t;
    final t3 = t2 * t;
    final h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    final h10 = t3 - 2.0 * t2 + t;
    final h01 = -2.0 * t3 + 3.0 * t2;
    final h11 = t3 - t2;

    out.setValues(
      h00 * p1.x +
          h10 * tension * (p2.x - p0.x) +
          h01 * p2.x +
          h11 * tension * (p3.x - p1.x),
      h00 * p1.y +
          h10 * tension * (p2.y - p0.y) +
          h01 * p2.y +
          h11 * tension * (p3.y - p1.y),
      h00 * p1.z +
          h10 * tension * (p2.z - p0.z) +
          h01 * p2.z +
          h11 * tension * (p3.z - p1.z),
    );
  }

  void _derivative(double u, Vector3 out) {
    final (index, t) = _segmentAt(u);
    final p0 = _controlPoint(index - 1);
    final p1 = _controlPoint(index);
    final p2 = _controlPoint(index + 1);
    final p3 = _controlPoint(index + 2);

    final t2 = t * t;
    final h00 = 6.0 * t2 - 6.0 * t;
    final h10 = 3.0 * t2 - 4.0 * t + 1.0;
    final h01 = -6.0 * t2 + 6.0 * t;
    final h11 = 3.0 * t2 - 2.0 * t;

    out.setValues(
      h00 * p1.x +
          h10 * tension * (p2.x - p0.x) +
          h01 * p2.x +
          h11 * tension * (p3.x - p1.x),
      h00 * p1.y +
          h10 * tension * (p2.y - p0.y) +
          h01 * p2.y +
          h11 * tension * (p3.y - p1.y),
      h00 * p1.z +
          h10 * tension * (p2.z - p0.z) +
          h01 * p2.z +
          h11 * tension * (p3.z - p1.z),
    );
  }

  void _secondDerivative(double u, Vector3 out) {
    final (index, t) = _segmentAt(u);
    final p0 = _controlPoint(index - 1);
    final p1 = _controlPoint(index);
    final p2 = _controlPoint(index + 1);
    final p3 = _controlPoint(index + 2);

    final h00 = 12.0 * t - 6.0;
    final h10 = 6.0 * t - 4.0;
    final h01 = -12.0 * t + 6.0;
    final h11 = 6.0 * t - 2.0;

    out.setValues(
      h00 * p1.x +
          h10 * tension * (p2.x - p0.x) +
          h01 * p2.x +
          h11 * tension * (p3.x - p1.x),
      h00 * p1.y +
          h10 * tension * (p2.y - p0.y) +
          h01 * p2.y +
          h11 * tension * (p3.y - p1.y),
      h00 * p1.z +
          h10 * tension * (p2.z - p0.z) +
          h01 * p2.z +
          h11 * tension * (p3.z - p1.z),
    );
  }

  // Scratch space for the maths above, which is called from the simulation and
  // must not allocate.
  final Vector3 _first = Vector3.zero();
  final Vector3 _second = Vector3.zero();
  final Vector3 _probe = Vector3.zero();
}
