/// Reads `.f3dmat compute` source into the typed tree of `kernel_ast.dart`,
/// refusing what is not a kernel with the line and column — 1.0.
///
/// ```text
/// compute PrefixSum {
///   workgroup 64;
///   buffer values: u32[] read_write;
///   kernel {
///     let i = id.x;
///     if i >= len(values) { return; }
///     ...
///   }
/// }
/// ```
///
/// **Typed here, once.** Every rule a translator would otherwise have to
/// know — which literal becomes which type, what a write to a read-only
/// buffer is, how a vector meets a scalar — is decided by this file, and
/// both translators read the answer off the tree.
library;

import '../kernel_exception.dart';
import 'kernel_ast.dart';

/// Every `compute` block of [source], in order. Other top-level blocks — a
/// `material` beside the kernels in one `.f3dmat` file — are skipped.
List<KKernel> parseKernels(String source) => _Parser(source).file();

final class _Token {
  const _Token(this.kind, this.text, this.line, this.column);

  /// `ident`, `int`, `float`, `punct` or `eof`.
  final String kind;
  final String text;
  final int line;
  final int column;

  @override
  String toString() => kind == 'eof' ? 'the end of the file' : '"$text"';
}

const List<String> _punctuation = <String>[
  '..',
  '&&',
  '||',
  '==',
  '!=',
  '<=',
  '>=',
  '<<',
  '>>',
  '+=',
  '-=',
  '*=',
  '/=',
  '%=',
  '{',
  '}',
  '(',
  ')',
  '[',
  ']',
  ';',
  ',',
  ':',
  '.',
  '=',
  '<',
  '>',
  '+',
  '-',
  '*',
  '/',
  '%',
  '&',
  '|',
  '^',
  '~',
  '!',
];

/// Words a local may not be called: the language's own, and the built-ins.
const Set<String> _reserved = <String>{
  'compute',
  'workgroup',
  'buffer',
  'texture',
  'image',
  'kernel',
  'let',
  'var',
  'if',
  'else',
  'for',
  'in',
  'break',
  'continue',
  'return',
  'true',
  'false',
  'store',
  'load',
  'len',
  'width',
  'height',
  'id',
  'f32',
  'i32',
  'u32',
  'bool',
  'vec2',
  'vec3',
  'vec4',
  'min',
  'max',
  'clamp',
  'abs',
  'floor',
  'ceil',
  'round',
  'trunc',
  'sqrt',
  'select',
  'read',
  'read_write',
  'rgba8',
};

