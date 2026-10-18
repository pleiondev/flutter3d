/// The engine's expression language once it has been read: a typed tree,
/// each node with its shape and the dimension of what it measures.
///
/// **One language for every place a document computes.** A property law
/// (`mu0 * exp(b / (T - c))`), a derived probe (`0.5 * m * dot(v, v)`), a
/// scenario's condition (`T > 373.15 [K] && p < 2 [bar]`) and a material's
/// fragment body are all written in it, and all read into this tree. The
/// material language is this language with a material's names bound and
/// its blocks around it, so a tool that reads one reads the other.
///
/// **Typed on the way in.** Every node carries its [ExpressionType]: how
/// many components it has and the [Dimension] of what it measures, both
/// worked out by the parser. A sum of a length and a time is refused while
/// the text is read, with where it is written, rather than computed into a
/// number nobody can interpret.
///
/// **Values are kept in coherent SI units.** `20 [°C]` is read as 293.15
/// kelvin and `5 [km]` as 5000 meters, so the tree, the evaluator and every
/// translator work in one unit per dimension and never convert.
///
/// **Read through a visitor, an open set.** [Expression] is an `abstract
/// base class` whose [Expression.accept] answers
/// [ExpressionVisitor.visitUnknown] by default, so a kind a later minor
/// adds, or a host's own (the material language's inputs and `sample`),
/// reaches a translator written against 1.0 as a node it refuses by name.
library;

import 'dart:math' as math;

import '../portable_math.dart';
import '../units.dart';
import 'expression_kernels.dart';

/// The type of a value in the expression language: its [name], how many
/// numbers it has ([components]) and the [dimension] they measure.
///
/// **An open class with constants**: [float], [vec2], [vec3], [vec4],
/// [boolean] and [texture] are the engine's, and a host may make its own
/// with the constructor (a handle it samples, as the material language's
/// [texture] is).
///
/// Equal by all four fields, so a `float` in meters is not a `float` in
/// seconds, and a dimensionless `vec3` is [vec3].
final class ExpressionType {
  /// A type written [name], of [components] numbers measuring [dimension];
  /// [isBoolean] for a truth value.
  const ExpressionType(
    this.name,
    this.components, {
    this.dimension = Dimension.none,
    this.isBoolean = false,
  });

  /// One number.
  static const ExpressionType float = ExpressionType('float', 1);

  /// Two numbers.
  static const ExpressionType vec2 = ExpressionType('vec2', 2);

  /// Three numbers.
  static const ExpressionType vec3 = ExpressionType('vec3', 3);

  /// Four numbers.
  static const ExpressionType vec4 = ExpressionType('vec4', 4);

  /// A truth value: what a comparison answers and a condition asks. Held as
  /// one number, one for true and nought for false, and not a number to
  /// arithmetic: `(a < b) + 1.0` is refused.
  static const ExpressionType boolean = ExpressionType(
    'bool',
    1,
    isBoolean: true,
  );

  /// A texture slot. Not a value: it can be sampled and nothing else, which
  /// is why its [components] is zero rather than some number of channels.
  static const ExpressionType texture = ExpressionType('texture', 0);

  /// Every value this version names, in declaration order. A later
  /// version appends; nothing is removed or renamed within a major.
  static const List<ExpressionType> values = <ExpressionType>[
    float,
    vec2,
    vec3,
    vec4,
    boolean,
    texture,
  ];

  /// The value called [name], or null for a name this version does not
  /// know, which is what a file written by a later version can carry.
  static ExpressionType? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The dimensionless numeric types, by how many components they have —
  /// `numeric[3]` is [vec3]. Index zero is absent on purpose: there is no
  /// zero-component number, and [texture] taking that slot would make an
  /// arithmetic mistake resolve to a texture instead of failing.
  static const Map<int, ExpressionType> numeric = <int, ExpressionType>{
    1: float,
    2: vec2,
    3: vec3,
    4: vec4,
  };

  /// The type of [components] numbers that measure what [unit] measures.
  static ExpressionType measuring(Unit unit, {int components = 1}) =>
      numeric[components]!.withDimension(unit.dimension);

  /// How it is written: `float`, `vec3`, `bool`.
  final String name;

