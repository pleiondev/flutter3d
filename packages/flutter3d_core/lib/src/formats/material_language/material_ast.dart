/// What a material written as source *is*, once it has been read — `gfx-84n`.
///
/// **The thing both backends read, rather than two transcriptions of it.** A
/// lighting model reaches four backends today as four separate texts: GLSL
/// that `impellerc` compiles, the same GLSL through `glsl_translate.dart` and
/// through `glsl_to_wgsl.dart`, and a hand-written Dart transcription for the
/// software rasteriser. The first three are one source translated, which is
/// why they cannot drift; the fourth is a person reading GLSL and writing
/// Dart, which is why it can. A material written in this language has neither
/// problem: the emitter turns this tree into GLSL and the software backend
/// evaluates the same tree, so there is nothing for two people to disagree
/// about.
///
/// **Sealed, so adding a node breaks every reader at compile time.** An
/// emitter that quietly skipped a node it did not know would produce a shader
/// that is missing a term — visible as a slightly wrong colour, in one backend,
/// with nothing red.
library;

import 'dart:math' as math;

/// A type in the material language.
///
/// A `final class` with const instances rather than an `enum`, which is the
/// rule for anything a published package exports: a later row adds `mat3` and
/// `int`, and adding a value to an exported enum breaks every `switch` written
/// against it. Nothing switches on these anyway — [components] is what every
/// reader actually asks.
final class MaterialType {
  const MaterialType._(this.name, this.components);

  /// One number.
  static const MaterialType float = MaterialType._('float', 1);
  static const MaterialType vec2 = MaterialType._('vec2', 2);
  static const MaterialType vec3 = MaterialType._('vec3', 3);
  static const MaterialType vec4 = MaterialType._('vec4', 4);

  /// A texture slot. Not a value: it can be sampled and nothing else, which is
  /// why its [components] is zero rather than some number of channels.
  static const MaterialType texture = MaterialType._('texture', 0);

  /// The numeric types, by how many components they have — `numeric[3]` is
  /// [vec3]. Index zero is absent on purpose: there is no zero-component
  /// number, and [texture] taking that slot would make an arithmetic mistake
  /// resolve to a texture instead of failing.
  static const Map<int, MaterialType> numeric = <int, MaterialType>{
    1: float,
    2: vec2,
    3: vec3,
    4: vec4,
  };

  final String name;

  /// Zero for [texture].
  final int components;

  bool get isNumeric => components > 0;

  @override
  String toString() => name;
}

/// One declared parameter: a name, a type and the value a variant that says
/// nothing about it gets.
///
/// **A compile-time constant, and the row says why that is the shape rather
/// than a compromise.** What `gfx-84n` asks the toolchain to generate is "the
/// entry points, the variants and the binding metadata" — a variant *is* a set
/// of parameter values compiled into its own entry point. A parameter that
/// changed per frame would need a uniform block per material, and this engine's
/// blocks are frozen by offset agreement across four backends: `surface.glsl`
/// says in as many words that appending to `FragInfo` moves offsets the
/// backends have already agreed on. That is the named gap, not this.
final class MaterialParameter {
  const MaterialParameter(this.name, this.type, this.defaultValue);

  final String name;
  final MaterialType type;

  /// As many numbers as [type] has components.
  final List<double> defaultValue;
}

/// One texture slot the material samples, by the name the engine binds it
/// under.
final class MaterialTextureSlot {
  const MaterialTextureSlot(this.name, this.bindingName);

  /// What the source calls it.
  final String name;

  /// What the engine binds — `base_color_texture` and the rest. A material
  /// cannot invent a slot, for the same reason it cannot invent a uniform
  /// block, so the parser holds the source name to one the engine already
  /// binds and says which names those are when it does not.
  final String bindingName;
}

