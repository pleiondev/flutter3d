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

  /// The shapes this type is built out of, or empty.
  ///
  /// **For the things a game builds rather than models.** The crypt's torch is
  /// a plate, an angled shaft and a cup with fire over it — real geometry, made
  /// out of the engine's own primitives by twenty lines of the game's code.
  /// There is no file to point at and there never will be, so a game that wants
  /// its torch to look like a torch in an editor writes down the same handful
  /// of shapes.
  ///
  /// **This is a second copy of a silhouette, and that is worth saying out
  /// loud.** The game's version and this one can drift, and nothing will catch
  /// it. It buys the thing the marks could not: a wall with a torch on it
  /// rather than a wall with a box on it. The way to remove the copy is to make
  /// the game build its fixtures from this list too, which is a change to the
  /// game rather than to the editor.
  List<Part> partsFor(EntityDef entity) =>
      _byType[entity.type]?.parts ?? const <Part>[];

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
  const Look({this.model, this.size, this.tint, this.parts = const <Part>[]});

  final String? model;
  final Vector3? size;
  final Vector3? tint;

  /// The shapes it is built out of, for a thing with no model.
  final List<Part> parts;

  factory Look.fromJson(Map<String, Object?> json) => Look(
        model: json['model'] is String ? json['model']! as String : null,
        size: _vector(json['size']),
        tint: _vector(json['tint']),
        parts: <Part>[
          for (final part in json['parts'] is List
              ? json['parts']! as List<Object?>
              : const <Object?>[])
            if (part is Map<String, Object?>) Part.fromJson(part),
        ],
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

/// One shape in a silhouette.
///
/// The primitives are the engine's own, which is what makes this data rather
/// than a drawing: a game names `cylinder` and a size, and the editor asks the
/// same `CylinderShape` the game would have asked for.
final class Part {
  const Part({
    required this.shape,
    required this.at,
    required this.size,
    required this.radius,
    required this.height,
    required this.pitch,
    required this.colour,
    required this.glows,
  });

  /// `box`, `cylinder`, `sphere` or `cone`. Anything else is drawn as a box,
  /// because a shape nobody recognises is still somewhere a thing is.
  final String shape;

  /// Where it sits, in the entity's own space: +Z into the wall it is on, so
  /// the level's yaw turns the whole thing.
  final Vector3 at;

  final Vector3 size;
  final double radius;
  final double height;

  /// Tilt about the entity's X, in radians. What holds a torch's shaft up and
  /// out of the wall.
  final double pitch;

  final Vector3 colour;

  /// Whether this part is the light rather than the thing holding it. Drawn so
  /// that a dark corridor cannot swallow it, which is the whole point of a
  /// flame.
  final bool glows;

  factory Part.fromJson(Map<String, Object?> json) => Part(
        shape: json['shape'] is String ? json['shape']! as String : 'box',
        at: Look._vector(json['at']) ?? Vector3.zero(),
        size: Look._vector(json['size']) ?? Vector3.all(0.1),
        radius: json['radius'] is num ? (json['radius']! as num).toDouble() : 0.05,
        height: json['height'] is num ? (json['height']! as num).toDouble() : 0.1,
        pitch: json['pitch'] is num ? (json['pitch']! as num).toDouble() : 0.0,
        colour: Look._vector(json['colour']) ??
            Look._vector(json['glow']) ??
            Vector3(0.6, 0.6, 0.62),
        glows: json['glow'] != null,
      );
}

/// Where a game keeps the file, if it keeps one.
const String kLooksFile = 'assets/editor.json';