  /// How many numbers a value of it has; zero for [texture].
  final int components;

  /// What its numbers measure; [Dimension.none] for a pure number.
  final Dimension dimension;

  /// Whether it is a truth value rather than a number.
  final bool isBoolean;

  /// Whether arithmetic takes it: a number or a vector, of any dimension.
  bool get isNumeric => components > 0 && !isBoolean;

  /// This type measuring [other] instead.
  ExpressionType withDimension(Dimension other) =>
      ExpressionType(name, components, dimension: other, isBoolean: isBoolean);

  @override
  bool operator ==(Object other) =>
      other is ExpressionType &&
      other.name == name &&
      other.components == components &&
      other.isBoolean == isBoolean &&
      other.dimension == dimension;

  @override
  int get hashCode => Object.hash(name, components, isBoolean, dimension);

  /// The [name], with the dimension in brackets when it has one:
  /// `vec3`, `float [m·s⁻¹]`.
  @override
  String toString() => dimension.isNone ? name : '$name [$dimension]';
}

/// A function the language knows: its [name], its [arity], how it is
/// computed ([apply]) and what its result measures ([dimension]).
///
/// **One table, read by every evaluator and translator.** A builtin that
/// existed in one reader and not another is the drift this language exists
/// against, so the parser, the evaluator and the translators all take the
/// same const instance.
///
/// **The vocabulary is GLSL's**, `clamp`, `mix`, `smoothstep` and the
/// broadcasting rules meaning what they mean there, because the material
/// language is written in it and its emitted shader has to read like the
/// source; the scientific ones ([exp], [log], [atan2], …) are named as C
/// names them.
///
/// **Computed on [Portable]**, never on `dart:math`'s transcendental
/// functions, so a value is the same bits on every platform.
///
/// An open class: a host may add a function of its own with the
/// constructor and hand it to the parser through `ExpressionScope`.
final class ExpressionBuiltin {
  /// A function called [name], of [arity] arguments, computed by [apply],
  /// whose result measures what [dimension] says, refusing arguments it
  /// answers null for with the sentence [units].
  const ExpressionBuiltin(
    this.name, {
    required this.arity,
    required this.apply,
    required this.dimension,
    required this.units,
    this.componentWise = true,
    this.resultComponents,
  });

  /// The word a source calls it by.
  final String name;

  /// How many arguments it takes.
  final int arity;

  /// The value, given each argument's components, in coherent SI units.
  /// Arguments are already broadcast to a common width when
  /// [componentWise] is set, so an implementation never has to think
  /// about `mix(vec3, vec3, float)`.
  final List<double> Function(List<List<double>> arguments) apply;

  /// The dimension of the result, given the arguments as the parser typed
  /// them; null refuses them, and the parser says [units].
  ///
  /// Takes the expressions rather than their types so that `pow(x, 2.0)`
  /// can square a length: the exponent is a constant the rule can read.
  final Dimension? Function(List<Expression> arguments) dimension;

  /// What [dimension] accepts, as the end of a sentence that starts with
  /// the function's name: `takes arguments of one dimension`.
  final String units;

  /// Whether a float argument beside a vector one is spread across it —
  /// `clamp(v, 0.0, 1.0)` and `mix(a, b, t)`. False for the ones that collapse
  /// a vector to a number, where a float argument means something else.
  final bool componentWise;

  /// Fixed for the collapsing ones, and null when the result is as wide as the
  /// widest argument.
  final int? resultComponents;

  // `dot` and `length` collapse a vector to a number, so — as [componentWise]
  // says of them — a float beside a vector is not spread: GLSL has no
  // `dot(vec3, float)`, and accepting one here parsed a material whose shader
  // then failed to compile.
  /// `dot(a, b)`: the dot product of two vectors of one width, a float;
  /// measures the product of their dimensions. A float beside a vector is
  /// refused, as GLSL refuses it.
  static const ExpressionBuiltin dot = ExpressionBuiltin(
    'dot',
    arity: 2,
    apply: _dot,
    dimension: _product,
    units: 'takes any two dimensions, and measures their product',
    componentWise: false,
    resultComponents: 1,
  );

