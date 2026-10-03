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
/// **What it does not emit is as deliberate.** No uniform block of its own
/// but one: the engine's shared blocks are frozen by offset agreement across
/// four backends, and the one block a material may add — `MaterialParams`,
/// filled from `Material.parameters` — is written for the program's
/// `uniform`s, and only when it has one (`P8`); a `param` is still a folded
/// constant. No sampler declaration, because `surface.glsl` already declares the ones the
/// engine binds and a second declaration is a duplicate symbol. No `#define`
/// the author chose, because a material that could switch headers on and off
/// could turn off the surface buffer and lie to every screen-space effect.
library;

import '../lighting_model.dart';
import 'material_ast.dart';

/// The `.frag` source for [program], which should already be specialised.
///
/// [describeMaterial] answers the other half — what the engine may bind to it.
String emitMaterialFragment(MaterialProgram program) {
  final light = program.light;
  final out = StringBuffer()
    ..writeln('#version 460 core')
    ..writeln()
    ..writeln('// Generated from a material written in the material language')
    ..writeln('// — gfx-84n. The source is the thing to edit; this file is')
    ..writeln('// what the shader build compiles and what the three GPU')
    ..writeln('// backends translate. The software backend evaluates the same')
    ..writeln('// tree instead of reading this.');
  if (light == null) {
    // It gathers no lights, so it keeps no light list — see
    // `LightingModel.usesLightList` — and no point-shadow block either, as
    // `unlit.frag` keeps none: a block declared and never bound is a
    // refused draw on WebGL2.
    out
      ..writeln('#define F3D_NO_POINT_SHADOW')
      ..writeln('#define F3D_NO_LIGHT_LIST')
      ..writeln('#include <lib/surface.glsl>')
      ..writeln();
  } else {
    // `P8`: a material with a lighting hook is a lit model, and includes
    // what `lambert.frag` does — the maps, the shadows, the light list.
    out
      ..writeln('#include <lib/material_maps.glsl>')
      ..writeln('#include <lib/shadow.glsl>')
      ..writeln();
  }

  // `P8`: an instance's own numbers, declared after every header's inputs so
  // it takes the location the engine's vertex stages give it, after
  // `v_lightmap_uv` — and only when read, since a varying no stage writes is
  // a link error on a stage that writes it not.
  if (program.inputsUsed.contains('instance')) {
    out
      ..writeln('in vec4 v_instance;')
      ..writeln();
  }

  // `P8`: the uniforms, as the block the engine binds `Material.parameters`
  // to. Declaration order, as std140 lays it out and every backend's
  // reflection reports it.
  final uniforms = <MaterialParameter>[
    for (final parameter in program.parameters)
      if (parameter.uniform) parameter,
  ];
  if (uniforms.isNotEmpty) {
    out.writeln('uniform MaterialParams {');
    for (final parameter in uniforms) {
      out.writeln('  ${parameter.type.name} ${parameter.name};');
    }
    out
      ..writeln('}')
      ..writeln('material_params;')
      ..writeln();
  }

  if (light == null) {
    // Both prototypes have to be satisfied whether or not anything calls
    // them, which is what `unlit.frag` says about its own pair. A material
    // without a `light` block never accumulates lights — it returns the light
    // the surface emits — so these are the same honest stubs.
    out
      ..writeln('// Never called: this material returns the light its surface')
      ..writeln('// emits rather than gathering any. The prototypes in')
      ..writeln('// surface.glsl still have to be satisfied.')
      ..writeln('vec3 ShadeLight(Surface s, LightSample light) {')
      ..writeln('  return s.albedo;')
      ..writeln('}')
      ..writeln()
      ..writeln('float LightVisibility(Surface s, LightSample light, int i) {')
      ..writeln('  return 1.0;')
      ..writeln('}')
      ..writeln();
  } else {
    // The `light` block is `ShadeLight`, which `AccumulateLights` multiplies
    // by the light's radiance, n·l and visibility; the visibility is the
    // shadow, as every lit model of the engine's has it.
    out
      ..writeln('// The material\'s light block, run once per light.')
      ..writeln('vec3 ShadeLight(Surface s, LightSample light) {');
    _statements(out, light, (value) => '  return ${_glsl(value)};');
    out
      ..writeln('}')
      ..writeln()
      ..writeln('float LightVisibility(Surface s, LightSample light, int i) {')
      ..writeln('  return ShadowFactor(s, light, i);')
      ..writeln('}')
      ..writeln();
  }

  out
    ..writeln('void main() {')
    ..writeln('  Surface s = ReadSurface();');
  if (light != null) {
    // `lit` as `lambert.frag` adds it up — see `kMaterialLitInput`.
    out
      ..writeln('  ApplyCommonMaps(s);')
      ..writeln(
        '  vec3 lit = AccumulateLights(s) * s.occlusion + '
        's.albedo * (s.ambient + SampleLightmap()) * s.occlusion + '
        's.emissive;',
      );
  }
  _statements(
    out,
    program.body,
    (value) =>
        '  vec4 result = ${_glsl(value)};\n'
        '  WriteSurface(result.rgb, result.a);',
  );
  out.writeln('}');
  return out.toString();
}

