/// Editing a `.fmat` document through the gate its own reader does not have.
///
/// **Two writers, and only one of them refuses.** A level material is written
/// back through `Level.fromJson`, which is strict about types and throws — the
/// application's own `setLevelMaterialField` does that gate itself, since it
/// needs `Level`, and this package stays without a genre or a document format
/// of its own to name. A `.fmat` is the other case, and the reason
/// [materialWith] exists here: `readFmat` almost never refuses anything, it
/// *warns* — an unknown alpha mode becomes opaque with a note, a shader it does
/// not ship becomes the scene's — so code that wrote straight into a material
/// document would be the one place that can produce a file which does not say
/// what it appears to say. Every editor built on this package gets the reader
/// standing behind the writer for free.
///
/// **Moved out of the model editor's material panel, not written for it.**
/// `flutter3d_editor`'s `MaterialPanel` was the only caller for as long as it
/// was the only program editing a `.fmat` field by field; a second editor
/// wanting the identical gate would otherwise have had to depend on an
/// application, which `tool/structure.dart` forbids and pub cannot express.
/// This package could not take it until [MaterialDocument] and [MaterialHint]
/// themselves left `flutter3d` for `flutter3d_formats` — a plain Dart package
/// this one can depend on without a Flutter SDK arriving behind it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';

/// [document] with one field changed, or null when the change would produce a
/// `.fmat` this engine's own reader does not take as written.
///
/// **The gate the material format does not have.** `readFmat` is deliberately
/// forgiving — an unknown key, an alpha mode it has never heard of, a shader it
/// does not ship are all warnings, because a file written by a newer tool
/// should still load minus what this build does not understand. That is right
/// for *reading* somebody else's file and wrong for *writing* one's own, so
/// three questions are asked of every edit before it is allowed to stand:
///
/// * does the value fit the shape the hint describes — a range takes a number,
///   a colour takes three or four of them, a path takes a string? With no hint,
///   does it at least match the shape the field already had? This is the check
///   the level reader does with its types and the material reader does not do
///   at all: `_number` answers the default for a string and says nothing.
/// * does reading the result back throw, or warn about something the document
///   was not already warning about?
/// * does the value come back as it went in? The writer omits a value that is
///   already the reader's default, and a key it omits is a key the file is
///   right without — but a key it writes *differently* is the reader having
///   understood something else.
///
/// What is deliberately not asked is whether the value is inside a range hint's
/// ends. The engine's own note says a hint describes a control and never
/// constrains the reader: a roughness of 1.5 is what the shader receives, and
/// an editor that refused to write it would be an editor that cannot open a
/// file it can draw. A caller says the value is outside; it does not veto it.
MaterialDocument? materialWith(
  MaterialDocument document,
  String key,
  Object? value, {
  MaterialHint? hint,
}) {
  final row = jsonDecode(writeFmat(document)) as Map<String, Object?>;
  if (!_fits(hint, value, _at(row, key))) return null;

  _put(row, key, value);
  final MaterialDocument next;
  try {
    next = readFmat(Uint8List.fromList(utf8.encode(jsonEncode(row))));
  } catch (_) {
    return null;
  }

  final had = document.warnings.toSet();
  if (next.warnings.any((String it) => !had.contains(it))) return null;

  final back = _at(jsonDecode(writeFmat(next)) as Map<String, Object?>, key);
  if (back != null && !_sameJson(back, value)) return null;
  return next;
}

/// Whether [value] is the shape [hint] describes, or — with no hint — the shape
/// [was] already had.
///
/// Clearing a field is always allowed: an absent key is what every optional
/// field in both formats means by "not set".
bool _fits(MaterialHint? hint, Object? value, Object? was) {
  if (value == null) return true;
  return switch (hint?.kind) {
    RangeHint() => value is num,
    ColorHint(:final channels) =>
      value is List<Object?> &&
          value.length >= 3 &&
          value.length <= channels &&
          value.every((Object? it) => it is num),
    TextureHint() => value is String,
    // An enum's list is what a picker offers, not what a file may contain: a
    // material naming a mode this build does not ship is a file this build
    // still has to be able to save. Anything the reader will take as a word.
    _ => was == null || _sameShape(value, was),
  };
}

