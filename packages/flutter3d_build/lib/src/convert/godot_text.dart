/// Godot's text resource format — `.tscn` scenes and `.tres` resources, the
/// versions Godot 3 (format 2) and Godot 4 (format 3) write.
library;

import '../build_exceptions.dart';

/// A constructor value: `Vector3(1, 2, 3)`, `ExtResource("1_ab")`.
final class GodotCall {
  const GodotCall(this.name, this.arguments);

  final String name;
  final List<Object?> arguments;

  /// The arguments that are numbers, in order.
  List<double> get numbers => <double>[
    for (final a in arguments)
      if (a is double) a,
  ];

  @override
  String toString() => '$name(${arguments.join(', ')})';
}

/// A `[section attrs]` and the `key = value` lines under it.
final class GodotSection {
  GodotSection(this.kind, this.attributes);

  /// `gd_scene`, `ext_resource`, `sub_resource`, `node`, `resource`.
  final String kind;
  final Map<String, Object?> attributes;
  final Map<String, Object?> properties = <String, Object?>{};

  String? text(String key) => switch (attributes[key]) {
    final String s => s,
    final double d => d == d.roundToDouble() ? '${d.toInt()}' : '$d',
    _ => null,
  };
}

/// Reads a `.tscn` or `.tres`.
///
/// Throws [SourceFormatException] with the line for anything it cannot read.
List<GodotSection> parseGodotText(String source) {
  final tokens = _lex(source);
  var at = 0;
  _Token peek() => tokens[at];
  _Token take() => tokens[at++];
  Never fail(String message) =>
      throw SourceFormatException('line ${peek().line}: $message');

  Object? value() {
    final t = take();
    switch (t.kind) {
      case 'number':
        return switch (t.text) {
          'inf' => double.infinity,
          '-inf' || 'inf_neg' => double.negativeInfinity,
          'nan' => double.nan,
          _ => double.parse(t.text),
        };
      case 'string':
        return t.text;
      case '[':
        final items = <Object?>[];
        while (peek().kind != ']') {
          if (peek().kind == ',') {
            take();
            continue;
          }
          items.add(value());
        }
        take();
        return items;
      case '{':
        final map = <String, Object?>{};
        while (peek().kind != '}') {
          if (peek().kind == ',') {
            take();
            continue;
          }
          final key = value();
          if (take().kind != ':') fail('expected ":" in a dictionary');
          map['$key'] = value();
        }
        take();
        return map;
      case 'word':
        switch (t.text) {
          case 'true':
            return true;
          case 'false':
            return false;
          case 'null':
            return null;
        }
        if (peek().kind == '(') {
          take();
          final arguments = <Object?>[];
          while (peek().kind != ')') {
            if (peek().kind == ',') {
              take();
              continue;
            }
            if (peek().kind == 'end') fail('unclosed ${t.text}(');
            arguments.add(value());
          }
          take();
          return GodotCall(t.text, arguments);
        }
        return t.text;
      default:
        at--;
        fail('expected a value, found "${t.text}"');
    }
  }

  final sections = <GodotSection>[];
  while (peek().kind != 'end') {
    if (peek().kind == '[') {
      take();
      final kind = take();
      if (kind.kind != 'word') fail('expected a section name');
      final attributes = <String, Object?>{};
      while (peek().kind != ']') {
        final key = take();
        if (key.kind != 'word') fail('expected an attribute');
        if (take().kind != '=') fail('expected "=" after ${key.text}');
        attributes[key.text] = value();
      }
      take();
      sections.add(GodotSection(kind.text, attributes));
      continue;
    }
    final key = take();
    if (key.kind != 'word' && key.kind != 'string') {
      at--;
      fail('expected a property');
    }
    if (take().kind != '=') {
      at--;
      fail('expected "=" after ${key.text}');
    }
    final v = value();
    if (sections.isEmpty) fail('a property before any section');
    sections.last.properties[key.text] = v;
  }
  return sections;
}

final class _Token {
  const _Token(this.kind, this.text, this.line);

  final String kind;
  final String text;
  final int line;
}

List<_Token> _lex(String source) {
  final tokens = <_Token>[];
  var line = 1;
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
    } else if (c == ' ' || c == '\t' || c == '\r') {
      i++;
    } else if (c == ';') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (c == '"' ||
        ((c == '&' || c == '^') &&
            i + 1 < source.length &&
            source[i + 1] == '"')) {
      final start = c == '"' ? i + 1 : i + 2;
      var j = start;
      final buffer = StringBuffer();
      while (j < source.length && source[j] != '"') {
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
      tokens.add(_Token('string', buffer.toString(), line));
      i = j + 1;
    } else if ('[](){},=:'.contains(c)) {
      tokens.add(_Token(c, c, line));
      i++;
    } else {
      final number = RegExp(
        r'-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?',
      ).matchAsPrefix(source, i);
      if (number != null) {
        tokens.add(_Token('number', number.group(0)!, line));
        i = number.end;
        continue;
      }
      final word = RegExp(r'[A-Za-z_@][\w/.\-@]*').matchAsPrefix(source, i);
      if (word == null) {
        throw SourceFormatException('line $line: unexpected "$c"');
      }
      final text = word.group(0)!;
      tokens.add(
        _Token(
          const <String>{'inf', 'nan', 'inf_neg'}.contains(text)
              ? 'number'
              : 'word',
          text,
          line,
        ),
      );
      i = word.end;
    }
  }
  tokens.add(_Token('end', '', line));
  return tokens;
}
