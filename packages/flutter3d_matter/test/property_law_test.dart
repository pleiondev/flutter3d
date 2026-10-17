/// A property's law: a constant, a table or a formula of the expression
/// language, read at a body's state, written and read back.
///
///     dart test test/property_law_test.dart
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:test/test.dart';

MatterState _at(double kelvin) => MatterState.at(temperature: kelvin);

PropertyLaw _again(PropertyLaw law) =>
    PropertyLaw.fromJson(jsonDecode(jsonEncode(law.toJson())));

void main() {
  test(
    'a constant is its value at every state, and a bare number in a file',
    () {
      const law = ConstantLaw(998.2);
      expect(law.at(_at(200.0)), 998.2);
      expect(law.at(const MatterState()), 998.2);
      expect(law.dependsOnState, isFalse);
      expect(law.toJson(), 998.2);
      expect(PropertyLaw.fromJson(998.2), law);
    },
  );

  test('a table interpolates on a line and holds its ends', () {
    const law = TableLaw(
      2.0,
      xs: <double>[300.0, 400.0, 600.0],
      ys: <double>[2.0, 4.0, 5.0],
    );
    expect(law.at(_at(300.0)), 2.0);
    expect(law.at(_at(350.0)), 3.0);
    expect(law.at(_at(500.0)), 4.5);
    expect(law.at(_at(400.0)), 4.0);
    // No extrapolation: the ends hold.
    expect(law.at(_at(100.0)), 2.0);
    expect(law.at(_at(900.0)), 5.0);
    expect(law.problems(), isEmpty);
    expect(
      const TableLaw(0, xs: <double>[1.0, 1.0], ys: <double>[0, 0]).problems(),
      isNotEmpty,
    );
  });

  test('a table at a point is that point, to the bit', () {
    final rng = math.Random(7);
    final xs = <double>[
      for (var i = 0; i < 20; i++) 250.0 + 10.0 * i + rng.nextDouble(),
    ];
    final ys = <double>[for (var i = 0; i < 20; i++) rng.nextDouble() * 1e-3];
    final law = TableLaw(ys[7], xs: xs, ys: ys);
    for (var i = 0; i < xs.length; i++) {
      expect(law.at(_at(xs[i])), ys[i]);
    }
  });

  test('a formula carries its unit and evaluates on the state', () {
    final law = FormulaLaw.andrade(
      1.002e-3,
      a: -13.22087,
      b: 1858.706,
      unit: 'Pa·s',
    );
    expect(law.dimension, Unit.pascalSecond.dimension);
    final expected = math.exp(-13.22087 + 1858.706 / 293.15);
    expect(law.at(_at(293.15)), closeTo(expected, expected * 1e-12));
    expect(law.at(_at(350.0)), lessThan(law.at(_at(293.15))));
  });

  test('the factories write the handbook forms', () {
    final arrhenius = FormulaLaw.arrhenius(
      9.891e-4,
      y0: 9.73e-5,
      activation: 21209.3,
      unit: 'Pa·s',
    );
    final at = 9.73e-5 * math.exp(21209.3 / (8.314462618 * 1100.0));
    expect(arrhenius.at(_at(1100.0)), closeTo(at, at * 1e-12));

    final polynomial = FormulaLaw.polynomial(
      998.2,
      coefficients: <double>[751.59611, 1.8912304, -0.0035873694],
      unit: 'kg/m³',
    );
    const t = 293.15;
    expect(
      polynomial.at(_at(t)),
      closeTo(751.59611 + 1.8912304 * t - 0.0035873694 * t * t, 1e-9),
    );
    expect(polynomial.dimension, Unit.kilogramPerCubicMeter.dimension);
  });

  test("a formula's input is held to its valid range", () {
    const law = FormulaLaw(
      0,
      expression: 'T',
      inputs: <String, LawInput>{
        'T': LawInput(
          MatterState.temperatureId,
          unit: Unit.kelvin,
          low: 273.15,
          high: 373.15,
        ),
      },
    );
    expect(law.at(_at(200.0)), 273.15);
    expect(law.at(_at(300.0)), 300.0);
    expect(law.at(_at(500.0)), 373.15);
  });

  test("a formula reads a plugin's quantity of the state", () {
    const law = FormulaLaw(
      0.6,
      expression: '0.6 * (1.0 - 0.5 * w)',
      inputs: <String, LawInput>{'w': LawInput(MatterState.wetnessId)},
    );
    expect(law.at(const MatterState()), 0.6);
    expect(
      law.at(
        const MatterState().withQuantity(
          MatterState.wetnessId,
          const Quantity(1.0, Unit.one),
        ),
      ),
      0.3,
    );
  });

  test('every kind survives its file, with what it says of itself', () {
    final laws = <PropertyLaw>[
      const ConstantLaw(
        0.6,
        confidence: Confidence.estimate,
        source: 'a rule of thumb',
        interval: PropertyInterval(0.5, 0.7),
      ),
      const TableLaw(
        4182.0,
        xs: <double>[273.16, 293.15, 363.16],
        ys: <double>[4219.4, 4182.0, 4205.2],
        confidence: Confidence.handbook,
      ),
      FormulaLaw.andrade(1.0, a: -13.0, b: 1800.0, unit: 'Pa·s'),
    ];
    for (final law in laws) {
      final read = _again(law);
      expect(read, law, reason: law.kind);
      expect(read.at(_at(310.0)), law.at(_at(310.0)), reason: law.kind);
      expect(read.confidence, law.confidence);
      expect(read.interval, law.interval);
    }
  });

  test('a law of a kind this build does not know reads as its value, kept', () {
    final json = <String, Object?>{
      'value': 0.5,
      'law': 'spline',
      'knots': <double>[1, 2, 3],
    };
    final read = PropertyLaw.fromJson(json);
    expect(read, isA<ConstantLaw>());
    expect(read.at(_at(1000.0)), 0.5);
    expect(read.toJson(), json);
  });

  test('a formula that does not read, or is not a number, is refused', () {
    expect(
      () => PropertyLaw.fromJson(<String, Object?>{
        'value': 1.0,
        'law': 'formula',
        'expression': 'T + 1 [m]',
      }),
      throwsA(isA<MaterialFormatException>()),
    );
    expect(
      () => PropertyLaw.fromJson(<String, Object?>{
        'value': 1.0,
        'law': 'formula',
        'expression': 'T > 1 [K]',
      }),
      throwsA(isA<MaterialFormatException>()),
    );
    expect(
      () => PropertyLaw.fromJson('hot', where: '"thermal.emissivity"'),
      throwsA(
        isA<MaterialFormatException>().having(
          (e) => e.message,
          'message',
          contains('thermal.emissivity'),
        ),
      ),
    );
  });
}
