/// Runs a material's tree, for a backend that has no shading language —
/// `gfx-84n`.
///
/// **The other reader of the tree the emitter writes GLSL from.** Every stage
/// in `flutter3d_cpu` is a person having read GLSL and written the same
/// program in Dart: it works, and it is the one thing about that backend that
/// can drift without anything going red, because nothing checks that the
/// transcription still says what the shader says. A material written in the
/// language has no transcription — `material_glsl.dart` writes GLSL from this
/// tree and this evaluates the same tree.
///
/// **Here rather than in the software backend**, because a backend package may
/// not depend on the engine's formats library: `flutter3d_cpu` has
/// `flutter3d_core` as a *dev* dependency with "nothing in `lib/` reaches it"
/// written beside it, and a backend that imported the engine would invert the
/// direction an application assembles the two in. What is left for the backend
/// is an adapter of about twenty lines, and it lives in the package that
/// already depends on both.
///
/// **It allocates a small list per node per fragment**, which a hand-written
/// stage does not. The software backend is the golden oracle at 64×48 rather
/// than a shipping renderer's fast path, and a material whose author needs it
/// fast there can still be written by hand and registered under the same name.
library;

import 'material_ast.dart';

/// What a fragment of the surface being shaded is, for [evaluateMaterial].
///
/// The caller fills [inputs] with every name in [materialInputs] — a backend
/// that left one out would throw at the one fragment that read it, so
/// [checkMaterialSurface] exists to ask that question once rather than per
/// draw.
final class MaterialSurfaceValues {
  const MaterialSurfaceValues({
    required this.inputs,
    required this.sample,
    this.uniforms = const <String, List<double>>{},
  });

  /// Input name to value, as many numbers as the input's type has components.
  final Map<String, List<double>> inputs;

  /// The draw's value of each `uniform` the program declares — `P8`, what
  /// `RenderMaterial.parameters` bound as `MaterialParams`. One it lacks reads its
  /// default, as the engine's own block reads nothing bound as nought.
  final Map<String, List<double>> uniforms;

  /// One texel, RGBA, from the slot the material declared.
  final List<double> Function(MaterialTextureSlot slot, double u, double v)
  sample;
}

/// The colour [program] returns for one fragment: rgb the light the surface
/// emits, a its opacity.
///
/// [program] must already be through [specializeMaterial] — a parameter has no
/// value until a variant gives it one, and a backend picking a default here
/// would be a backend disagreeing with the compiled shader.
List<double> evaluateMaterial(
  MaterialProgram program,
  MaterialSurfaceValues surface,
) => _run(program.name, program.body, surface);

/// How the surface answers one light, from [program]'s `light` block —
/// `P8`: three numbers, which the caller multiplies by the light's radiance,
/// `n·l` and shadow, as `AccumulateLights` does with `ShadeLight`.
///
/// [surface]'s inputs carry [materialLightInputs] for the light as well as
/// the surface's own. Throws a [StateError] for a program with no block.
List<double> evaluateMaterialLight(
  MaterialProgram program,
  MaterialSurfaceValues surface,
) => _run(
  program.name,
  program.light ?? (throw StateError('"${program.name}" has no light block.')),
  surface,
);

/// What [program]'s `ambient` block gives — version 2: three numbers, the
/// light the surface takes from its surroundings, which the caller treats
/// as `ShadeAmbient` is treated. [surface]'s inputs carry
/// [materialAmbientInputs] as well. Throws a [StateError] for a program
/// with no block.
List<double> evaluateMaterialAmbient(
  MaterialProgram program,
  MaterialSurfaceValues surface,
) => _run(
  program.name,
  program.ambient ??
      (throw StateError('"${program.name}" has no ambient block.')),
  surface,
);

/// What [program]'s `composite` block gives — version 2: `lit`. [surface]'s
/// inputs carry [materialCompositeInputs] as well. Throws a [StateError]
/// for a program with no block.
List<double> evaluateMaterialComposite(
  MaterialProgram program,
  MaterialSurfaceValues surface,
) => _run(
  program.name,
  program.composite ??
      (throw StateError('"${program.name}" has no composite block.')),
  surface,
);

/// `lit` for one fragment of a lit [program], as the emitted `main` adds it
/// up — version 2's hooks and switches included, so a backend that
/// evaluates has one answer to call rather than a second transcription.
///
/// [surface] carries the surface's inputs; [direct] is the lights gathered
/// through the `light` block, already without the directional ones when
/// the state block switched them off — the one part only the caller's loop
/// can know — and [lightmap] the level's baked light at the fragment.
List<double> composeMaterialLit(
  MaterialProgram program,
  MaterialSurfaceValues surface, {
  required List<double> direct,
  required List<double> lightmap,
}) {
  List<double> input(String name) =>
      surface.inputs[name] ??
      (throw StateError('This backend does not know the input "$name".'));
  final albedo = input('albedo');
  final occlusion = input('occlusion');
  final emissive = input('emissive');
  MaterialSurfaceValues adding(Map<String, List<double>> more) =>
      MaterialSurfaceValues(
        inputs: <String, List<double>>{...surface.inputs, ...more},
        uniforms: surface.uniforms,
        sample: surface.sample,
      );

  final indirect = !program.state.environment
      ? const <double>[0, 0, 0]
      : program.ambient != null
      ? evaluateMaterialAmbient(
          program,
          adding(<String, List<double>>{'lightmap': lightmap}),
        )
      : applyBinary('*', albedo, applyBinary('+', input('ambient'), lightmap));
  if (program.composite != null) {
    return evaluateMaterialComposite(
      program,
      adding(<String, List<double>>{'direct': direct, 'indirect': indirect}),
    );
  }
  return applyBinary(
    '+',
    applyBinary('*', applyBinary('+', direct, indirect), occlusion),
    emissive,
  );
}