/// Writes [body]'s bindings, and its return as [returns] spells it.
void _statements(
  StringBuffer out,
  List<MaterialStatement> body,
  String Function(MaterialExpression value) returns,
) {
  for (final statement in body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        out.writeln('  ${value.type.name} $name = ${_glsl(value)};');
      case MaterialReturn(:final value):
        out.writeln(returns(value));
    }
  }
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
  // `P8`: a lighting hook makes it a lit model, which applies the normal,
  // occlusion and emissive maps and reads the shadows and the light list —
  // all of it live, because the parser holds the fragment body to reading
  // `lit`, which adds every one of them up.
  final lit = program.light != null;

  // A material that reads nothing off the lit surface still goes through
  // `ReadSurface`, which is what applies the base colour tint and the mask
  // cutoff — so `FragInfo` is always read and always bound, the way it is for
  // every model except `Normals`.
  return MaterialBindings(
    name: program.name,
    // Always: `ReadSurface` samples the base colour map for the albedo every
    // material reads, whether or not the source names the slot. Asked of the
    // source alone, a material that never wrote `texture` was drawn with the
    // map unbound — black on Impeller and a refused draw on WebGL2, found
    // the first time one was drawn on a GPU (`P8`, `material-language`).
    usesAlbedoTexture: true,
    usesMaterialMaps:
        lit ||
        samples.contains('normal_texture') ||
        samples.contains('occlusion_texture') ||
        samples.contains('emissive_texture') ||
        samples.contains('metallic_roughness_texture'),
    usesMetallicRoughnessMap: samples.contains('metallic_roughness_texture'),
    usesMetallic: reads.contains('metallic'),
    usesLightList: lit,
    uniforms: <String, List<double>>{
      for (final parameter in program.parameters)
        if (parameter.uniform) parameter.name: parameter.defaultValue,
    },
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
    this.usesLightList = false,
    this.uniforms = const <String, List<double>>{},
  });

  final String name;
  final bool usesAlbedoTexture;
  final bool usesMaterialMaps;
  final bool usesMetallicRoughnessMap;
  final bool usesMetallic;

  /// Each `uniform` the program declares, with its default, in declaration
  /// order — `P8`: the members of the `MaterialParams` block, and what
  /// `Material.parameters` has to hold for the renderer to bind it.
  final Map<String, List<double>> uniforms;

  /// Whether the stage declares `MaterialParams`, which is whether the
  /// program has a uniform.
  bool get usesMaterialParameters => uniforms.isNotEmpty;

  /// Whether the stage gathers lights: true for a material with a `light`
  /// block — `P8` — and false for one that returns the light its surface
  /// emits, whose stage declares no light list.
  final bool usesLightList;

  /// The [LightingModel] these bindings describe, with the label and entry
  /// point the application chose.
  ///
  /// **Build the model here, not by hand.** Every flag comes off the program,
  /// [usesLightList] included, which a hand-built model gets wrong the moment
  /// the material samples a map: `LightingModel` defaults the list to its maps,
  /// the emitted stage never declares it, and the bind is a thrown "Failed to
  /// bind texture" on Impeller and a dropped draw on WebGL.
  LightingModel lightingModel({
    required String label,
    required String shaderName,
    String? vertexShaderName,
    bool vertexStageMorphs = true,
  }) => LightingModel(
    label,
    shaderName,
    vertexShaderName: vertexShaderName,
    usesAlbedoTexture: usesAlbedoTexture,
    usesMaterialMaps: usesMaterialMaps,
    usesMetallicRoughnessMap: usesMetallicRoughnessMap,
    usesMetallic: usesMetallic,
    usesLightList: usesLightList,
    usesMaterialParameters: usesMaterialParameters,
    vertexStageMorphs: vertexStageMorphs,
  );
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
    case MaterialParamRef(:final parameter) when parameter.uniform:
      return 'material_params.${parameter.name}';
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
      // The language spreads a float beside a vector for every component-wise
      // builtin, and `broadcastArguments` evaluates it that way; GLSL does only
      // for some positions of some of them — `pow(vec3, float)`,
      // `mix(float, vec3, float)` and `min(float, vec3)` do not compile. So the
      // spread is written out, which every overload accepts and which says
      // what the software backend computes.
      var width = 1;
      for (final argument in arguments) {
        if (argument.type.components > width) width = argument.type.components;
      }
      String spread(MaterialExpression argument) {
        final text = _glsl(argument);
        return builtin.componentWise &&
                width > 1 &&
                argument.type.components == 1
            ? '${MaterialType.numeric[width]!.name}($text)'
            : text;
      }

      return '${builtin.glsl}(${arguments.map(spread).join(', ')})';
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