List<_Token> _lex(String source) {
  final tokens = <_Token>[];
  var at = 0;
  var line = 1;
  var lineStart = 0;
  bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  bool isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
  bool isIdent(int c) => isIdentStart(c) || isDigit(c);
  while (at < source.length) {
    final c = source.codeUnitAt(at);
    if (c == 0x0A) {
      line += 1;
      at += 1;
      lineStart = at;
      continue;
    }
    if (c == 0x20 || c == 0x09 || c == 0x0D) {
      at += 1;
      continue;
    }
    if (source.startsWith('//', at)) {
      while (at < source.length && source.codeUnitAt(at) != 0x0A) {
        at += 1;
      }
      continue;
    }
    if (source.startsWith('/*', at)) {
      final end = source.indexOf('*/', at + 2);
      if (end < 0) {
        throw ComputeKernelException(
          'a comment that never ends',
          line: line,
          column: at - lineStart + 1,
        );
      }
      for (var i = at; i < end; i++) {
        if (source.codeUnitAt(i) == 0x0A) {
          line += 1;
          lineStart = i + 1;
        }
      }
      at = end + 2;
      continue;
    }
    final column = at - lineStart + 1;
    if (isIdentStart(c)) {
      final start = at;
      while (at < source.length && isIdent(source.codeUnitAt(at))) {
        at += 1;
      }
      tokens.add(_Token('ident', source.substring(start, at), line, column));
      continue;
    }
    if (isDigit(c)) {
      final start = at;
      var float = false;
      while (at < source.length && isDigit(source.codeUnitAt(at))) {
        at += 1;
      }
      // A point followed by a digit continues the number; `0..n` is a range.
      if (at + 1 < source.length &&
          source.codeUnitAt(at) == 0x2E &&
          isDigit(source.codeUnitAt(at + 1))) {
        float = true;
        at += 1;
        while (at < source.length && isDigit(source.codeUnitAt(at))) {
          at += 1;
        }
      }
      if (at < source.length &&
          (source.codeUnitAt(at) == 0x65 || source.codeUnitAt(at) == 0x45)) {
        var look = at + 1;
        if (look < source.length &&
            (source.codeUnitAt(look) == 0x2B ||
                source.codeUnitAt(look) == 0x2D)) {
          look += 1;
        }
        if (look < source.length && isDigit(source.codeUnitAt(look))) {
          float = true;
          at = look;
          while (at < source.length && isDigit(source.codeUnitAt(at))) {
            at += 1;
          }
        }
      }
      // A suffix: `u` or `i` on an integer, `f` on either.
      if (at < source.length) {
        final s = source.codeUnitAt(at);
        if (s == 0x66 || (!float && (s == 0x75 || s == 0x69))) {
          at += 1;
          if (s == 0x66) float = true;
        }
      }
      if (at < source.length && isIdent(source.codeUnitAt(at))) {
        throw ComputeKernelException(
          'a number runs into a name: '
          '"${source.substring(start, at + 1)}"',
          line: line,
          column: column,
        );
      }
      tokens.add(
        _Token(
          float ? 'float' : 'int',
          source.substring(start, at),
          line,
          column,
        ),
      );
      continue;
    }
    final punct = _punctuation.where((p) => source.startsWith(p, at));
    if (punct.isEmpty) {
      throw ComputeKernelException(
        'a character the language does not have: "${source[at]}"',
        line: line,
        column: column,
      );
    }
    tokens.add(_Token('punct', punct.first, line, column));
    at += punct.first.length;
  }
  tokens.add(_Token('eof', '', line, at - lineStart + 1));
  return tokens;
}

/// The locals in scope, innermost last.
final class _Scope {
  _Scope(this.parent);
  final _Scope? parent;
  final Map<String, KLocal> locals = <String, KLocal>{};

  KLocal? find(String name) => locals[name] ?? parent?.find(name);
}

final class _Parser {
  _Parser(String source) : _tokens = _lex(source);

  final List<_Token> _tokens;
  int _at = 0;

  // Per kernel.
  Map<String, KBinding> _bindings = <String, KBinding>{};
  _Scope _scope = _Scope(null);
  int _loops = 0;

  _Token get _peek => _tokens[_at];
  _Token _next() => _tokens[_at++];

  Never _fail(String message, [_Token? at]) {
    final token = at ?? _peek;
    throw ComputeKernelException(
      message,
      line: token.line,
      column: token.column,
    );
  }

  bool _is(String text) => _peek.kind != 'eof' && _peek.text == text;

  bool _accept(String text) {
    if (!_is(text)) return false;
    _at += 1;
    return true;
  }

  _Token _expect(String text) {
    if (!_is(text)) _fail('expected "$text", found $_peek');
    return _next();
  }

  String _name(String what) {
    final token = _peek;
    if (token.kind != 'ident') _fail('expected $what, found $token');
    _at += 1;
    return token.text;
  }

  List<KKernel> file() {
    final kernels = <KKernel>[];
    final names = <String>{};
    while (_peek.kind != 'eof') {
      final word = _peek;
      if (word.kind != 'ident') _fail('expected a block, found $word');
      if (word.text != 'compute') {
        _skipBlock();
        continue;
      }
      _at += 1;
      final kernel = _kernel();
      if (!names.add(kernel.name)) {
        _fail('a second kernel called "${kernel.name}"', word);
      }
      kernels.add(kernel);
    }
    return kernels;
  }

  /// A top-level block that is not a kernel: its words up to the brace that
  /// closes the one it opens.
  void _skipBlock() {
    while (_peek.kind != 'eof' && !_is('{')) {
      _at += 1;
    }
    if (_peek.kind == 'eof') return;
    var depth = 0;
    do {
      final token = _next();
      if (token.text == '{' && token.kind == 'punct') depth += 1;
      if (token.text == '}' && token.kind == 'punct') depth -= 1;
      if (token.kind == 'eof') _fail('a block that never closes', token);
    } while (depth > 0);
  }

