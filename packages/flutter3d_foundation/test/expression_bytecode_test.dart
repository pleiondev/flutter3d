/// The internal bytecode: it answers what the closures answer, bit for bit,
/// on every expression fixture; it survives its own encoding; and it
/// refuses a program whose units do not add up when it is loaded.
///
/// Mutation: make the interpreter's `dot` sum from the last lane, and the
/// fixture comparison fails on `sqrt(dot(v, v)) - length(v)`; drop the unit
/// check of `add` from `verify`, and the tampered program loads.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_foundation/src/expressions/expression_bytecode.dart';
import 'package:test/test.dart';

import 'expression_fixtures.dart';

List<int> _bits(List<double> value) => <int>[
  for (final component in value)
    (ByteData(8)..setFloat64(0, component)).getInt64(0),
];

void main() {
  test('the bytecode answers what the closures answer, bit for bit', () {
    for (final fixture in expressionFixtures) {
      final expression = parseExpression(fixture.source, scope: fixture.scope);
      final closures = CompiledExpression(expression);
      final bytecode = ExpressionBytecode.compile(expression);
      final decoded = ExpressionBytecode.decode(bytecode.encode());
      for (final values in fixture.values) {
        final expected = _bits(
          closures.evaluate(<List<double>>[
            for (final name in closures.variables) values[name]!,
          ]),
        );
        expect(
          _bits(bytecode.runNamed(values)),
          expected,
          reason: '${fixture.source} at $values',
        );
        expect(_bits(decoded.runNamed(values)), expected);
      }
    }
  });

  test('the header names the format and its version', () {
    final bytes = ExpressionBytecode.compile(
      parseExpression('1.0 + 2.0'),
    ).encode();
    expect(bytes.sublist(0, 4), expressionBytecodeMagic);
    expect(
      ByteData.sublistView(bytes).getUint16(4, Endian.little),
      expressionBytecodeVersion,
    );
    final newer = Uint8List.fromList(bytes)
      ..[4] = expressionBytecodeVersion + 1;
    expect(
      () => ExpressionBytecode.decode(newer),
      throwsA(isA<ExpressionBytecodeException>()),
    );
    expect(
      () => ExpressionBytecode.decode(Uint8List.fromList(<int>[1, 2, 3])),
      throwsA(isA<ExpressionBytecodeException>()),
    );
  });

  test('a program whose units do not add up is refused when loaded', () {
    final scope = ExpressionScope.quantities(<String, Unit>{
      'T': Unit.kelvin,
      'x': Unit.meter,
    });
    final mixed = ExpressionBytecode.compile(
      parseExpression('T * x', scope: scope),
    ).encode();
    final multiply = Uint8List.fromList(mixed);
    final mixedData = ByteData.sublistView(multiply);
    final count = mixedData.getUint16(16, Endian.little);
    final codeAt = multiply.length - count * 16;
    // Turn the multiply into an add: a kelvin plus a meter.
    expect(
      mixedData.getUint16(codeAt + (count - 1) * 16, Endian.little),
      ExpressionOp.multiply,
    );
    mixedData.setUint16(
      codeAt + (count - 1) * 16,
      ExpressionOp.add,
      Endian.little,
    );
    expect(
      () => ExpressionBytecode.decode(multiply),
      throwsA(
        isA<ExpressionBytecodeException>().having(
          (e) => e.message,
          'message',
          contains('adds two units'),
        ),
      ),
    );
  });

  test('a builtin a host added has no opcode, and says so', () {
    const twice = ExpressionBuiltin(
      'twice',
      arity: 1,
      apply: _twice,
      dimension: _same,
      units: 'takes any dimension',
    );
    final expression = parseExpression(
      'twice(2.0)',
      scope: const ExpressionScope(builtins: <ExpressionBuiltin>[twice]),
    );
    expect(CompiledExpression(expression).evaluate(const []), <double>[4]);
    expect(
      () => ExpressionBytecode.compile(expression),
      throwsUnsupportedError,
    );
  });
}

List<double> _twice(List<List<double>> a) => <double>[a[0][0] * 2];

Dimension? _same(List<Expression> a) => a[0].type.dimension;
