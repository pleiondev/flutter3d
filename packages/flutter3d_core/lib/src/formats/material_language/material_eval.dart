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

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        Expression,
        ExpressionBinary,
        ExpressionCall,
        ExpressionConstant,
        ExpressionConstruct,
        ExpressionNegate,
        ExpressionSwizzle;
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
  final runner = _Runner(program.name, vertex, vertexBlock: true);
  for (final statement in body) {
    statement.accept(runner);
  }
  return runner.written;
}

/// What [program]'s `surface` block writes for one fragment — version 3, a
/// material lit by the standard model: each output it names, by name,
/// computed against the surface as read. An output the block does not
/// write is absent, and the caller keeps the surface's own; a written
/// `normal` is the caller's to make unit length, as the emitted stage does.
/// Throws a [StateError] for a program with no block.
Map<String, List<double>> evaluateMaterialSurface(
  MaterialProgram program,
  MaterialSurfaceValues surface,
) {
  final body =
      program.surface ??
      (throw StateError('"${program.name}" has no surface block.'));
  final runner = _Runner(program.name, surface, vertexBlock: true);
  for (final statement in body) {
    statement.accept(runner);
  }
  return runner.written;
}

List<double> _run(
  String name,
  List<MaterialStatement> body,
  MaterialSurfaceValues surface,
) {
  final runner = _Runner(name, surface, vertexBlock: false);
  for (final statement in body) {
    final returned = statement.accept(runner);
    if (returned != null) return returned;
  }
  // The parser refuses a body whose last statement is not a return, so this is
  // a program nobody parsed rather than a case with a sensible answer.
  throw StateError('"$name" has no return.');
}

/// Runs one block's statements in order: a `let` binds, an `out` is
/// written, and a `return` answers its value, which ends the block.
final class _Runner extends MaterialStatementVisitor<List<double>?> {
  _Runner(this.name, MaterialSurfaceValues surface, {required this.vertexBlock})
    : _evaluator = _Evaluator(surface);

  final String name;
  final bool vertexBlock;
  final _Evaluator _evaluator;
  final Map<String, List<double>> written = <String, List<double>>{};

  @override
  List<double>? visitLet(MaterialLet statement) {
    _evaluator.scope[statement.name] = statement.value.accept(_evaluator);
    return null;
  }

  @override
  List<double>? visitOutput(MaterialOutput statement) {
    // Only a vertex or a surface block writes outputs, run by
    // [evaluateMaterialVertex] and [evaluateMaterialSurface].
    if (!vertexBlock) {
      throw StateError(
        '"$name" writes an output outside a vertex or a surface block.',
      );
    }
    written[statement.output.name] = statement.value.accept(_evaluator);
    return null;
  }

  @override
  List<double>? visitReturn(MaterialReturn statement) {
    if (vertexBlock) throw StateError('"$name"\'s vertex block returns.');
    return statement.value.accept(_evaluator);
  }

  @override
  List<double>? visitUnknown(MaterialStatement statement) =>
      throw ArgumentError.value(
        statement,
        'statement',
        'not a statement this build of the material language knows',
      );
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

/// One fragment's values for every kind of expression, with the `let`s
/// bound so far in [scope].
final class _Evaluator extends MaterialExpressionVisitor<List<double>> {
  _Evaluator(this.surface);

  final MaterialSurfaceValues surface;
  final Map<String, List<double>> scope = <String, List<double>>{};

  @override
  List<double> visitConstant(ExpressionConstant expression) => expression.value;

  @override
  List<double> visitInputRef(MaterialInputRef expression) =>
      surface.inputs[expression.input.name] ??
      (throw StateError(
        'This backend does not know the surface input '
        '"${expression.input.name}".',
      ));

  @override
  List<double> visitLocalRef(MaterialLocalRef expression) =>
      scope[expression.name] ??
      (throw StateError('"${expression.name}" is read before it is bound.'));

  @override
  List<double> visitParamRef(MaterialParamRef expression) {
    final parameter = expression.parameter;
    if (!parameter.uniform) {
      throw StateError(
        'The parameter "${parameter.name}" has no value. Specialise the '
        'program before drawing with it.',
      );
    }
    final value = surface.uniforms[parameter.name];
    return value != null && value.length >= parameter.type.components
        ? value.sublist(0, parameter.type.components)
        : parameter.defaultValue;
  }

  @override
  List<double> visitConstruct(ExpressionConstruct expression) => <double>[
    for (final argument in expression.arguments) ...argument.accept(this),
  ];

  @override
  List<double> visitSwizzle(ExpressionSwizzle expression) {
    final value = expression.target.accept(this);
    return <double>[for (final index in expression.components) value[index]];
  }

  @override
  List<double> visitNegate(ExpressionNegate expression) => <double>[
    for (final component in expression.operand.accept(this)) -component,
  ];

  @override
  List<double> visitBinary(ExpressionBinary expression) => applyBinary(
    expression.op,
    expression.left.accept(this),
    expression.right.accept(this),
  );

  @override
  List<double> visitCall(ExpressionCall expression) => expression.builtin.apply(
    broadcastArguments(<List<double>>[
      for (final argument in expression.arguments) argument.accept(this),
    ], expression.builtin),
  );

  @override
  List<double> visitSample(MaterialSample expression) {
    final at = expression.uv.accept(this);
    return surface.sample(expression.slot, at[0], at[1]);
  }

  @override
  List<double> visitUnknown(Expression expression) => throw ArgumentError.value(
    expression,
    'expression',
    'not an expression this build of the material language knows',
  );
}
