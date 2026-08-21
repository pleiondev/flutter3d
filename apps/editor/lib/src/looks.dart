import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// What a game's own words look like, told to the editor by the game.
///
/// **The one thing an editor cannot work out and must not guess.** A document
/// says `type: torch` and where it is; what a torch *looks* like is in the
/// game's code — the crypt builds one out of primitives and a light, and there
/// is no torch model anywhere for anybody to find. The same goes for a monster:
/// the level says `kind: runner` and the game holds the map from `runner` to a
/// file.
///
/// So the game says. An optional `assets/editor.json` beside a game's other
/// assets maps its types to a model, a size and a colour:
///
/// ```json
/// {
///   "monster": { "model": "assets/models/monster_{kind}.glb",
///                "size": [0.9, 1.9, 0.9] },
///   "torch":   { "size": [0.22, 0.75, 0.22], "tint": [1.0, 0.55, 0.15] }
/// }
/// ```
///
/// **This is not the editor learning a vocabulary.** It reads a file it does
/// not understand the words of: `monster` and `torch` are keys to it, exactly
/// as they are in a level. A game that never writes one gets marks, which is
/// what it got before — and nothing here is required for an editor to work.
///
/// `{kind}` is any property of the entity, put into the path. One line covers
/// three monsters, and a game that adds a fourth adds a file rather than a
/// mapping.
final class Looks {
  const Looks(this._byType);

  /// A game that has said nothing, which is most of them.
  static const Looks none = Looks(<String, Look>{});

  final Map<String, Look> _byType;

  bool get isEmpty => _byType.isEmpty;

  factory Looks.parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) return none;
    return Looks(<String, Look>{
      for (final entry in json.entries)
        if (entry.value is Map<String, Object?>)
          entry.key: Look.fromJson(entry.value! as Map<String, Object?>),
    });
  }

  /// The model [entity] should be drawn as, or null.
  ///
  /// **What the entity itself says wins**, always: a level that names a model
  /// on one particular door has said something about that door, and a rule
  /// about doors in general must not overrule it.
  String? modelFor(EntityDef entity) =>
      entity.string('model') ?? _fill(_byType[entity.type]?.model, entity);

  /// How big its mark should be, or null for the default.
  Vector3? sizeFor(EntityDef entity) =>
      entity.vector('size') ?? _byType[entity.type]?.size;

  /// What colour to draw the mark, or null to keep the one from the type's
  /// name.
  Vector3? tintFor(EntityDef entity) => _byType[entity.type]?.tint;

  /// Puts `{property}` into a path from the entity's own properties.
  ///
  /// A missing property leaves the path alone rather than half-substituted:
  /// `monster_{kind}.glb` with no kind is a file nobody has, and a model that
  /// will not read leaves the mark — which is what somebody wants to see.
  static String? _fill(String? path, EntityDef entity) {
    if (path == null) return null;
    return path.replaceAllMapped(RegExp(r'\{(\w+)\}'), (Match match) {
      final value = entity.properties[match.group(1)];
      return value is String ? value : match.group(0)!;
    });
  }
}

/// What one type looks like.
final class Look {
  const Look({this.model, this.size, this.tint});

  final String? model;
  final Vector3? size;
  final Vector3? tint;

  factory Look.fromJson(Map<String, Object?> json) => Look(
        model: json['model'] is String ? json['model']! as String : null,
        size: _vector(json['size']),
        tint: _vector(json['tint']),
      );

  static Vector3? _vector(Object? value) {
    if (value is! List || value.length < 3) return null;
    if (value.any((Object? it) => it is! num)) return null;
    return Vector3(
      (value[0]! as num).toDouble(),
      (value[1]! as num).toDouble(),
      (value[2]! as num).toDouble(),
    );
  }
}

/// Where a game keeps the file, if it keeps one.
const String kLooksFile = 'assets/editor.json';