/// One value the fragment body can read.
///
/// The set is the intersection of what `surface.glsl`'s `Surface` carries and
/// what `cpu_shaders_surface.dart`'s `Surface` carries, which is the same
/// struct written twice — so an input here is a field both already have, never
/// something one side would have to compute.
final class MaterialInput {
  const MaterialInput(this.name, this.type, this.glsl);

  final String name;
  final MaterialType type;

  /// The GLSL that reads it, given a `Surface s` in scope.
  final String glsl;
}

/// Every input, and the single list of them.
///
/// The software backend's evaluator has to know each one by name, and a test
/// walks this list to check that it does — a backend that silently returned
/// zero for an input it had not heard of would draw a material that is subtly
/// wrong on one backend only.
const List<MaterialInput> kMaterialInputs = <MaterialInput>[
  MaterialInput('albedo', MaterialType.vec3, 's.albedo'),
  MaterialInput('alpha', MaterialType.float, 's.alpha'),
  MaterialInput('normal', MaterialType.vec3, 's.n'),
  MaterialInput('view', MaterialType.vec3, 's.v'),
  MaterialInput('nDotV', MaterialType.float, 's.n_dot_v'),
  MaterialInput('metallic', MaterialType.float, 's.metallic'),
  MaterialInput('roughness', MaterialType.float, 's.roughness'),
  MaterialInput('occlusion', MaterialType.float, 's.occlusion'),
  MaterialInput('emissive', MaterialType.vec3, 's.emissive'),
  MaterialInput('ambient', MaterialType.vec3, 's.ambient'),
  MaterialInput('uv', MaterialType.vec2, 'v_texcoord'),
  MaterialInput('world', MaterialType.vec3, 'v_world_position'),
];

/// A function the language knows, its type rule and how to compute it.
///
/// **One table, read by the emitter and by the evaluator.** A builtin that
/// existed on one side and not the other is the exact failure this whole row
/// is against, so neither side has its own list: the emitter takes [glsl] and
/// the software backend takes [apply], from the same const instance.
final class MaterialBuiltin {
  const MaterialBuiltin._(
    this.name, {
    required this.arity,
    required this.glsl,
    required this.apply,
    this.componentWise = true,
    this.resultComponents,
  });

  final String name;
  final int arity;

  /// The GLSL name, which is the same word for all of these — the language's
  /// vocabulary is GLSL's on purpose, so that an author who knows one knows the
  /// other and the emitted shader reads like the source.
  final String glsl;

  /// The value, given each argument's components. Arguments are already
  /// broadcast to a common width when [componentWise] is set, so an
  /// implementation here never has to think about `mix(vec3, vec3, float)`.
  final List<double> Function(List<List<double>> arguments) apply;

  /// Whether a float argument beside a vector one is spread across it —
  /// `clamp(v, 0.0, 1.0)` and `mix(a, b, t)`. False for the ones that collapse
  /// a vector to a number, where a float argument means something else.
  final bool componentWise;

  /// Fixed for the collapsing ones, and null when the result is as wide as the
  /// widest argument.
  final int? resultComponents;