  /// `length(v)`: the Euclidean length of `v`, a float in `v`'s dimension.
  static const ExpressionBuiltin length = ExpressionBuiltin(
    'length',
    arity: 1,
    apply: _length,
    dimension: _first,
    units: 'takes any dimension',
    componentWise: false,
    resultComponents: 1,
  );

  /// `normalize(v)`: `v` scaled to length one, a pure direction; a vector of
  /// length nought answers nought in every component rather than NaN.
  static const ExpressionBuiltin normalize = ExpressionBuiltin(
    'normalize',
    arity: 1,
    apply: _normalize,
    dimension: _pure,
    units: 'takes any dimension, and answers a pure direction',
    componentWise: false,
  );

  /// `mix(a, b, t)`: `a + (b - a) * t`, component by component, between two
  /// ends of one dimension by a pure fraction `t`.
  static const ExpressionBuiltin mix = ExpressionBuiltin(
    'mix',
    arity: 3,
    apply: _mix,
    dimension: _mixDimension,
    units: 'takes two ends of one dimension and a pure number between them',
  );

  /// `clamp(x, low, high)`: `x` held between `low` and `high`, all of one
  /// dimension; `low` wins when the two cross.
  static const ExpressionBuiltin clamp = ExpressionBuiltin(
    'clamp',
    arity: 3,
    apply: _clamp,
    dimension: _same,
    units: 'takes arguments of one dimension',
  );

  /// `smoothstep(edge0, edge1, x)`: a Hermite ramp from nought at `edge0` to
  /// one at `edge1`, all of one dimension; a pure number, and a step where
  /// the edges meet.
  static const ExpressionBuiltin smoothstep = ExpressionBuiltin(
    'smoothstep',
    arity: 3,
    apply: _smoothstep,
    dimension: _sameToPure,
    units: 'takes arguments of one dimension',
  );

  /// `step(edge, x)`: nought where `x` is below `edge`, one from it; both of
  /// one dimension, the result a pure number.
  static const ExpressionBuiltin step = ExpressionBuiltin(
    'step',
    arity: 2,
    apply: _step,
    dimension: _sameToPure,
    units: 'takes arguments of one dimension',
  );

  /// `pow(x, y)`: `x` to the power `y`. A pure number takes any pure power;
  /// a quantity takes only a constant whole power of at most
  /// [expressionPowerLimit] either way, and measures its dimension raised to
  /// it.
  static const ExpressionBuiltin pow = ExpressionBuiltin(
    'pow',
    arity: 2,
    apply: _pow,
    dimension: _powDimension,
    units:
        'takes a pure number to a pure power, or a quantity to a constant '
        'whole power',
  );

  /// `min(a, b)`: the smaller of two values of one dimension, component by
  /// component; the first when they are equal.
  static const ExpressionBuiltin min = ExpressionBuiltin(
    'min',
    arity: 2,
    apply: _min,
    dimension: _same,
    units: 'takes arguments of one dimension',
  );

  /// `max(a, b)`: the larger of two values of one dimension, component by
  /// component; the second when they are equal.
  static const ExpressionBuiltin max = ExpressionBuiltin(
    'max',
    arity: 2,
    apply: _max,
    dimension: _same,
    units: 'takes arguments of one dimension',
  );

  /// `abs(x)`: the magnitude of each component, in `x`'s dimension.
  static const ExpressionBuiltin abs = ExpressionBuiltin(
    'abs',
    arity: 1,
    apply: _abs,
    dimension: _first,
    units: 'takes any dimension',
  );

  /// `sqrt(x)`: the square root of each component. Takes only a dimension
  /// whose exponents are all even, and halves them: the root of an area is a
  /// length.
  static const ExpressionBuiltin sqrt = ExpressionBuiltin(
    'sqrt',
    arity: 1,
    apply: _sqrt,
    dimension: _sqrtDimension,
    units: 'takes a dimension whose exponents are even',
  );

  /// `floor(x)`: each component rounded down to a whole number, in `x`'s
  /// dimension.
  static const ExpressionBuiltin floor = ExpressionBuiltin(
    'floor',
    arity: 1,
    apply: _floor,
    dimension: _first,
    units: 'takes any dimension',
  );

