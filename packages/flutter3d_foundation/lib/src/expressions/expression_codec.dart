/// An expression as a document stores it: its source text, written so that
/// reading it back gives the same tree.
library;

import '../units.dart';
import 'expression_ast.dart';
import 'expression_parser.dart';

/// Writes an [Expression] as text the parser reads back to the same tree,
/// and reads it.
///
/// **Canonical, not as typed.** Every binary operation is in parentheses,
/// a number is written with the digits that read back to the same double,
/// and a number with a dimension is written in the coherent unit of that
/// dimension (`293.15 [K]` for what was typed `20 [°C]`), so two documents
/// that mean the same expression store the same text.
///
/// A document keeps an expression as this text under a key of its own;
/// [toJson] and [fromJson] are that string.
final class ExpressionCodec {
  /// A codec reading in [scope].
  const ExpressionCodec({this.scope = const ExpressionScope()});

  /// What names mean when a text is read back.
  final ExpressionScope scope;

  /// [expression] as canonical text.
  ///
  /// Throws [ArgumentError] for a kind of node this build cannot write.
  String encode(Expression expression) => expression.accept(const _Writer());

  /// The expression [text] holds.
  ///
  /// Throws [ExpressionSyntaxException] for text that is not one.
  Expression decode(String text) => parseExpression(text, scope: scope);

  /// [expression] as a document stores it: [encode]'s text.
  Object toJson(Expression expression) => encode(expression);

  /// The expression a document stored as [toJson] writes it.
  ///
  /// Throws [ExpressionSyntaxException] for anything else.
  Expression fromJson(Object? json) => switch (json) {
    final String text => decode(text),
    _ => throw ExpressionSyntaxException(
      'an expression is stored as its text, not as $json',
      1,
      1,
    ),
  };
}

final class _Writer extends ExpressionVisitor<String> {
  const _Writer();

  @override
  String visitConstant(ExpressionConstant expression) {
    final type = expression.type;
    if (type.isBoolean) return expression.value.single != 0 ? 'true' : 'false';
    final unit = type.dimension.isNone
        ? ''
        : ' [${Unit.coherent(type.dimension).symbol}]';
    final numbers = <String>[
      for (final value in expression.value) _number(value, unit),
    ];
    return type.components == 1
        ? numbers.single
        : '${ExpressionType.numeric[type.components]!.name}'
              '(${numbers.join(', ')})';
  }

  @override
  String visitVariable(ExpressionVariable expression) => expression.name;

  @override
  String visitConstruct(ExpressionConstruct expression) =>
      '${ExpressionType.numeric[expression.type.components]!.name}'
      '(${expression.arguments.map((a) => a.accept(this)).join(', ')})';

  @override
  String visitSwizzle(ExpressionSwizzle expression) {
    final target = expression.target.accept(this);
    final wrapped = expression.target is ExpressionVariable
        ? target
        : '($target)';
    return '$wrapped.${expression.components.map((i) => 'xyzw'[i]).join()}';
  }

  @override
  String visitNegate(ExpressionNegate expression) =>
      '(-${expression.operand.accept(this)})';

  @override
  String visitNot(ExpressionNot expression) =>
      '(!${expression.operand.accept(this)})';

  @override
  String visitBinary(ExpressionBinary expression) =>
      '(${expression.left.accept(this)} ${expression.op} '
      '${expression.right.accept(this)})';

  @override
  String visitCall(ExpressionCall expression) =>
      '${expression.builtin.name}'
      '(${expression.arguments.map((a) => a.accept(this)).join(', ')})';

  @override
  String visitConditional(ExpressionConditional expression) =>
      '(${expression.condition.accept(this)} ? '
      '${expression.then.accept(this)} : '
      '${expression.otherwise.accept(this)})';

  @override
  String visitUnknown(Expression expression) => throw ArgumentError.value(
    expression,
    'expression',
    'not an expression this build of the expression language can write',
  );

  /// The shortest digits that read back to [value], then [unit]; a negative
  /// one in parentheses, so `a - -1.0` cannot read as anything else.
  ///
  /// A NaN is written as the division that makes one, which reads back as
  /// that division rather than as a constant: the one value the text does
  /// not carry exactly.
  static String _number(double value, String unit) {
    if (value.isNaN) return '(0.0$unit / 0.0)';
    final text = value.isInfinite
        ? '${value > 0 ? '' : '-'}1e999'
        : value.toString();
    return value.isNegative ? '($text$unit)' : '$text$unit';
  }
}
