/// Reads a material written as source into a [MaterialProgram] — `gfx-84n`.
///
/// ```text
/// material RimLight {
///   param float rimPower = 2.0;
///   param vec3 rimColor = vec3(0.2, 0.6, 1.0);
///   texture base = base_color_texture;
///
///   fragment {
///     let facing = clamp(nDotV, 0.0, 1.0);
///     let rim = pow(1.0 - facing, rimPower);
///     return vec4(albedo + rimColor * rim, alpha);
///   }
/// }
/// ```
///
/// **The vocabulary is GLSL's, and that is the whole design.** `clamp`, `mix`,
/// `pow`, the swizzles and the broadcasting rules all mean what they mean in
/// GLSL, because the emitted shader has to read like the source for anybody
/// debugging the pair — and because a language that invented its own `mix`
/// would have to explain how it differs from the one every author already
/// knows. What is *not* GLSL is everything a material must not be allowed to
/// do: declare a uniform block, sample a texture the engine does not bind,
/// write to a global, or loop. Those are refusals with a sentence attached
/// rather than omissions.
///
/// **Typed on the way in, not on the way out.** Every expression node carries
/// its type because the parser worked it out; an emitter that had to infer
/// types would be a second type checker, and the two would disagree about
/// something like `vec3 * float` on one backend only.
library;

import 'material_ast.dart';

/// What the engine binds, and therefore the only names a `texture` declaration
/// may point at.
///
/// A material cannot invent a slot: the renderer binds textures by these names
/// and a name it does not know reaches the GPU as a missing sampler, which on
/// Metal is a crash rather than a black texture. The list is short because the
/// set really is that small — `surface.glsl` declares them.
const List<String> kMaterialTextureBindings = <String>[
  'base_color_texture',
  'normal_texture',
  'occlusion_texture',
  'emissive_texture',
  'metallic_roughness_texture',
];

/// A material source that could not be read, with where it went wrong.
///
/// Line and column rather than a byte offset: the author is looking at the
/// text in an editor, and "at 1:14" is a place they can put a cursor.
final class MaterialSyntaxError implements Exception {
  const MaterialSyntaxError(this.message, this.line, this.column);

  final String message;
  final int line;
  final int column;

  @override
  String toString() => 'MaterialSyntaxError at $line:$column: $message';
}

/// Reads [source] as one material.
MaterialProgram parseMaterial(String source) =>
    _Parser(_lex(source)).parseMaterial();

// ---------------------------------------------------------------------------
// Lexing
// ---------------------------------------------------------------------------

/// A token's kind, as the character or word that opens it.
///
/// Strings rather than a type of their own: the parser compares against
/// literals it writes out anyway (`'{'`, `'return'`), and a kind enum would be
/// a second spelling of the same set with a conversion between them.
final class _Token {
  const _Token(this.kind, this.text, this.line, this.column, [this.number]);

  /// One of `name`, `number`, `end`, or the punctuation itself.
  final String kind;
  final String text;
  final int line;
  final int column;
  final double? number;
}

const String _punctuation = '{}()=;,.+-*/';

List<_Token> _lex(String source) {
  final tokens = <_Token>[];
  var line = 1;
  var column = 1;
  var at = 0;

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
    // `//` to the end of the line. A material is a thing an author comments,
    // and a language with no comments is one whose files grow a README beside
    // them.
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
      final text = source.substring(at, end);
      final value = double.tryParse(text);
      if (value == null) {
        throw MaterialSyntaxError(
          '"$text" is not a number.',
          startLine,
          startColumn,
        );
      }
      advance(end - at);
      tokens.add(_Token('number', text, startLine, startColumn, value));
      continue;
    }
    if (_isNameStart(ch)) {
      var end = at;
      while (end < source.length && _isNamePart(source[end])) {
        end++;
      }
      final text = source.substring(at, end);
      advance(end - at);
      tokens.add(_Token('name', text, startLine, startColumn));
      continue;
    }
    if (_punctuation.contains(ch)) {
      advance(1);
      tokens.add(_Token(ch, ch, startLine, startColumn));
      continue;
    }
    throw MaterialSyntaxError(
      '"$ch" is not part of this language.',
      startLine,
      startColumn,
    );
  }
  tokens.add(_Token('end', '', line, column));
  return tokens;
}

