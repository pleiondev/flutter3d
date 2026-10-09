/// A reader for USD's text layer, `.usda`: prims, their properties and
/// metadata, as a tree of plain values.
///
/// **What composition this does: none.** A layer is read as it is written.
/// `references` and `payload` are kept as metadata for the stage reader,
/// which turns a reference to another file into a nested prefab; a
/// `variantSet` is read past, `over` and `class` prims are kept and marked
/// so the stage reader can leave them out. Crate (`.usdc`), the binary
/// layer, is not read here at all — the refusal names `usdcat`, which turns
/// one into the other.
library;

import '../build_exceptions.dart';

/// A path, `</World/Chair>` or `</World/Looks/Red.outputs:surface>`.
final class UsdPath {
  const UsdPath(this.text);

  final String text;

  @override
  String toString() => '<$text>';
}

/// An asset path, `@./chair.usda@`.
final class UsdAsset {
  const UsdAsset(this.path, {this.target});

  final String path;

  /// The prim a reference names after the asset, `@chair.usda@</Chair>`.
  final UsdPath? target;

  @override
  String toString() => '@$path@${target ?? ''}';
}

/// A named identifier value: `true`, `None`, a token written bare.
final class UsdWord {
  const UsdWord(this.word);

  final String word;

  @override
  String toString() => word;
}

