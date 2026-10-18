/// The expressions every evaluator of the language is held to: what each
/// reads, given what, with the answer worked out by hand where one can be.
///
/// Shared by `expressions_test.dart`, which holds the closure compiler to
/// the reference walker and to the hand answers, and
/// `expression_bytecode_test.dart`, which holds the bytecode to both.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// One fixture: [source] read in [scope], evaluated at each of [values]
/// (components in coherent units, by name).
final class ExpressionFixture {
  const ExpressionFixture(
    this.source, {
    this.variables = const <String, ExpressionType>{},
    this.values = const <Map<String, List<double>>>[<String, List<double>>{}],
    this.expected,
  });

  final String source;
  final Map<String, ExpressionType> variables;
  final List<Map<String, List<double>>> values;

  /// The answer at the first of [values], to within a few units in the
  /// last place, where it is known without the code.
  final List<double>? expected;

  ExpressionScope get scope => ExpressionScope(variables: variables);
}

final ExpressionType _kelvin = ExpressionType.measuring(Unit.kelvin);
final ExpressionType _pascal = ExpressionType.measuring(Unit.pascal);
final ExpressionType _meters3 = ExpressionType.vec3.withDimension(
  Dimension.length,
);
final ExpressionType _velocity3 = ExpressionType.vec3.withDimension(
  Unit.meterPerSecond.dimension,
);

/// A spread of temperatures, the hot path of a law.
final List<Map<String, List<double>>> _temperatures =
    <Map<String, List<double>>>[
      for (var t = 250.0; t <= 650.0; t += 37.5)
        <String, List<double>>{
          'T': <double>[t],
          'p': <double>[1e5 + t * 13],
        },
    ];

final List<ExpressionFixture> expressionFixtures = <ExpressionFixture>[
  const ExpressionFixture('1.0 + 2.0 * 3.0', expected: <double>[7]),
  const ExpressionFixture('(1.0 + 2.0) * 3.0', expected: <double>[9]),
  const ExpressionFixture(
    '-vec3(1.0, 2.0, 3.0).zyx',
    expected: <double>[-3, -2, -1],
  ),
  const ExpressionFixture('20 [°C]', expected: <double>[293.15]),
  const ExpressionFixture('5 [km] + 250 [m]', expected: <double>[5250]),
  const ExpressionFixture('1.5e-3 [m] * 2.0', expected: <double>[3e-3]),
  // Andrade's law for a liquid's viscosity, in pascal-seconds.
  ExpressionFixture(
    '1.8e-6 [Pa·s] * exp(1850 [K] / T)',
    variables: <String, ExpressionType>{'T': _kelvin},
    values: _temperatures,
  ),
  // A polynomial in temperature.
  ExpressionFixture(
    '1000 [kg/m³] * (1.0 - 2.1e-4 [K^-1] * (T - 277.13 [K]) - '
    '5e-6 [K^-2] * (T - 277.13 [K]) * (T - 277.13 [K]))',
    variables: <String, ExpressionType>{'T': _kelvin},
    values: _temperatures,
  ),
  ExpressionFixture(
    'T > 100 [°C] && p < 2 [bar] ? 1.0 : 0.0',
    variables: <String, ExpressionType>{'T': _kelvin, 'p': _pascal},
    values: _temperatures,
  ),
  ExpressionFixture(
    '!(T >= 400 [K]) || p == 1e5 [Pa]',
    variables: <String, ExpressionType>{'T': _kelvin, 'p': _pascal},
    values: _temperatures,
  ),
  ExpressionFixture(
    'sqrt(dot(v, v)) - length(v)',
    variables: <String, ExpressionType>{'v': _velocity3},
    values: <Map<String, List<double>>>[
      <String, List<double>>{
        'v': <double>[3, 4, 12],
      },
      <String, List<double>>{
        'v': <double>[0.1, -0.2, 0.3],
      },
    ],
    expected: const <double>[0],
  ),
  ExpressionFixture(
    'normalize(x) * 2.0 + mix(x, x * 2.0, 0.25) / 1 [m]',
    variables: <String, ExpressionType>{'x': _meters3},
    values: <Map<String, List<double>>>[
      <String, List<double>>{
        'x': <double>[1, 2, 2],
      },
      <String, List<double>>{
        'x': <double>[0, 0, 0],
      },
    ],
  ),
  ExpressionFixture(
    'vec4(sin(a), cos(a), tan(a * 0.5), atan2(sin(a), cos(a)))',
    variables: <String, ExpressionType>{'a': ExpressionType.float},
    values: <Map<String, List<double>>>[
      for (var a = -7.0; a < 7.0; a += 0.61)
        <String, List<double>>{
          'a': <double>[a],
        },
    ],
  ),
  ExpressionFixture(
    'vec3(asin(s), acos(s), atan(s * 10.0)) + log(exp(s) + 1.0)',
    variables: <String, ExpressionType>{'s': ExpressionType.float},
    values: <Map<String, List<double>>>[
      for (var s = -1.0; s <= 1.0; s += 0.125)
        <String, List<double>>{
          's': <double>[s],
        },
    ],
  ),
  ExpressionFixture(
    'clamp(smoothstep(0.2, 0.8, f), 0.1, 0.9) + step(0.5, f) + '
    'fract(f * 3.7) + floor(f * 3.7) + abs(-f) + sign(f - 0.5) + '
    'min(f, 0.3) + max(f, 0.6) + pow(f, 2.2)',
    variables: <String, ExpressionType>{'f': ExpressionType.float},
    values: <Map<String, List<double>>>[
      for (var f = 0.0; f <= 1.0; f += 0.0625)
        <String, List<double>>{
          'f': <double>[f],
        },
    ],
  ),
  // A squared length keeps its unit through pow with a constant exponent.
  ExpressionFixture(
    'pow(r, 2.0) * 3.14159 / 1 [m²]',
    variables: <String, ExpressionType>{
      'r': ExpressionType.measuring(Unit.meter),
    },
    values: <Map<String, List<double>>>[
      <String, List<double>>{
        'r': <double>[2],
      },
    ],
    expected: const <double>[12.56636],
  ),
];