/// What [program]'s `vertex` block writes for one vertex — version 2: each
/// output it names, by name. [vertex] carries [materialVertexInputs]; an
/// output the block does not write is absent, and the caller keeps its own.
/// Throws a [StateError] for a program with no block.
Map<String, List<double>> evaluateMaterialVertex(
  MaterialProgram program,
  MaterialSurfaceValues vertex,
) {
  final body =
      program.vertex ??
      (throw StateError('"${program.name}" has no vertex block.'));
  final scope = <String, List<double>>{};
  final written = <String, List<double>>{};
  for (final statement in body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        scope[name] = _evaluate(value, vertex, scope);
      case MaterialOutput(:final output, :final value):
        written[output.name] = _evaluate(value, vertex, scope);
      case MaterialReturn():
        throw StateError('"${program.name}"\'s vertex block returns.');
    }
  }
  return written;
}

List<double> _run(
  String name,
  List<MaterialStatement> body,
  MaterialSurfaceValues surface,
) {
  final scope = <String, List<double>>{};
  for (final statement in body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        scope[name] = _evaluate(value, surface, scope);
      case MaterialReturn(:final value):
        return _evaluate(value, surface, scope);
      case MaterialOutput():
        // Only a vertex block writes outputs, and it is run by
        // [evaluateMaterialVertex].
        throw StateError('"$name" writes an output outside a vertex block.');
    }
  }
  // The parser refuses a body whose last statement is not a return, so this is
  // a program nobody parsed rather than a case with a sensible answer.
  throw StateError('"$name" has no return.');
}

/// Throws [ArgumentError] unless [inputs] answers every name in
/// [materialInputs], with the right number of components.
///
/// A backend calls this once, where it can be seen, rather than discovering a
/// missing input at whichever fragment first reads it.
void checkMaterialSurface(Map<String, List<double>> inputs) {
  for (final input in materialInputs) {
    final value = inputs[input.name];
    if (value == null) {
      throw ArgumentError('The surface has no "${input.name}".');
    }
    if (value.length != input.type.components) {
      throw ArgumentError(
        '"${input.name}" is a ${input.type} and was given ${value.length} '
        'components.',
      );
    }
  }
}

List<double> _evaluate(
  MaterialExpression expression,
  MaterialSurfaceValues surface,
  Map<String, List<double>> scope,
) {
  switch (expression) {
    case MaterialConstant(:final value):
      return value;
    case MaterialInputRef(:final input):
      final value = surface.inputs[input.name];
      if (value == null) {
        throw StateError(
          'This backend does not know the surface input "${input.name}".',
        );
      }
      return value;
    case MaterialLocalRef(:final name):
      final value = scope[name];
      if (value == null) {
        throw StateError('"$name" is read before it is bound.');
      }
      return value;
    case MaterialParamRef(:final parameter) when parameter.uniform:
      final value = surface.uniforms[parameter.name];
      return value != null && value.length >= parameter.type.components
          ? value.sublist(0, parameter.type.components)
          : parameter.defaultValue;
    case MaterialParamRef(:final parameter):
      throw StateError(
        'The parameter "${parameter.name}" has no value. Specialise the '
        'program before drawing with it.',
      );
    case MaterialConstruct(:final arguments):
      return <double>[
        for (final argument in arguments)
          ..._evaluate(argument, surface, scope),
      ];
    case MaterialSwizzle(:final target, :final components):
      final value = _evaluate(target, surface, scope);
      return <double>[for (final index in components) value[index]];
    case MaterialNegate(:final operand):
      return <double>[
        for (final component in _evaluate(operand, surface, scope)) -component,
      ];
    case MaterialBinary(:final op, :final left, :final right):
      return applyBinary(
        op,
        _evaluate(left, surface, scope),
        _evaluate(right, surface, scope),
      );
    case MaterialCall(:final builtin, :final arguments):
      return builtin.apply(
        broadcastArguments(<List<double>>[
          for (final argument in arguments) _evaluate(argument, surface, scope),
        ], builtin),
      );
    case MaterialSample(:final slot, :final uv):
      final at = _evaluate(uv, surface, scope);
      return surface.sample(slot, at[0], at[1]);
  }
}