  /// `fract(x)`: what each component is above its [floor], from nought up to
  /// one, in `x`'s dimension.
  static const ExpressionBuiltin fract = ExpressionBuiltin(
    'fract',
    arity: 1,
    apply: _fract,
    dimension: _first,
    units: 'takes any dimension',
  );

  /// `sin(a)`: the sine of an angle in radians or of a pure number; a pure
  /// number.
  static const ExpressionBuiltin sin = ExpressionBuiltin(
    'sin',
    arity: 1,
    apply: _sin,
    dimension: _angleToPure,
    units: 'takes an angle or a pure number',
  );

  /// `cos(a)`: the cosine of an angle in radians or of a pure number; a pure
  /// number.
  static const ExpressionBuiltin cos = ExpressionBuiltin(
    'cos',
    arity: 1,
    apply: _cos,
    dimension: _angleToPure,
    units: 'takes an angle or a pure number',
  );

  /// `tan(a)`: the tangent of an angle in radians or of a pure number; a
  /// pure number.
  static const ExpressionBuiltin tan = ExpressionBuiltin(
    'tan',
    arity: 1,
    apply: _tan,
    dimension: _angleToPure,
    units: 'takes an angle or a pure number',
  );

  /// `asin(x)`: the arcsine of a pure number, in radians as a pure number.
  static const ExpressionBuiltin asin = ExpressionBuiltin(
    'asin',
    arity: 1,
    apply: _asin,
    dimension: _pureOnly,
    units: 'takes a pure number',
  );

  /// `acos(x)`: the arccosine of a pure number, in radians as a pure number.
  static const ExpressionBuiltin acos = ExpressionBuiltin(
    'acos',
    arity: 1,
    apply: _acos,
    dimension: _pureOnly,
    units: 'takes a pure number',
  );

  /// `atan(x)`: the arctangent of a pure number, in radians as a pure
  /// number.
  static const ExpressionBuiltin atan = ExpressionBuiltin(
    'atan',
    arity: 1,
    apply: _atan,
    dimension: _pureOnly,
    units: 'takes a pure number',
  );

  /// `atan2(y, x)`: the angle of the point (`x`, `y`) in radians, from minus
  /// pi to pi, as a pure number; both of one dimension.
  static const ExpressionBuiltin atan2 = ExpressionBuiltin(
    'atan2',
    arity: 2,
    apply: _atan2,
    dimension: _sameToPure,
    units: 'takes arguments of one dimension',
  );

  /// `exp(x)`: e to the power `x`, of a pure number.
  static const ExpressionBuiltin exp = ExpressionBuiltin(
    'exp',
    arity: 1,
    apply: _exp,
    dimension: _pureOnly,
    units: 'takes a pure number',
  );

  /// `log(x)`: the natural logarithm of a pure number.
  static const ExpressionBuiltin log = ExpressionBuiltin(
    'log',
    arity: 1,
    apply: _log,
    dimension: _pureOnly,
    units: 'takes a pure number',
  );

  /// `sign(x)`: one, nought or minus one by the sign of each component, a
  /// pure number; NaN stays NaN.
  static const ExpressionBuiltin sign = ExpressionBuiltin(
    'sign',
    arity: 1,
    apply: _sign,
    dimension: _pure,
    units: 'takes any dimension',
  );

  /// Every value this version names, in declaration order. A later
  /// version appends; nothing is removed or renamed within a major.
  static const List<ExpressionBuiltin> values = <ExpressionBuiltin>[
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
    tan,
    asin,
    acos,
    atan,
    atan2,
    exp,
    log,
    sign,
  ];

  /// Every builtin of the language, in the order a reference lists them.
  static const List<ExpressionBuiltin> all = <ExpressionBuiltin>[
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
    tan,
    asin,
    acos,
    atan,
    atan2,
    exp,
    log,
    sign,
  ];

  /// The one of [all] called [name], or null.
  static ExpressionBuiltin? byName(String name) {
    for (final builtin in all) {
      if (builtin.name == name) return builtin;
    }
    return null;
  }

  @override
  String toString() => name;
}