bool _sameShape(Object? value, Object? was) => switch ((value, was)) {
  (num(), num()) => true,
  (bool(), bool()) => true,
  (String(), String()) => true,
  (final List<Object?> a, final List<Object?> b) => a.length == b.length,
  _ => false,
};

/// Whether two decoded JSON values say the same thing, numerically.
///
/// The `1` a caller writes and the `1.0` the writer prints are the same
/// number, and a gate that called them different would refuse every whole
/// value somebody typed.
bool _sameJson(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  if (a is List<Object?> && b is List<Object?>) {
    return a.length == b.length &&
        <int>[
          for (var i = 0; i < a.length; i++) i,
        ].every((int i) => _sameJson(a[i], b[i]));
  }
  return a == b;
}

/// The value at [key], where a key may name one slot inside `textures`.
///
/// One level of nesting and no more: `textures/albedo` is the only shape a
/// `.fmat` puts a value a caller edits inside another object, and a general
/// path syntax would be a thing to specify for the sake of one case.
Object? _at(Map<String, Object?> row, String key) {
  final slash = key.indexOf('/');
  if (slash < 0) return row[key];
  final nested = row[key.substring(0, slash)];
  return nested is Map<String, Object?>
      ? nested[key.substring(slash + 1)]
      : null;
}

void _put(Map<String, Object?> row, String key, Object? value) {
  final slash = key.indexOf('/');
  if (slash < 0) {
    if (value == null) {
      row.remove(key);
    } else {
      row[key] = value;
    }
    return;
  }
  final outer = key.substring(0, slash);
  final inner = key.substring(slash + 1);
  final nested = <String, Object?>{...?row[outer] as Map<String, Object?>?};
  if (value == null) {
    nested.remove(inner);
  } else {
    nested[inner] = value;
  }
  if (nested.isEmpty) {
    row.remove(outer);
  } else {
    row[outer] = nested;
  }
}

/// The fields of a `.fmat`, the way a panel built from it should show them.
///
/// **The document's own writing, not a list of fields written here.** Every key
/// comes from `writeFmat`, which is what makes this survive the format growing
/// one: a key added to the writer appears the day it is added, and a key
/// nothing hints is shown by its type. `hints` and `parameters` are lifted out
/// because they are a panel's other two sections rather than fields, and `fmat`
/// because the version is the reader's business.
///
/// A texture slot arrives as `textures/albedo`, which is the key [materialWith]
/// takes and the one a row is keyed by.
Map<String, Object?> materialDocumentFields(MaterialDocument document) {
  final row = jsonDecode(writeFmat(document)) as Map<String, Object?>;
  final textures = row['textures'];
  return <String, Object?>{
    for (final entry in row.entries)
      if (!const <String>{
        'fmat',
        'hints',
        'parameters',
        'textures',
      }.contains(entry.key))
        entry.key: entry.value,
    if (textures is Map<String, Object?>)
      for (final slot in textures.entries) 'textures/${slot.key}': slot.value,
  };
}

/// The hint for one field of a `.fmat`.
///
/// The engine's table for the fields every material has, the file's own for
/// everything else — which is [MaterialDocument.hints]' whole purpose and the
/// only thing that can describe a parameter this engine has never heard of. A
/// texture slot is a path whatever it is called, so an unhinted one is offered
/// as a file rather than as a string somebody types blind.
MaterialHint? materialDocumentHint(MaterialDocument document, String key) =>
    document.hints[key] ??
    builtInMaterialHints[key] ??
    (key.startsWith('textures/') ? const MaterialHint(TextureHint()) : null);
