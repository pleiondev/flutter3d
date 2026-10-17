/// The record of how every `.f3dmat` in the repository reads: its tree, the
/// GLSL of every stage it becomes, and the colour the software evaluator
/// gives it. `material_language_read_as_before_test.dart` holds the files
/// to `test/fixtures/material_language_read.txt`, and
/// `tool/material_record.dart` writes it again, which is only ever right
/// when the language itself changes on purpose or a source joins.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// The `.f3dmat` files of the repository, from this package's directory:
/// a fixture of every version, and the materials that ship.
const List<String> materialRecordSources = <String>[
  'test/fixtures/v1/rim_glow.f3dmat',
  'test/fixtures/v2/rim_glow.f3dmat',
  '../flutter3d/example/shaders/instance_tint.f3dmat',
  '../flutter3d/example/shaders/rim_glow.f3dmat',
  '../flutter3d/example/shaders/toon_hook.f3dmat',
  '../flutter3d_effects/assets_src/liquid.f3dmat',
  '../flutter3d_effects/assets_src/seabed.f3dmat',
  // Version 3: a material's own version and its updates, `directional
  // off`, the instanced and lightmapped vertex halves, and a light block
  // reading the light's row and a light type by name.
  'test/fixtures/v3/rim_glow.f3dmat',
  'test/fixtures/v3/tube_light.f3dmat',
  // And the standard model's injection points: a surface block, a light
  // block reading `standard`, and a plugin's light type in its loop.
  'test/fixtures/v3/sheen_standard.f3dmat',
  '../flutter3d/test/fixtures/materials/hatch.f3dmat',
];

/// Where the record is, from this package's directory.
const String materialRecordPath = 'test/fixtures/material_language_read.txt';

/// The record as the language reads [materialRecordSources] today.
String materialLanguageRecord() {
  final text = StringBuffer();
  for (final path in materialRecordSources) {
    final program = parseMaterial(File(path).readAsStringSync());
    text.writeln('== $path');
    _describe(program, text);
  }
  return text.toString();
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
  // Version 3: the model a material is lit by, written only where it names
  // one, so the record of every other source is what it was.
  if (program.lighting case final lighting?) {
    text.writeln('lighting $lighting');
  }
  for (final (name, body) in <(String, List<MaterialStatement>?)>[
    ('fragment', program.isStandard ? null : program.body),
    ('surface', program.surface),
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
    // Every other stage the block becomes, from version 3, when the
    // instanced and lightmapped halves arrived: the record of a version 2
    // source is what it was before they did.
    if (program.languageVersion >= materialLanguageVariantsVersion) {
      for (final MapEntry(key: stage, value: glsl) in emitMaterialVertexStages(
        variant,
      ).entries.skip(1)) {
        text
          ..writeln('--- vertex glsl $stage')
          ..writeln(glsl);
      }
    }
  }
  if (program.kind == MaterialStageKind.surface) {
    text.writeln('--- evaluated');
    for (final facing in <double>[0.05, 0.5, 0.95]) {
      final surface = _surface(facing);
      if (variant.isStandard) {
        // The standard model writes the surface: what the record holds of
        // the material is what its surface block writes and its answer to
        // the light given the model's own.
        if (variant.surface != null) {
          final written = evaluateMaterialSurface(variant, surface);
          text.writeln(
            '  surface at $facing: ${[for (final MapEntry(:key, :value) in written.entries) '$key ${_round(value)}'].join('; ')}',
          );
        }
      } else {
        text.writeln(
          '  at $facing: ${_round(evaluateMaterial(variant, surface))}',
        );
      }
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
    // Version 3's light row: a light of a plugin's own type, and the
    // `tube` of `tube_light.f3dmat`'s `lighttype`.
    'lightKind': <double>[16],
    'lightParams': <double>[2, 0.5, 0, 0],
    'tube': <double>[1],
    // Version 3's standard model: its own answer to the light.
    'standard': <double>[0.4, 0.3, 0.2],
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

  String _all(List<Expression> list) =>
      list.map((e) => e.accept(this)).join(', ');

  @override
  String visitConstant(ExpressionConstant expression) =>
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
  String visitConstruct(ExpressionConstruct expression) =>
      'construct:${expression.type}(${_all(expression.arguments)})';

  @override
  String visitSwizzle(ExpressionSwizzle expression) =>
      'swizzle:${expression.type}${expression.components}'
      '(${expression.target.accept(this)})';

  @override
  String visitNegate(ExpressionNegate expression) =>
      'negate:${expression.type}(${expression.operand.accept(this)})';

  @override
  String visitBinary(ExpressionBinary expression) =>
      'binary:${expression.op}:${expression.type}'
      '(${expression.left.accept(this)}, ${expression.right.accept(this)})';

  @override
  String visitCall(ExpressionCall expression) =>
      'call:${expression.builtin.name}:${expression.type}'
      '(${_all(expression.arguments)})';

  @override
  String visitSample(MaterialSample expression) =>
      'sample:${expression.slot.name}(${expression.uv.accept(this)})';

  @override
  String visitUnknown(Expression expression) => '?';
}
