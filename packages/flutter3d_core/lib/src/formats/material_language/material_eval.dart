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
/// The caller fills [inputs] with every name in [kMaterialInputs] — a backend
/// that left one out would throw at the one fragment that read it, so
/// [checkMaterialSurface] exists to ask that question once rather than per
/// draw.
final class MaterialSurfaceValues {
  const MaterialSurfaceValues({required this.inputs, required this.sample});

  /// Input name to value, as many numbers as the input's type has components.
  final Map<String, List<double>> inputs;

  /// One texel, RGBA, from the slot the material declared.
  final List<double> Function(MaterialTextureSlot slot, double u, double v)
  sample;
}

/// The colour [program] returns for one fragment: rgb the light the surface
/// emits, a its opacity.
///
/// [program] must already be through [specialiseMaterial] — a parameter has no
/// value until a variant gives it one, and a backend picking a default here
/// would be a backend disagreeing with the compiled shader.
List<double> evaluateMaterial(
  MaterialProgram program,
  MaterialSurfaceValues surface,
) {
  final scope = <String, List<double>>{};
  for (final statement in program.body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        scope[name] = _evaluate(value, surface, scope);
      case MaterialReturn(:final value):
        return _evaluate(value, surface, scope);
    }
  }
  // The parser refuses a body whose last statement is not a return, so this is
  // a program nobody parsed rather than a case with a sensible answer.
  throw StateError('"${program.name}" has no return.');
}

/// Throws [ArgumentError] unless [inputs] answers every name in
/// [kMaterialInputs], with the right number of components.
///
/// A backend calls this once, where it can be seen, rather than discovering a
/// missing input at whichever fragment first reads it.
void checkMaterialSurface(Map<String, List<double>> inputs) {
  for (final input in kMaterialInputs) {
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