  KKernel _kernel() {
    final nameToken = _peek;
    final name = _name('the kernel\'s name');
    _bindings = <String, KBinding>{};
    _scope = _Scope(null);
    _loops = 0;
    (int, int, int)? workgroup;
    List<KStmt>? body;
    _expect('{');
    while (!_accept('}')) {
      final word = _peek;
      switch (word.text) {
        case 'workgroup':
          _at += 1;
          if (workgroup != null) _fail('a second workgroup size', word);
          workgroup = _workgroup();
        case 'buffer':
          _at += 1;
          _buffer(word);
        case 'texture' || 'image':
          _at += 1;
          _texture(word);
        case 'kernel':
          _at += 1;
          if (body != null) _fail('a second kernel body', word);
          body = _block();
        default:
          _fail(
            'expected workgroup, buffer, texture, image or kernel, found '
            '$word',
          );
      }
    }
    if (body == null) _fail('"$name" has no kernel body', nameToken);
    return KKernel(
      name: name,
      workgroup: workgroup ?? (64, 1, 1),
      bindings: _bindings.values.toList(),
      body: body,
    );
  }

  (int, int, int) _workgroup() {
    final sizes = <int>[];
    final first = _peek;
    do {
      final token = _next();
      final value = token.kind == 'int' ? int.tryParse(token.text) : null;
      if (value == null || value < 1) {
        _fail('a workgroup size is a whole number above zero', token);
      }
      sizes.add(value);
    } while (_accept(','));
    _expect(';');
    if (sizes.length > 3) _fail('a workgroup has three dimensions', first);
    while (sizes.length < 3) {
      sizes.add(1);
    }
    final (x, y, z) = (sizes[0], sizes[1], sizes[2]);
    // WebGPU's guaranteed minimums, which every placement meets.
    if (x > 256 || y > 256 || z > 64 || x * y * z > 256) {
      _fail(
        'a workgroup of $x × $y × $z is more than every device runs: at '
        'most 256 × 256 × 64, and 256 invocations in all',
        first,
      );
    }
    return (x, y, z);
  }

  void _declare(_Token at, String name, KBinding Function(int) make) {
    if (_reserved.contains(name)) {
      _fail('"$name" is a word of the language', at);
    }
    if (_bindings.containsKey(name)) _fail('a second binding "$name"', at);
    _bindings[name] = make(_bindings.length);
  }

  void _buffer(_Token word) {
    final nameToken = _peek;
    final name = _name('the buffer\'s name');
    _expect(':');
    final typeToken = _peek;
    final element = switch (_name('a scalar type')) {
      'f32' => KType.f32,
      'i32' => KType.i32,
      'u32' => KType.u32,
      _ => _fail('a buffer holds f32, i32 or u32', typeToken),
    };
    _expect('[');
    _expect(']');
    var writable = false;
    if (_peek.kind == 'ident') {
      final access = _next();
      writable = switch (access.text) {
        'read' => false,
        'read_write' => true,
        _ => _fail('a buffer is read or read_write', access),
      };
    }
    _expect(';');
    _declare(
      nameToken,
      name,
      (int index) => KBinding(
        name: name,
        kind: KBindingKind.buffer,
        element: element,
        writable: writable,
        index: index,
        line: word.line,
      ),
    );
  }

  void _texture(_Token word) {
    final image = word.text == 'image';
    final nameToken = _peek;
    final name = _name('the ${word.text}\'s name');
    _expect(':');
    final format = _peek;
    if (_name('a texel format') != 'rgba8') {
      _fail('a ${word.text} is rgba8 in this version', format);
    }
    _expect(';');
    _declare(
      nameToken,
      name,
      (int index) => KBinding(
        name: name,
        kind: image ? KBindingKind.image : KBindingKind.texture,
        element: KType.vec4,
        writable: image,
        index: index,
        line: word.line,
      ),
    );
  }

  List<KStmt> _block() {
    _expect('{');
    final outer = _scope;
    _scope = _Scope(outer);
    final statements = <KStmt>[];
    while (!_accept('}')) {
      if (_peek.kind == 'eof') _fail('a block that never closes');
      statements.add(_statement());
    }
    _scope = outer;
    return statements;
  }

