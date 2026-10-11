/// Every `.f3dmat` in the repository reads as it read before the material
/// language stood on the expression language: the same tree, the same
/// GLSL, and the same colour from the software evaluator.
///
///     dart test test/formats/material_language_read_as_before_test.dart
///
/// The record in `test/fixtures/material_language_read.txt` was written by
/// the parser of the release before the rebase, from these same files; the
/// test writes it again with `F3D_WRITE_MATERIAL_RECORD=1`, which is only
/// ever right when the language itself changes on purpose.
///
/// Mutation: let the base parser fold a sum of two constants, and the tree
/// of `rim_glow.f3dmat` changes; take `exp` out of the material's own
/// builtins' exclusion, and a `let exp` in a version 1 file stops reading.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

/// The `.f3dmat` files of the repository, from this package's directory.
const List<String> _sources = <String>[
  'test/fixtures/v1/rim_glow.f3dmat',
  'test/fixtures/v2/rim_glow.f3dmat',
  '../flutter3d/example/shaders/instance_tint.f3dmat',
  '../flutter3d/example/shaders/rim_glow.f3dmat',
  '../flutter3d/example/shaders/toon_hook.f3dmat',
  '../flutter3d_effects/assets_src/liquid.f3dmat',
  '../flutter3d_effects/assets_src/seabed.f3dmat',
];

const String _record = 'test/fixtures/material_language_read.txt';

void main() {
  test('every .f3dmat reads, emits and evaluates as it did', () {
    final text = StringBuffer();
    for (final path in _sources) {
      final program = parseMaterial(File(path).readAsStringSync());
      text.writeln('== $path');
      _describe(program, text);
    }
    final written = text.toString();
    if (Platform.environment['F3D_WRITE_MATERIAL_RECORD'] == '1') {
      File(_record).writeAsStringSync(written);
    }
    expect(written, File(_record).readAsStringSync());
  });

  test('a name the expression language added stays free in a material', () {
    final program = parseMaterial('''
material Free {
  fragment {
    let exp = 2.0;
    let atan2 = exp * 0.5;
    return vec4(albedo * atan2, alpha);
  }
}
''');
    expect(program.body, hasLength(3));
  });
}

void _describe(MaterialProgram program, StringBuffer text) {
  text
    ..writeln(
      'name ${program.name} v${program.languageVersion} '
      '${program.kind} inputs ${program.inputsUsed.toList()..sort()}',
    )
    ..writeln(
      'params ${[for (final p in program.parameters) '${p.name}:${p.type}=${p.defaultValue}${p.uniform ? ' uniform ${p.block}' : ''}']}',
    )
    ..writeln(
      'textures ${[for (final t in program.textures) '${t.name}=${t.bindingName}']}',
    );
  for (final (name, body) in <(String, List<MaterialStatement>?)>[
    ('fragment', program.body),
    ('light', program.light),
    ('vertex', program.vertex),
    ('ambient', program.ambient),
    ('composite', program.composite),
  ]) {
    if (body == null) continue;
    text.writeln('$name:');
    for (final statement in body) {
      text.writeln('  ${statement.accept(const _Statements())}');
    }
  }
  final variant = specializeMaterial(program, MaterialVariant(program.name));
  text.writeln('--- glsl');
  text.writeln(emitMaterialFragment(variant));
  if (variant.vertex != null) {
    text.writeln('--- vertex glsl');
    text.writeln(emitMaterialVertex(variant));
  }
  if (program.kind == MaterialStageKind.surface) {
    text.writeln('--- evaluated');
    for (final facing in <double>[0.05, 0.5, 0.95]) {
      final surface = _surface(facing);
      text.writeln(
        '  at $facing: ${_round(evaluateMaterial(variant, surface))}',
      );
      if (variant.light != null) {
        text.writeln(
          '  light: ${_round(evaluateMaterialLight(variant, surface))}',
        );
      }
    }
  }
}

