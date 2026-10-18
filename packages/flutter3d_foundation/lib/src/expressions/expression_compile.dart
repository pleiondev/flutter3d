/// Runs an expression: the typed tree compiled once into a chain of Dart
/// closures, then called as often as the host likes.
///
/// **Compiled, not walked.** A law is evaluated per body per step and a
/// probe per reading, so the tree is turned into closures once, each node
/// one closure that calls its operands' and computes its own value, and a
/// variable a slot read by index. Nothing is looked up by name, and no
/// visitor is dispatched, when the value is asked for.
///
/// **A number is a `double`, not a list.** A node of one component compiles
/// to a closure that answers a `double`, with its operator or builtin
/// chosen when it is compiled, so a law of scalars allocates nothing on the
/// way to its result. Only a vector node answers a list.
///
/// **The same bits everywhere.** Every operation is `+ - * /`, a comparison,
/// `sqrt` or a [Portable] function, through the kernels every evaluator of
/// the language shares, so a value computed under the VM and in a browser
/// is the same number to the last bit.
library;

import 'dart:math' as math;

import '../portable_math.dart';
import '../units.dart';
import 'expression_ast.dart';
import 'expression_kernels.dart';

typedef _Slots = List<List<double>>;
typedef _Scalar = double Function(_Slots slots);
typedef _Vector = List<double> Function(_Slots slots);

/// One compiled node: [scalar] for a value of one component, [vector] for
/// a wider one. Each reads the other's shape on demand, so an operand of
/// either kind serves a parent of either kind.
final class _Node {
  _Node.scalar(_Scalar this.scalar) : _vector = null;
  _Node.vector(_Vector this._vector) : scalar = null;

  final _Scalar? scalar;
  final _Vector? _vector;

  bool get isScalar => scalar != null;

  /// The value as a double; for a vector node, its first component.
  _Scalar get asScalar {
    if (scalar case final s?) return s;
    final v = _vector!;
    return (slots) => v(slots)[0];
  }

  /// The value as a list; for a scalar node, a list of one.
  _Vector get asVector {
    if (_vector case final v?) return v;
    final s = scalar!;
    return (slots) => <double>[s(slots)];
  }
}

/// An [Expression] ready to evaluate.
///
/// The variables it reads are numbered in [variables]: [evaluate] takes
/// their values in that order, in coherent SI units, and [evaluateNamed]
/// takes them by name, as quantities in any unit of the right dimension.
final class CompiledExpression {
  /// [expression], compiled.
  ///
  /// Throws [ArgumentError] for a kind of node this build does not know.
  factory CompiledExpression(Expression expression) {
    final compiler = _Compiler();
    final run = expression.accept(compiler).asVector;
    return CompiledExpression._(
      expression,
      List<String>.unmodifiable(compiler.slots.keys),
      List<ExpressionType>.unmodifiable(compiler.types),
      run,
    );
  }

  CompiledExpression._(this.expression, this.variables, this.types, this._run)
    : _units = <Unit>[for (final type in types) Unit.coherent(type.dimension)];

  /// What was compiled.
  final Expression expression;

  /// The names it reads, in the order [evaluate] takes their values.
  final List<String> variables;

  /// The type of each of [variables], in the same order.
  final List<ExpressionType> types;

  final _Vector _run;

  /// The coherent unit of each of [types], worked out once: [evaluateNamed]
  /// converts every quantity it is given into one.
  final List<Unit> _units;

  /// The coherent unit of the value, for [quantity].
  late final Unit _unit = Unit.coherent(type.dimension);

  /// The type of the value.
  ExpressionType get type => expression.type;

  /// The value, given each of [variables]' in [slots], in order, each as
  /// many numbers as its type has components, in the coherent unit of its
  /// dimension.
  List<double> evaluate(List<List<double>> slots) => _run(slots);

