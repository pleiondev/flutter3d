import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'data_plugin.dart' show DataPluginFormatException;

/// An entity kind a data plugin declares: the properties a level must give
/// it, and optionally a box it occupies.
///
/// **A genre's rules as data, where the engine has a data form for them.** A
/// level names its entities by type, and `EntityKinds` is what says which
/// types exist and what each needs; that table is the one rule a genre
/// writes that is already data-shaped. So a data plugin can add a kind, its
/// required properties are checked by the level validator with the same
/// sentences the built-in kinds use, and a kind with a [collider] places a
/// box of the entity's `size` — a trigger volume, a solid block — exactly as
/// `EntityKind.place` does for the engine's own. What it does when something
/// enters that box is a system's job, written in Wasm or Dart.
final class DataEntityKind extends EntityKind {
  const DataEntityKind(
    super.type, {
    required this.owner,
    this.requires = const <String>[],
    this.collider,
  });

  /// The plugin that declared it, by id, for the sentences a level reads.
  final String owner;

  /// Properties every entity of this kind must have.
  final List<String> requires;

  /// The box it occupies, or null for a kind that is only a marker.
  final ColliderKind? collider;

  /// Reads one declaration: `{"type": "vent", "requires": ["size"],
  /// "collider": "trigger"}`. Throws a [DataPluginFormatException] saying what is
  /// wrong.
  factory DataEntityKind.fromJson(
    Map<String, Object?> json, {
    required String owner,
  }) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw DataPluginFormatException('an entity kind names no type');
    }
    final requires = json['requires'] ?? const <Object?>[];
    if (requires is! List<Object?> || requires.any((r) => r is! String)) {
      throw DataPluginFormatException(
        'entity kind "$type": requires is not a list of '
        'property names',
      );
    }
    final collider = switch (json['collider']) {
      null => null,
      'trigger' => ColliderKind.trigger,
      'static' => ColliderKind.static,
      'kinematic' => ColliderKind.kinematic,
      final Object other => throw DataPluginFormatException(
        'entity kind "$type": collider "$other" is not trigger, static or '
        'kinematic',
      ),
    };
    return DataEntityKind(
      type,
      owner: owner,
      requires: List<String>.unmodifiable(requires.cast<String>()),
      collider: collider,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (requires.isNotEmpty) 'requires': requires,
    if (collider != null) 'collider': collider!.name,
  };

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    for (final key in requires) {
      if (entity.properties.containsKey(key)) continue;
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "$key", which plugin "$owner" requires of a $type',
          where: scope.describe(entity),
        ),
      );
    }
    if (collider != null) requireSize(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final kind = collider;
    if (kind != null) place(entity, context, kind: kind);
  }
}
