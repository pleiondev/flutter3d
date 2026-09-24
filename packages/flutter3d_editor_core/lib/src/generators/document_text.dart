/// The text a generated level document is written as.
///
/// **Byte for byte the layout the shipped documents already have**, which
/// is the whole of the reason this is not `JsonEncoder`. Every level in the
/// repository was written by a generator, and a generator's output is checked
/// by running it again and diffing: a rewritten generator that changed the
/// spacing, the escaping or the way a number is spelled would rewrite every
/// document it owns while claiming to rebuild it, and a diff that is all
/// noise is a diff nobody reads.
///
/// So the rules here are that layout's, spelled out:
///
///  * a number is its shortest round-tripping spelling, with `.0` on a whole
///    double and an exponent only below `1e-4` or from `1e16` up, written
///    `1e-05` and `1e+16`; an `int` is written as one;
///  * a string escapes everything outside printable ASCII as `\uXXXX`;
///  * [inline] separates with `, ` and `: `; [indented] puts one value per
///    line; [compact] is the level layout, one line per brush.
abstract final class DocumentText {
  /// [value] on one line: `{"a": 1, "b": [2.0, 3.0]}`.
  static String inline(Object? value) {
    final out = StringBuffer();
    _inline(value, out);
    return out.toString();
  }

  /// [value] one member per line, [indent] spaces a level: the layout a track
  /// document and a template's files are written in.
  static String indented(Object? value, int indent) {
    final out = StringBuffer();
    _indented(value, indent, 0, out);
    return out.toString();
  }

  /// Compact where compact reads better: one line per brush, per entity.
  ///
  /// A level document is read far more often in a diff than in an editor, and
  /// the two want opposite things — a pretty-printer puts a brush on nine
  /// lines, so moving one reads as nine changes. A map goes on one line when
  /// it fits in 110 characters **and** none of its values is itself a
  /// structure longer than 60 — without the second condition a brush with a
  /// long route in it collapses onto one unreadable line that happens to be
  /// under the limit. A list of numbers and strings is always one line.
  static String compact(Object? value, [int depth = 0]) {
    final pad = '  ' * depth;
    switch (value) {
      case final Map<Object?, Object?> map:
        final one = inline(map);
        final fits =
            one.length <= 110 &&
            !map.values.any(
              (Object? v) => (v is Map || v is List) && inline(v).length > 60,
            );
        if (fits) return '$pad$one';
        final rows = <String>[
          for (final MapEntry(:key, :value) in map.entries)
            '$pad  ${inline(key)}: ${_member(value, depth)}',
        ];
        return '$pad{\n${rows.join(',\n')}\n$pad}';
      case final List<Object?> list:
        if (list.every((Object? v) => v is num || v is String || v is bool)) {
          return '$pad${inline(list)}';
        }
        return '$pad[\n${list.map((Object? v) => compact(v, depth + 1)).join(',\n')}\n$pad]';
      default:
        return '$pad${inline(value)}';
    }
  }

  /// A map member's value in [compact]: a structure laid out one level
  /// deeper, starting on the key's line; anything else on one line.
  static String _member(Object? value, int depth) =>
      value is Map || value is List
      ? compact(value, depth + 1).trimLeft()
      : inline(value);

  /// A number as the documents spell it. See the class comment.
  static String number(num value) {
    if (value is int) return '$value';
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) {
      throw ArgumentError.value(value, 'value', 'has no JSON spelling');
    }
    if (d == 0.0) return d.isNegative ? '-0.0' : '0.0';
    final (negative, digits, point) = _shortest(d);
    final sign = negative ? '-' : '';
    if (point <= -4 || point > 16) {
      final mantissa = digits.length == 1
          ? digits
          : '${digits[0]}.${digits.substring(1)}';
      final exponent = point - 1;
      final magnitude = exponent.abs().toString().padLeft(2, '0');
      return '$sign${mantissa}e${exponent < 0 ? '-' : '+'}$magnitude';
    }
    if (point <= 0) return '${sign}0.${'0' * -point}$digits';
    if (point >= digits.length) {
      return '$sign$digits${'0' * (point - digits.length)}.0';
    }
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }

  /// A string with every character outside printable ASCII escaped.
  static String string(String value) {
    final out = StringBuffer('"');
    for (final unit in value.codeUnits) {
      switch (unit) {
        case 0x22:
          out.write(r'\"');
        case 0x5C:
          out.write(r'\\');
        case 0x0A:
          out.write(r'\n');
        case 0x0D:
          out.write(r'\r');
        case 0x09:
          out.write(r'\t');
        case 0x08:
          out.write(r'\b');
        case 0x0C:
          out.write(r'\f');
        case >= 0x20 && <= 0x7E:
          out.writeCharCode(unit);
        default:
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      }
    }
    out.write('"');
    return out.toString();
  }

  /// The shortest digits that read back as [value], and where the decimal
  /// point goes among them: `123.45` is `('12345', 3)`, `0.001` is `('1', -2)`.
  ///
  /// Taken from Dart's own shortest spelling, which is the same digits in a
  /// different layout.
  static (bool, String, int) _shortest(double value) {
    final text = value.abs().toString();
    final e = text.indexOf('e');
    final (mantissa, exponent) = e < 0
        ? (text, 0)
        : (text.substring(0, e), int.parse(text.substring(e + 1)));
    final dot = mantissa.indexOf('.');
    final whole = dot < 0 ? mantissa : mantissa.substring(0, dot);
    final fraction = dot < 0 ? '' : mantissa.substring(dot + 1);
    final all = '$whole$fraction';
    final leading = all.length - all.replaceFirst(RegExp('^0+'), '').length;
    final digits = all.substring(leading).replaceFirst(RegExp(r'0+$'), '');
    return (
      value.isNegative,
      digits.isEmpty ? '0' : digits,
      whole.length - leading + exponent,
    );
  }

  static void _inline(Object? value, StringBuffer out) {
    switch (value) {
      case null:
        out.write('null');
      case final bool flag:
        out.write(flag ? 'true' : 'false');
      case final num n:
        out.write(number(n));
      case final String s:
        out.write(string(s));
      case final List<Object?> list:
        out.write('[');
        for (final (i, v) in list.indexed) {
          if (i > 0) out.write(', ');
          _inline(v, out);
        }
        out.write(']');
      case final Map<Object?, Object?> map:
        out.write('{');
        for (final (i, MapEntry(:key, :value)) in map.entries.indexed) {
          if (i > 0) out.write(', ');
          out
            ..write(string(key! as String))
            ..write(': ');
          _inline(value, out);
        }
        out.write('}');
      default:
        throw ArgumentError.value(value, 'value', 'is not a JSON value');
    }
  }

  static void _indented(
    Object? value,
    int indent,
    int depth,
    StringBuffer out,
  ) {
    final inner = ' ' * (indent * (depth + 1));
    final outer = ' ' * (indent * depth);
    switch (value) {
      case final List<Object?> list when list.isNotEmpty:
        out.write('[\n');
        for (final (i, v) in list.indexed) {
          if (i > 0) out.write(',\n');
          out.write(inner);
          _indented(v, indent, depth + 1, out);
        }
        out.write('\n$outer]');
      case final Map<Object?, Object?> map when map.isNotEmpty:
        out.write('{\n');
        for (final (i, MapEntry(:key, :value)) in map.entries.indexed) {
          if (i > 0) out.write(',\n');
          out.write('$inner${string(key! as String)}: ');
          _indented(value, indent, depth + 1, out);
        }
        out.write('\n$outer}');
      default:
        _inline(value, out);
    }
  }
}
