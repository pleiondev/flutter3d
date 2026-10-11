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
import 'package:flutter3d_foundation/src/expressions/expression_ast.dart'
    show expressionPowerLimit;
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

  // Mutation: drop the limit from `verify`'s `pow`, and the program raised
  // to the seventeenth loads.
  test('a power past the limit is refused by the parser and the loader', () {
    final scope = ExpressionScope.quantities(<String, Unit>{'x': Unit.meter});
    expect(
      parseExpression('pow(x, 16.0)', scope: scope).type.dimension,
      Dimension.length.pow(expressionPowerLimit),
    );
    expect(
      () => parseExpression('pow(x, 17.0)', scope: scope),
      throwsA(isA<ExpressionSyntaxException>()),
    );
    expect(
      () => parseExpression('pow(x, -17.0)', scope: scope),
      throwsA(isA<ExpressionSyntaxException>()),
    );

    // The same program written by hand: `pow(x, 16.0)` with its exponent
    // and the dimension it writes both turned to the seventeenth, so the
    // units still agree and only the limit stands in the way.
    final bytes = Uint8List.fromList(
      ExpressionBytecode.compile(
        parseExpression('pow(x, 16.0)', scope: scope),
      ).encode(),
    );
    final data = ByteData.sublistView(bytes);
    final constants = data.getUint16(10, Endian.little);
    final dimensions = data.getUint16(12, Endian.little);
    const header = 24;
    expect(data.getFloat64(header, Endian.little), 16.0);
    data.setFloat64(header, 17.0, Endian.little);
    final stride = Dimension.bases.length + 1;
    final meter = Dimension.bases.indexOf('m');
    var raised = 0;
    for (var d = 0; d < dimensions; d++) {
      final at = header + constants * 8 + d * stride + meter;
      if (data.getInt8(at) == expressionPowerLimit) {
        data.setInt8(at, expressionPowerLimit + 1);
        raised++;
      }
    }
    expect(raised, 1);
    expect(
      () => ExpressionBytecode.decode(bytes),
      throwsA(
        isA<ExpressionBytecodeException>().having(
          (e) => e.message,
          'message',
          contains('not a constant whole number from -16 to 16'),
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