/// One property of a prim: an attribute or a relationship.
final class UsdProperty {
  UsdProperty({
    required this.name,
    required this.typeName,
    this.value,
    this.isRelationship = false,
    this.uniform = false,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  /// With its namespace: `xformOp:translate`, `inputs:diffuseColor.connect`,
  /// `primvars:st:indices`.
  final String name;

  /// `float3`, `point3f[]`, `token`; `rel` for a relationship.
  final String typeName;

  /// The authored value, or the first time sample's: a `double`, a
  /// `String`, a `List`, a [UsdPath], a [UsdAsset], a [UsdWord] or null.
  final Object? value;

  final bool isRelationship;
  final bool uniform;

  /// What the parentheses after it said: `interpolation`, `elementSize`.
  final Map<String, Object?> metadata;
}

/// One prim: `def Xform "World" (…) { … }`.
final class UsdPrim {
  UsdPrim({
    required this.specifier,
    required this.typeName,
    required this.name,
    required this.parent,
  });

  /// `def`, `over` or `class`.
  final String specifier;

  /// `Xform`, `Mesh`, `Material`, `Shader`, or empty for a typeless prim.
  final String typeName;
  final String name;
  final UsdPrim? parent;

  final Map<String, Object?> metadata = <String, Object?>{};
  final Map<String, UsdProperty> properties = <String, UsdProperty>{};
  final List<UsdPrim> children = <UsdPrim>[];

  /// The absolute path, `/World/Chair`.
  String get path {
    final above = parent;
    return above == null ? '/$name' : '${above.path}/$name';
  }

  /// The value of property [name], or null.
  Object? operator [](String name) => properties[name]?.value;

  /// The prim at the absolute or relative [path] below this one's root.
  UsdPrim? find(String path) {
    var root = this;
    while (root.parent != null) {
      root = root.parent!;
    }
    final parts = path.split('/').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    // [root] is one of the layer's top-level prims; the path starts at it.
    if (parts.first != root.name) return null;
    var at = root;
    for (final part in parts.skip(1)) {
      final next = at.children.where((UsdPrim c) => c.name == part).firstOrNull;
      if (next == null) return null;
      at = next;
    }
    return at;
  }
}

/// A parsed `.usda` layer.
final class UsdLayer {
  UsdLayer();

  final Map<String, Object?> metadata = <String, Object?>{};
  final List<UsdPrim> prims = <UsdPrim>[];

  /// The prim at the absolute [path], or null.
  UsdPrim? find(String path) {
    final parts = path.split('/').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final top = prims.where((UsdPrim p) => p.name == parts.first).firstOrNull;
    return parts.length == 1 ? top : top?.find(path);
  }

  /// `upAxis`, `Y` when the layer does not say.
  String get upAxis => switch (metadata['upAxis']) {
    final String axis => axis,
    final UsdWord word => word.word,
    _ => 'Y',
  };

  /// `metersPerUnit`, 0.01 when the layer does not say — USD's own
  /// default, centimetres. In metres per one of the layer's units.
  double get metersPerUnit => switch (metadata['metersPerUnit']) {
    final double m when m > 0.0 => m,
    _ => 0.01,
  };

  /// Whether the layer named `metersPerUnit` itself.
  bool get saysMetersPerUnit => metadata['metersPerUnit'] is double;
}

/// Whether [bytes] begin as a text USD layer.
bool isUsdaText(List<int> bytes) =>
    bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '#usda';

/// Whether [bytes] begin as a binary USD layer.
bool isUsdCrate(List<int> bytes) =>
    bytes.length >= 8 && String.fromCharCodes(bytes.take(8)) == 'PXR-USDC';

/// Reads [source] as a `.usda` layer.
///
/// Throws [SourceFormatException] with the line for anything it cannot read.
UsdLayer parseUsda(String source) => _UsdaParser(_lexUsda(source)).layer();

final class _Token {
  const _Token(this.kind, this.text, this.line);

  /// `word`, `number`, `string`, `asset`, `path`, `end`, or the punctuation.
  final String kind;
  final String text;
  final int line;
}

List<_Token> _lexUsda(String source) {
  final tokens = <_Token>[];
  var line = 1;
  var i = 0;
  // The `#usda 1.0` header is a comment to everything after it.
  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
    } else if (c == ' ' || c == '\t' || c == '\r') {
      i++;
    } else if (c == '#') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (c == '"' || c == "'") {
      final triple =
          i + 2 < source.length && source[i + 1] == c && source[i + 2] == c;
      final quote = triple ? '$c$c$c' : c;
      final start = i + quote.length;
      var j = start;
      final buffer = StringBuffer();
      while (j < source.length && !source.startsWith(quote, j)) {
        if (source[j] == '\\' && j + 1 < source.length) {
          j++;
          buffer.write(switch (source[j]) {
            'n' => '\n',
            't' => '\t',
            _ => source[j],
          });
        } else {
          if (source[j] == '\n') line++;
          buffer.write(source[j]);
        }
        j++;
      }
      if (j >= source.length) {
        throw SourceFormatException('line $line: unclosed string');
      }
      tokens.add(_Token('string', buffer.toString(), line));
      i = j + quote.length;
    } else if (c == '@') {
      final triple = source.startsWith('@@@', i);
      final quote = triple ? '@@@' : '@';
      final end = source.indexOf(quote, i + quote.length);
      if (end < 0) {
        throw SourceFormatException('line $line: unclosed asset path');
      }
      tokens.add(
        _Token('asset', source.substring(i + quote.length, end), line),
      );
      i = end + quote.length;
    } else if (c == '<') {
      final end = source.indexOf('>', i);
      if (end < 0) throw SourceFormatException('line $line: unclosed path');
      tokens.add(_Token('path', source.substring(i + 1, end), line));
      i = end + 1;
    } else if ('()[]{}=,;:'.contains(c)) {
      tokens.add(_Token(c, c, line));
      i++;
    } else if (_isNumberStart(source, i)) {
      final match = RegExp(
        r'[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?|[-+]?inf|nan',
      ).matchAsPrefix(source, i);
      if (match == null) throw SourceFormatException('line $line: bad number');
      tokens.add(_Token('number', match.group(0)!, line));
      i = match.end;
    } else if (_isWordChar(c)) {
      var j = i;
      while (j < source.length &&
          (_isWordChar(source[j]) ||
              source[j] == '.' ||
              (source[j] == ':' &&
                  j + 1 < source.length &&
                  _isWordChar(source[j + 1])))) {
        j++;
      }
      tokens.add(_Token('word', source.substring(i, j), line));
      i = j;
    } else {
      throw SourceFormatException('line $line: unexpected "$c"');
    }
  }
  tokens.add(_Token('end', '', line));
  return tokens;
}

