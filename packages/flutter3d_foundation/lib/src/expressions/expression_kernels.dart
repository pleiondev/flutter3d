/// The scalar arithmetic every evaluator of the expression language
/// computes through, in one order of operations.
///
/// **Internal.** The closure compiler, the reference evaluator and the
/// bytecode interpreter all call these, which is what makes them agree to
/// the bit; a port of the bytecode to another language ports these as
/// written, with [Portable] for the transcendental ones.
library;

import 'dart:math' as math;

import '../portable_math.dart' show Portable;

/// One component of a binary operator: a comparison or a logical operator
/// answers one for true and nought for false.
double expressionOperatorAt(String op, double a, double b) => switch (op) {
  '+' => a + b,
  '-' => a - b,
  '*' => a * b,
  '/' => a / b,
  '<' => a < b ? 1.0 : 0.0,
  '<=' => a <= b ? 1.0 : 0.0,
  '>' => a > b ? 1.0 : 0.0,
  '>=' => a >= b ? 1.0 : 0.0,
  '==' => a == b ? 1.0 : 0.0,
  '!=' => a != b ? 1.0 : 0.0,
  '&&' => a != 0 && b != 0 ? 1.0 : 0.0,
  '||' => a != 0 || b != 0 ? 1.0 : 0.0,
  _ => throw ArgumentError('"$op" is not an operator.'),
};

/// `a·b`, summed from the first component on, from nought.
double dotOf(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// The square root of [dotOf] a vector with itself.
double lengthOf(List<double> a) => math.sqrt(dotOf(a, a));

/// `a + (b - a) * t`.
double mixAt(double a, double b, double t) => a + (b - a) * t;

/// [x] held between [low] and [high], [low] winning when they cross.
double clampAt(double x, double low, double high) =>
    x < low ? low : (x > high ? high : x);

/// Hermite smoothing of [x] between two edges; a step where they meet.
double smoothstepAt(double edge0, double edge1, double x) {
  if (edge0 == edge1) return x < edge0 ? 0 : 1;
  final t = clampAt((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

/// Nought below [edge], one from it.
double stepAt(double edge, double x) => x < edge ? 0.0 : 1.0;

/// The smaller, the first when equal.
double minAt(double a, double b) => a < b ? a : b;

/// The larger, the second when equal.
double maxAt(double a, double b) => a > b ? a : b;

/// [x] without its sign.
double absAt(double x) => x < 0 ? -x : x;

/// The whole number at or below [x].
double floorAt(double x) => x.floorToDouble();

/// What [x] is above [floorAt] it.
double fractAt(double x) => x - x.floorToDouble();

/// One, nought or minus one, by the sign of [x]; NaN stays NaN.
double signAt(double x) => x > 0 ? 1.0 : (x < 0 ? -1.0 : x);
