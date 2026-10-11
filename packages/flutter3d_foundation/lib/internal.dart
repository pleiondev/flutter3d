/// What a host language built on the expression language reads: the
/// recursive-descent [ExpressionParser] it extends, the [ExpressionToken]s
/// it walks, and the operator arithmetic every evaluator of the language
/// shares ([applyExpressionOperator], [broadcastExpressionArguments]).
///
/// **For the engine's own packages; not covered by semver for
/// applications.** `flutter3d_core`'s material language extends the parser
/// and evaluates through the shared arithmetic, so the two read and compute
/// the same language. The parser's hooks, its cursor and its token kinds
/// follow the grammar, and a minor that grows the grammar may change them.
/// An application reads expressions through `parseExpression` and the
/// types `package:flutter3d_foundation/flutter3d_foundation.dart` names.
/// This is a library of its own rather than `src/` imports so that what the
/// core depends on is in the API snapshot, and a change shows in review.
library;

export 'src/expressions/expression_ast.dart'
    show
        applyExpressionOperator,
        broadcastExpressionArguments,
        expressionOperators;
export 'src/expressions/expression_parser.dart'
    show ExpressionParser, ExpressionToken, tokenizeExpression;