  /// The value, given [values] by name: a [Quantity] in any unit of the
  /// variable's dimension, a `double` for a dimensionless one, a `bool`, or
  /// a `List<double>` of its components in coherent units.
  ///
  /// Throws [ArgumentError] for a name it reads and [values] lacks, and
  /// [UnitMismatchException] for a quantity of another dimension.
  List<double> evaluateNamed(Map<String, Object> values) => _run(<List<double>>[
    for (var i = 0; i < variables.length; i++)
      _slot(variables[i], types[i], _units[i], values[variables[i]]),
  ]);

  /// A scalar value as a [Quantity] in the coherent unit of its dimension,
  /// given [values] as for [evaluateNamed].
  Quantity quantity(Map<String, Object> values) {
    if (type.components != 1 || type.isBoolean) {
      throw StateError('$type is not a scalar quantity.');
    }
    return Quantity(evaluateNamed(values).single, _unit);
  }

  /// A truth value, given [values] as for [evaluateNamed].
  bool truth(Map<String, Object> values) {
    if (!type.isBoolean) throw StateError('$type is not a bool.');
    return evaluateNamed(values).single != 0;
  }
}

/// [value] as the slot of the variable [name] of [type], whose coherent
/// unit is [coherent]: its components in that unit.
List<double> _slot(
  String name,
  ExpressionType type,
  Unit coherent,
  Object? value,
) {
  final List<double> slot = switch (value) {
    null => throw ArgumentError.value(
      name,
      'values',
      'the expression reads "$name", and no value was given for it',
    ),
    final Quantity quantity => <double>[quantity.valueIn(coherent)],
    final bool truth when type.isBoolean => <double>[truth ? 1 : 0],
    final num number when type.dimension.isNone && !type.isBoolean => <double>[
      number.toDouble(),
    ],
    num _ => throw UnitMismatchException(Unit.one, coherent),
    final List<double> components => components,
    _ => throw ArgumentError.value(
      value,
      name,
      'a value is a Quantity, a double, a bool or a list of components',
    ),
  };
  if (slot.length != type.components) {
    throw ArgumentError.value(
      value,
      name,
      '"$name" is a $type, and was given ${slot.length} components',
    );
  }
  return slot;
}

/// The arithmetic operators, each as the function of one component that
/// `expressionOperatorAt` computes for it: the same expressions, chosen
/// once when a node is compiled rather than by its symbol per component.
double _add(double a, double b) => a + b;
double _subtract(double a, double b) => a - b;
double _multiply(double a, double b) => a * b;
double _divide(double a, double b) => a / b;
double _less(double a, double b) => a < b ? 1.0 : 0.0;
double _lessEqual(double a, double b) => a <= b ? 1.0 : 0.0;
double _greater(double a, double b) => a > b ? 1.0 : 0.0;
double _greaterEqual(double a, double b) => a >= b ? 1.0 : 0.0;
double _equal(double a, double b) => a == b ? 1.0 : 0.0;
double _notEqual(double a, double b) => a != b ? 1.0 : 0.0;

double Function(double, double) _operator(String op) => switch (op) {
  '+' => _add,
  '-' => _subtract,
  '*' => _multiply,
  '/' => _divide,
  '<' => _less,
  '<=' => _lessEqual,
  '>' => _greater,
  '>=' => _greaterEqual,
  '==' => _equal,
  '!=' => _notEqual,
  _ => throw ArgumentError('"$op" is not an operator.'),
};

/// The engine's component-wise builtins of one argument, as the function
/// of one component their list form applies to each. Keyed by identity: a
/// host's own builtin keeps its own [ExpressionBuiltin.apply], whatever it
/// is called.
final Map<ExpressionBuiltin, double Function(double)> _unaryKernels =
    Map<ExpressionBuiltin, double Function(double)>.identity()
      ..addAll(<ExpressionBuiltin, double Function(double)>{
        ExpressionBuiltin.abs: absAt,
        ExpressionBuiltin.sqrt: math.sqrt,
        ExpressionBuiltin.floor: floorAt,
        ExpressionBuiltin.fract: fractAt,
        ExpressionBuiltin.sin: Portable.sin,
        ExpressionBuiltin.cos: Portable.cos,
        ExpressionBuiltin.tan: Portable.tan,
        ExpressionBuiltin.asin: Portable.asin,
        ExpressionBuiltin.acos: Portable.acos,
        ExpressionBuiltin.atan: Portable.atan,
        ExpressionBuiltin.exp: Portable.exp,
        ExpressionBuiltin.log: Portable.log,
        ExpressionBuiltin.sign: signAt,
      });

