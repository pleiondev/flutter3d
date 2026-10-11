/// The reference evaluator: the tree walked once per evaluation, every node
/// computed where it stands.
///
/// **Internal, and kept as the yardstick.** The closure compiler and the
/// bytecode interpreter are what runs; this is the plainest reading of the
/// tree there is, and the tests hold both of them to its answers, bit for
/// bit, on every fixture.
library;

import 'expression_ast.dart';

/// The value of [expression], given each variable's components by name in
/// coherent units.
List<double> evaluateExpressionReference(
  Expression expression,
  Map<String, List<double>> values,
) => expression.accept(_Walker(values));

final class _Walker extends ExpressionVisitor<List<double>> {
  const _Walker(this.values);

  final Map<String, List<double>> values;

  @override
  List<double> visitConstant(ExpressionConstant expression) => expression.value;

  @override
  List<double> visitVariable(ExpressionVariable expression) =>
      values[expression.name] ??
      (throw ArgumentError('no value for "${expression.name}"'));

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
  List<double> visitNot(ExpressionNot expression) => <double>[
    expression.operand.accept(this)[0] != 0 ? 0 : 1,
  ];

  @override
  List<double> visitBinary(ExpressionBinary expression) =>
      applyExpressionOperator(
        expression.op,
        expression.left.accept(this),
        expression.right.accept(this),
      );

  @override
  List<double> visitCall(ExpressionCall expression) => expression.builtin.apply(
    broadcastExpressionArguments(<List<double>>[
      for (final argument in expression.arguments) argument.accept(this),
    ], expression.builtin),
  );

  @override
  List<double> visitConditional(ExpressionConditional expression) =>
      expression.condition.accept(this)[0] != 0
      ? expression.then.accept(this)
      : expression.otherwise.accept(this);

  @override
  List<double> visitUnknown(Expression expression) =>
      throw ArgumentError.value(expression, 'expression', 'unknown kind');
}