  KStmt _statement() {
    final word = _peek;
    final line = word.line;
    switch (word.text) {
      case 'let' || 'var' when word.kind == 'ident':
        _at += 1;
        final nameToken = _peek;
        final name = _name('a name');
        if (_reserved.contains(name) || _bindings.containsKey(name)) {
          _fail('"$name" is already a word or a binding', nameToken);
        }
        if (_scope.locals.containsKey(name)) {
          _fail('a second "$name" in one block', nameToken);
        }
        KType? declared;
        if (_accept(':')) declared = _type();
        _expect('=');
        var value = _expression();
        value = declared == null
            ? _concrete(value)
            : _coerce(value, declared, nameToken);
        _expect(';');
        final local = KLocal(name, value.type, mutable: word.text == 'var');
        _scope.locals[name] = local;
        return KDeclare(local, value, line);
      case 'if' when word.kind == 'ident':
        return _if();
      case 'for' when word.kind == 'ident':
        _at += 1;
        final nameToken = _peek;
        final name = _name('the counter\'s name');
        if (_reserved.contains(name) || _bindings.containsKey(name)) {
          _fail('"$name" is already a word or a binding', nameToken);
        }
        _expect('in');
        var from = _expression();
        _expect('..');
        var to = _expression();
        final type = _unify(from.type, to.type, nameToken)?.concrete;
        if (type == null || (type != KType.i32 && type != KType.u32)) {
          _fail('a range counts in i32 or u32', nameToken);
        }
        from = _coerce(from, type, nameToken);
        to = _coerce(to, type, nameToken);
        final counter = KLocal(name, type, mutable: false);
        final outer = _scope;
        _scope = _Scope(outer)..locals[name] = counter;
        _loops += 1;
        final body = _block();
        _loops -= 1;
        _scope = outer;
        return KFor(counter, from, to, body, line);
      case 'break' || 'continue' when word.kind == 'ident':
        _at += 1;
        if (_loops == 0) _fail('"${word.text}" outside a loop', word);
        _expect(';');
        return word.text == 'break' ? KBreak(line) : KContinue(line);
      case 'return' when word.kind == 'ident':
        _at += 1;
        _expect(';');
        return KReturn(line);
      case 'store' when word.kind == 'ident':
        _at += 1;
        _expect('(');
        final binding = _bindingNamed(KBindingKind.image, 'an image');
        _expect(',');
        final x = _coordinate();
        _expect(',');
        final y = _coordinate();
        _expect(',');
        final value = _coerce(_expression(), KType.vec4, word);
        _expect(')');
        _expect(';');
        return KImageStore(binding, x, y, value, line);
    }
    if (word.kind != 'ident') _fail('expected a statement, found $word');
    _at += 1;
    final binding = _bindings[word.text];
    if (binding != null) {
      if (binding.kind != KBindingKind.buffer) {
        _fail('a ${binding.kind.name} is written with store(), not assigned');
      }
      if (!binding.writable) {
        _fail('"${binding.name}" is read only; declare it read_write', word);
      }
      _expect('[');
      final index = _index();
      _expect(']');
      final operator = _assignment();
      var value = _expression();
      if (operator != '=') {
        value = _binary(
          operator.substring(0, 1),
          KBufferRead(binding, index),
          value,
          word,
        );
      }
      _expect(';');
      return KBufferWrite(
        binding,
        index,
        _coerce(value, binding.element, word),
        line,
      );
    }
    final local = _scope.find(word.text);
    if (local == null) _fail('nothing is called "${word.text}"', word);
    if (!local.mutable) {
      _fail('"${local.name}" is a let; declare it with var to assign it', word);
    }
    final operator = _assignment();
    var value = _expression();
    if (operator != '=') {
      value = _binary(operator.substring(0, 1), KLocalRef(local), value, word);
    }
    _expect(';');
    return KAssign(local, _coerce(value, local.type, word), line);
  }

  String _assignment() {
    final token = _next();
    if (const <String>[
          '=',
          '+=',
          '-=',
          '*=',
          '/=',
          '%=',
        ].contains(token.text) &&
        token.kind == 'punct') {
      return token.text;
    }
    _fail('expected an assignment, found $token', token);
  }