bool _isDigit(String ch) => ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;

bool _isNameStart(String ch) =>
    (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
    (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
    ch == '_';

bool _isNamePart(String ch) => _isNameStart(ch) || _isDigit(ch);

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

final class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  int at = 0;

  final List<MaterialParameter> parameters = <MaterialParameter>[];
  final List<MaterialTextureSlot> textures = <MaterialTextureSlot>[];
  final Map<String, MaterialType> locals = <String, MaterialType>{};
  final Set<String> inputsUsed = <String>{};

  _Token get current => tokens[at];

  Never fail(String message, [_Token? where]) {
    final token = where ?? current;
    throw MaterialSyntaxError(message, token.line, token.column);
  }

  _Token take(String kind, String what) {
    if (current.kind != kind) {
      fail(
        'expected $what, found "${current.text.isEmpty ? 'the end of the '
                  'file' : current.text}".',
      );
    }
    final token = current;
    at++;
    return token;
  }

  bool takeIf(String kind) {
    if (current.kind != kind) return false;
    at++;
    return true;
  }

  bool takeWordIf(String word) {
    if (current.kind != 'name' || current.text != word) return false;
    at++;
    return true;
  }

  MaterialProgram parseMaterial() {
    if (!takeWordIf('material')) {
      fail('a material starts with the word "material".');
    }
    final name = take('name', 'the material\'s name').text;
    take('{', '"{" after the material\'s name');

    List<MaterialStatement>? body;
    while (!takeIf('}')) {
      if (current.kind == 'end') fail('the material is never closed with "}".');
      if (takeWordIf('param')) {
        parseParameter();
      } else if (takeWordIf('texture')) {
        parseTexture();
      } else if (takeWordIf('fragment')) {
        if (body != null) fail('a material has one fragment body.');
        body = parseBody();
      } else {
        fail(
          '"${current.text}" is not a declaration: a material holds "param", '
          '"texture" and one "fragment".',
        );
      }
    }
    if (body == null) fail('the material has no fragment body.');

    return MaterialProgram(
      name: name,
      parameters: parameters,
      textures: textures,
      body: body,
      inputsUsed: inputsUsed,
    );
  }

  void parseParameter() {
    final type = parseType();
    if (!type.isNumeric) {
      fail(
        'a parameter is a number or a vector; a texture is declared with '
        '"texture".',
      );
    }
    final nameToken = take('name', 'the parameter\'s name');
    checkFreeName(nameToken);
    take(
      '=',
      '"=" and a default value — a parameter without one is a '
          'parameter a variant can forget to set',
    );
    final value = parseConstant(type);
    take(';', '";" after the parameter');
    parameters.add(MaterialParameter(nameToken.text, type, value));
  }

  void parseTexture() {
    final nameToken = take('name', 'the slot\'s name');
    checkFreeName(nameToken);
    take('=', '"=" and the engine binding this slot reads');
    final binding = take('name', 'the engine binding\'s name');
    if (!kMaterialTextureBindings.contains(binding.text)) {
      fail(
        '"${binding.text}" is not a texture this engine binds. It binds '
        '${kMaterialTextureBindings.join(', ')} — a material cannot introduce '
        'a slot, because the renderer binds by name and a name it does not '
        'know reaches the GPU as a missing sampler.',
        binding,
      );
    }
    take(';', '";" after the texture');
    textures.add(MaterialTextureSlot(nameToken.text, binding.text));
  }

  /// A name may not shadow an input, a builtin or an earlier declaration.
  ///
  /// GLSL would allow some of this and the result is a material whose author
  /// thinks they are reading the surface normal and is reading their own
  /// variable — a bug that looks like the lighting being wrong.
  void checkFreeName(_Token token) {
    final name = token.text;
    for (final input in kMaterialInputs) {
      if (input.name == name) {
        fail('"$name" is one of the surface inputs.', token);
      }
    }
    if (MaterialBuiltin.byName(name) != null || name == 'sample') {
      fail('"$name" is a builtin function.', token);
    }
    if (MaterialType.numeric.values.any((t) => t.name == name)) {
      fail('"$name" is a type.', token);
    }
    for (final parameter in parameters) {
      if (parameter.name == name) fail('"$name" is declared twice.', token);
    }
    for (final slot in textures) {
      if (slot.name == name) fail('"$name" is declared twice.', token);
    }
    if (locals.containsKey(name)) {
      fail('"$name" is already bound in this body.', token);
    }
  }

  MaterialType parseType() {
    final token = take('name', 'a type');
    for (final type in MaterialType.numeric.values) {
      if (type.name == token.text) return type;
    }
    fail(
      '"${token.text}" is not a type: float, vec2, vec3 and vec4 are.',
      token,
    );
  }

  /// A parameter's default: a literal, or a constructor of literals.
  List<double> parseConstant(MaterialType type) {
    final expression = parseExpression();
    if (expression is! MaterialConstant) {
      fail('a parameter\'s default has to be a constant.');
    }
    if (expression.type != type) {
      fail(
        'the default is a ${expression.type}, and the parameter is a $type.',
      );
    }
    return expression.value;
  }

  List<MaterialStatement> parseBody() {
    take('{', '"{" after "fragment"');
    final body = <MaterialStatement>[];
    while (!takeIf('}')) {
      if (current.kind == 'end') fail('the fragment body is never closed.');
      if (takeWordIf('let')) {
        final nameToken = take('name', 'the name being bound');
        checkFreeName(nameToken);
        take('=', '"=" after the name');
        final value = parseExpression();
        if (!value.type.isNumeric) {
          fail('a "let" binds a number or a vector, not a ${value.type}.');
        }
        take(';', '";" after the binding');
        locals[nameToken.text] = value.type;
        body.add(MaterialLet(nameToken.text, value));
      } else if (takeWordIf('return')) {
        final value = parseExpression();
        if (value.type != MaterialType.vec4) {
          fail(
            'a fragment body returns a vec4 — rgb the light the surface '
            'emits, a its opacity — and this one returns a ${value.type}.',
          );
        }
        take(';', '";" after the returned value');
        body.add(MaterialReturn(value));
        if (current.kind != '}') {
          fail('nothing follows the return in a fragment body.');
        }
      } else {
        fail(
          '"${current.text}" is not a statement: a fragment body is "let" '
          'bindings and one "return".',
        );
      }
    }
    if (body.isEmpty || body.last is! MaterialReturn) {
      fail('the fragment body has no "return".');
    }
    return body;
  }

  // Expressions, by precedence: sum over product over unary over postfix.

  MaterialExpression parseExpression() {
    var left = parseProduct();
    while (current.kind == '+' || current.kind == '-') {
      final op = take(current.kind, 'an operator');
      final right = parseProduct();
      left = binary(op, left, right);
    }
    return left;
  }

  MaterialExpression parseProduct() {
    var left = parseUnary();
    while (current.kind == '*' || current.kind == '/') {
      final op = take(current.kind, 'an operator');
      final right = parseUnary();
      left = binary(op, left, right);
    }
    return left;
  }

  MaterialExpression parseUnary() {
    if (current.kind == '-') {
      final token = take('-', '"-"');
      final operand = parseUnary();
      if (!operand.type.isNumeric) {
        fail('a ${operand.type} cannot be negated.', token);
      }
      if (operand is MaterialConstant) {
        return MaterialConstant(<double>[
          for (final component in operand.value) -component,
        ], operand.type);
      }
      return MaterialNegate(operand);
    }
    return parsePostfix();
  }

  MaterialExpression parsePostfix() {
    var value = parsePrimary();
    while (takeIf('.')) {
      final field = take('name', 'a component after "."');
      value = swizzle(value, field);
    }
    return value;
  }

  MaterialExpression parsePrimary() {
    if (takeIf('(')) {
      final inner = parseExpression();
      take(')', '")"');
      return inner;
    }
    if (current.kind == 'number') {
      final token = take('number', 'a number');
      return MaterialConstant(<double>[token.number!], MaterialType.float);
    }
    if (current.kind != 'name') {
      fail('expected a value, found "${current.text}".');
    }

    final token = take('name', 'a value');
    final name = token.text;

    // A constructor.
    for (final type in MaterialType.numeric.values) {
      if (type.name == name) return construct(type, token);
    }
    if (name == 'sample') return sampleCall(token);
    final builtin = MaterialBuiltin.byName(name);
    if (builtin != null) return call(builtin, token);

    final local = locals[name];
    if (local != null) return MaterialLocalRef(name, local);
    final parameter = parameterNamed(name);
    // Carried as a reference and folded by `specialiseMaterial`, so that one
    // parse serves every variant.
    if (parameter != null) return MaterialParamRef(parameter);
    for (final input in kMaterialInputs) {
      if (input.name == name) {
        inputsUsed.add(name);
        return MaterialInputRef(input);
      }
    }
    if (textureNamed(name) != null) {
      fail('"$name" is a texture; it is read with sample($name, uv).', token);
    }
    fail('"$name" is not bound here.', token);
  }

  MaterialParameter? parameterNamed(String name) {
    for (final parameter in parameters) {
      if (parameter.name == name) return parameter;
    }
    return null;
  }

  MaterialTextureSlot? textureNamed(String name) {
    for (final slot in textures) {
      if (slot.name == name) return slot;
    }
    return null;
  }

  List<MaterialExpression> arguments() {
    take('(', '"(" and the arguments');
    final arguments = <MaterialExpression>[];
    if (!takeIf(')')) {
      do {
        arguments.add(parseExpression());
      } while (takeIf(','));
      take(')', '")" after the arguments');
    }
    return arguments;
  }

  MaterialExpression construct(MaterialType type, _Token token) {
    final parts = arguments();
    var components = 0;
    for (final part in parts) {
      if (!part.type.isNumeric) {
        fail('a ${part.type} is not a number and cannot go in a $type.', token);
      }
      components += part.type.components;
    }
    // GLSL's own rule for the one-argument case: `vec3(1.0)` is every
    // component. Anything else has to add up exactly.
    if (parts.length == 1 && parts.single.type == MaterialType.float) {
      final only = parts.single;
      if (only is MaterialConstant) {
        return MaterialConstant(
          List<double>.filled(type.components, only.value.single),
          type,
        );
      }
      return MaterialConstruct(
        List<MaterialExpression>.filled(type.components, only),
        type,
      );
    }
    if (components != type.components) {
      fail(
        'a $type takes ${type.components} components and these add up to '
        '$components.',
        token,
      );
    }
    if (parts.every((p) => p is MaterialConstant)) {
      return MaterialConstant(<double>[
        for (final part in parts) ...(part as MaterialConstant).value,
      ], type);
    }
    return MaterialConstruct(parts, type);
  }

  MaterialExpression sampleCall(_Token token) {
    take('(', '"(" after sample');
    final slotToken = take('name', 'the texture slot');
    final slot = textureNamed(slotToken.text);
    if (slot == null) {
      fail(
        '"${slotToken.text}" is not a texture this material declares.',
        slotToken,
      );
    }
    take(',', '"," and the coordinates');
    final uv = parseExpression();
    if (uv.type != MaterialType.vec2) {
      fail('sample takes a vec2 of coordinates, not a ${uv.type}.', token);
    }
    take(')', '")" after sample');
    return MaterialSample(slot, uv);
  }

  MaterialExpression call(MaterialBuiltin builtin, _Token token) {
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
          '${MaterialType.numeric[width]}.',
          token,
        );
      }
    }
    final resultWidth = builtin.resultComponents ?? width;
    return MaterialCall(builtin, parts, MaterialType.numeric[resultWidth]!);
  }

  MaterialExpression binary(
    _Token op,
    MaterialExpression left,
    MaterialExpression right,
  ) {
    if (!left.type.isNumeric || !right.type.isNumeric) {
      fail('"${op.text}" works on numbers, not on a texture.', op);
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
    return MaterialBinary(
      op.text,
      left,
      right,
      MaterialType.numeric[a > b ? a : b]!,
    );
  }

  MaterialExpression swizzle(MaterialExpression target, _Token field) {
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
    final type = MaterialType.numeric[indices.length]!;
    if (target is MaterialConstant) {
      return MaterialConstant(<double>[
        for (final index in indices) target.value[index],
      ], type);
    }
    return MaterialSwizzle(target, indices, type);
  }
}