/// The same for the builtins of two arguments.
final Map<ExpressionBuiltin, double Function(double, double)> _binaryKernels =
    Map<ExpressionBuiltin, double Function(double, double)>.identity()
      ..addAll(<ExpressionBuiltin, double Function(double, double)>{
        ExpressionBuiltin.step: stepAt,
        ExpressionBuiltin.pow: Portable.pow,
        ExpressionBuiltin.min: minAt,
        ExpressionBuiltin.max: maxAt,
        ExpressionBuiltin.atan2: Portable.atan2,
      });

/// The same for the builtins of three arguments.
final Map<ExpressionBuiltin, double Function(double, double, double)>
_ternaryKernels =
    Map<ExpressionBuiltin, double Function(double, double, double)>.identity()
      ..addAll(<ExpressionBuiltin, double Function(double, double, double)>{
        ExpressionBuiltin.mix: mixAt,
        ExpressionBuiltin.clamp: clampAt,
        ExpressionBuiltin.smoothstep: smoothstepAt,
      });

final class _Compiler extends ExpressionVisitor<_Node> {
  /// Each variable's slot, in the order they were met.
  final Map<String, int> slots = <String, int>{};
  final List<ExpressionType> types = <ExpressionType>[];

  @override
  _Node visitConstant(ExpressionConstant expression) {
    if (expression.value.length == 1) {
      final value = expression.value[0];
      return _Node.scalar((_) => value);
    }
    final value = List<double>.unmodifiable(expression.value);
    return _Node.vector((_) => value);
  }

  @override
  _Node visitVariable(ExpressionVariable expression) {
    final slot = slots.putIfAbsent(expression.name, () {
      types.add(expression.type);
      return types.length - 1;
    });
    if (types[slot] != expression.type) {
      throw ArgumentError.value(
        expression.name,
        'expression',
        'is read as a ${types[slot]} and as a ${expression.type}',
      );
    }
    if (expression.type.components == 1) {
      return _Node.scalar((slots) => slots[slot][0]);
    }
    return _Node.vector((slots) => slots[slot]);
  }

  @override
  _Node visitConstruct(ExpressionConstruct expression) {
    final parts = <_Node>[
      for (final argument in expression.arguments) argument.accept(this),
    ];
    if (expression.type.components == 1) return parts.single;
    final vectors = <_Vector>[for (final part in parts) part.asVector];
    return _Node.vector(
      (slots) => <double>[for (final part in vectors) ...part(slots)],
    );
  }

  @override
  _Node visitSwizzle(ExpressionSwizzle expression) {
    final target = expression.target.accept(this);
    final components = expression.components;
    if (components.length == 1) {
      if (target.isScalar) return target;
      final vector = target.asVector;
      final index = components[0];
      return _Node.scalar((slots) => vector(slots)[index]);
    }
    final vector = target.asVector;
    return _Node.vector((slots) {
      final value = vector(slots);
      return <double>[for (final index in components) value[index]];
    });
  }

  @override
  _Node visitNegate(ExpressionNegate expression) {
    final operand = expression.operand.accept(this);
    if (operand.scalar case final value?) {
      return _Node.scalar((slots) => -value(slots));
    }
    final vector = operand.asVector;
    return _Node.vector(
      (slots) => <double>[for (final component in vector(slots)) -component],
    );
  }

  @override
  _Node visitNot(ExpressionNot expression) {
    final operand = expression.operand.accept(this).asScalar;
    return _Node.scalar((slots) => operand(slots) != 0 ? 0.0 : 1.0);
  }

