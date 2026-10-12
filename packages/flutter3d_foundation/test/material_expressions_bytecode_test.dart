/// Every expression of the repository's `.f3dmat` files gives the same bits
/// from the expression language's closures and from its internal bytecode.
///
///     dart test test/material_expressions_bytecode_test.dart
///
/// A material's expressions are this language's, so the bytecode a later
/// minor may publish has to carry them. The files are read by path, and
/// their expressions picked out by a reader written here: the material
/// language itself is `flutter3d_core`'s, which this package sits under.
/// The reader takes a material's declarations and `let`s for what they are
/// and the rest of its structure as words to step over, and binds the
/// inputs a body reads from [_inputs]. An expression that `sample`s a
/// texture is the material's own and has no opcode, so it is counted rather
/// than compared.
///
/// Mutation: make the bytecode's `clamp` take its bounds the other way
/// round, and the rim's facing differs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_foundation/internal.dart';
import 'package:test/test.dart';

const List<String> _sources = <String>[
  '../flutter3d_core/test/fixtures/v1/rim_glow.f3dmat',
  '../flutter3d_core/test/fixtures/v2/rim_glow.f3dmat',
  '../flutter3d_core/test/fixtures/v3/rim_glow.f3dmat',
  '../flutter3d/example/shaders/instance_tint.f3dmat',
  '../flutter3d/example/shaders/rim_glow.f3dmat',
  '../flutter3d/example/shaders/toon_hook.f3dmat',
  '../flutter3d_effects/assets_src/liquid.f3dmat',
  '../flutter3d_effects/assets_src/seabed.f3dmat',
];

/// The tokens the material language reads, as `materialSyntax` has them.
const ExpressionSyntax _materialSyntax = ExpressionSyntax(
  units: false,
  exponents: false,
  logic: false,
  punctuation: '{}=;:>',
);

/// What a material's bodies read, by name and width: the surface's, a
/// light's, the scene behind a translucent surface, a vertex's, the two
/// hooks', and a full-screen stage's and a kernel's. A name read here and
/// missing from the table fails the test with the name.
const Map<String, int> _inputs = <String, int>{
  'albedo': 3,
  'alpha': 1,
  'normal': 3,
  'view': 3,
  'nDotV': 1,
  'metallic': 1,
  'roughness': 1,
  'occlusion': 1,
  'emissive': 3,
  'ambient': 3,
  'uv': 2,
  'world': 3,
  'instance': 4,
  'lit': 3,
  'lightDir': 3,
  'halfDir': 3,
  'nDotL': 1,
  'nDotH': 1,
  'vDotH': 1,
  'sceneDepth': 1,
  'viewDepth': 1,
  'scenePosition': 3,
  'position': 3,
  'objectNormal': 3,
  'color': 4,
  'origin': 3,
  'lightmap': 3,
  'direct': 3,
  'indirect': 3,
  'cell': 2,
  'size': 2,
};

/// `sample(slot, uv)`: a texture read, which no opcode carries.
final class _Sample extends Expression {
  const _Sample() : super(ExpressionType.vec4);
}

/// Picks every expression out of a material source.
final class _MaterialReader extends ExpressionParser {
  _MaterialReader(String source)
    : super(
        tokenizeExpression(source, syntax: _materialSyntax),
        syntax: _materialSyntax,
      );

  final Map<String, ExpressionType> names = <String, ExpressionType>{};
  final List<Expression> found = <Expression>[];

  List<Expression> read() {
    while (current.kind != 'end') {
      final word = current.kind == 'name' ? current.text : '';
      position++;
      switch (word) {
        case 'param' || 'uniform':
          if (skipIf('(')) {
            expectToken('name', 'a block');
            expectToken(')', '")"');
          }
          final type = expectToken('name', 'a type').text;
          final name = expectToken('name', 'a name').text;
          names[name] = ExpressionType.numeric.values.firstWhere(
            (t) => t.name == type,
          );
          if (skipIf('=')) found.add(this.parseExpression());
        case 'let':
          final name = expectToken('name', 'a name').text;
          expectToken('=', '"="');
          final value = this.parseExpression();
          names[name] = value.type;
          found.add(value);
        case 'out':
          expectToken('name', 'an output');
          expectToken('=', '"="');
          found.add(this.parseExpression());
        case 'return':
          found.add(this.parseExpression());
      }
    }
    return found;
  }

  @override
  Expression resolveName(ExpressionToken name) {
    final type =
        names[name.text] ??
        switch (_inputs[name.text]) {
          final int width => ExpressionType.numeric[width]!,
          null => this.fail(
            '"${name.text}" is not in this test\'s inputs.',
            where: name,
          ),
        };
    return ExpressionVariable(name.text, type);
  }

  @override
  Expression? parseSpecialCall(ExpressionToken name) {
    if (name.text != 'sample') return null;
    expectToken('(', '"("');
    expectToken('name', 'a texture');
    expectToken(',', '","');
    this.parseExpression();
    expectToken(')', '")"');
    return const _Sample();
  }
}

List<int> _bits(List<double> value) => <int>[
  for (final component in value)
    (ByteData(8)..setFloat64(0, component)).getInt64(0),
];

void main() {
  test('every .f3dmat expression runs the same in bytecode', () {
    var compared = 0;
    var sampling = 0;
    for (final path in _sources) {
      final expressions = _MaterialReader(File(path).readAsStringSync()).read();
      for (final expression in expressions) {
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
            reason: '$path: ${const ExpressionCodec().encode(expression)}',
          );
        }
        compared++;
      }
    }
    // 247 when this was written, and none of them samples.
    expect(compared, greaterThanOrEqualTo(240));
    expect(sampling, lessThan(compared));
  });
}