  static const MaterialBuiltin dot = MaterialBuiltin._(
    'dot',
    arity: 2,
    glsl: 'dot',
    apply: _dot,
    resultComponents: 1,
  );
  static const MaterialBuiltin length = MaterialBuiltin._(
    'length',
    arity: 1,
    glsl: 'length',
    apply: _length,
    resultComponents: 1,
  );
  static const MaterialBuiltin normalize = MaterialBuiltin._(
    'normalize',
    arity: 1,
    glsl: 'normalize',
    apply: _normalize,
    componentWise: false,
  );
  static const MaterialBuiltin mix = MaterialBuiltin._(
    'mix',
    arity: 3,
    glsl: 'mix',
    apply: _mix,
  );
  static const MaterialBuiltin clamp = MaterialBuiltin._(
    'clamp',
    arity: 3,
    glsl: 'clamp',
    apply: _clamp,
  );
  static const MaterialBuiltin smoothstep = MaterialBuiltin._(
    'smoothstep',
    arity: 3,
    glsl: 'smoothstep',
    apply: _smoothstep,
  );
  static const MaterialBuiltin step = MaterialBuiltin._(
    'step',
    arity: 2,
    glsl: 'step',
    apply: _step,
  );
  static const MaterialBuiltin pow = MaterialBuiltin._(
    'pow',
    arity: 2,
    glsl: 'pow',
    apply: _pow,
  );
  static const MaterialBuiltin min = MaterialBuiltin._(
    'min',
    arity: 2,
    glsl: 'min',
    apply: _min,
  );
  static const MaterialBuiltin max = MaterialBuiltin._(
    'max',
    arity: 2,
    glsl: 'max',
    apply: _max,
  );
  static const MaterialBuiltin abs = MaterialBuiltin._(
    'abs',
    arity: 1,
    glsl: 'abs',
    apply: _abs,
  );
  static const MaterialBuiltin sqrt = MaterialBuiltin._(
    'sqrt',
    arity: 1,
    glsl: 'sqrt',
    apply: _sqrt,
  );
  static const MaterialBuiltin floor = MaterialBuiltin._(
    'floor',
    arity: 1,
    glsl: 'floor',
    apply: _floor,
  );
  static const MaterialBuiltin fract = MaterialBuiltin._(
    'fract',
    arity: 1,
    glsl: 'fract',
    apply: _fract,
  );
  static const MaterialBuiltin sin = MaterialBuiltin._(
    'sin',
    arity: 1,
    glsl: 'sin',
    apply: _sin,
  );
  static const MaterialBuiltin cos = MaterialBuiltin._(
    'cos',
    arity: 1,
    glsl: 'cos',
    apply: _cos,
  );

  static const List<MaterialBuiltin> all = <MaterialBuiltin>[
    dot,
    length,
    normalize,
    mix,
    clamp,
    smoothstep,
    step,
    pow,
    min,
    max,
    abs,
    sqrt,
    floor,
    fract,
    sin,
    cos,
  ];

  static MaterialBuiltin? byName(String name) {
    for (final builtin in all) {
      if (builtin.name == name) return builtin;
    }
    return null;
  }
}

/// An expression, typed by the parser rather than by whoever reads it later.
sealed class MaterialExpression {
  const MaterialExpression(this.type);

  final MaterialType type;
}

/// A literal, and the one place a `vec3(1.0, 0.0, 0.0)` that is entirely
/// constant ends up: the parser folds a constructor whose arguments are all
/// literals, because a parameter is a constant too and folding is what makes a
/// variant's value reach the shader as a number.
final class MaterialConstant extends MaterialExpression {
  const MaterialConstant(this.value, MaterialType type) : super(type);

  final List<double> value;
}

/// One of [kMaterialInputs].
final class MaterialInputRef extends MaterialExpression {
  MaterialInputRef(this.input) : super(input.type);

  final MaterialInput input;
}

/// A declared parameter, before a variant has said what it is.
///
/// Kept as a reference through parsing and folded to a [MaterialConstant] by
/// [specialiseMaterial] — the source is parsed once and every variant is a
/// fold of the same tree, rather than a parse per variant that could differ in
/// some other way than the numbers.
final class MaterialParamRef extends MaterialExpression {
  MaterialParamRef(this.parameter) : super(parameter.type);

  final MaterialParameter parameter;
}

/// A `let` bound earlier in the body.
final class MaterialLocalRef extends MaterialExpression {
  const MaterialLocalRef(this.name, MaterialType type) : super(type);

  final String name;
}

/// `vec3(...)`, `vec4(...)` and the rest, with arguments that are not all
/// constant.
///
/// GLSL's own rule, kept: the arguments' components are laid end to end and
/// must add up to the result's width, so `vec4(rgb, a)` works and `vec4(rgb)`
/// does not.
final class MaterialConstruct extends MaterialExpression {
  const MaterialConstruct(this.arguments, MaterialType type) : super(type);