  KStmt _if() {
    final word = _next();
    final condition = _coerce(_expression(), KType.boolean, word);
    final then = _block();
    var otherwise = const <KStmt>[];
    if (_accept('else')) {
      otherwise = _is('if') ? <KStmt>[_if()] : _block();
    }
    return KIf(condition, then, otherwise, word.line);
  }

  KType _type() {
    final token = _peek;
    return switch (_name('a type')) {
      'f32' => KType.f32,
      'i32' => KType.i32,
      'u32' => KType.u32,
      'bool' => KType.boolean,
      'vec2' => KType.vec2,
      'vec3' => KType.vec3,
      'vec4' => KType.vec4,
      final other => _fail('"$other" is not a type', token),
    };
  }

  KBinding _bindingNamed(KBindingKind kind, String what) {
    final token = _peek;
    final name = _name(what);
    final binding = _bindings[name];
    if (binding == null) _fail('nothing is called "$name"', token);
    if (binding.kind != kind) _fail('"$name" is not $what', token);
    return binding;
  }

  /// An index into a buffer: i32 or u32.
  KExpr _index() {
    final token = _peek;
    final index = _concrete(_expression());
    if (index.type != KType.i32 && index.type != KType.u32) {
      _fail('an index is i32 or u32, not ${index.type}', token);
    }
    return index;
  }

  KExpr _coordinate() => _index();

  // ------------------------------------------------------------ expressions

  KExpr _expression() => _binaryLevel(0);

  static const List<List<String>> _levels = <List<String>>[
    <String>['||'],
    <String>['&&'],
    <String>['|'],
    <String>['^'],
    <String>['&'],
    <String>['==', '!='],
    <String>['<', '<=', '>', '>='],
    <String>['<<', '>>'],
    <String>['+', '-'],
    <String>['*', '/', '%'],
  ];

  KExpr _binaryLevel(int level) {
    if (level == _levels.length) return _unary();
    var left = _binaryLevel(level + 1);
    while (_peek.kind == 'punct' && _levels[level].contains(_peek.text)) {
      final op = _next();
      final right = _binaryLevel(level + 1);
      left = _binary(op.text, left, right, op);
    }
    return left;
  }

  /// The common type of two operands, an abstract literal taking the
  /// other's; null when they have none.
  KType? _unify(KType a, KType b, _Token at) {
    if (a == b) return a;
    if (a.isAbstract && b.isAbstract) return KType.abstractFloat;
    if (a.isAbstract) return _accepts(b, a) ? b : null;
    if (b.isAbstract) return _accepts(a, b) ? a : null;
    return null;
  }

  /// Whether a literal of abstract type [literal] may become [type].
  static bool _accepts(KType type, KType literal) =>
      literal == KType.abstractInt
      ? (type == KType.i32 || type == KType.u32 || type == KType.f32)
      : type == KType.f32;

  KExpr _binary(String op, KExpr left, KExpr right, _Token at) {
    final a = left.type;
    final b = right.type;
    switch (op) {
      case '&&' || '||':
        return KBinary(
          op,
          _coerce(left, KType.boolean, at),
          _coerce(right, KType.boolean, at),
          KType.boolean,
        );
      case '<<' || '>>':
        final type = _concrete(left).type;
        if (type != KType.i32 && type != KType.u32) {
          _fail('"$op" shifts an i32 or a u32, not $a', at);
        }
        return KBinary(
          op,
          _coerce(left, type, at),
          _coerce(right, KType.u32, at),
          type,
        );
    }
    if (a == KType.uvec3 || b == KType.uvec3) {
      _fail('the id is read one component at a time: id.x', at);
    }
    if (a.isVector || b.isVector) {
      if (!const <String>['+', '-', '*', '/'].contains(op)) {
        _fail('"$op" is not defined on vectors', at);
      }
      if (a.isVector && b.isVector) {
        if (a != b) _fail('$a $op $b: the sizes differ', at);
        return KBinary(op, left, right, a);
      }
      final vector = a.isVector ? a : b;
      if (vector.scalar != KType.f32) _fail('$a $op $b has no meaning', at);
      return KBinary(
        op,
        a.isVector ? left : _coerce(left, KType.f32, at),
        b.isVector ? right : _coerce(right, KType.f32, at),
        vector,
      );
    }
    final type = _unify(a, b, at);
    if (type == null) {
      _fail(
        '$a $op $b: the two sides differ; convert one with f32(), i32() or '
        'u32()',
        at,
      );
    }
    if (type.isAbstract) return _fold(op, left, right, type, at);
    final l = _coerce(left, type, at);
    final r = _coerce(right, type, at);
    switch (op) {
      case '==' || '!=':
        return KBinary(op, l, r, KType.boolean);
      case '<' || '<=' || '>' || '>=':
        if (type == KType.boolean) _fail('"$op" does not order booleans', at);
        return KBinary(op, l, r, KType.boolean);
      case '&' || '|' || '^':
        if (type != KType.i32 && type != KType.u32) {
          _fail('"$op" is bitwise, on i32 or u32, not $type', at);
        }
        return KBinary(op, l, r, type);
      default:
        if (type == KType.boolean) _fail('"$op" on booleans', at);
        return KBinary(op, l, r, type);
    }
  }

