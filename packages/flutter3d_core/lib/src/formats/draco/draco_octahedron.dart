/// Draco's octahedral normals — `gfx-82n`.
///
/// **Normals are stored as two integers, not three.** A unit vector has two
/// degrees of freedom, so Draco projects it onto an octahedron and unwraps that
/// onto a square: the middle of the square is one pole, the corners are the
/// other, and the diamond joining the edge midpoints is the boundary between
/// the two hemispheres. Everything below follows
/// `compression/attributes/normal_compression_utils.h` and the canonicalized
/// prediction transform beside it, operation for operation — the arithmetic is
/// full of sign cases that are individually plausible and jointly wrong if any
/// one is off.
///
/// **The prediction is canonicalized, which is the part with no shortcut.** A
/// correction is added to a prediction in a *rotated* frame: the predictor's
/// own position decides a rotation and whether the diamond is inverted, the sum
/// happens there, and the result is rotated back. That is what lets the
/// corrections stay small and positive near the seams of the unwrapping.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The quantisation the octahedral coordinates live in.
final class OctahedronToolBox {
  OctahedronToolBox(int quantizationBits)
    : assert(
        quantizationBits >= 2 && quantizationBits <= 30,
        'octahedral quantisation must be between 2 and 30 bits',
      ),
      quantizationBits = quantizationBits,
      maxQuantizedValue = (1 << quantizationBits) - 1,
      maxValue = (1 << quantizationBits) - 2,
      centerValue = ((1 << quantizationBits) - 2) ~/ 2,
      dequantizationScale = 2.0 / ((1 << quantizationBits) - 2);

  /// From a stored `max_quantized_value`, which is always `2^b − 1`.
  factory OctahedronToolBox.fromMaxQuantized(int maxQuantizedValue) {
    if (maxQuantizedValue.isEven) {
      throw ArgumentError(
        'max quantized value $maxQuantizedValue is even, so it is not '
        'two-to-the-something minus one',
      );
    }
    var bits = 0;
    var value = maxQuantizedValue;
    while (value > 0) {
      value >>= 1;
      bits++;
    }
    return OctahedronToolBox(bits);
  }

  final int quantizationBits;
  final int maxQuantizedValue;
  final int maxValue;
  final int centerValue;
  final double dequantizationScale;

  /// Whether `(s, t)`, with the centre already at the origin, is on the near
  /// hemisphere.
  bool isInDiamond(int s, int t) => s.abs() + t.abs() <= centerValue;

  /// Mirrors a point across the diamond's edge, which is how the far
  /// hemisphere is addressed.
  void invertDiamond(Int32List point, int at) {
    var s = point[at];
    var t = point[at + 1];
    final int signS;
    final int signT;
    if (s >= 0 && t >= 0) {
      signS = 1;
      signT = 1;
    } else if (s <= 0 && t <= 0) {
      signS = -1;
      signT = -1;
    } else {
      signS = s > 0 ? 1 : -1;
      signT = t > 0 ? 1 : -1;
    }
    final cornerS = signS * centerValue;
    final cornerT = signT * centerValue;
    var us = s + s - cornerS;
    var ut = t + t - cornerT;
    if (signS * signT >= 0) {
      final temp = us;
      us = -ut;
      ut = -temp;
    } else {
      final temp = us;
      us = ut;
      ut = temp;
    }
    us += cornerS;
    ut += cornerT;
    s = us ~/ 2;
    t = ut ~/ 2;
    point[at] = s;
    point[at + 1] = t;
  }

  /// Wraps a coordinate back into the square.
  int modMax(int x) {
    if (x > centerValue) return x - maxQuantizedValue;
    if (x < -centerValue) return x + maxQuantizedValue;
    return x;
  }

  /// Scales an integer vector onto the octahedron: afterwards the absolute
  /// values of its three components sum to exactly [centerValue].
  ///
  /// `CanonicalizeIntegerVector`. The third component is *derived* rather than
  /// scaled, so that the sum is exact whatever the two truncating divisions
  /// lost — the geometric normal predictor feeds this straight into
  /// [integerVectorToOctahedralCoords], which assumes it.
  void canonicalizeIntegerVector(Int32List vector) {
    final absSum = vector[0].abs() + vector[1].abs() + vector[2].abs();
    if (absSum == 0) {
      vector[0] = centerValue;
      return;
    }
    vector[0] = (vector[0] * centerValue) ~/ absSum;
    vector[1] = (vector[1] * centerValue) ~/ absSum;
    final rest = centerValue - vector[0].abs() - vector[1].abs();
    vector[2] = vector[2] >= 0 ? rest : -rest;
  }