  final List<MaterialExpression> arguments;
}

/// `.x`, `.rgb`, `.xy` — component indices into the target.
final class MaterialSwizzle extends MaterialExpression {
  const MaterialSwizzle(this.target, this.components, MaterialType type)
    : super(type);

  final MaterialExpression target;

  /// Zero-based, in the order written.
  final List<int> components;
}

/// Unary minus. The only unary operator, because `!` needs a bool type the
/// language has not got.
final class MaterialNegate extends MaterialExpression {
  MaterialNegate(this.operand) : super(operand.type);

  final MaterialExpression operand;
}

/// `+ - * /`, with GLSL's broadcasting: a float beside a vector spreads.
final class MaterialBinary extends MaterialExpression {
  const MaterialBinary(this.op, this.left, this.right, MaterialType type)
    : super(type);

  final String op;
  final MaterialExpression left;
  final MaterialExpression right;
}

/// A call to one of [MaterialBuiltin.all].
final class MaterialCall extends MaterialExpression {
  const MaterialCall(this.builtin, this.arguments, MaterialType type)
    : super(type);

  final MaterialBuiltin builtin;
  final List<MaterialExpression> arguments;
}

/// `sample(slot, uv)`.
///
/// Its own node rather than a [MaterialBuiltin] because it is the one
/// expression that reads something outside the material: a builtin's [
/// MaterialBuiltin.apply] takes numbers and returns numbers, and this one
/// needs whatever the backend binds textures with.
final class MaterialSample extends MaterialExpression {
  const MaterialSample(this.slot, this.uv) : super(MaterialType.vec4);

  final MaterialTextureSlot slot;
  final MaterialExpression uv;
}

sealed class MaterialStatement {
  const MaterialStatement();
}

/// `let name = expr;` — single assignment, so nothing here is a variable.
final class MaterialLet extends MaterialStatement {
  const MaterialLet(this.name, this.value);

  final String name;
  final MaterialExpression value;
}

/// `return expr;` — a `vec4`, rgb being the light the surface emits and a its
/// opacity, which is what `WriteSurface` takes.
final class MaterialReturn extends MaterialStatement {
  const MaterialReturn(this.value);

  final MaterialExpression value;
}

/// A material read from source: its name, what it declares, and its body.
final class MaterialProgram {
  const MaterialProgram({
    required this.name,
    required this.parameters,
    required this.textures,
    required this.body,
    required this.inputsUsed,
  });

  final String name;
  final List<MaterialParameter> parameters;
  final List<MaterialTextureSlot> textures;
  final List<MaterialStatement> body;

  /// Which of [kMaterialInputs] the body actually reads.
  ///
  /// **This is the binding metadata `gfx-84n` asks the toolchain to
  /// generate.** `LightingModel`'s `uses…` flags are declared by hand today,
  /// with a comment saying reflection cannot answer the question — a uniform
  /// block is reported present because the GLSL declared it, even when the
  /// compiled shader binds nothing for it, and binding that phantom block
  /// segfaults inside Metal. A material whose source this package parsed does
  /// not have that problem: what it reads is what is written down.
  final Set<String> inputsUsed;

  MaterialParameter? parameter(String name) {
    for (final parameter in parameters) {
      if (parameter.name == name) return parameter;
    }
    return null;
  }
}

/// One compiled entry point: a program with its parameters pinned.
///
/// The name is the entry point a `LightingModel` asks the bundle for, so two
/// variants of one source are two shaders on the GPU and two stages on the
/// software backend — which is what they have to be, since a parameter is a
/// constant folded into the code.
final class MaterialVariant {
  const MaterialVariant(this.name, [this.values = const {}]);

  final String name;

  /// Parameter name to value. Anything not named keeps its default.
  final Map<String, List<double>> values;
}

