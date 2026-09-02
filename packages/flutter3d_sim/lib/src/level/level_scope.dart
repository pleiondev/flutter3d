import 'entity_types.dart';
import 'level.dart';

/// What an entity can see of the level it sits in.
///
/// Passed to [EntityKind.validate] rather than the whole [Level], so a kind can
/// answer "does this key exist" without walking every entity for each one — the
/// set is gathered once — and so what a kind is allowed to look at stays a
/// short, readable list.
final class LevelScope {
  LevelScope(this.level)
    : keys = <String>{
        for (final key in level.ofType(EntityTypes.key))
          if (key.string('color') != null) key.string('color')!,
      };

  final Level level;

  /// Every key colour some pickup in this level provides.
  final Set<String> keys;

  /// Where to look, for an issue message: `entities[4] door "north"`.
  String describe(EntityDef entity) {
    final index = level.entities.indexOf(entity);
    return 'entities[$index] ${entity.type}'
        '${entity.name == null ? '' : ' "${entity.name}"'}';
  }
}