  /// Where a canonicalized integer vector sits on the unwrapped square —
  /// `IntegerVectorToQuantizedOctahedralCoords`, written into [out].
  ///
  /// The right hemisphere maps straight onto the inner diamond; the left one
  /// is folded out into the four corners. The last step moves the handful of
  /// points that have two names — the corners of the square are all the same
  /// pole — onto the one the encoder uses.
  void integerVectorToOctahedralCoords(Int32List vector, Int32List out) {
    final x = vector[0], y = vector[1], z = vector[2];
    final (int s, int t) = x >= 0
        ? (y + centerValue, z + centerValue)
        : (
            y < 0 ? z.abs() : maxValue - z.abs(),
            z < 0 ? y.abs() : maxValue - y.abs(),
          );
    final (int cs, int ct) = switch ((s, t)) {
      (0, 0) => (maxValue, maxValue),
      (0, final t) when t == maxValue => (maxValue, maxValue),
      (final s, 0) when s == maxValue => (maxValue, maxValue),
      (0, final t) when t > centerValue => (0, centerValue - (t - centerValue)),
      (final s, final t) when s == maxValue && t < centerValue => (
        s,
        centerValue + (centerValue - t),
      ),
      (final s, final t) when t == maxValue && s < centerValue => (
        centerValue + (centerValue - s),
        t,
      ),
      (final s, 0) when s > centerValue => (centerValue - (s - centerValue), 0),
      _ => (s, t),
    };
    out[0] = cs;
    out[1] = ct;
  }

  /// The unit vector `(s, t)` stands for, written into [out] at [at].
  void toUnitVector(int s, int t, Float32List out, int at) {
    var y = s * dequantizationScale - 1.0;
    var z = t * dequantizationScale - 1.0;
    final x = 1.0 - y.abs() - z.abs();
    // Negative x means the point is outside the diamond, on the far
    // hemisphere; mirroring (y, z) along the nearest diagonal is what unwraps
    // it back onto the octahedron.
    final offset = x < 0 ? -x : 0.0;
    y += y < 0 ? offset : -offset;
    z += z < 0 ? offset : -offset;

    final normSquared = x * x + y * y + z * z;
    if (normSquared < 1e-6) {
      out[at] = 0.0;
      out[at + 1] = 0.0;
      out[at + 2] = 0.0;
      return;
    }
    final d = 1.0 / math.sqrt(normSquared);
    out[at] = x * d;
    out[at + 1] = y * d;
    out[at + 2] = z * d;
  }
}

/// The canonicalized octahedral prediction transform.
///
/// Rotates the correction into the frame the predictor implies, adds it there,
/// and rotates back. [predicted] and [correction] are pairs; the answer is
/// written over [predicted].
void octahedronComputeOriginal(
  OctahedronToolBox box,
  Int32List point,
  int predictedAt,
  int correctionS,
  int correctionT,
) {
  final centre = box.centerValue;
  point[predictedAt] -= centre;
  point[predictedAt + 1] -= centre;

  final inDiamond = box.isInDiamond(point[predictedAt], point[predictedAt + 1]);
  if (!inDiamond) box.invertDiamond(point, predictedAt);

  final inBottomLeft = _isInBottomLeft(
    point[predictedAt],
    point[predictedAt + 1],
  );
  final rotation = _rotationCount(point[predictedAt], point[predictedAt + 1]);
  if (!inBottomLeft) _rotate(point, predictedAt, rotation);

  point[predictedAt] = box.modMax(point[predictedAt] + correctionS);
  point[predictedAt + 1] = box.modMax(point[predictedAt + 1] + correctionT);

  if (!inBottomLeft) _rotate(point, predictedAt, (4 - rotation) % 4);
  if (!inDiamond) box.invertDiamond(point, predictedAt);

  point[predictedAt] += centre;
  point[predictedAt + 1] += centre;
}

bool _isInBottomLeft(int s, int t) {
  if (s == 0 && t == 0) return true;
  return s < 0 && t <= 0;
}

int _rotationCount(int s, int t) {
  if (s == 0) {
    if (t == 0) return 0;
    return t > 0 ? 3 : 1;
  }
  if (s > 0) return t >= 0 ? 2 : 1;
  return t <= 0 ? 0 : 3;
}

void _rotate(Int32List point, int at, int count) {
  final s = point[at];
  final t = point[at + 1];
  switch (count) {
    case 1:
      point[at] = t;
      point[at + 1] = -s;
    case 2:
      point[at] = -s;
      point[at + 1] = -t;
    case 3:
      point[at] = -t;
      point[at + 1] = s;
  }
}