bool _isWordChar(String c) =>
    (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
    (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
    (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
    c == '_';

bool _isNumberStart(String s, int i) {
  final c = s[i];
  if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) return true;
  if ((c == '-' || c == '+' || c == '.') && i + 1 < s.length) {
    final d = s[i + 1];
    return (d.compareTo('0') >= 0 && d.compareTo('9') <= 0) ||
        d == '.' ||
        s.startsWith('inf', i + 1);
  }
  return false;
}

const Set<String> _listOps = <String>{
  'prepend',
  'append',
  'add',
  'delete',
  'reorder',
};

final class _UsdaParser {
  _UsdaParser(this.tokens);

  final List<_Token> tokens;
  int at = 0;

  _Token get peek => tokens[at];
  _Token take() => tokens[at++];

  Never fail(String message) => throw SourceFormatException(
    'line ${peek.line}: $message (at "${peek.text}")',
  );

  void expect(String kind) {
    if (peek.kind != kind) fail('expected "$kind"');
    at++;
  }

  bool takeIf(String kind) {
    if (peek.kind != kind) return false;
    at++;
    return true;
  }

  UsdLayer layer() {
    final layer = UsdLayer();
    if (peek.kind == '(') layer.metadata.addAll(metadata());
    while (peek.kind != 'end') {
      final prim = this.prim(null);
      if (prim != null) layer.prims.add(prim);
    }
    return layer;
  }

  /// `( key = value … )`, with list operations and bare doc strings.
  Map<String, Object?> metadata() {
    expect('(');
    final out = <String, Object?>{};
    while (!takeIf(')')) {
      if (peek.kind == 'string') {
        out['doc'] = take().text;
        continue;
      }
      if (takeIf(';') || takeIf(',')) continue;
      if (peek.kind != 'word') fail('expected a metadata key');
      var key = take().text;
      if (_listOps.contains(key) && peek.kind == 'word') {
        key = take().text;
      }
      if (takeIf('=')) {
        out[key] = value();
      } else {
        out[key] = true;
      }
    }
    return out;
  }

  UsdPrim? prim(UsdPrim? parent) {
    if (peek.kind != 'word') fail('expected def, over or class');
    final specifier = take().text;
    if (specifier != 'def' && specifier != 'over' && specifier != 'class') {
      fail('expected def, over or class');
    }
    final typeName = peek.kind == 'word' ? take().text : '';
    if (peek.kind != 'string') fail('expected the prim\'s name');
    final prim = UsdPrim(
      specifier: specifier,
      typeName: typeName,
      name: take().text,
      parent: parent,
    );
    if (peek.kind == '(') prim.metadata.addAll(metadata());
    expect('{');
    while (!takeIf('}')) {
      if (takeIf(';')) continue;
      final word = peek.text;
      if (peek.kind == 'word' &&
          (word == 'def' || word == 'over' || word == 'class') &&
          _isPrimAhead()) {
        final child = this.prim(prim);
        if (child != null) prim.children.add(child);
      } else if (peek.kind == 'word' && word == 'variantSet') {
        skipVariantSet();
      } else if (peek.kind == 'word' && word == 'variants') {
        // A variant selection in the body: `variants = {...}` is metadata
        // in practice; read and dropped.
        take();
        expect('=');
        value();
      } else {
        property(prim);
      }
    }
    return prim;
  }

  /// Whether the `def`/`over`/`class` at the cursor opens a prim rather
  /// than naming an attribute's type (nothing is typed `def`, but the check
  /// keeps the reading honest).
  bool _isPrimAhead() {
    final next = tokens[at + 1];
    return next.kind == 'string' ||
        (next.kind == 'word' && tokens[at + 2].kind == 'string');
  }

  void skipVariantSet() {
    take(); // variantSet
    if (peek.kind == 'string') take();
    expect('=');
    skipBraces();
  }

  void skipBraces() {
    expect('{');
    var depth = 1;
    while (depth > 0) {
      final t = take();
      if (t.kind == 'end') fail('unclosed braces');
      if (t.kind == '{') depth++;
      if (t.kind == '}') depth--;
    }
  }

  void property(UsdPrim prim) {
    var uniform = false;
    var relationship = false;
    while (peek.kind == 'word' &&
        const <String>{
          'custom',
          'uniform',
          'varying',
          'config',
          ..._listOps,
        }.contains(peek.text)) {
      if (take().text == 'uniform') uniform = true;
    }
    if (peek.kind != 'word') fail('expected a property');
    var typeName = take().text;
    if (typeName == 'rel') {
      relationship = true;
    } else if (peek.kind == '[') {
      take();
      expect(']');
      typeName = '$typeName[]';
    }
    if (peek.kind != 'word') fail('expected the property\'s name');
    var name = take().text;
    Object? value;
    var timeSampled = false;
    if (name.endsWith('.timeSamples')) {
      name = name.substring(0, name.length - '.timeSamples'.length);
      timeSampled = true;
    }
    if (takeIf('=')) {
      value = timeSampled ? firstSample() : this.value();
    }
    final metadata = peek.kind == '(' ? this.metadata() : <String, Object?>{};
    final existing = prim.properties[name];
    prim.properties[name] = UsdProperty(
      name: name,
      typeName: relationship ? 'rel' : typeName,
      value: value ?? existing?.value,
      isRelationship: relationship,
      uniform: uniform,
      metadata: <String, Object?>{...?existing?.metadata, ...metadata},
    );
  }

  /// `{ 0: v, 24: w }`: the first sample's value — a converter writes a
  /// rest pose, not the animation.
  Object? firstSample() {
    expect('{');
    Object? first;
    var any = false;
    while (!takeIf('}')) {
      if (takeIf(',')) continue;
      value(); // the time
      expect(':');
      final v = value();
      if (!any) {
        first = v;
        any = true;
      }
    }
    return first;
  }

  Object? value() {
    final t = peek;
    switch (t.kind) {
      case 'number':
        take();
        return switch (t.text) {
          'inf' || '+inf' => double.infinity,
          '-inf' => double.negativeInfinity,
          'nan' => double.nan,
          _ => double.parse(t.text),
        };
      case 'string':
        take();
        return t.text;
      case 'asset':
        take();
        final target = peek.kind == 'path' ? UsdPath(take().text) : null;
        return UsdAsset(t.text, target: target);
      case 'path':
        take();
        return UsdPath(t.text);
      case '(':
        take();
        final items = <Object?>[];
        while (!takeIf(')')) {
          if (takeIf(',')) continue;
          items.add(value());
        }
        return items;
      case '[':
        take();
        final items = <Object?>[];
        while (!takeIf(']')) {
          if (takeIf(',')) continue;
          items.add(value());
        }
        return items;
      case '{':
        // A dictionary: `{ string a = "b" }`. Kept as a map of its keys.
        take();
        final map = <String, Object?>{};
        while (!takeIf('}')) {
          if (takeIf(';') || takeIf(',')) continue;
          if (peek.kind == 'word' && tokens[at + 1].kind == 'word') take();
          final key = take().text;
          if (takeIf('=')) map[key] = value();
        }
        return map;
      case 'word':
        take();
        return switch (t.text) {
          'true' => true,
          'false' => false,
          'None' => null,
          _ => UsdWord(t.text),
        };
      default:
        fail('expected a value');
    }
  }
}