  /// [op] over two abstract literals, worked out now: a literal comes of
  /// it, as WGSL evaluates a constant expression before it has a type.
  KExpr _fold(String op, KExpr left, KExpr right, KType type, _Token at) {
    if (left is! KIntLiteral && left is! KFloatLiteral ||
        right is! KIntLiteral && right is! KFloatLiteral) {
      _fail('an expression of literals only must have a type', at);
    }
    final float = type == KType.abstractFloat;
    num value(KExpr e) =>
        e is KIntLiteral ? e.value : (e as KFloatLiteral).value;
    final x = value(left);
    final y = value(right);
    if (const <String>['==', '!=', '<', '<=', '>', '>='].contains(op)) {
      final answer = switch (op) {
        '==' => x == y,
        '!=' => x != y,
        '<' => x < y,
        '<=' => x <= y,
        '>' => x > y,
        _ => x >= y,
      };
      return KBoolLiteral(answer);
    }
    if (float) {
      final double r = switch (op) {
        '+' => (x + y).toDouble(),
        '-' => (x - y).toDouble(),
        '*' => (x * y).toDouble(),
        '/' => x / y,
        '%' => x.remainder(y).toDouble(),
        _ => _fail('"$op" on float literals', at),
      };
      return KFloatLiteral(r, '$r', KType.abstractFloat);
    }
    final int i = switch (op) {
      '+' => (x + y).toInt(),
      '-' => (x - y).toInt(),
      '*' => (x * y).toInt(),
      '/' => y == 0 ? _fail('a division by zero', at) : x ~/ y,
      '%' => y == 0 ? _fail('a division by zero', at) : x.remainder(y).toInt(),
      '&' => x.toInt() & y.toInt(),
      '|' => x.toInt() | y.toInt(),
      '^' => x.toInt() ^ y.toInt(),
      _ => _fail('"$op" on integer literals', at),
    };
    return KIntLiteral(i, KType.abstractInt);
  }

  /// [e] with an abstract type made concrete: i32 for an integer literal,
  /// f32 for a float one.
  KExpr _concrete(KExpr e) =>
      e.type.isAbstract ? _coerce(e, e.type.concrete, null) : e;

  /// [e] as a [type]; an abstract literal becomes one, anything else must
  /// already be one.
  KExpr _coerce(KExpr e, KType type, _Token? at) {
    if (e.type == type) return e;
    if (e.type.isAbstract && _accepts(type, e.type)) {
      switch (e) {
        case KIntLiteral(:final value):
          if (type == KType.f32) {
            return KFloatLiteral(
              roundToF32(value.toDouble()),
              '$value',
              KType.f32,
            );
          }
          final fits = type == KType.u32
              ? value >= 0 && value <= 0xFFFFFFFF
              : value >= -0x80000000 && value <= 0x7FFFFFFF;
          if (!fits) _fail('$value does not fit in $type', at);
          return KIntLiteral(value, type);
        case KFloatLiteral(:final value, :final text):
          final rounded = roundToF32(value);
          if (!rounded.isFinite) _fail('$text is not a finite f32', at);
          return KFloatLiteral(rounded, text, KType.f32);
        case KUnary(:final op, :final operand):
          return KUnary(op, _coerce(operand, type, at), type);
        default:
          break;
      }
    }
    _fail('expected $type, found ${e.type.concrete}', at);
  }

