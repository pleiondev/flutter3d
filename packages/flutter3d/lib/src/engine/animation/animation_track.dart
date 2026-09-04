import 'dart:math' as math;
import 'dart:typed_data';

/// How a track's values are blended between keyframes.
///
/// The full glTF set. Leaving one out is not an option: `STEP` is what makes a
/// mechanical animation read as mechanical, and `CUBICSPLINE` stores three
/// values per key, so a decoder that assumes linear would read tangents as
/// values and produce a violently wrong result rather than a slightly wrong one.
enum AnimationInterpolation {
  /// Hold the previous key until the next one.
  step,

  /// Straight-line blend; spherical for rotations.
  linear,

  /// Cubic Hermite spline with authored in and out tangents.
  cubicSpline;

  static AnimationInterpolation fromGltf(String? name) => switch (name) {
    'STEP' => AnimationInterpolation.step,
    'CUBICSPLINE' => AnimationInterpolation.cubicSpline,
    // LINEAR is the spec's default when the sampler omits the field.
    _ => AnimationInterpolation.linear,
  };

  /// Values stored per keyframe: a cubic key carries an in tangent, the value,
  /// and an out tangent.
  int get valuesPerKey => this == cubicSpline ? 3 : 1;
}

/// Which node property a track drives.
enum AnimationPath {
  translation(3),
  rotation(4),
  scale(3),

  /// Morph target weights. Decoded so the clip is complete, but the player has
  /// nothing to apply them to until morph targets exist.
  weights(0);

  const AnimationPath(this.componentCount);

  /// Components per keyframe value; zero means "as many as the mesh has
  /// morph targets", which only the accessor knows.
  final int componentCount;

  static AnimationPath? fromGltf(String? name) => switch (name) {
    'translation' => AnimationPath.translation,
    'rotation' => AnimationPath.rotation,
    'scale' => AnimationPath.scale,
    'weights' => AnimationPath.weights,
    _ => null,
  };
}

/// One animated property of one node.
///
/// Times and values are flat typed arrays rather than a list of keyframe
/// objects: sampling runs every frame for every animated node, and a list of
/// small objects is the shape that turns into GC pressure inside the frame
/// budget.
final class AnimationTrack {
  AnimationTrack({
    required this.nodeIndex,
    required this.path,
    required this.interpolation,
    required this.times,
    required this.values,
    required this.componentCount,
  }) {
    if (times.isEmpty) {
      throw ArgumentError('An animation track needs at least one keyframe.');
    }
    final expected = times.length * componentCount * interpolation.valuesPerKey;
    if (values.length != expected) {
      throw ArgumentError(
        'Track for node $nodeIndex has ${times.length} keys and '
        '${values.length} values; ${interpolation.name} interpolation of '
        '$componentCount components needs $expected.',
      );
    }
  }

  /// Index into the model's node list.
  final int nodeIndex;

  final AnimationPath path;
  final AnimationInterpolation interpolation;

  /// Keyframe times in seconds, ascending.
  final Float32List times;

  /// Keyframe values, `componentCount * valuesPerKey` per key.
  final Float32List values;

  /// Components in one value: 3 for translation and scale, 4 for a rotation,
  /// the morph target count for weights.
  final int componentCount;

  /// When the first keyframe is, in seconds.
  ///
  /// The player reads [endTime] to know when a clip is over and never needs
  /// this, because it samples from zero. It is for a tool that lays tracks out
  /// on a timeline, where a track starting late is a gap somebody has to see.
  double get startTime => times.first;

  double get endTime => times.last;

  int get keyCount => times.length;

  /// Samples the track at [time], writing [componentCount] values into [out].
  ///
  /// Times outside the track are clamped to its ends, as glTF requires: a clip
  /// whose tracks start at different times must hold the first pose rather than
  /// extrapolating backwards into nonsense.
  void sample(double time, Float32List out) {
    if (out.length < componentCount) {
      throw ArgumentError(
        'out needs $componentCount slots, got ${out.length}.',
      );
    }

    final count = times.length;
    if (count == 1 || time <= times[0]) {
      _readValue(0, out);
      return;
    }
    if (time >= times[count - 1]) {
      _readValue(count - 1, out);
      return;
    }

    // Binary search for the interval; a linear scan would be fine for a hand-
    // authored clip and quadratic for a baked one with thousands of keys.
    var low = 0;
    var high = count - 1;
    while (high - low > 1) {
      final mid = (low + high) >> 1;
      if (times[mid] <= time) {
        low = mid;
      } else {
        high = mid;
      }
    }

    final t0 = times[low];
    final t1 = times[high];
    final span = t1 - t0;
    // Coincident keys would divide by zero; treating them as a step is what
    // authoring tools mean by two keys at the same time.
    final alpha = span <= 0.0 ? 0.0 : (time - t0) / span;

    switch (interpolation) {
      case AnimationInterpolation.step:
        _readValue(low, out);

      case AnimationInterpolation.linear:
        if (path == AnimationPath.rotation) {
          _slerp(low, high, alpha, out);
        } else {
          _lerp(low, high, alpha, out);
        }

      case AnimationInterpolation.cubicSpline:
        _hermite(low, high, alpha, span, out);
        if (path == AnimationPath.rotation) _normalizeQuaternion(out);
    }
  }

