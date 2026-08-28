import 'dart:typed_data';

/// One key a document may carry, with the value this object would write.
///
/// See [writeThrough] for what is done with it.
final class WriteThroughField {
  const WriteThroughField(this.key, this.value, {this.whenAbsent = true});

  final String key;
  final Object? value;

  /// Whether to add this key to a document that did not carry it.
  ///
  /// False for a value equal to its default: a document that has nothing to say
  /// must go on saying nothing, which is what keeps a level a readable diff.
  final bool whenAbsent;
}

/// Writes [fields] into a map, through the document this object came from.
///
/// **The rule that makes a level survive being read and written back**, and it
/// is three lines long:
///
/// * a key the document had, whose value has not changed, is given back
///   **exactly as it arrived** — same position, same `4` rather than `4.0`,
///   even when it happens to equal the default;
/// * a key the document had, whose value has changed, is written canonically
///   **in the place the document put it**;
/// * a key the document did not have is added only when it has something to
///   say, and everything this format does not know is copied through untouched.
///
/// The last of those is why `generatedBy` and the racing document's `track`
/// come back: they are simply not this type's business, and a writer that
/// deletes what it does not recognise is a writer nobody can use. `EntityDef`
/// has held that principle since it was written — «an editor written against a
/// later version must not silently strip the properties it does not recognise»
/// — and this is the rest of the format catching up.
///
/// [source] is empty for an object built in Dart rather than read, and then
/// this degrades exactly to the elide-by-default writer it replaces.
Map<String, Object?> writeThrough(
  Map<String, Object?> source,
  List<WriteThroughField> fields,
) {
  final byKey = <String, WriteThroughField>{
    for (final field in fields) field.key: field,
  };
  final out = <String, Object?>{};

  for (final entry in source.entries) {
    final field = byKey[entry.key];
    if (field == null) {
      out[entry.key] = entry.value;
      continue;
    }
    out[entry.key] = sameJsonValue(entry.value, field.value)
        ? entry.value
        : field.value;
  }

  for (final field in fields) {
    if (out.containsKey(field.key) || !field.whenAbsent) continue;
    out[field.key] = field.value;
  }
  return out;
}

/// One number as it survives a `Vector3`, which is single precision.
final Float32List _narrow = Float32List(1);
double _asFloat32(double value) {
  _narrow[0] = value;
  return _narrow[0];
}

/// Whether two decoded JSON values say the same thing.
///
/// **Numerically**, so the `4` a level document wrote and the `4.0` this code
/// holds are the same value and the document keeps its own spelling. Without
/// that, reading and writing `crypt.json` would rewrite a hundred and fifty-six
/// coordinates that nobody touched.
bool sameJsonValue(Object? a, Object? b) {
  if (a is num && b is num) {
    final x = a.toDouble();
    final y = b.toDouble();
    if (x == y) return true;
    // **And at the precision the value actually survives at.** Every coordinate
    // in this format passes through a `Vector3`, which is single precision, so
    // a document saying `0.034` gets `0.034000001847743988` back — a different
    // double denoting the same stored number. Comparing as doubles would
    // rewrite every vector in every level on the first save.
    return _asFloat32(x) == _asFloat32(y);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameJsonValue(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameJsonValue(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}