  KExpr _unary() {
    final token = _peek;
    if (token.kind == 'punct' &&
        (token.text == '-' || token.text == '!' || token.text == '~')) {
      _at += 1;
      final operand = _unary();
      final type = operand.type;
      switch (token.text) {
        case '-':
          if (operand is KIntLiteral && type == KType.abstractInt) {
            return KIntLiteral(-operand.value, type);
          }
          if (operand is KFloatLiteral && type == KType.abstractFloat) {
            return KFloatLiteral(-operand.value, '-${operand.text}', type);
          }
          if (type == KType.u32 ||
              type == KType.boolean ||
              type == KType.uvec3) {
            _fail('"-" does not negate $type', token);
          }
          return KUnary('-', operand, type);
        case '!':
          return KUnary(
            '!',
            _coerce(operand, KType.boolean, token),
            KType.boolean,
          );
        default:
          final concrete = _concrete(operand);
          if (concrete.type != KType.i32 && concrete.type != KType.u32) {
            _fail('"~" inverts the bits of an i32 or a u32', token);
          }
          return KUnary('~', concrete, concrete.type);
      }
    }
    return _postfix(_primary());
  }

  KExpr _postfix(KExpr e) {
    var current = e;
    while (_is('.')) {
      final dot = _next();
      final token = _peek;
      final name = _name('a component');
      if (!current.type.isVector) {
        _fail('a ${current.type} has no components', dot);
      }
      final components = <int>[];
      for (final c in name.split('')) {
        final index = switch (c) {
          'x' || 'r' => 0,
          'y' || 'g' => 1,
          'z' || 'b' => 2,
          'w' || 'a' => 3,
          _ => _fail('"$c" is not a component', token),
        };
        if (index >= current.type.components) {
          _fail('a ${current.type} has no ".$c"', token);
        }
        components.add(index);
      }
      if (components.length > 4) _fail('a swizzle of more than four', token);
      if (current.type == KType.uvec3 && components.length != 1) {
        _fail('the id is read one component at a time: id.x', token);
      }
      final type = components.length == 1
          ? current.type.scalar!
          : KType.vector(components.length);
      current = KSwizzle(current, components, type);
    }
    return current;
  }

  KExpr _primary() {
    final token = _next();
    switch (token.kind) {
      case 'int':
        final text = token.text;
        final suffix = text.endsWith('u')
            ? KType.u32
            : text.endsWith('i')
            ? KType.i32
            : null;
        final digits = suffix == null
            ? text
            : text.substring(0, text.length - 1);
        final value = int.parse(digits);
        if (suffix == null) return KIntLiteral(value, KType.abstractInt);
        return _coerce(KIntLiteral(value, KType.abstractInt), suffix, token);
      case 'float':
        final text = token.text;
        final suffixed = text.endsWith('f');
        final value = double.parse(
          suffixed ? text.substring(0, text.length - 1) : text,
        );
        final literal = KFloatLiteral(value, text, KType.abstractFloat);
        return suffixed ? _coerce(literal, KType.f32, token) : literal;
      case 'punct' when token.text == '(':
        final inner = _expression();
        _expect(')');
        return inner;
      case 'ident':
        break;
      default:
        _fail('expected a value, found $token', token);
    }
    final name = token.text;
    switch (name) {
      case 'true' || 'false':
        return KBoolLiteral(name == 'true');
      case 'id':
        return const KInvocationId();
    }
    if (_is('(')) return _call(token);
    final binding = _bindings[name];
    if (binding != null) {
      if (binding.kind != KBindingKind.buffer) {
        _fail('a ${binding.kind.name} is read with load()', token);
      }
      _expect('[');
      final index = _index();
      _expect(']');
      return KBufferRead(binding, index);
    }
    final local = _scope.find(name);
    if (local == null) _fail('nothing is called "$name"', token);
    return KLocalRef(local);
  }

  List<KExpr> _arguments() {
    _expect('(');
    final arguments = <KExpr>[];
    if (!_accept(')')) {
      do {
        arguments.add(_expression());
      } while (_accept(','));
      _expect(')');
    }
    return arguments;
  }