/// Twelve significant digits: what reads as before is the tree and the
/// GLSL to the character, and the colour to well past what a pixel holds;
/// the last bits are the transcendental functions', which run on
/// `Portable` maths now rather than on the platform's.
String _round(List<double> value) =>
    value.map((v) => v.toStringAsPrecision(12)).join(', ');

MaterialSurfaceValues _surface(double facing) => MaterialSurfaceValues(
  inputs: <String, List<double>>{
    'albedo': <double>[0.8, 0.4, 0.2],
    'alpha': <double>[0.9],
    'normal': <double>[0, 0, 1],
    'view': <double>[0, 0.3, 0.95],
    'nDotV': <double>[facing],
    'metallic': <double>[0.1],
    'roughness': <double>[0.6],
    'occlusion': <double>[0.95],
    'emissive': <double>[0.01, 0.02, 0.03],
    'ambient': <double>[0.2, 0.25, 0.3],
    'uv': <double>[0.25, 0.75],
    'world': <double>[1.5, -0.5, 3.25],
    'instance': <double>[0.3, 0.6, 0.9, 1],
    'lit': <double>[0.7, 0.6, 0.5],
    'sceneDepth': <double>[4],
    'viewDepth': <double>[3.75],
    'scenePosition': <double>[1, 2, 3],
    'lightDir': <double>[0.3, 0.8, 0.52],
    'halfDir': <double>[0.2, 0.7, 0.68],
    'nDotL': <double>[0.52],
    'nDotH': <double>[0.68],
    'vDotH': <double>[0.85],
  },
  sample: (slot, u, v) => <double>[u, v, 0.5, 1],
);

final class _Statements extends MaterialStatementVisitor<String> {
  const _Statements();

  @override
  String visitLet(MaterialLet statement) =>
      'let ${statement.name} = ${statement.value.accept(const _Tree())}';

  @override
  String visitReturn(MaterialReturn statement) =>
      'return ${statement.value.accept(const _Tree())}';

  @override
  String visitOutput(MaterialOutput statement) =>
      'out ${statement.output.name} = '
      '${statement.value.accept(const _Tree())}';

  @override
  String visitUnknown(MaterialStatement statement) => '?';
}

/// The tree, every node with its kind and its type.
final class _Tree extends MaterialExpressionVisitor<String> {
  const _Tree();

  String _all(List<MaterialExpression> list) =>
      list.map((e) => e.accept(this)).join(', ');

  @override
  String visitConstant(MaterialConstant expression) =>
      'const:${expression.type}${expression.value}';

  @override
  String visitInputRef(MaterialInputRef expression) =>
      'input:${expression.input.name}:${expression.type}';

  @override
  String visitParamRef(MaterialParamRef expression) =>
      'param:${expression.parameter.name}:${expression.type}';

  @override
  String visitLocalRef(MaterialLocalRef expression) =>
      'local:${expression.name}:${expression.type}';

  @override
  String visitConstruct(MaterialConstruct expression) =>
      'construct:${expression.type}(${_all(expression.arguments)})';

  @override
  String visitSwizzle(MaterialSwizzle expression) =>
      'swizzle:${expression.type}${expression.components}'
      '(${expression.target.accept(this)})';

  @override
  String visitNegate(MaterialNegate expression) =>
      'negate:${expression.type}(${expression.operand.accept(this)})';

  @override
  String visitBinary(MaterialBinary expression) =>
      'binary:${expression.op}:${expression.type}'
      '(${expression.left.accept(this)}, ${expression.right.accept(this)})';

  @override
  String visitCall(MaterialCall expression) =>
      'call:${expression.builtin.name}:${expression.type}'
      '(${_all(expression.arguments)})';

  @override
  String visitSample(MaterialSample expression) =>
      'sample:${expression.slot.name}(${expression.uv.accept(this)})';

  @override
  String visitUnknown(MaterialExpression expression) => '?';
}