/// An expression, typed by the parser rather than by whoever reads it later.
///
/// **An open set, read through a visitor.** A translator walks the tree with
/// [accept] and an [ExpressionVisitor] rather than a `switch` over the kinds.
/// A kind a later minor adds, or a host's own, arrives at
/// [ExpressionVisitor.visitUnknown], so a translator written against 1.0
/// keeps compiling and refuses the node by name instead of breaking.
abstract base class Expression {
  /// For a kind of expression, typed [type] by whoever built it.
  const Expression(this.type);

  /// What the parser worked out the value is.
  final ExpressionType type;

  /// Hands this expression to the [visitor]'s method for its kind;
  /// [ExpressionVisitor.visitUnknown] by default — what a kind the visitor
  /// predates answers, including a host's own kind that does not override
  /// this.
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitUnknown(this);
}

/// Something that reads every kind of [Expression]: a translator, an
/// evaluator, a check.
///
/// **One method per kind 1.0 knows, and [visitUnknown] for the rest.** Each
/// `visit…` here is abstract, so a reader written against 1.0 says what it
/// does with every kind there is; a kind a later minor adds gains a method
/// whose default body hands the node to [visitUnknown], so the same reader
/// keeps compiling and answers the new kind as it answers any it does not
/// know — usually by refusing it with its name.
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class ExpressionVisitor<R> {
  /// For a reader, which supplies a method for every kind.
  const ExpressionVisitor();

  /// Answers a literal or a folded constant.
  R visitConstant(ExpressionConstant expression);

  /// Answers a name the host binds.
  R visitVariable(ExpressionVariable expression);

  /// Answers a vector constructor whose arguments are not all constant.
  R visitConstruct(ExpressionConstruct expression);

  /// Answers a selection of components.
  R visitSwizzle(ExpressionSwizzle expression);

  /// Answers a unary minus.
  R visitNegate(ExpressionNegate expression);

  /// Answers a `!` of a truth value.
  R visitNot(ExpressionNot expression);

  /// Answers a binary operator.
  R visitBinary(ExpressionBinary expression);

  /// Answers a call of a builtin.
  R visitCall(ExpressionCall expression);

  /// Answers a `?:` choice between two values.
  R visitConditional(ExpressionConditional expression);

  /// What a kind this visitor has no method for answers: one a later minor
  /// added, or a host's own.
  R visitUnknown(Expression expression);
}

/// A literal, in coherent SI units, and the one place a `vec3(1.0, 0.0,
/// 0.0)` that is entirely constant ends up: the parser folds a constructor,
/// a swizzle and a negation whose operands are all literals.
final class ExpressionConstant extends Expression {
  /// The constant [value] of [type], unchecked: the parser makes these.
  const ExpressionConstant(this.value, ExpressionType type) : super(type);

  /// As many numbers as [type] has components; one or nought for a
  /// [ExpressionType.boolean].
  final List<double> value;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitConstant(this);
}

/// A name the host binds: a temperature, a body's speed, a material's
/// input. Its value arrives with each evaluation.
///
/// A `base class`, so a host can tell its kinds of name apart — the material
/// language's inputs, parameters and `let`s are each one — while a reader
/// that knows only this language sees them all as variables.
base class ExpressionVariable extends Expression {
  /// The name [name], bound by the host, of [type].
  const ExpressionVariable(this.name, ExpressionType type) : super(type);

  /// The name as the source writes it.
  final String name;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitVariable(this);
}

/// `vec3(...)`, `vec4(...)` and the rest, with arguments that are not all
/// constant.
///
/// GLSL's own rule, kept: the arguments' components are laid end to end and
/// must add up to the result's width, so `vec4(rgb, a)` works and `vec4(rgb)`
/// does not; one float fills every component.
final class ExpressionConstruct extends Expression {
  /// A [type] built from [arguments], unchecked: the parser makes these
  /// once their widths add up.
  const ExpressionConstruct(this.arguments, ExpressionType type) : super(type);

  /// The arguments, whose components are laid end to end in this order.
  final List<Expression> arguments;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitConstruct(this);
}

/// `.x`, `.rgb`, `.xy` — component indices into the target.
final class ExpressionSwizzle extends Expression {
  /// The [components] of [target], making a value of [type]; unchecked, the
  /// parser makes these.
  const ExpressionSwizzle(this.target, this.components, ExpressionType type)
    : super(type);

  /// The value the components are taken from.
  final Expression target;

  /// Zero-based, in the order written.
  final List<int> components;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitSwizzle(this);
}

