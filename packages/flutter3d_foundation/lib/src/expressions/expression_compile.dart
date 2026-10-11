/// Runs an expression: the typed tree compiled once into a chain of Dart
/// closures, then called as often as the host likes.
///
/// **Compiled, not walked.** A law is evaluated per body per step and a
/// probe per reading, so the tree is turned into closures once, each node
/// one closure that calls its operands' and computes its own value, and a
/// variable a slot read by index. Nothing is looked up by name, and no
/// visitor is dispatched, when the value is asked for.
///
/// **The same bits everywhere.** Every operation is `+ - * /`, a comparison,
/// `sqrt` or a [Portable] function, through the kernels every evaluator of
/// the language shares, so a value computed under the VM and in a browser
/// is the same number to the last bit.
library;

import '../units.dart';
import 'expression_ast.dart';
import 'expression_kernels.dart';

/// The value of one evaluation, in the coherent unit of its dimension.
typedef _Eval = List<double> Function(List<List<double>> slots);

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
    final run = expression.accept(compiler);
    return CompiledExpression._(
      expression,
      List<String>.unmodifiable(compiler.slots.keys),
      List<ExpressionType>.unmodifiable(compiler.types),
      run,
    );
  }

  CompiledExpression._(this.expression, this.variables, this.types, this._run);

  /// What was compiled.
  final Expression expression;

  /// The names it reads, in the order [evaluate] takes their values.
  final List<String> variables;

  /// The type of each of [variables], in the same order.
  final List<ExpressionType> types;

  final _Eval _run;

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
      expressionSlot(variables[i], types[i], values[variables[i]]),
  ]);

  /// A scalar value as a [Quantity] in the coherent unit of its dimension,
  /// given [values] as for [evaluateNamed].
  Quantity quantity(Map<String, Object> values) {
    if (type.components != 1 || type.isBoolean) {
      throw StateError('$type is not a scalar quantity.');
    }
    return Quantity(
      evaluateNamed(values).single,
      Unit.coherent(type.dimension),
    );
  }

  /// A truth value, given [values] as for [evaluateNamed].
  bool truth(Map<String, Object> values) {
    if (!type.isBoolean) throw StateError('$type is not a bool.');
    return evaluateNamed(values).single != 0;
  }
}

/// [value] as the slot of the variable [name] of [type]: its components in
/// the coherent unit of the type's dimension.
///
/// Shared by every evaluator that takes values by name.
List<double> expressionSlot(String name, ExpressionType type, Object? value) {
  final coherent = Unit.coherent(type.dimension);
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
    final num _ => throw UnitMismatchException(Unit.one, coherent),
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

final class _Compiler extends ExpressionVisitor<_Eval> {
  /// Each variable's slot, in the order they were met.
  final Map<String, int> slots = <String, int>{};
  final List<ExpressionType> types = <ExpressionType>[];

  @override
  _Eval visitConstant(ExpressionConstant expression) {
    final value = List<double>.unmodifiable(expression.value);
    return (_) => value;
  }

  @override
  _Eval visitVariable(ExpressionVariable expression) {
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
    return (slots) => slots[slot];
  }

  @override
  _Eval visitConstruct(ExpressionConstruct expression) {
    final parts = <_Eval>[
      for (final argument in expression.arguments) argument.accept(this),
    ];
    return (slots) => <double>[for (final part in parts) ...part(slots)];
  }

  @override
  _Eval visitSwizzle(ExpressionSwizzle expression) {
    final target = expression.target.accept(this);
    final components = expression.components;
    return (slots) {
      final value = target(slots);
      return <double>[for (final index in components) value[index]];
    };
  }

  @override
  _Eval visitNegate(ExpressionNegate expression) {
    final operand = expression.operand.accept(this);
    return (slots) => <double>[
      for (final component in operand(slots)) -component,
    ];
  }

  @override
  _Eval visitNot(ExpressionNot expression) {
    final operand = expression.operand.accept(this);
    return (slots) => <double>[operand(slots)[0] != 0 ? 0 : 1];
  }

  @override
  _Eval visitBinary(ExpressionBinary expression) {
    final left = expression.left.accept(this);
    final right = expression.right.accept(this);
    final op = expression.op;
    // Short-circuit, as the reader of `p > 0 && q / p > 1` expects; the
    // value is the same either way, which is what the bytecode relies on.
    if (op == '&&') {
      return (slots) => <double>[
        left(slots)[0] != 0 && right(slots)[0] != 0 ? 1 : 0,
      ];
    }
    if (op == '||') {
      return (slots) => <double>[
        left(slots)[0] != 0 || right(slots)[0] != 0 ? 1 : 0,
      ];
    }
    if (expression.left.type.components == 1 &&
        expression.right.type.components == 1) {
      return (slots) => <double>[
        expressionOperatorAt(op, left(slots)[0], right(slots)[0]),
      ];
    }
    return (slots) => applyExpressionOperator(op, left(slots), right(slots));
  }

  @override
  _Eval visitCall(ExpressionCall expression) {
    final arguments = <_Eval>[
      for (final argument in expression.arguments) argument.accept(this),
    ];
    final builtin = expression.builtin;
    return (slots) => builtin.apply(
      broadcastExpressionArguments(<List<double>>[
        for (final argument in arguments) argument(slots),
      ], builtin),
    );
  }

  @override
  _Eval visitConditional(ExpressionConditional expression) {
    final condition = expression.condition.accept(this);
    final then = expression.then.accept(this);
    final otherwise = expression.otherwise.accept(this);
    return (slots) => condition(slots)[0] != 0 ? then(slots) : otherwise(slots);
  }

  @override
  _Eval visitUnknown(Expression expression) => throw ArgumentError.value(
    expression,
    'expression',
    'not an expression this build of the expression language knows',
  );
}