  @override
  _Node visitBinary(ExpressionBinary expression) {
    final left = expression.left.accept(this);
    final right = expression.right.accept(this);
    final op = expression.op;
    // Short-circuit, as the reader of `p > 0 && q / p > 1` expects; the
    // value is the same either way, which is what the bytecode relies on.
    if (op == '&&' || op == '||') {
      final a = left.asScalar;
      final b = right.asScalar;
      return op == '&&'
          ? _Node.scalar((slots) => a(slots) != 0 && b(slots) != 0 ? 1.0 : 0.0)
          : _Node.scalar((slots) => a(slots) != 0 || b(slots) != 0 ? 1.0 : 0.0);
    }
    final f = _operator(op);
    if (left.scalar case final a?) {
      if (right.scalar case final b?) {
        return switch (op) {
          '+' => _Node.scalar((slots) => a(slots) + b(slots)),
          '-' => _Node.scalar((slots) => a(slots) - b(slots)),
          '*' => _Node.scalar((slots) => a(slots) * b(slots)),
          '/' => _Node.scalar((slots) => a(slots) / b(slots)),
          _ => _Node.scalar((slots) => f(a(slots), b(slots))),
        };
      }
      final b = right.asVector;
      return _Node.vector((slots) {
        final x = a(slots);
        final v = b(slots);
        return <double>[for (var i = 0; i < v.length; i++) f(x, v[i])];
      });
    }
    final a = left.asVector;
    if (right.scalar case final b?) {
      return _Node.vector((slots) {
        final v = a(slots);
        final y = b(slots);
        return <double>[for (var i = 0; i < v.length; i++) f(v[i], y)];
      });
    }
    final b = right.asVector;
    return _Node.vector((slots) {
      final v = a(slots);
      final w = b(slots);
      return <double>[for (var i = 0; i < v.length; i++) f(v[i], w[i])];
    });
  }

  @override
  _Node visitCall(ExpressionCall expression) {
    final arguments = <_Node>[
      for (final argument in expression.arguments) argument.accept(this),
    ];
    final builtin = expression.builtin;
    // A call whose arguments are all one number, of a builtin the engine
    // defines, is its kernel on doubles: the function the builtin's own
    // list form applies to each component.
    if (expression.type.components == 1 &&
        arguments.every((argument) => argument.isScalar)) {
      if (_unaryKernels[builtin] case final f? when arguments.length == 1) {
        final a = arguments[0].scalar!;
        return _Node.scalar((slots) => f(a(slots)));
      }
      if (_binaryKernels[builtin] case final f? when arguments.length == 2) {
        final a = arguments[0].scalar!;
        final b = arguments[1].scalar!;
        return _Node.scalar((slots) => f(a(slots), b(slots)));
      }
      if (_ternaryKernels[builtin] case final f? when arguments.length == 3) {
        final a = arguments[0].scalar!;
        final b = arguments[1].scalar!;
        final c = arguments[2].scalar!;
        return _Node.scalar((slots) => f(a(slots), b(slots), c(slots)));
      }
    }
    final vectors = <_Vector>[
      for (final argument in arguments) argument.asVector,
    ];
    _Vector call() =>
        (slots) => builtin.apply(
          broadcastExpressionArguments(<List<double>>[
            for (final argument in vectors) argument(slots),
          ], builtin),
        );
    if (expression.type.components == 1) {
      final run = call();
      return _Node.scalar((slots) => run(slots)[0]);
    }
    return _Node.vector(call());
  }

  @override
  _Node visitConditional(ExpressionConditional expression) {
    final condition = expression.condition.accept(this).asScalar;
    final then = expression.then.accept(this);
    final otherwise = expression.otherwise.accept(this);
    if (expression.type.components == 1) {
      final a = then.asScalar;
      final b = otherwise.asScalar;
      return _Node.scalar(
        (slots) => condition(slots) != 0 ? a(slots) : b(slots),
      );
    }
    final a = then.asVector;
    final b = otherwise.asVector;
    return _Node.vector((slots) => condition(slots) != 0 ? a(slots) : b(slots));
  }

  @override
  _Node visitUnknown(Expression expression) => throw ArgumentError.value(
    expression,
    'expression',
    'not an expression this build of the expression language knows',
  );
}
