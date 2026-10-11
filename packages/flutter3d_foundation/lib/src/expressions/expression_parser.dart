/// Reads the expression language: text into a typed [Expression].
///
/// ```text
/// mu0 * exp(b / (T - c))                 a law, T bound by the host in K
/// 0.5 * m * dot(v, v)                    a derived probe, in J
/// T > 100 [°C] && p < 2 [bar]            a condition, a bool
/// clamp(nDotV, 0.0, 1.0)                 a material's facing
/// ```
///
/// **The grammar.** Loosest first: `c ? a : b`; `||`; `&&`; the comparisons
/// `< <= > >= == !=` (one per operand pair, not chained); `+ -`; `* /`;
/// unary `-` and `!`; a swizzle `.xyz`; and a primary: a number with an
/// optional unit in brackets (`9.81 [m/s²]`), `true`, `false`, a
/// parenthesis, a constructor (`float`, `vec2`, `vec3`, `vec4`), a call of
/// a builtin, or a name the host binds. `//` comments run to the end of the
/// line.
///
/// **Units are checked while the text is read.** A number in brackets is
/// read in its unit and kept in the coherent SI unit of its dimension; a
/// sum of two dimensions, a comparison across them or a builtin given
/// arguments its rule refuses is an [ExpressionSyntaxException] that says
/// where.
///
/// **A host language stands on it.** [ExpressionParser] is a `base class`
/// with a cursor over the tokens and two hooks, [ExpressionParser.resolveName]
/// and [ExpressionParser.parseSpecialCall]: the material language extends it,
/// reads its declarations and blocks itself, and hands every expression to
/// [ExpressionParser.parseExpression], so its expressions are this
/// language's, typed by these rules. [ExpressionSyntax] says which of the
/// language's tokens a host reads, so a host whose files predate units or
/// comparisons reads them exactly as it always did.
library;

import '../exceptions.dart';
import '../units.dart';
import 'expression_ast.dart';

/// Text that is not an expression, with where it went wrong.
///
/// Line and column rather than a byte offset: the author is looking at the
/// text in an editor, and "at 1:14" is a place they can put a cursor.
final class ExpressionSyntaxException extends Flutter3dFormatException {
  const ExpressionSyntaxException(this.message, this.line, this.column);

  @override
  final String message;

  /// From 1.
  final int line;

  /// From 1.
  final int column;

  @override
  String toString() => 'ExpressionSyntaxException at $line:$column: $message';
}

/// Which of the language's tokens a reader takes, beyond the arithmetic
/// every reader has.
///
/// The material language reads its versions 1 and 2 with
/// `ExpressionSyntax(units: false, exponents: false, logic: false,
/// punctuation: '{}=;')`, so a character those versions did not know is
/// refused as it always was.
final class ExpressionSyntax {
  const ExpressionSyntax({
    this.units = true,
    this.exponents = true,
    this.logic = true,
    this.punctuation = '',
  });

  /// The whole language, as a document's expression is read.
  static const ExpressionSyntax standard = ExpressionSyntax();

  /// A unit in brackets after a number: `9.81 [m/s²]`.
  final bool units;

  /// An exponent in a number: `1.5e-3`.
  final bool exponents;

  /// Truth values: the comparisons, `&&`, `||`, `!`, `? :`, `true` and
  /// `false`.
  final bool logic;

  /// Single characters the host's own grammar uses, each a token of its
  /// own: `{}=;` for the material language's blocks and declarations.
  final String punctuation;
}

/// One token of a source.
///
/// [kind] is `name`, `number`, `unit`, `end`, or the punctuation itself
/// (`(`, `<=`, `&&`): a parser compares against literals it writes out
/// anyway, and a kind enum would be a second spelling of the same set.
final class ExpressionToken {
  const ExpressionToken(
    this.kind,
    this.text,
    this.line,
    this.column, [
    this.number,
  ]);

  final String kind;

  /// As written; a unit's text without its brackets.
  final String text;

  /// From 1.
  final int line;

  /// From 1.
  final int column;

  /// A number token's value as written.
  final double? number;

  @override
  String toString() => '$kind "$text" at $line:$column';
}

