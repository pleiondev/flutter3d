/// How fast a law runs: a law-shaped expression evaluated a hundred
/// thousand times, by the closures and by the bytecode, inside the test's
/// minute, and every answer the same bits as the first.
///
///     dart test test/expression_speed_test.dart
///
/// A measurement printed rather than a budget asserted: a time bound in a
/// test is a flaky test on a loaded machine, and the minute every test has
/// is the bound. What it prints is the cost of one evaluation of each, for
/// comparing a change against the last one. The VM gives a test no count of
/// the objects it allocated without a service connection, so allocations
/// are left to the profiler; a scalar law allocates one list, its result.
///
/// Mutation: make the closures look up their operator by its symbol on
/// every call again, and the closures' line roughly doubles.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_foundation/src/expressions/expression_bytecode.dart';
import 'package:test/test.dart';

const int _runs = 100000;

List<int> _bits(List<double> value) => <int>[
  for (final component in value)
    (ByteData(8)..setFloat64(0, component)).getInt64(0),
];

void main() {
  test('a law runs a hundred thousand times, the same every time', () {
    // A viscosity: Andrade's law over a temperature, a pressure correction
    // and a clamp, the shape a property law has.
    final law = parseExpression(
      'clamp(mu0 * exp(b / (T - c)) * (1.0 + k * p), 0.0, 10.0)',
      scope: ExpressionScope.quantities(<String, Unit>{
        'mu0': Unit.one,
        'b': Unit.kelvin,
        'c': Unit.kelvin,
        'T': Unit.kelvin,
        'k': Unit.one / Unit.pascal,
        'p': Unit.pascal,
      }),
    );
    final closures = CompiledExpression(law);
    final bytecode = ExpressionBytecode.compile(law);
    const values = <String, double>{
      'mu0': 2.414e-5,
      'b': 247.8,
      'c': 140.0,
      'T': 293.15,
      'k': 1e-9,
      'p': 101325.0,
    };
    final slots = <List<double>>[
      for (final name in closures.variables) <double>[values[name]!],
    ];
    final first = _bits(closures.evaluate(slots));
    expect(_bits(bytecode.run(slots)), first);

    final watch = Stopwatch()..start();
    var same = 0;
    for (var i = 0; i < _runs; i++) {
      // ignore: avoid-self-compare, two timed runs compared so neither is optimised away
      if (closures.evaluate(slots)[0] == closures.evaluate(slots)[0]) same++;
    }
    final closureMicros = watch.elapsedMicroseconds / (2 * _runs);
    watch
      ..reset()
      ..start();
    for (var i = 0; i < _runs; i++) {
      // ignore: avoid-self-compare, two timed runs compared so neither is optimised away
      if (bytecode.run(slots)[0] == bytecode.run(slots)[0]) same++;
    }
    final bytecodeMicros = watch.elapsedMicroseconds / (2 * _runs);
    expect(same, 2 * _runs);
    expect(_bits(closures.evaluate(slots)), first);
    expect(_bits(bytecode.run(slots)), first);
    // ignore: avoid_print
    print(
      'one evaluation: closures ${closureMicros.toStringAsFixed(3)} µs, '
      'bytecode ${bytecodeMicros.toStringAsFixed(3)} µs',
    );
  });
}
