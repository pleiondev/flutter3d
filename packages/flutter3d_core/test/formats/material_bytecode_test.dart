/// Every expression of every `.f3dmat` in the repository gives the same
/// bits from the expression language's closures and from its internal
/// bytecode.
///
///     dart test test/formats/material_bytecode_test.dart
///
/// A material's expressions are the expression language's, so the bytecode
/// a later minor may publish has to carry them; the ones that `sample` a
/// texture are the material's own and have no opcode, and are counted
/// rather than compared.
///
/// Mutation: make the bytecode's `clamp` take its bounds the other way
/// round, and the rim's facing differs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CompiledExpression;
// The bytecode is internal to the foundation in 1.0, and this is the test
// that holds it to the material fixtures.
// ignore: implementation_imports
import 'package:flutter3d_foundation/src/expressions/expression_bytecode.dart';
import 'package:test/test.dart';

const List<String> _sources = <String>[
  'test/fixtures/v1/rim_glow.f3dmat',
  'test/fixtures/v2/rim_glow.f3dmat',
  '../flutter3d/example/shaders/instance_tint.f3dmat',
  '../flutter3d/example/shaders/rim_glow.f3dmat',
  '../flutter3d/example/shaders/toon_hook.f3dmat',
  '../flutter3d_effects/assets_src/liquid.f3dmat',
  '../flutter3d_effects/assets_src/seabed.f3dmat',
];

List<int> _bits(List<double> value) => <int>[
  for (final component in value)
    (ByteData(8)..setFloat64(0, component)).getInt64(0),
];

void main() {
  test('every .f3dmat expression runs the same in bytecode', () {
    var compared = 0;
    var sampling = 0;
    for (final path in _sources) {
      final program = parseMaterial(File(path).readAsStringSync());
      for (final variant in <MaterialProgram>[
        program,
        specializeMaterial(program, MaterialVariant(program.name)),
      ]) {
        for (final body in <List<MaterialStatement>?>[
          variant.body,
          variant.light,
          variant.vertex,
          variant.ambient,
          variant.composite,
        ]) {
          for (final statement in body ?? const <MaterialStatement>[]) {
            final expression = switch (statement) {
              MaterialLet(:final value) => value,
              MaterialReturn(:final value) => value,
              MaterialOutput(:final value) => value,
              _ => throw StateError('$statement'),
            };
            final ExpressionBytecode bytecode;
            try {
              bytecode = ExpressionBytecode.compile(expression);
            } on UnsupportedError {
              sampling++;
              continue;
            }
            final closures = CompiledExpression(expression);
            for (var seed = 0; seed < 8; seed++) {
              final slots = <List<double>>[
                for (var i = 0; i < closures.variables.length; i++)
                  <double>[
                    for (var c = 0; c < closures.types[i].components; c++)
                      ((seed * 7 + i * 3 + c) % 11) / 4.0 - 1.1,
                  ],
              ];
              final byName = <String, List<double>>{
                for (var i = 0; i < closures.variables.length; i++)
                  closures.variables[i]: slots[i],
              };
              expect(
                _bits(bytecode.runNamed(byName)),
                _bits(closures.evaluate(slots)),
                reason: '$path: $statement',
              );
            }
            compared++;
          }
        }
      }
    }
    expect(compared, greaterThan(40));
    expect(sampling, lessThan(compared));
  });
}