/// [source] as tokens, ending with one of kind `end`.
///
/// Throws [ExpressionSyntaxException] for a character [syntax] does not
/// take.
List<ExpressionToken> tokenizeExpression(
  String source, {
  ExpressionSyntax syntax = ExpressionSyntax.standard,
}) {
  final tokens = <ExpressionToken>[];
  var line = 1;
  var column = 1;
  var at = 0;
  final single = '(),.+-*/${syntax.punctuation}';
  const pairs = <String>['<=', '>=', '==', '!=', '&&', '||'];
  const logical = '<>!?:';

  void advance(int count) {
    for (var i = 0; i < count; i++) {
      if (source[at + i] == '\n') {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    at += count;
  }

  while (at < source.length) {
    final ch = source[at];
    if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
      advance(1);
      continue;
    }
    // `//` to the end of the line. A file is a thing an author comments,
    // and a language with no comments is one whose files grow a README
    // beside them.
    if (ch == '/' && at + 1 < source.length && source[at + 1] == '/') {
      while (at < source.length && source[at] != '\n') {
        advance(1);
      }
      continue;
    }

    final startLine = line;
    final startColumn = column;
    if (_isDigit(ch) ||
        (ch == '.' && at + 1 < source.length && _isDigit(source[at + 1]))) {
      var end = at;
      while (end < source.length &&
          (_isDigit(source[end]) || source[end] == '.')) {
        end++;
      }
      if (syntax.exponents &&
          end < source.length &&
          (source[end] == 'e' || source[end] == 'E')) {
        var digits = end + 1;
        if (digits < source.length &&
            (source[digits] == '+' || source[digits] == '-')) {
          digits++;
        }
        if (digits < source.length && _isDigit(source[digits])) {
          end = digits;
          while (end < source.length && _isDigit(source[end])) {
            end++;
          }
        }
      }
      final text = source.substring(at, end);
      final value = double.tryParse(text);
      if (value == null) {
        throw ExpressionSyntaxException(
          '"$text" is not a number.',
          startLine,
          startColumn,
        );
      }
      advance(end - at);
      tokens.add(
        ExpressionToken('number', text, startLine, startColumn, value),
      );
      continue;
    }
    if (_isNameStart(ch)) {
      var end = at;
      while (end < source.length && _isNamePart(source[end])) {
        end++;
      }
      final text = source.substring(at, end);
      advance(end - at);
      tokens.add(ExpressionToken('name', text, startLine, startColumn));
      continue;
    }
    if (syntax.units && ch == '[') {
      final close = source.indexOf(']', at);
      final newline = source.indexOf('\n', at);
      if (close < 0 || (newline >= 0 && newline < close)) {
        throw ExpressionSyntaxException(
          'a unit in "[" is never closed with "]".',
          startLine,
          startColumn,
        );
      }
      final text = source.substring(at + 1, close).trim();
      advance(close + 1 - at);
      tokens.add(ExpressionToken('unit', text, startLine, startColumn));
      continue;
    }
    if (syntax.logic && at + 1 < source.length) {
      final pair = source.substring(at, at + 2);
      if (pairs.contains(pair)) {
        advance(2);
        tokens.add(ExpressionToken(pair, pair, startLine, startColumn));
        continue;
      }
    }
    if (single.contains(ch) || (syntax.logic && logical.contains(ch))) {
      advance(1);
      tokens.add(ExpressionToken(ch, ch, startLine, startColumn));
      continue;
    }
    throw ExpressionSyntaxException(
      '"$ch" is not part of this language.',
      startLine,
      startColumn,
    );
  }
  tokens.add(ExpressionToken('end', '', line, column));
  return tokens;
}

bool _isDigit(String ch) => ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;

bool _isNameStart(String ch) =>
    (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
    (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
    ch == '_';

bool _isNamePart(String ch) => _isNameStart(ch) || _isDigit(ch);

/// What the names in a source mean: the variables the host binds, the
/// builtins it may call and the units it may write.
final class ExpressionScope {
  const ExpressionScope({
    this.variables = const <String, ExpressionType>{},
    this.builtins = ExpressionBuiltin.all,
    this.units = const <Unit>[],
  });

  /// A scope binding each of [variables] as a scalar in its unit's
  /// dimension: `{'T': Unit.kelvin, 'p': Unit.pascal}`.
  factory ExpressionScope.quantities(
    Map<String, Unit> variables, {
    List<ExpressionBuiltin> builtins = ExpressionBuiltin.all,
    List<Unit> units = const <Unit>[],
  }) => ExpressionScope(
    variables: <String, ExpressionType>{
      for (final MapEntry(:key, :value) in variables.entries)
        key: ExpressionType.measuring(value),
    },
    builtins: builtins,
    units: units,
  );

  /// Each name the host binds, with its type. Its value arrives with each
  /// evaluation, in the coherent unit of the type's dimension.
  final Map<String, ExpressionType> variables;

  /// The functions a source may call.
  final List<ExpressionBuiltin> builtins;

  /// The host's own units, read in brackets before the built-in ones, as
  /// `Unit.parse`'s `also` reads them.
  final List<Unit> units;
}

/// [source], one expression, read in [scope].
///
/// Throws [ExpressionSyntaxException] for text that is not one, with where.
Expression parseExpression(
  String source, {
  ExpressionScope scope = const ExpressionScope(),
  ExpressionSyntax syntax = ExpressionSyntax.standard,
}) {
  final parser = ExpressionParser(
    tokenizeExpression(source, syntax: syntax),
    scope: scope,
    syntax: syntax,
  );
  final expression = parser.parseExpression();
  if (parser.current.kind != 'end') {
    parser.fail(
      'nothing follows the expression, and "${parser.current.text}" '
      'does.',
    );
  }
  return expression;
}

/// The parser: a cursor over [tokens], the expression grammar, and two
/// hooks a host language overrides.
///
/// A `base class`: the material language extends it with its declarations
/// and blocks and reads every expression through [parseExpression].
base class ExpressionParser {
  ExpressionParser(
    this.tokens, {
    this.scope = const ExpressionScope(),
    this.syntax = ExpressionSyntax.standard,
  });

  /// What is read, ending with a token of kind `end`.
  final List<ExpressionToken> tokens;

  /// What the names mean.
  final ExpressionScope scope;

  /// Which tokens the grammar takes: the comparisons and `? :` only with
  /// [ExpressionSyntax.logic], a unit only with [ExpressionSyntax.units].
  final ExpressionSyntax syntax;

  /// The index of [current] in [tokens].
  int position = 0;

  /// The token being read.
  ExpressionToken get current => tokens[position];

  /// Throws an [ExpressionSyntaxException] at [where], [current] by default.
  Never fail(String message, [ExpressionToken? where]) {
    final token = where ?? current;
    throw ExpressionSyntaxException(message, token.line, token.column);
  }

  /// [current], which must be of [kind], and moves past it; [what] is how
  /// the refusal names what was expected.
  ExpressionToken take(String kind, String what) {
    if (current.kind != kind) {
      fail(
        'expected $what, found "${current.text.isEmpty ? 'the end of the '
                  'file' : current.text}".',
      );
    }
    final token = current;
    position++;
    return token;
  }

  /// Moves past [current] if it is of [kind].
  bool takeIf(String kind) {
    if (current.kind != kind) return false;
    position++;
    return true;
  }

  /// Moves past [current] if it is the name [word].
  bool takeWordIf(String word) {
    if (current.kind != 'name' || current.text != word) return false;
    position++;
    return true;
  }

  // ---------------------------------------------------------------- hooks

  /// What [name] means where it is read as a value: by default one of the
  /// scope's variables, and a refusal for anything else.
  ///
  /// A host overrides it for names of its own kinds, as the material
  /// language does for its inputs, parameters and `let`s.
  Expression resolveName(ExpressionToken name) {
    final type = scope.variables[name.text];
    if (type != null) return ExpressionVariable(name.text, type);
    fail('"${name.text}" is not bound here.', name);
  }

  /// A call the host reads itself, given the name before its `(`, or null
  /// to read it as a builtin. Asked after the constructors and before the
  /// builtins; the material language reads `sample(slot, uv)` here.
  Expression? parseSpecialCall(ExpressionToken name) => null;

  /// The builtin called [name], from the scope's.
  ExpressionBuiltin? builtinNamed(String name) {
    for (final builtin in scope.builtins) {
      if (builtin.name == name) return builtin;
    }
    return null;
  }

  // ---------------------------------------------------------- the grammar

  /// One expression, from [current] on.
  Expression parseExpression() =>
      syntax.logic ? parseConditional() : parseSum();

  /// `c ? a : b`, right to left.
  Expression parseConditional() {
    final condition = parseOr();
    if (current.kind != '?') return condition;
    final question = take('?', '"?"');
    final then = parseExpression();
    take(':', '":" and the value when the condition is false');
    final otherwise = parseExpression();
    if (!condition.type.isBoolean) {
      fail('a condition is a bool, and this is a ${condition.type}.', question);
    }
    if (then.type != otherwise.type) {
      fail(
        'the two values of "?" are a ${then.type} and a ${otherwise.type}; '
        'they have to be one type.',
        question,
      );
    }
    return ExpressionConditional(condition, then, otherwise);
  }

  Expression parseOr() {
    var left = parseAnd();
    while (current.kind == '||') {
      final op = take('||', 'an operator');
      left = logical(op, left, parseAnd());
    }
    return left;
  }

  Expression parseAnd() {
    var left = parseComparison();
    while (current.kind == '&&') {
      final op = take('&&', 'an operator');
      left = logical(op, left, parseComparison());
    }
    return left;
  }

  Expression parseComparison() {
    final left = parseSum();
    const comparisons = <String>{'<', '<=', '>', '>=', '==', '!='};
    if (!comparisons.contains(current.kind)) return left;
    final op = take(current.kind, 'an operator');
    final right = parseSum();
    if (comparisons.contains(current.kind)) {
      fail('comparisons do not chain: write "a < b && b < c".', current);
    }
    return comparison(op, left, right);
  }

  /// `+` and `-`, left to right.
  Expression parseSum() {
    var left = parseProduct();
    while (current.kind == '+' || current.kind == '-') {
      final op = take(current.kind, 'an operator');
      final right = parseProduct();
      left = binary(op, left, right);
    }
    return left;
  }

  /// `*` and `/`, left to right.
  Expression parseProduct() {
    var left = parseUnary();
    while (current.kind == '*' || current.kind == '/') {
      final op = take(current.kind, 'an operator');
      final right = parseUnary();
      left = binary(op, left, right);
    }
    return left;
  }

  /// `-` and `!`. A negated constant is folded.
  Expression parseUnary() {
    if (current.kind == '-') {
      final token = take('-', '"-"');
      final operand = parseUnary();
      if (!operand.type.isNumeric) {
        fail('a ${operand.type} cannot be negated.', token);
      }
      if (operand is ExpressionConstant) {
        return ExpressionConstant(<double>[
          for (final component in operand.value) -component,
        ], operand.type);
      }
      return ExpressionNegate(operand);
    }
    if (syntax.logic && current.kind == '!') {
      final token = take('!', '"!"');
      final operand = parseUnary();
      if (!operand.type.isBoolean) {
        fail('"!" takes a bool, and this is a ${operand.type}.', token);
      }
      return ExpressionNot(operand);
    }
    return parsePostfix();
  }

  /// A primary and its swizzles.
  Expression parsePostfix() {
    var value = parsePrimary();
    while (takeIf('.')) {
      final field = take('name', 'a component after "."');
      value = swizzle(value, field);
    }
    return value;
  }

  /// A number, a parenthesis, a constructor, a call or a name.
  Expression parsePrimary() {
    if (takeIf('(')) {
      final inner = parseExpression();
      take(')', '")"');
      return inner;
    }
    if (current.kind == 'number') {
      final token = take('number', 'a number');
      if (current.kind == 'unit') return quantity(token, take('unit', ''));
      return ExpressionConstant(<double>[token.number!], ExpressionType.float);
    }
    if (current.kind != 'name') {
      fail('expected a value, found "${current.text}".');
    }

    final token = take('name', 'a value');
    final name = token.text;
    if (syntax.logic && (name == 'true' || name == 'false')) {
      return ExpressionConstant(<double>[
        name == 'true' ? 1 : 0,
      ], ExpressionType.boolean);
    }
    for (final type in ExpressionType.numeric.values) {
      if (type.name == name) return construct(type, token);
    }
    if (current.kind == '(') {
      if (parseSpecialCall(token) case final special?) return special;
    }
    final builtin = builtinNamed(name);
    if (builtin != null) return call(builtin, token);
    return resolveName(token);
  }

  // --------------------------------------------------------- the typing

  /// `9.81 [m/s²]`: the number in the coherent unit of its dimension.
  Expression quantity(ExpressionToken number, ExpressionToken unitToken) {
    final Unit unit;
    try {
      unit = Unit.parse(unitToken.text, also: scope.units);
    } on UnitFormatException catch (error) {
      fail('"[${unitToken.text}]" is not a unit: ${error.reason}.', unitToken);
    }
    return ExpressionConstant(<double>[
      number.number! * unit.scale + unit.offset,
    ], ExpressionType.measuring(unit));
  }

  /// The arguments of a call, between parentheses.
  List<Expression> arguments() {
    take('(', '"(" and the arguments');
    final arguments = <Expression>[];
    if (!takeIf(')')) {
      do {
        arguments.add(parseExpression());
      } while (takeIf(','));
      take(')', '")" after the arguments');
    }
    return arguments;
  }

  /// A constructor of [type], folded when its parts are constant.
  Expression construct(ExpressionType type, ExpressionToken token) {
    final parts = arguments();
    var components = 0;
    for (final part in parts) {
      if (!part.type.isNumeric) {
        fail('a ${part.type} is not a number and cannot go in a $type.', token);
      }
      components += part.type.components;
    }
    final dimension = parts.isEmpty
        ? Dimension.none
        : parts.first.type.dimension;
    if (parts.any((part) => part.type.dimension != dimension)) {
      fail(
        'the parts of a $type measure different things: '
        '${parts.map((part) => part.type.dimension).toSet().join(', ')}.',
        token,
      );
    }
    final typed = type.withDimension(dimension);
    // GLSL's own rule for the one-argument case: `vec3(1.0)` is every
    // component. Anything else has to add up exactly.
    if (parts.length == 1 && parts.single.type.components == 1) {
      final only = parts.single;
      if (only is ExpressionConstant) {
        return ExpressionConstant(
          List<double>.filled(type.components, only.value.single),
          typed,
        );
      }
      return ExpressionConstruct(
        List<Expression>.filled(type.components, only),
        typed,
      );
    }
    if (components != type.components) {
      fail(
        'a $type takes ${type.components} components and these add up to '
        '$components.',
        token,
      );
    }
    if (parts.every((p) => p is ExpressionConstant)) {
      return ExpressionConstant(<double>[
        for (final part in parts) ...(part as ExpressionConstant).value,
      ], typed);
    }
    return ExpressionConstruct(parts, typed);
  }

  /// A call of [builtin], its arguments checked by count, width and unit.
  Expression call(ExpressionBuiltin builtin, ExpressionToken token) {
    final parts = arguments();
    if (parts.length != builtin.arity) {
      fail(
        '${builtin.name} takes ${builtin.arity} arguments and was given '
        '${parts.length}.',
        token,
      );
    }
    var width = 1;
    for (final part in parts) {
      if (!part.type.isNumeric) {
        fail('${builtin.name} takes numbers, not a ${part.type}.', token);
      }
      if (part.type.components > width) width = part.type.components;
    }
    for (final part in parts) {
      final components = part.type.components;
      if (components != width && !(builtin.componentWise && components == 1)) {
        fail(
          '${builtin.name} was given a ${part.type} beside a '
          '${ExpressionType.numeric[width]}.',
          token,
        );
      }
    }
    final dimension =
        builtin.dimension(parts) ??
        fail(
          '${builtin.name} ${builtin.units}, and was given '
          '${parts.map((part) => part.type).join(', ')}.',
          token,
        );
    final resultWidth = builtin.resultComponents ?? width;
    return ExpressionCall(
      builtin,
      parts,
      ExpressionType.numeric[resultWidth]!.withDimension(dimension),
    );
  }

  /// `+ - * /`, with GLSL's broadcasting; a sum or a difference of one
  /// dimension, a product or a quotient of any two.
  Expression binary(ExpressionToken op, Expression left, Expression right) {
    for (final side in <Expression>[left, right]) {
      if (!side.type.isNumeric) {
        fail('"${op.text}" works on numbers, not on a ${side.type.name}.', op);
      }
    }
    final a = left.type.components;
    final b = right.type.components;
    if (a != b && a != 1 && b != 1) {
      fail(
        'a ${left.type} and a ${right.type} cannot be combined with '
        '"${op.text}".',
        op,
      );
    }
    final dimension = switch (op.text) {
      '*' => left.type.dimension * right.type.dimension,
      '/' => left.type.dimension / right.type.dimension,
      _ when left.type.dimension == right.type.dimension => left.type.dimension,
      _ => fail(
        'a ${left.type} and a ${right.type} cannot be '
        '${op.text == '+' ? 'added' : 'subtracted'}: they measure different '
        'things.',
        op,
      ),
    };
    return ExpressionBinary(
      op.text,
      left,
      right,
      ExpressionType.numeric[a > b ? a : b]!.withDimension(dimension),
    );
  }

  /// A comparison of two numbers of one dimension, or `==` and `!=` of two
  /// bools.
  Expression comparison(ExpressionToken op, Expression left, Expression right) {
    final equality = op.text == '==' || op.text == '!=';
    final bothBool = left.type.isBoolean && right.type.isBoolean;
    if (!(equality && bothBool)) {
      for (final side in <Expression>[left, right]) {
        if (!side.type.isNumeric || side.type.components != 1) {
          fail('"${op.text}" compares two numbers, not a ${side.type}.', op);
        }
      }
      if (left.type.dimension != right.type.dimension) {
        fail(
          'a ${left.type} and a ${right.type} cannot be compared: they '
          'measure different things.',
          op,
        );
      }
    }
    return ExpressionBinary(op.text, left, right, ExpressionType.boolean);
  }

  /// `&&` and `||` of two bools.
  Expression logical(ExpressionToken op, Expression left, Expression right) {
    if (!left.type.isBoolean || !right.type.isBoolean) {
      fail(
        '"${op.text}" takes two bools, and was given a ${left.type} and a '
        '${right.type}.',
        op,
      );
    }
    return ExpressionBinary(op.text, left, right, ExpressionType.boolean);
  }

  /// `.xyz` and `.rgb`, folded on a constant.
  Expression swizzle(Expression target, ExpressionToken field) {
    if (!target.type.isNumeric) {
      fail('a ${target.type} has no components.', field);
    }
    const sets = <String>['xyzw', 'rgba'];
    final indices = <int>[];
    String? chosen;
    for (final letter in field.text.split('')) {
      final set = sets.firstWhere((s) => s.contains(letter), orElse: () => '');
      if (set.isEmpty) {
        fail(
          '"$letter" is not a component: xyzw and rgba are, and one '
          'swizzle does not mix the two.',
          field,
        );
      }
      // GLSL refuses `.xg` too, and for the reason it reads badly rather than
      // for one about the hardware: two names for the same component in one
      // expression is somebody having lost track of which vector they are in.
      chosen ??= set;
      if (set != chosen) {
        fail('"${field.text}" mixes xyzw with rgba.', field);
      }
      final index = set.indexOf(letter);
      if (index >= target.type.components) {
        fail('a ${target.type} has no "$letter".', field);
      }
      indices.add(index);
    }
    if (indices.isEmpty || indices.length > 4) {
      fail('"${field.text}" is not one to four components.', field);
    }
    final type = ExpressionType.numeric[indices.length]!.withDimension(
      target.type.dimension,
    );
    if (target is ExpressionConstant) {
      return ExpressionConstant(<double>[
        for (final index in indices) target.value[index],
      ], type);
    }
    return ExpressionSwizzle(target, indices, type);
  }
}
