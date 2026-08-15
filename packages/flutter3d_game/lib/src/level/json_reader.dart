import 'package:vector_math/vector_math.dart';

import 'level.dart' show LevelFormatException;

/// Reading a decoded JSON object, with the type checks in one place.
///
/// An extension rather than a pile of helper functions, so a reader says what
/// it wants — `json.vector3('at')` — instead of threading the map through
/// something that has to be named for it.
///
/// Strict about types and lenient about absence, on purpose. A missing optional
/// field takes its default; a field of the wrong type is an error that names
/// the key. The alternative — quietly accepting a string where a number belongs
/// — produces a document that loads and plays wrong, which costs far more to
/// find than a refusal at load time.
extension JsonObjectReader on Map<String, Object?> {
  /// A required vector, or [fallback] when the key is absent.
  Vector3 vector3(String key, {Vector3? fallback}) {
    final value = this[key];
    if (value == null) {
      if (fallback != null) return fallback.clone();
      throw LevelFormatException('"$key" is required');
    }
    if (value is! List || value.length < 3) {
      throw LevelFormatException('"$key" must be three numbers');
    }
    return Vector3(
      _number(value[0], key),
      _number(value[1], key),
      _number(value[2], key),
    );
  }

  /// A colour, where the fourth component defaults to opaque.
  Vector4 vector4(String key, {required Vector4 fallback}) {
    final value = this[key];
    if (value == null) return fallback.clone();
    if (value is! List || value.length < 3) {
      throw LevelFormatException('"$key" must be three or four numbers');
    }
    return Vector4(
      _number(value[0], key),
      _number(value[1], key),
      _number(value[2], key),
      value.length > 3 ? _number(value[3], key) : 1.0,
    );
  }

  double numberOr(String key, double fallback) {
    final value = this[key];
    if (value == null) return fallback;
    if (value is! num) throw LevelFormatException('"$key" must be a number');
    return value.toDouble();
  }

  bool flagOr(String key, {bool fallback = false}) {
    final value = this[key];
    if (value == null) return fallback;
    if (value is! bool) throw LevelFormatException('"$key" must be true or false');
    return value;
  }

  /// A whole number, or null when the key is absent.
  ///
  /// Reads a `num` and rounds, because JSON has one number type and `4` in a
  /// hand-written document is as likely to arrive as `4.0`.
  int? integer(String key) {
    final value = this[key];
    if (value == null) return null;
    if (value is! num) throw LevelFormatException('"$key" must be a number');
    return value.round();
  }

  String? text(String key) {
    final value = this[key];
    if (value == null) return null;
    if (value is! String) throw LevelFormatException('"$key" must be a string');
    return value;
  }

  /// A list of nested objects, or an empty list when the key is absent.
  List<Map<String, Object?>> objects(String key) {
    final value = this[key];
    if (value == null) return const <Map<String, Object?>>[];
    if (value is! List) {
      throw LevelFormatException(
        '"$key" must be a list, not ${value.runtimeType}',
      );
    }
    return value.map((Object? e) => e.asJsonObject(key)).toList();
  }

  /// A map of named nested objects, or an empty map.
  Map<String, Map<String, Object?>> objectMap(String key) {
    final value = this[key];
    if (value == null) return const <String, Map<String, Object?>>{};
    if (value is! Map) {
      throw LevelFormatException('"$key" must be an object');
    }
    // Typed on the way out of the map: `entries` on a bare `Map` yields
    // `dynamic`, and an extension method never resolves on a dynamic receiver —
    // it compiles and then fails at run time with a missing-method error.
    return <String, Map<String, Object?>>{
      for (final MapEntry<Object?, Object?> entry
          in value.cast<Object?, Object?>().entries)
        entry.key.toString(): entry.value.asJsonObject(key),
    };
  }

  /// An enum value by its name, naming the alternatives when it is not one.
  T enumValue<T extends Enum>(
    String key,
    List<T> values,
    T fallback, {
    required String describedAs,
  }) {
    final name = text(key);
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw LevelFormatException(
      'unknown $describedAs "$name"; expected one of '
      '${values.map((T v) => v.name).join(', ')}',
    );
  }

  static double _number(Object? value, String key) {
    if (value is! num) throw LevelFormatException('"$key" must be numbers');
    return value.toDouble();
  }
}

extension JsonValueReader on Object? {
  /// This value as a JSON object, or an error naming where it was expected.
  Map<String, Object?> asJsonObject(String context) {
    final value = this;
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    throw LevelFormatException('$context must be an object');
  }
}

extension JsonVectorWriter on Vector3 {
  /// The three components, ready for `jsonEncode`.
  List<double> toJson() => <double>[x, y, z];
}

extension JsonColorWriter on Vector4 {
  List<double> toJson() => <double>[x, y, z, w];
}