  KExpr _call(_Token token) {
    final name = token.text;
    switch (name) {
      case 'len':
        _expect('(');
        final binding = _bindingNamed(KBindingKind.buffer, 'a buffer');
        _expect(')');
        return KBufferLength(binding);
      case 'width' || 'height':
        _expect('(');
        final at = _peek;
        final bindingName = _name('a texture or an image');
        final binding = _bindings[bindingName];
        if (binding == null || binding.kind == KBindingKind.buffer) {
          _fail('"$bindingName" is not a texture or an image', at);
        }
        _expect(')');
        return KTextureSize(binding, height: name == 'height');
      case 'load':
        _expect('(');
        final binding = _bindingNamed(KBindingKind.texture, 'a texture');
        _expect(',');
        final x = _coordinate();
        _expect(',');
        final y = _coordinate();
        _expect(')');
        return KTextureLoad(binding, x, y);
    }
    final arguments = _arguments();
    void count(int n) {
      if (arguments.length != n) {
        _fail('$name takes $n argument${n == 1 ? '' : 's'}', token);
      }
    }

    switch (name) {
      case 'f32' || 'i32' || 'u32':
        count(1);
        final type = switch (name) {
          'f32' => KType.f32,
          'i32' => KType.i32,
          _ => KType.u32,
        };
        final argument = arguments.single;
        if (argument.type.isAbstract) return _coerce(argument, type, token);
        if (!argument.type.isNumericScalar && argument.type != KType.boolean) {
          _fail('$name() converts a scalar, not ${argument.type}', token);
        }
        return KCall(name, <KExpr>[argument], type);
      case 'min' || 'max':
        count(2);
        final type = _same(arguments, token, name);
        return KCall(name, _all(arguments, type, token), type);
      case 'clamp':
        count(3);
        final type = _same(arguments, token, name);
        return KCall(name, _all(arguments, type, token), type);
      case 'abs':
        count(1);
        final argument = _concrete(arguments.single);
        if (argument.type == KType.boolean || argument.type == KType.uvec3) {
          _fail('abs() of ${argument.type}', token);
        }
        return KCall(name, <KExpr>[argument], argument.type);
      case 'floor' || 'ceil' || 'round' || 'trunc' || 'sqrt':
        count(1);
        var argument = arguments.single;
        if (argument.type.isAbstract) {
          argument = _coerce(argument, KType.f32, token);
        }
        if (argument.type != KType.f32 && argument.type.scalar != KType.f32) {
          _fail(
            '$name() takes an f32 or a vector, not ${argument.type}',
            token,
          );
        }
        return KCall(name, <KExpr>[argument], argument.type);
      case 'select':
        count(3);
        final condition = _coerce(arguments[0], KType.boolean, token);
        final type = _same(arguments.sublist(1), token, name);
        return KCall(name, <KExpr>[
          condition,
          ..._all(arguments.sublist(1), type, token),
        ], type);
      case 'vec2' || 'vec3' || 'vec4':
        final size = int.parse(name.substring(3));
        final parts = <KExpr>[
          for (final a in arguments)
            a.type.isAbstract ? _coerce(a, KType.f32, token) : a,
        ];
        for (final part in parts) {
          if (part.type != KType.f32 && part.type.scalar != KType.f32) {
            _fail(
              '$name() is made of f32s and vectors, not ${part.type}',
              token,
            );
          }
        }
        final total = parts.fold<int>(0, (n, p) => n + p.type.components);
        if (!(total == size || (parts.length == 1 && total == 1))) {
          _fail('$name() needs $size components, and was given $total', token);
        }
        return KCall(name, parts, KType.vector(size));
    }
    _fail('nothing is called "$name"', token);
  }

  /// The one type every argument has, abstract literals taking it.
  KType _same(List<KExpr> arguments, _Token at, String name) {
    KType? type;
    for (final argument in arguments) {
      type = type == null ? argument.type : _unify(type, argument.type, at);
      if (type == null) _fail('$name() takes arguments of one type', at);
    }
    final concrete = type!.concrete;
    if (concrete == KType.boolean && name != 'select') {
      _fail('$name() of booleans', at);
    }
    if (concrete == KType.uvec3) _fail('$name() of the id', at);
    return concrete;
  }

  List<KExpr> _all(List<KExpr> arguments, KType type, _Token at) => <KExpr>[
    for (final argument in arguments) _coerce(argument, type, at),
  ];
}