  /// Reads the value part of key [index]; for cubic keys that is the middle of
  /// the in-tangent / value / out-tangent triple.
  void _readValue(int index, Float32List out) {
    final base =
        index * componentCount * interpolation.valuesPerKey +
        (interpolation == AnimationInterpolation.cubicSpline
            ? componentCount
            : 0);
    for (var i = 0; i < componentCount; i++) {
      out[i] = values[base + i];
    }
  }

  void _lerp(int low, int high, double alpha, Float32List out) {
    final a = low * componentCount;
    final b = high * componentCount;
    for (var i = 0; i < componentCount; i++) {
      out[i] = values[a + i] + (values[b + i] - values[a + i]) * alpha;
    }
  }

  /// Spherical interpolation for quaternions.
  ///
  /// Component-wise lerp of a quaternion is the classic shortcut, and it is
  /// wrong twice: the result is not unit length, and the rotation speeds up in
  /// the middle of the arc. On a 90-degree key interval the error is visible.
  void _slerp(int low, int high, double alpha, Float32List out) {
    final a = low * 4;
    final b = high * 4;

    var x0 = values[a],
        y0 = values[a + 1],
        z0 = values[a + 2],
        w0 = values[a + 3];
    final x1 = values[b],
        y1 = values[b + 1],
        z1 = values[b + 2],
        w1 = values[b + 3];

    var dot = x0 * x1 + y0 * y1 + z0 * z1 + w0 * w1;
    // q and -q are the same rotation; flipping the near end takes the short way
    // round instead of spinning the long way.
    if (dot < 0.0) {
      x0 = -x0;
      y0 = -y0;
      z0 = -z0;
      w0 = -w0;
      dot = -dot;
    }

    double s0, s1;
    if (dot > 0.9995) {
      // Nearly parallel: the sine terms lose all their precision, and a
      // straight blend is indistinguishable at this angle anyway.
      s0 = 1.0 - alpha;
      s1 = alpha;
    } else {
      final theta = _acos(dot);
      final sinTheta = _sin(theta);
      s0 = _sin((1.0 - alpha) * theta) / sinTheta;
      s1 = _sin(alpha * theta) / sinTheta;
    }

    out[0] = x0 * s0 + x1 * s1;
    out[1] = y0 * s0 + y1 * s1;
    out[2] = z0 * s0 + z1 * s1;
    out[3] = w0 * s0 + w1 * s1;
    _normalizeQuaternion(out);
  }

  /// Cubic Hermite between two keys, per the glTF appendix.
  ///
  /// Tangents are authored in value-per-second and therefore scale by the key
  /// interval; forgetting that factor produces an animation that looks right at
  /// one frame rate and overshoots at another.
  void _hermite(int low, int high, double alpha, double span, Float32List out) {
    final stride = componentCount * 3;
    final a = low * stride;
    final b = high * stride;

    final t2 = alpha * alpha;
    final t3 = t2 * alpha;

    final h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    final h10 = t3 - 2.0 * t2 + alpha;
    final h01 = -2.0 * t3 + 3.0 * t2;
    final h11 = t3 - t2;

    for (var i = 0; i < componentCount; i++) {
      final v0 = values[a + componentCount + i];
      final outTangent0 = values[a + componentCount * 2 + i];
      final v1 = values[b + componentCount + i];
      final inTangent1 = values[b + i];

      out[i] =
          h00 * v0 +
          h10 * span * outTangent0 +
          h01 * v1 +
          h11 * span * inTangent1;
    }
  }

  static void _normalizeQuaternion(Float32List out) {
    final length = _sqrt(
      out[0] * out[0] + out[1] * out[1] + out[2] * out[2] + out[3] * out[3],
    );
    if (length <= 0.0) {
      out[0] = 0.0;
      out[1] = 0.0;
      out[2] = 0.0;
      out[3] = 1.0;
      return;
    }
    final inverse = 1.0 / length;
    out[0] *= inverse;
    out[1] *= inverse;
    out[2] *= inverse;
    out[3] *= inverse;
  }

  @override
  String toString() =>
      'AnimationTrack(node $nodeIndex, ${path.name}, '
      '${interpolation.name}, $keyCount keys)';
}

double _sqrt(double v) => v <= 0.0 ? 0.0 : math.sqrt(v);

/// Guarded against a dot product that rounds just past 1, which would make
/// `acos` return NaN and blank the rotation for one frame.
double _acos(double v) => math.acos(v.clamp(-1.0, 1.0));

double _sin(double v) => math.sin(v);
