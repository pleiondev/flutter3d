/// Turns a parsed material into the GLSL this engine's shader build already
/// compiles — `gfx-84n`.
///
/// **It emits into the existing convention rather than beside it.** The result
/// is a `.frag` shaped exactly like `unlit.frag`: it includes
/// `<lib/surface.glsl>`, satisfies the `ShadeLight` and `LightVisibility`
/// prototypes that header declares, reads the surface with `ReadSurface()` and
/// writes it with `WriteSurface()`. That is what "through the existing
/// generators" means in the row's acceptance — `impellerc` compiles it,
/// `glsl_translate.dart` turns it into GLSL ES 3.00 for WebGL2, and
/// `glsl_to_wgsl.dart` prepares it for glslang and naga, all without knowing a
/// material language exists.
///
/// **What it does not emit is as deliberate.** No uniform block, because the
/// engine's blocks are frozen by offset agreement across four backends. No
/// sampler declaration, because `surface.glsl` already declares the ones the
/// engine binds and a second declaration is a duplicate symbol. No `#define`
/// the author chose, because a material that could switch headers on and off
/// could turn off the surface buffer and lie to every screen-space effect.
library;

import 'material_ast.dart';

/// The `.frag` source for [program], which should already be specialised.
///
/// [describeMaterial] answers the other half — what the engine may bind to it.
String emitMaterialFragment(MaterialProgram program) {
  final out = StringBuffer()
    ..writeln('#version 460 core')
    ..writeln()
    ..writeln('// Generated from a material written in the material language')
    ..writeln('// — gfx-84n. The source is the thing to edit; this file is')
    ..writeln('// what the shader build compiles and what the three GPU')
    ..writeln('// backends translate. The software backend evaluates the same')
    ..writeln('// tree instead of reading this.')
    ..writeln('#include <lib/surface.glsl>')
    ..writeln();

  // Both prototypes have to be satisfied whether or not anything calls them,
  // which is what `unlit.frag` says about its own pair. A material in this
  // language never accumulates lights — it returns the light the surface
  // emits — so these are the same honest stubs.
  out
    ..writeln('// Never called: a material in this language returns the light')
    ..writeln('// its surface emits rather than gathering any. The prototypes')
    ..writeln('// in surface.glsl still have to be satisfied.')
    ..writeln('vec3 ShadeLight(Surface s, LightSample light) {')
    ..writeln('  return s.albedo;')
    ..writeln('}')
    ..writeln()
    ..writeln('float LightVisibility(Surface s, LightSample light, int i) {')
    ..writeln('  return 1.0;')
    ..writeln('}')
    ..writeln()
    ..writeln('void main() {')
    ..writeln('  Surface s = ReadSurface();');

  for (final statement in program.body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        out.writeln('  ${value.type.name} $name = ${_glsl(value)};');
      case MaterialReturn(:final value):
        out
          ..writeln('  vec4 result = ${_glsl(value)};')
          ..writeln('  WriteSurface(result.rgb, result.a);');
    }
  }

  out.writeln('}');
  return out.toString();
}

/// What the engine may bind to [program]'s compiled shader.
///
/// **The row asks the toolchain to generate the binding metadata, and this is
/// it.** `LightingModel`'s `uses…` flags are hand-declared today, under a
/// comment saying why reflection cannot answer the question: a compiled shader
/// keeps a uniform block only if something reads it, and binding one it
/// dropped segfaults inside Metal with no Dart stack trace. A material this
/// package parsed is a different case — what it reads is written down, so the
/// flags come from the tree rather than from somebody remembering.
///
/// Nothing here answers for a vertex stage. `gfx-75n` took that seam and this
/// language describes a fragment body only, so a material that wants its own
/// vertex stage names an entry point the bundle already has.
MaterialBindings describeMaterial(MaterialProgram program) {
  final samples = <String>{
    for (final slot in program.textures) slot.bindingName,
  };
  final reads = program.inputsUsed;

  // A material that reads nothing off the lit surface still goes through
  // `ReadSurface`, which is what applies the base colour tint and the mask
  // cutoff — so `FragInfo` is always read and always bound, the way it is for
  // every model except `Normals`.
  return MaterialBindings(
    name: program.name,
    usesAlbedoTexture: samples.contains('base_color_texture'),
    usesMaterialMaps:
        samples.contains('normal_texture') ||
        samples.contains('occlusion_texture') ||
        samples.contains('emissive_texture') ||
        samples.contains('metallic_roughness_texture'),
    usesMetallicRoughnessMap: samples.contains('metallic_roughness_texture'),
    usesMetallic: reads.contains('metallic'),
  );
}

/// What [describeMaterial] found, in the shape `LightingModel` takes.
///
/// A record of the answer rather than a `LightingModel` itself, because
/// building one needs a label and a vertex stage name that are the
/// application's to choose — and because this package would otherwise decide
/// how a material is shown in a picker.
final class MaterialBindings {
  const MaterialBindings({
    required this.name,
    required this.usesAlbedoTexture,
    required this.usesMaterialMaps,
    required this.usesMetallicRoughnessMap,
    required this.usesMetallic,
  });

  final String name;
  final bool usesAlbedoTexture;
  final bool usesMaterialMaps;
  final bool usesMetallicRoughnessMap;
  final bool usesMetallic;
}

String _glsl(MaterialExpression expression) {
  switch (expression) {
    case MaterialConstant(:final value, :final type):
      if (type == MaterialType.float) return _number(value.single);
      return '${type.name}(${value.map(_number).join(', ')})';
    case MaterialInputRef(:final input):
      return input.glsl;
    case MaterialLocalRef(:final name):
      return name;
    case MaterialParamRef(:final parameter):
      // Reachable only for a program nothing specialised, which is a caller
      // skipping a step rather than a shape this emitter supports: a
      // parameter has no GLSL, because it is not a uniform.
      throw StateError(
        'The parameter "${parameter.name}" has no value. Call '
        'specialiseMaterial before emitting.',
      );
    case MaterialConstruct(:final arguments, :final type):
      return '${type.name}(${arguments.map(_glsl).join(', ')})';
    case MaterialSwizzle(:final target, :final components):
      const letters = 'xyzw';
      final field = components.map((i) => letters[i]).join();
      return '${_glsl(target)}.$field';
    case MaterialNegate(:final operand):
      return '-(${_glsl(operand)})';
    case MaterialBinary(:final op, :final left, :final right):
      // Fully parenthesised rather than tracking precedence a second time:
      // the parser already decided the shape, and an emitter that re-derived
      // it could put the brackets somewhere the tree does not mean.
      return '(${_glsl(left)} $op ${_glsl(right)})';
    case MaterialCall(:final builtin, :final arguments):
      return '${builtin.glsl}(${arguments.map(_glsl).join(', ')})';
    case MaterialSample(:final slot, :final uv):
      return 'texture(${slot.bindingName}, ${_glsl(uv)})';
  }
}

/// A GLSL float literal, which always has a decimal point.
///
/// `2` is an `int` in GLSL, and `pow(x, 2)` fails to compile against a
/// `pow(float, float)` overload — a whole number reaching the shader without
/// its point is the classic way a generated shader stops building.
String _number(double value) {
  if (!value.isFinite) {
    throw ArgumentError('$value cannot be written as a GLSL literal.');
  }
  final text = value.toString();
  return text.contains('.') || text.contains('e') ? text : '$text.0';
}
