/// A data plugin's `entityKinds`, read through the plugin API's
/// `DataSectionRegistry`: [entityKindsSection] and the [DataEntityKind]s it
/// adds to the engine's `EntityKinds`.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        DataSection,
        DataSectionInstall,
        DataSectionRead,
        DocumentFormatException,
        PluginException;
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A data plugin's `entityKinds`: the kinds a level may name, each a
/// [DataEntityKind] declared as `{"type": "vent", "requires": ["size"],
/// "collider": "trigger"}` and added to the engine's [EntityKinds] when the
/// plugin is installed, under the plugin's own scope.
///
/// Registered by the application in the engine's `DataSectionRegistry`. A
/// simulation that reads the plugin needs the section: a level that names
/// one of its kinds is refused without it.
const DataSection entityKindsSection = _EntityKindsSection();

final class _EntityKindsSection extends DataSection {
  const _EntityKindsSection();

  @override
  String get name => 'entityKinds';

  @override
  Object read(DataSectionRead step) {
    final written = step.written;
    final context = step.context;
    return List<DataEntityKind>.unmodifiable(<DataEntityKind>[
      for (final entry in switch (written) {
        null => const <Object?>[],
        final List<Object?> list when list.every((e) => e is Map) => list,
        _ => throw const DocumentFormatException(
          '"entityKinds" is not a list of objects',
        ),
      })
        DataEntityKind.fromJson(
          (entry! as Map).cast<String, Object?>(),
          owner: context.plugin,
        ),
    ]);
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final kind in section as List<DataEntityKind>) kind.toJson(),
  ];

  @override
  void install(DataSectionInstall step) {
    final host = step.host;
    final section = step.section;
    final context = step.context;
    final declared = section as List<DataEntityKind>;
    if (declared.isEmpty) return;
    final kinds = host.maybeRegistry<EntityKinds>();
    if (kinds == null) {
      throw PluginException(
        'plugin "${context.plugin}" declares entity kinds '
        '(${declared.map((k) => k.type).join(', ')}), and this engine has no '
        'EntityKinds to add them to',
      );
    }
    kinds.addAll(declared);
  }
}

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
  /// A kind of [type] declared by plugin [owner], requiring no property
  /// and placing no box unless told otherwise.
  const DataEntityKind(
    super.type, {
    required this.owner,
    this.requires = const <String>[],
    this.collider,
  });

  /// Reads one declaration: `{"type": "vent", "requires": ["size"],
  /// "collider": "trigger"}`. Throws a [DocumentFormatException] saying what is
  /// wrong.
  factory DataEntityKind.fromJson(
    Map<String, Object?> json, {
    required String owner,
  }) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw DocumentFormatException('an entity kind names no type');
    }
    final requires = json['requires'] ?? const <Object?>[];
    if (requires is! List<Object?> || requires.any((r) => r is! String)) {
      throw DocumentFormatException(
        'entity kind "$type": requires is not a list of '
        'property names',
      );
    }
    final collider = switch (json['collider']) {
      null => null,
      'trigger' => ColliderKind.trigger,
      'static' => ColliderKind.static,
      'kinematic' => ColliderKind.kinematic,
      final Object other => throw DocumentFormatException(
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

  /// The plugin that declared it, by id, for the sentences a level reads.
  final String owner;

  /// Properties every entity of this kind must have.
  final List<String> requires;

  /// The box it occupies, or null for a kind that is only a marker.
  final ColliderKind? collider;

  /// The declaration as [DataEntityKind.fromJson] reads it, leaving out
  /// what is empty.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (requires.isNotEmpty) 'requires': requires,
    if (collider != null) 'collider': collider!.name,
  };

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    for (final key in requires) {
      if (entity.properties.containsKey(key)) continue;
      out.add(
        LevelIssue(
          Severity.error,
          'has no "$key", which plugin "$owner" requires of a $type',
          where: scope.describe(entity),
        ),
      );
    }
    if (collider != null) requireSize(entity, scope, out);
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
    final kind = collider;
    if (kind != null) place(entity, context, kind: kind);
  }
}
