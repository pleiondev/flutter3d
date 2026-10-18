import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'level.dart' show LevelFormatException;

/// Reading a decoded JSON object, with the type checks in one place.
///
/// An extension rather than a pile of helper functions, so a reader says what
/// it wants — `json.vector3('at')` — instead of threading the map through
/// something that has to be named for it.
///
/// **The names carry the policy**, because both readers are extensions on the
/// same type and any name they share is ambiguous the moment a file can see
/// both. `numberOr` and `flagOr` take a fallback; `integerOrNull` and
/// `textOrNull` answer null; the short names — `number`, `integer`, `flag`,
/// `text` — belong to `SnapshotFields`, which is lenient by design. One file
/// already worked around the collision with an extension override at the call
/// site, which is the sort of fix that stays until somebody reads it.
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

  /// A colour in linear light, `[r, g, b]` or `[r, g, b, a]`, or [fallback]
  /// when the key is absent.
  ///
  /// **Read at double precision.** A colour read through a `Vector3` came
  /// back through float32, so a fog of 0.05 was written back as
  /// 0.05000000074505806.
  LinearColor linearColor(String key, {required LinearColor fallback}) {
    final value = this[key];
    if (value == null) return fallback;
    if (value is! List || value.length < 3 || value.length > 4) {
      throw LevelFormatException('"$key" must be three or four numbers');
    }
    return LinearColor(
      _number(value[0], key),
      _number(value[1], key),
      _number(value[2], key),
      value.length > 3 ? _number(value[3], key) : 1.0,
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

  /// The number under [key], or [fallback] when it is absent. Throws a
  /// [LevelFormatException] when it is there and not a number.
  double numberOr(String key, double fallback) {
    final value = this[key];
    if (value == null) return fallback;
    if (value is! num) throw LevelFormatException('"$key" must be a number');
    return value.toDouble();
  }

  /// The bool under [key], or [fallback] when it is absent. Throws a
  /// [LevelFormatException] when it is there and not a bool.
  bool flagOr(String key, {bool fallback = false}) {
    final value = this[key];
    if (value == null) return fallback;
    if (value is! bool) {
      throw LevelFormatException('"$key" must be true or false');
    }
    return value;
  }

  /// A whole number, or null when the key is absent.
  ///
  /// Reads a `num` and rounds, because JSON has one number type and `4` in a
  /// hand-written document is as likely to arrive as `4.0`.
  int? integerOrNull(String key) {
    final value = this[key];
    if (value == null) return null;
    if (value is! num) throw LevelFormatException('"$key" must be a number');
    return value.round();
  }

  /// The string under [key], or null when it is absent. Throws a
  /// [LevelFormatException] when it is there and not a string.
  String? textOrNull(String key) {
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
  ///
  /// **For a game's own documents, not the engine's.** The engine's formats
  /// read explicit wire tables (`LightType.fromWireName`), so a rename
  /// in Dart never changes a file; a game reading a property it wrote with
  /// its own enum's names reaches for this.
  T enumValue<T extends Enum>(
    String key,
    List<T> values,
    T fallback, {
    required String describedAs,
  }) {
    final name = textOrNull(key);
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

/// Reading one JSON value as a level document's nested object.
extension JsonValueReader on Object? {
  /// This value as a JSON object, or an error naming where it was expected.
  Map<String, Object?> asJsonObject(String context) {
    final value = this;
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    throw LevelFormatException('$context must be an object');
  }
}

/// Writing a [Vector3] the way a level document holds one.
extension JsonVectorWriter on Vector3 {
  /// The three components, ready for `jsonEncode`.
  List<double> toJson() => <double>[x, y, z];
}

/// Writing a [Vector4] colour the way a level document holds one.
extension JsonColorWriter on Vector4 {
  /// The four components, `[x, y, z, w]`, the fourth always written; what
  /// [JsonObjectReader.vector4] reads back.
  List<double> toJson() => <double>[x, y, z, w];
}

/// Writing a [LinearColor] the way a level document holds one.
extension JsonLinearColorWriter on LinearColor {
  /// `[r, g, b]`, and the coverage after them only when it is not opaque:
  /// what [JsonObjectReader.linearColor] reads back.
  List<double> toJson() => <double>[r, g, b, if (a != 1.0) a];
}