/// [program] with [variant]'s parameter values folded in, ready to emit or to
/// evaluate.
///
/// **Folding is what makes a variant an entry point rather than a setting.**
/// Every [MaterialParamRef] becomes the number the variant gives it, and a
/// subtree that is then entirely constant collapses — so `pow(x, rimPower)`
/// with `rimPower = 2.0` reaches the GPU as `pow(x, 2.0)` and reaches the
/// software backend as the same multiplication, from one decision.
///
/// Throws [ArgumentError] for a value of the wrong width or a name the program
/// does not declare: a variant that set `rimPowr` would otherwise compile to
/// the default and look like the parameter not working.
MaterialProgram specialiseMaterial(
  MaterialProgram program,
  MaterialVariant variant,
) {
  for (final MapEntry(:key, :value) in variant.values.entries) {
    final parameter = program.parameter(key);
    if (parameter == null) {
      throw ArgumentError(
        'Variant "${variant.name}" sets "$key", which '
        '"${program.name}" does not declare.',
      );
    }
    if (value.length != parameter.type.components) {
      throw ArgumentError(
        'Variant "${variant.name}" gives "$key" ${value.length} components, '
        'and it is a ${parameter.type}.',
      );
    }
  }

  return MaterialProgram(
    name: variant.name,
    parameters: program.parameters,
    textures: program.textures,
    body: <MaterialStatement>[
      for (final statement in program.body)
        switch (statement) {
          MaterialLet(:final name, :final value) => MaterialLet(
            name,
            _fold(value, variant),
          ),
          MaterialReturn(:final value) => MaterialReturn(_fold(value, variant)),
        },
    ],
    inputsUsed: program.inputsUsed,
  );
}

MaterialExpression _fold(MaterialExpression expression, MaterialVariant v) {
  switch (expression) {
    case MaterialConstant():
    case MaterialInputRef():
    case MaterialLocalRef():
      return expression;
    case MaterialParamRef(:final parameter):
      return MaterialConstant(
        v.values[parameter.name] ?? parameter.defaultValue,
        parameter.type,
      );
    case MaterialConstruct(:final arguments, :final type):
      final folded = <MaterialExpression>[
        for (final argument in arguments) _fold(argument, v),
      ];
      if (folded.every((f) => f is MaterialConstant)) {
        return MaterialConstant(<double>[
          for (final f in folded) ...(f as MaterialConstant).value,
        ], type);
      }
      return MaterialConstruct(folded, type);
    case MaterialSwizzle(:final target, :final components, :final type):
      final folded = _fold(target, v);
      if (folded is MaterialConstant) {
        return MaterialConstant(<double>[
          for (final index in components) folded.value[index],
        ], type);
      }
      return MaterialSwizzle(folded, components, type);
    case MaterialNegate(:final operand):
      final folded = _fold(operand, v);
      if (folded is MaterialConstant) {
        return MaterialConstant(<double>[
          for (final component in folded.value) -component,
        ], folded.type);
      }
      return MaterialNegate(folded);
    case MaterialBinary(:final op, :final left, :final right, :final type):
      final a = _fold(left, v);
      final b = _fold(right, v);
      if (a is MaterialConstant && b is MaterialConstant) {
        return MaterialConstant(applyBinary(op, a.value, b.value), type);
      }
      return MaterialBinary(op, a, b, type);
    case MaterialCall(:final builtin, :final arguments, :final type):
      final folded = <MaterialExpression>[
        for (final argument in arguments) _fold(argument, v),
      ];
      if (folded.every((f) => f is MaterialConstant)) {
        return MaterialConstant(
          builtin.apply(
            broadcastArguments(<List<double>>[
              for (final f in folded) (f as MaterialConstant).value,
            ], builtin),
          ),
          type,
        );
      }
      return MaterialCall(builtin, folded, type);
    case MaterialSample(:final slot, :final uv):
      return MaterialSample(slot, _fold(uv, v));
  }
}