/// Unary minus.
final class ExpressionNegate extends Expression {
  /// Minus [operand], of [operand]'s type.
  ExpressionNegate(this.operand) : super(operand.type);

  /// The value negated.
  final Expression operand;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitNegate(this);
}

/// `!`, the negation of a truth value.
final class ExpressionNot extends Expression {
  /// The negation of [operand], a truth value.
  const ExpressionNot(this.operand) : super(ExpressionType.boolean);

  /// The truth value negated.
  final Expression operand;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitNot(this);
}

/// A binary operator: `+ - * /` with GLSL's broadcasting (a float beside a
/// vector spreads), the comparisons `< <= > >= == !=` of two numbers of one
/// dimension, and `&&` and `||` of two truth values.
final class ExpressionBinary extends Expression {
  /// [left] [op] [right], of [type]; unchecked, the parser makes these.
  const ExpressionBinary(this.op, this.left, this.right, ExpressionType type)
    : super(type);

  /// The operator as written, one of [expressionOperators].
  final String op;

  /// The operand before the operator.
  final Expression left;

  /// The operand after the operator.
  final Expression right;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitBinary(this);
}

/// Every binary operator, loosest-binding first within each group.
const List<String> expressionOperators = <String>[
  '||',
  '&&',
  '<',
  '<=',
  '>',
  '>=',
  '==',
  '!=',
  '+',
  '-',
  '*',
  '/',
];

/// A call to an [ExpressionBuiltin].
final class ExpressionCall extends Expression {
  /// A call of [builtin] with [arguments], of [type]; unchecked, the parser
  /// makes these once the builtin accepts the arguments.
  const ExpressionCall(this.builtin, this.arguments, ExpressionType type)
    : super(type);

  /// The function called.
  final ExpressionBuiltin builtin;

  /// The arguments, as many as [ExpressionBuiltin.arity], in the order
  /// written.
  final List<Expression> arguments;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitCall(this);
}

/// `condition ? then : otherwise`: one of two values of one type, by a
/// truth value. Only the chosen one is computed.
final class ExpressionConditional extends Expression {
  /// [then] where [condition] holds and [otherwise] where it does not,
  /// typed as [then].
  ExpressionConditional(this.condition, this.then, this.otherwise)
    : super(then.type);

  /// The truth value that chooses.
  final Expression condition;

  /// The value when [condition] holds.
  final Expression then;

  /// The value when [condition] does not hold, of the same type as [then].
  final Expression otherwise;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitConditional(this);
}

// ---------------------------------------------------------------------------
// The arithmetic, shared by every evaluator
// ---------------------------------------------------------------------------

/// A binary operator on two values, with GLSL's broadcasting: a
/// one-component value beside a wider one is spread across it.
///
/// Shared, through `package:flutter3d_foundation/internal.dart`, because
/// every reader that evaluates — the closure compiler, the material
/// language's software stage — computes the same operators, and a second
/// implementation of "what does vec3 * float mean" is exactly the drift
/// this language exists to remove. A comparison or a logical operator
/// answers one for true and nought for false.
List<double> applyExpressionOperator(
  String op,
  List<double> a,
  List<double> b,
) {
  final width = a.length > b.length ? a.length : b.length;
  double at(List<double> value, int i) =>
      value.length == 1 ? value[0] : value[i];
  return <double>[
    for (var i = 0; i < width; i++)
      expressionOperatorAt(op, at(a, i), at(b, i)),
  ];
}

/// Spreads a one-component argument across the widest one, for the builtins
/// that take a float beside a vector.
///
/// Shared by every evaluator, for the reason [applyExpressionOperator] is.
List<List<double>> broadcastExpressionArguments(
  List<List<double>> arguments,
  ExpressionBuiltin builtin,
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

List<double> _dot(List<List<double>> a) => <double>[dotOf(a[0], a[1])];

List<double> _length(List<List<double>> a) => <double>[lengthOf(a[0])];

List<double> _normalize(List<List<double>> a) {
  final length = lengthOf(a[0]);
  // GLSL's own behaviour is undefined at zero length; zero is the answer that
  // does not put a NaN through the rest of the shader, and it is what
  // `vector_math`'s `normalize` does too, so the two backends agree.
  if (length == 0) return List<double>.filled(a[0].length, 0);
  return <double>[for (final component in a[0]) component / length];
}

List<double> _mix(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) mixAt(a[0][i], a[1][i], a[2][i]),
];

