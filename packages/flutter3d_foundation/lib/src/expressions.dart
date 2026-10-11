/// The engine's expression language: [parseExpression] reads text into a
/// typed [Expression], [CompiledExpression] runs it on [Portable] maths, and
/// [ExpressionCodec] writes it back as the text a document stores.
///
/// What an application or a plugin uses, named. The parser a host language
/// extends, its tokens and the shared operator arithmetic are in
/// `package:flutter3d_foundation/internal.dart`.
library;

export 'expressions/expression_ast.dart'
    show
        Expression,
        ExpressionBinary,
        ExpressionBuiltin,
        ExpressionCall,
        ExpressionConditional,
        ExpressionConstant,
        ExpressionConstruct,
        ExpressionNegate,
        ExpressionNot,
        ExpressionSwizzle,
        ExpressionType,
        ExpressionVariable,
        ExpressionVisitor;
export 'expressions/expression_codec.dart' show ExpressionCodec;
export 'expressions/expression_compile.dart' show CompiledExpression;
export 'expressions/expression_parser.dart'
    show
        ExpressionScope,
        ExpressionSyntax,
        ExpressionSyntaxException,
        parseExpression;
