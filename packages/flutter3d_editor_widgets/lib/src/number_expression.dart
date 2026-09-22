/// What a person may type into a number field — `ux-15`.
///
/// **A field that takes only a number is a field people do arithmetic beside.**
/// A third of a metre is `1/3`, a quarter turn is `90`, and a part measured in
/// millimetres is `24mm` — and the alternative to reading those here is a
/// calculator open next to the editor and a number typed in twice. So this is
/// a four-operator expression reader with brackets, `pi`, and the units the
/// two kinds of field in this application are measured in.
///
/// **It answers null rather than throwing, and null means "not a number".**
/// The field puts back what the document says when it gets one, which is the
/// same thing it already did for `1,5,` — an unreadable entry is a slip, not
/// an error worth a dialog.
///
/// **No variables, no functions, no precedence beyond the four operators.**
/// Every one of those is a thing somebody would then reasonably expect to
/// work everywhere, and the useful half — arithmetic and a unit — is the half
/// that fits in a hundred lines with no parser generator behind it.
library;

import 'dart:math' as math;

/// What a field's own numbers mean, so a typed unit can be converted into it.
enum NumberUnit {
  /// A count, a factor, a weight: a suffix means nothing and is refused.
  plain,

  /// Scene units, which this project's own documents are in.
  metres,

  /// What a rotation field shows. Radians are what the arithmetic uses and
  /// `TransformFields` converts at its own edge; a person types degrees.
  degrees,
}

/// [said] as a number in [unit]'s own terms, or null when it is not one.
///
/// Whitespace is ignored throughout, a comma is a decimal point (the same rule
/// `NumberField.parse` has always had, for a keyboard that types one), and the
/// result must be finite — `1/0` is not a position.
double? evaluateNumber(String said, {NumberUnit unit = NumberUnit.plain}) {
  final _Reader reader = _Reader(said.replaceAll(',', '.'), unit);
  final double? value = reader.expression();
  if (value == null || !reader.atEnd) return null;
  return value.isFinite ? value : null;
}

/// How much of [unit] one of the suffix is worth, or null when the suffix is
/// not one this kind of field knows.
double? _factorFor(String suffix, NumberUnit unit) => switch (unit) {
  NumberUnit.plain => null,
  NumberUnit.metres => switch (suffix) {
    'mm' => 0.001,
    'cm' => 0.01,
    'dm' => 0.1,
    'm' => 1.0,
    'km' => 1000.0,
    'in' || '"' => 0.0254,
    'ft' || "'" => 0.3048,
    _ => null,
  },
  NumberUnit.degrees => switch (suffix) {
    'deg' || '°' => 1.0,
    'rad' => 180.0 / math.pi,
    'turn' || 'turns' => 360.0,
    _ => null,
  },
};

/// A recursive-descent reader over one line of arithmetic.
///
/// Its own small class rather than a closure over indices, because "how far
/// have we read" is the one piece of state and every method needs it.
final class _Reader {
  _Reader(this.said, this.unit);

  final String said;
  final NumberUnit unit;
  int _at = 0;

  bool get atEnd {
    _skipSpace();
    return _at >= said.length;
  }

  void _skipSpace() {
    while (_at < said.length && said[_at] == ' ') {
      _at++;
    }
  }

  bool _take(String character) {
    _skipSpace();
    if (_at >= said.length || said[_at] != character) return false;
    _at++;
    return true;
  }

  /// `term (('+' | '-') term)*`
  double? expression() {
    double? left = term();
    if (left == null) return null;
    while (true) {
      if (_take('+')) {
        final double? right = term();
        if (right == null) return null;
        left = left! + right;
      } else if (_take('-')) {
        final double? right = term();
        if (right == null) return null;
        left = left! - right;
      } else {
        return left;
      }
    }
  }

  /// `factor (('*' | '/') factor)*`
  double? term() {
    double? left = factor();
    if (left == null) return null;
    while (true) {
      if (_take('*')) {
        final double? right = factor();
        if (right == null) return null;
        left = left! * right;
      } else if (_take('/')) {
        final double? right = factor();
        if (right == null) return null;
        left = left! / right;
      } else {
        return left;
      }
    }
  }

  /// `'-'? primary`, and a leading `+` for symmetry with it.
  double? factor() {
    _skipSpace();
    if (_take('-')) {
      final double? value = factor();
      return value == null ? null : -value;
    }
    if (_take('+')) return factor();
    return primary();
  }

  /// A bracketed expression, `pi`, or a number with an optional unit.
  double? primary() {
    _skipSpace();
    if (_take('(')) {
      final double? inside = expression();
      if (inside == null || !_take(')')) return null;
      return inside;
    }
    if (_word('pi')) return _unitAfter(math.pi);
    final int from = _at;
    while (_at < said.length && _isNumberCharacter(said[_at])) {
      _at++;
    }
    if (_at == from) return null;
    final double? value = double.tryParse(said.substring(from, _at));
    if (value == null) return null;
    return _unitAfter(value);
  }

  /// [value] scaled by whatever unit follows it, or [value] when none does.
  ///
  /// A suffix this kind of field does not know is a refusal rather than an
  /// ignored trailing word: `10kg` in a length field is somebody meaning
  /// something this cannot do, and reading it as 10 metres would be worse
  /// than saying no.
  double? _unitAfter(double value) {
    _skipSpace();
    final int from = _at;
    while (_at < said.length && _isUnitCharacter(said[_at])) {
      _at++;
    }
    if (_at == from) return value;
    final double? factor = _factorFor(
      said.substring(from, _at).toLowerCase(),
      unit,
    );
    if (factor == null) return null;
    return value * factor;
  }

  bool _word(String want) {
    _skipSpace();
    if (!said.startsWith(want, _at)) return false;
    final int after = _at + want.length;
    // Not the front of a longer word: `pipe` is not pi followed by `pe`.
    if (after < said.length && _isUnitCharacter(said[after])) return false;
    _at = after;
    return true;
  }

  static bool _isNumberCharacter(String it) =>
      (it.codeUnitAt(0) >= 0x30 && it.codeUnitAt(0) <= 0x39) || it == '.';

  static bool _isUnitCharacter(String it) =>
      (it.codeUnitAt(0) >= 0x61 && it.codeUnitAt(0) <= 0x7A) ||
      (it.codeUnitAt(0) >= 0x41 && it.codeUnitAt(0) <= 0x5A) ||
      it == '°' ||
      it == '"' ||
      it == "'";
}