List<double> _clamp(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) clampAt(a[0][i], a[1][i], a[2][i]),
];

List<double> _smoothstep(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) smoothstepAt(a[0][i], a[1][i], a[2][i]),
];

List<double> _step(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) stepAt(a[0][i], a[1][i]),
];

List<double> _pow(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) Portable.pow(a[0][i], a[1][i]),
];

List<double> _min(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) minAt(a[0][i], a[1][i]),
];

List<double> _max(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) maxAt(a[0][i], a[1][i]),
];

List<double> _atan2(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) Portable.atan2(a[0][i], a[1][i]),
];

List<double> _each(List<double> value, double Function(double) f) => <double>[
  for (final component in value) f(component),
];

List<double> _abs(List<List<double>> a) => _each(a[0], absAt);
List<double> _sqrt(List<List<double>> a) => _each(a[0], math.sqrt);
List<double> _floor(List<List<double>> a) => _each(a[0], floorAt);
List<double> _fract(List<List<double>> a) => _each(a[0], fractAt);
List<double> _sin(List<List<double>> a) => _each(a[0], Portable.sin);
List<double> _cos(List<List<double>> a) => _each(a[0], Portable.cos);
List<double> _tan(List<List<double>> a) => _each(a[0], Portable.tan);
List<double> _asin(List<List<double>> a) => _each(a[0], Portable.asin);
List<double> _acos(List<List<double>> a) => _each(a[0], Portable.acos);
List<double> _atan(List<List<double>> a) => _each(a[0], Portable.atan);
List<double> _exp(List<List<double>> a) => _each(a[0], Portable.exp);
List<double> _log(List<List<double>> a) => _each(a[0], Portable.log);
List<double> _sign(List<List<double>> a) => _each(a[0], signAt);

// ---------------------------------------------------------------------------
// The unit rules
// ---------------------------------------------------------------------------

Dimension? _first(List<Expression> a) => a[0].type.dimension;

Dimension? _pure(List<Expression> a) => Dimension.none;

Dimension? _pureOnly(List<Expression> a) =>
    a.every((e) => e.type.dimension.isNone) ? Dimension.none : null;

Dimension? _same(List<Expression> a) =>
    a.every((e) => e.type.dimension == a[0].type.dimension)
    ? a[0].type.dimension
    : null;

Dimension? _sameToPure(List<Expression> a) =>
    _same(a) == null ? null : Dimension.none;

Dimension? _product(List<Expression> a) =>
    a[0].type.dimension * a[1].type.dimension;

Dimension? _mixDimension(List<Expression> a) =>
    a[0].type.dimension == a[1].type.dimension && a[2].type.dimension.isNone
    ? a[0].type.dimension
    : null;

Dimension? _angleToPure(List<Expression> a) =>
    a[0].type.dimension.isNone || a[0].type.dimension == Dimension.angle
    ? Dimension.none
    : null;

Dimension? _sqrtDimension(List<Expression> a) {
  final exponents = a[0].type.dimension.exponents;
  if (exponents.values.any((e) => e.isOdd)) return null;
  return Dimension(<String, int>{
    for (final MapEntry(:key, :value) in exponents.entries)
      if (value != 0) key: value ~/ 2,
  });
}

/// The largest whole power, either way, `pow` raises a quantity to: `m^16`
/// is a dimension, `m^17` is refused. The parser holds `pow` to it, and the
/// bytecode verifier holds a loaded program to the same, so neither reads a
/// dimension whose exponents the other would not.
const int expressionPowerLimit = 16;

Dimension? _powDimension(List<Expression> a) {
  final base = a[0].type.dimension;
  final exponent = a[1];
  if (!exponent.type.dimension.isNone) return null;
  if (base.isNone) return Dimension.none;
  if (exponent case ExpressionConstant(:final value)
      when value.length == 1 &&
          value.single == value.single.truncateToDouble() &&
          value.single.abs() <= expressionPowerLimit) {
    return base.pow(value.single.toInt());
  }
  return null;
}
