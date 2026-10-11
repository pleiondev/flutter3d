/// The expression language: what it reads, how it types what it reads, how
/// it refuses, and that the compiled closures answer what the tree says.
///
/// Mutation: make `ExpressionParser.binary` accept a sum of two dimensions,
/// and "a sum across dimensions is refused where it is written" fails; make
/// the closure for `/` multiply, and the fixture comparison fails on its
/// first law.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_foundation/src/expressions/expression_reference.dart';
import 'package:test/test.dart';

import 'expression_fixtures.dart';

Matcher _refused(String message, {int? line, int? column}) => throwsA(
  isA<ExpressionSyntaxException>()
      .having((e) => e.message, 'message', message)
      .having((e) => e.line, 'line', line ?? anything)
      .having((e) => e.column, 'column', column ?? anything),
);

/// The bits of each component, so two answers compare to the last bit and
/// NaN equals NaN.
List<int> _bits(List<double> value) => <int>[
  for (final component in value)
    (ByteData(8)..setFloat64(0, component)).getInt64(0),
];

void main() {
  group('reading', () {
    test('a number in a unit is kept in the coherent unit', () {
      final celsius = parseExpression('20 [°C]') as ExpressionConstant;
      expect(celsius.value.single, closeTo(293.15, 1e-12));
      expect(celsius.type, ExpressionType.measuring(Unit.kelvin));
      final speed = parseExpression('36 [km/h]') as ExpressionConstant;
      expect(speed.value.single, closeTo(10, 1e-12));
      expect(speed.type.dimension, Unit.meterPerSecond.dimension);
    });

    test('a product makes its unit and a sum keeps one', () {
      final scope = ExpressionScope.quantities(<String, Unit>{
        'm': Unit.kilogram,
        'v': Unit.meterPerSecond,
      });
      final energy = parseExpression('0.5 * m * v * v', scope: scope);
      expect(energy.type.dimension, Unit.joule.dimension);
      final sum = parseExpression('v + 1 [km/h]', scope: scope);
      expect(sum.type.dimension, Unit.meterPerSecond.dimension);
    });

    test('a sum across dimensions is refused where it is written', () {
      final scope = ExpressionScope.quantities(<String, Unit>{
        'T': Unit.kelvin,
      });
      expect(
        () => parseExpression('T + 1 [s]', scope: scope),
        _refused(
          'a float [K] and a float [s] cannot be added: they measure '
          'different things.',
          line: 1,
          column: 3,
        ),
      );
      expect(
        () => parseExpression('T < 3 [m]', scope: scope),
        _refused(
          'a float [K] and a float [m] cannot be compared: they measure '
          'different things.',
        ),
      );
    });

    test('a builtin checks the units of what it is given', () {
      final scope = ExpressionScope.quantities(<String, Unit>{
        'T': Unit.kelvin,
        'r': Unit.meter,
      });
      expect(
        () => parseExpression('exp(T)', scope: scope),
        _refused('exp takes a pure number, and was given float [K].'),
      );
      expect(
        parseExpression('sqrt(r * r)', scope: scope).type.dimension,
        Dimension.length,
      );
      expect(
        () => parseExpression('sqrt(r)', scope: scope),
        _refused(
          'sqrt takes a dimension whose exponents are even, and was given '
          'float [m].',
        ),
      );
      expect(
        parseExpression('pow(r, 3.0)', scope: scope).type.dimension,
        Dimension.length.pow(3),
      );
      expect(
        () => parseExpression('pow(r, 0.5)', scope: scope),
        throwsA(isA<ExpressionSyntaxException>()),
      );
      expect(parseExpression('sin(30 [°])').type, ExpressionType.float);
    });

    test('a condition is a bool, and arithmetic does not take one', () {
      expect(parseExpression('1.0 < 2.0').type, ExpressionType.boolean);
      expect(
        () => parseExpression('(1.0 < 2.0) + 1.0'),
        _refused('"+" works on numbers, not on a bool.'),
      );
      expect(
        () => parseExpression('1.0 ? 2.0 : 3.0'),
        _refused('a condition is a bool, and this is a float.'),
      );
      expect(
        () => parseExpression('1.0 < 2.0 < 3.0'),
        _refused('comparisons do not chain: write "a < b && b < c".'),
      );
      expect(
        () => parseExpression('true && 1.0'),
        _refused('"&&" takes two bools, and was given a bool and a float.'),
      );
    });

    test('a name nobody bound, a unit nobody knows, and trailing text', () {
      expect(
        () => parseExpression('T * 2.0'),
        _refused('"T" is not bound here.', line: 1, column: 1),
      );
      expect(
        () => parseExpression('2.0 [furlong]'),
        _refused('"[furlong]" is not a unit: no unit "furlong".'),
      );
      expect(
        () => parseExpression('2.0 3.0'),
        _refused('nothing follows the expression, and "3.0" does.'),
      );
      expect(
        () => parseExpression('2.0 # 3.0'),
        _refused('"#" is not part of this language.'),
      );
    });

    test('a host language takes only the tokens it names', () {
      const arithmetic = ExpressionSyntax(
        units: false,
        exponents: false,
        logic: false,
      );
      expect(
        () => parseExpression('1.0 < 2.0', syntax: arithmetic),
        _refused('"<" is not part of this language.'),
      );
      expect(
        () => parseExpression('2.0 [m]', syntax: arithmetic),
        _refused('"[" is not part of this language.'),
      );
    });

    test('the visitor reaches a host kind as a variable, an unknown one as '
        'unknown', () {
      final names = _Names();
      parseExpression(
        'a * clamp(b, 0.0, 1.0)',
        scope: const ExpressionScope(
          variables: <String, ExpressionType>{
            'a': ExpressionType.float,
            'b': ExpressionType.float,
          },
        ),
      ).accept(names);
      expect(names.seen, <String>['a', 'b']);
      expect(const _Foreign().accept(names), 'unknown');
    });
  });

  group('evaluating', () {
    test('the closures answer what the tree says, bit for bit', () {
      for (final fixture in expressionFixtures) {
        final expression = parseExpression(
          fixture.source,
          scope: fixture.scope,
        );
        final compiled = CompiledExpression(expression);
        for (final values in fixture.values) {
          final reference = evaluateExpressionReference(expression, values);
          final closures = compiled.evaluate(<List<double>>[
            for (final name in compiled.variables) values[name]!,
          ]);
          expect(
            _bits(closures),
            _bits(reference),
            reason: '${fixture.source} at $values',
          );
        }
        if (fixture.expected case final expected?) {
          final value = evaluateExpressionReference(
            expression,
            fixture.values.first,
          );
          for (var i = 0; i < expected.length; i++) {
            expect(
              value[i],
              closeTo(expected[i], 1e-9 * (1 + expected[i].abs())),
              reason: fixture.source,
            );
          }
        }
      }
    });

    test('a law takes quantities in any unit of its dimension', () {
      final law = CompiledExpression(
        parseExpression(
          '1.8e-6 [Pa·s] * exp(1850 [K] / T)',
          scope: ExpressionScope.quantities(<String, Unit>{'T': Unit.kelvin}),
        ),
      );
      final atKelvin = law.quantity(<String, Object>{
        'T': const Quantity(293.15, Unit.kelvin),
      });
      final atCelsius = law.quantity(<String, Object>{
        'T': const Quantity(20, Unit.celsius),
      });
      expect(atKelvin.unit, Unit.pascalSecond);
      expect(atCelsius.value, atKelvin.value);
      expect(
        atKelvin.value,
        closeTo(1.8e-6 * 550.46, 1e-8),
        reason: 'exp(1850 / 293.15) is about 550.46',
      );
      expect(
        () =>
            law.quantity(<String, Object>{'T': const Quantity(1, Unit.meter)}),
        throwsA(isA<UnitMismatchException>()),
      );
      expect(() => law.quantity(const <String, Object>{}), throwsArgumentError);
    });

    test('a condition answers a truth value, only its chosen branch runs', () {
      final condition = CompiledExpression(
        parseExpression(
          'p > 0 [Pa] && 1 [Pa] / p > 0.5 ? true : false',
          scope: ExpressionScope.quantities(<String, Unit>{'p': Unit.pascal}),
        ),
      );
      expect(
        condition.truth(<String, Object>{'p': const Quantity(1, Unit.pascal)}),
        isTrue,
      );
      expect(
        condition.truth(<String, Object>{'p': const Quantity(0, Unit.pascal)}),
        isFalse,
      );
    });

    test('Portable maths, not the platform\'s', () {
      final value = CompiledExpression(
        parseExpression(
          'sin(x)',
          scope: const ExpressionScope(
            variables: <String, ExpressionType>{'x': ExpressionType.float},
          ),
        ),
      ).evaluateNamed(<String, Object>{'x': 1.0e5});
      expect(value.single, Portable.sin(1.0e5));
    });
  });

  group('the codec', () {
    test('writes text that reads back to the same tree', () {
      for (final fixture in expressionFixtures) {
        final codec = ExpressionCodec(scope: fixture.scope);
        final expression = codec.decode(fixture.source);
        final text = codec.encode(expression);
        final again = codec.decode(text);
        expect(codec.encode(again), text, reason: fixture.source);
        expect(again.type, expression.type, reason: text);
        for (final values in fixture.values) {
          expect(
            _bits(evaluateExpressionReference(again, values)),
            _bits(evaluateExpressionReference(expression, values)),
            reason: text,
          );
        }
      }
    });

    test('a number in a unit is stored in the coherent unit', () {
      const codec = ExpressionCodec();
      expect(codec.encode(codec.decode('20 [°C]')), '293.15 [K]');
      expect(codec.encode(codec.decode('-2 [km]')), '(-2000.0 [m])');
      expect(codec.toJson(codec.decode('1.0 + 2.0')), '(1.0 + 2.0)');
      expect(
        () => codec.fromJson(3),
        throwsA(isA<ExpressionSyntaxException>()),
      );
    });
  });
}

final class _Names extends ExpressionVisitor<String> {
  final List<String> seen = <String>[];

  @override
  String visitConstant(ExpressionConstant expression) => 'constant';

  @override
  String visitVariable(ExpressionVariable expression) {
    seen.add(expression.name);
    return expression.name;
  }

  @override
  String visitConstruct(ExpressionConstruct expression) => 'construct';

  @override
  String visitSwizzle(ExpressionSwizzle expression) => 'swizzle';

  @override
  String visitNegate(ExpressionNegate expression) => 'negate';

  @override
  String visitNot(ExpressionNot expression) => 'not';

  @override
  String visitBinary(ExpressionBinary expression) {
    expression.left.accept(this);
    expression.right.accept(this);
    return 'binary';
  }

  @override
  String visitCall(ExpressionCall expression) {
    for (final argument in expression.arguments) {
      argument.accept(this);
    }
    return 'call';
  }

  @override
  String visitConditional(ExpressionConditional expression) => 'conditional';

  @override
  String visitUnknown(Expression expression) => 'unknown';
}

final class _Foreign extends Expression {
  const _Foreign() : super(ExpressionType.float);
}