/// `+ - * /` on two values, with GLSL's broadcasting.
///
/// Exported because the software backend evaluates the same operators and a
/// second implementation of "what does vec3 * float mean" is exactly the drift
/// this language exists to remove.
List<double> applyBinary(String op, List<double> a, List<double> b) {
  final width = a.length > b.length ? a.length : b.length;
  double at(List<double> value, int i) =>
      value.length == 1 ? value[0] : value[i];
  return <double>[
    for (var i = 0; i < width; i++)
      switch (op) {
        '+' => at(a, i) + at(b, i),
        '-' => at(a, i) - at(b, i),
        '*' => at(a, i) * at(b, i),
        '/' => at(a, i) / at(b, i),
        _ => throw ArgumentError('"$op" is not an operator.'),
      },
  ];
}

/// Spreads a one-component argument across the widest one, for the builtins
/// that take a float beside a vector.
///
/// Shared by the folder and the software backend, for the reason
/// [applyBinary] is.
List<List<double>> broadcastArguments(
  List<List<double>> arguments,
  MaterialBuiltin builtin,
) {
  if (!builtin.componentWise) return arguments;
  var width = 1;
  for (final argument in arguments) {
    if (argument.length > width) width = argument.length;
  }
  return <List<double>>[
    for (final argument in arguments)
      argument.length == width
          ? argument
          : List<double>.filled(width, argument.single),
  ];
}

List<double> _dot(List<List<double>> a) {
  var sum = 0.0;
  for (var i = 0; i < a[0].length; i++) {
    sum += a[0][i] * a[1][i];
  }
  return <double>[sum];
}

List<double> _length(List<List<double>> a) {
  var sum = 0.0;
  for (final component in a[0]) {
    sum += component * component;
  }
  return <double>[math.sqrt(sum)];
}

List<double> _normalize(List<List<double>> a) {
  final length = _length(a)[0];
  // GLSL's own behaviour is undefined at zero length; zero is the answer that
  // does not put a NaN through the rest of the shader, and it is what
  // `vector_math`'s `normalize` does too, so the two backends agree.
  if (length == 0) return List<double>.filled(a[0].length, 0);
  return <double>[for (final component in a[0]) component / length];
}

List<double> _mix(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[0][i] + (a[1][i] - a[0][i]) * a[2][i],
];

List<double> _clamp(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++)
    a[0][i] < a[1][i]
        ? a[1][i]
        : a[0][i] > a[2][i]
        ? a[2][i]
        : a[0][i],
];

List<double> _smoothstep(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++)
    _smoothstepAt(a[0][i], a[1][i], a[2][i]),
];

double _smoothstepAt(double edge0, double edge1, double x) {
  if (edge0 == edge1) return x < edge0 ? 0 : 1;
  var t = (x - edge0) / (edge1 - edge0);
  t = t < 0 ? 0 : (t > 1 ? 1 : t);
  return t * t * (3 - 2 * t);
}

List<double> _step(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[1][i] < a[0][i] ? 0.0 : 1.0,
];

List<double> _pow(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) math.pow(a[0][i], a[1][i]).toDouble(),
];

List<double> _min(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[0][i] < a[1][i] ? a[0][i] : a[1][i],
];

List<double> _max(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[0][i] > a[1][i] ? a[0][i] : a[1][i],
];

List<double> _abs(List<List<double>> a) => <double>[
  for (final component in a[0]) component < 0 ? -component : component,
];

List<double> _sqrt(List<List<double>> a) => <double>[
  for (final component in a[0]) math.sqrt(component),
];

List<double> _floor(List<List<double>> a) => <double>[
  for (final component in a[0]) component.floorToDouble(),
];

List<double> _fract(List<List<double>> a) => <double>[
  for (final component in a[0]) component - component.floorToDouble(),
];

List<double> _sin(List<List<double>> a) => <double>[
  for (final component in a[0]) math.sin(component),
];

List<double> _cos(List<List<double>> a) => <double>[
  for (final component in a[0]) math.cos(component),
];
