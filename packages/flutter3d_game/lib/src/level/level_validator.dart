import 'entity_kind.dart';
import 'level.dart';
import 'level_issue.dart';

export 'entity_kind.dart' show EntityRegistry, EntityTypes;
export 'level_issue.dart';

/// Reads a level and says what is wrong with it.
///
/// ## Why this exists at all
///
/// Every check is for a mistake that otherwise surfaces as a confusing moment
/// during play rather than as an error: a door whose key is in no room, a
/// button wired to a lift somebody renamed, a spawn point that was deleted so
/// the player starts inside the floor. None of those throw. They are all cheap
/// to find here, by name, before the level ever loads.
///
/// ## What it does and does not decide
///
/// Anything about *one* entity belongs to that entity's [EntityKind] and is
/// asked for rather than known here — which is why this file has no list of
/// what a door needs, or a lift, or a note. What is left is what only a whole
/// level can answer: that there is exactly one spawn, that no two things share
/// a name, that the geometry is sane, that something is lit.
final class LevelValidator {
  LevelValidator({EntityRegistry? registry})
      : registry = registry ?? EntityRegistry.standard;

  /// Which entity kinds this build can spawn.
  final EntityRegistry registry;

  List<LevelIssue> validate(Level level) {
    final issues = <LevelIssue>[];
    final scope = LevelScope(level);

    _checkBrushes(level, issues);
    _checkTheSetOfEntities(level, issues);
    _checkEachEntity(level, scope, issues);
    _checkLighting(level, issues);
    return issues;
  }

  /// Validates and throws, listing every error at once.
  ///
  /// For loading: a level with a broken reference should refuse to start rather
  /// than start and be unfinishable.
  void assertValid(Level level) {
    final errors =
        validate(level).where((LevelIssue i) => i.isError).toList();
    if (errors.isEmpty) return;
    throw LevelFormatException(
      'level "${level.name}" has ${errors.length} '
      '${errors.length == 1 ? 'error' : 'errors'}:\n'
      '${errors.map((LevelIssue e) => '  $e').join('\n')}',
    );
  }

  // MARK: - One entity at a time, answered by its own kind

  void _checkEachEntity(
    Level level,
    LevelScope scope,
    List<LevelIssue> issues,
  ) {
    for (final entity in level.entities) {
      final kind = registry[entity.type];
      if (kind == null) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'unknown type "${entity.type}", so nothing will spawn here',
            where: scope.describe(entity),
          ),
        );
        continue;
      }
      kind.validate(entity, scope, issues);
    }
  }

  // MARK: - Questions only the whole level can answer

  void _checkTheSetOfEntities(Level level, List<LevelIssue> issues) {
    final spawns = level.ofType(EntityTypes.playerSpawn).length;
    if (spawns == 0) {
      issues.add(
        const LevelIssue(
          LevelIssueSeverity.error,
          'no ${EntityTypes.playerSpawn}: the player would start at the origin, '
          'which is usually inside the floor',
        ),
      );
    } else if (spawns > 1) {
      issues.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'there are $spawns ${EntityTypes.playerSpawn} entities and nothing '
          'decides which one is used',
        ),
      );
    }

    if (level.ofType(EntityTypes.exit).isEmpty) {
      issues.add(
        const LevelIssue(
          LevelIssueSeverity.warning,
          'no ${EntityTypes.exit}: the level cannot be finished',
        ),
      );
    }

    final names = <String, int>{};
    for (var i = 0; i < level.entities.length; i++) {
      final name = level.entities[i].name;
      if (name == null) continue;
      final previous = names[name];
      if (previous != null) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'name "$name" is already used by entities[$previous], so a '
            'reference to it is ambiguous',
            where: 'entities[$i] ${level.entities[i].type}',
          ),
        );
      }
      names[name] = i;
    }
  }

  void _checkBrushes(Level level, List<LevelIssue> issues) {
    if (level.brushes.isEmpty) {
      issues.add(
        const LevelIssue(
          LevelIssueSeverity.error,
          'the level has no geometry, so there is nothing to stand on',
        ),
      );
    }

    for (var i = 0; i < level.brushes.length; i++) {
      final brush = level.brushes[i];
      final where = 'brushes[$i]';

      if (brush.size.x <= 0.0 || brush.size.y <= 0.0 || brush.size.z <= 0.0) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'size ${brush.size} has a zero or negative side',
            where: where,
          ),
        );
        continue;
      }

      if (!level.materials.containsKey(brush.material) &&
          brush.material != 'default') {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.warning,
            'material "${brush.material}" is not defined, so this will render '
            'as plain grey',
            where: where,
          ),
        );
      }
    }

    _checkOverlaps(level, issues);
  }

  /// Reports solid brushes that share more than a token amount of volume.
  ///
  /// A warning rather than an error, and the distinction matters: overlapping
  /// brushes are harmless to collision — the union is what the player feels —
  /// and they are how anybody builds a wall meeting a floor. What they cost is
  /// z-fighting on coincident faces, so they are worth surfacing and not worth
  /// refusing.
  ///
  /// Compared against a cell grid rather than every pair, so a level with
  /// thousands of brushes does not take quadratic time to check.
  void _checkOverlaps(Level level, List<LevelIssue> issues) {
    const cell = 8.0;
    final buckets = <int, List<int>>{};

    for (var i = 0; i < level.brushes.length; i++) {
      final brush = level.brushes[i];
      if (!brush.solid) continue;
      final min = brush.min;
      final max = brush.max;
      for (var x = (min.x / cell).floor(); x <= (max.x / cell).floor(); x++) {
        for (var z = (min.z / cell).floor(); z <= (max.z / cell).floor(); z++) {
          (buckets[(x << 32) ^ (z & 0xFFFFFFFF)] ??= <int>[]).add(i);
        }
      }
    }

    final reported = <int>{};
    for (final bucket in buckets.values) {
      for (var a = 0; a < bucket.length; a++) {
        for (var b = a + 1; b < bucket.length; b++) {
          final ia = bucket[a];
          final ib = bucket[b];
          final lo = ia < ib ? ia : ib;
          final hi = ia < ib ? ib : ia;
          if (!reported.add((lo << 32) ^ hi)) continue;

          final volume =
              level.brushes[ia].overlapVolumeWith(level.brushes[ib]);
          // A shared face has zero volume; this is about real interpenetration.
          if (volume < 0.05) continue;

          issues.add(
            LevelIssue(
              LevelIssueSeverity.warning,
              'overlaps brushes[$ib] by ${volume.toStringAsFixed(2)} m³, which '
              'will z-fight where their faces meet',
              where: 'brushes[$ia]',
            ),
          );
        }
      }
    }
  }

  void _checkLighting(Level level, List<LevelIssue> issues) {
    if (level.lights.isEmpty) {
      issues.add(
        const LevelIssue(
          LevelIssueSeverity.warning,
          'no lights: the level will be black',
        ),
      );
      return;
    }

    var lit = false;
    for (var i = 0; i < level.lights.length; i++) {
      final light = level.lights[i];
      if (light.intensity > 0.0) lit = true;
      if (light.intensity <= 0.0) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.warning,
            'has no intensity and contributes nothing',
            where: 'lights[$i]',
          ),
        );
      }
      if (light.type == LevelLightType.point && light.range <= 0.0) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.warning,
            'is a point light with unbounded range, which lights the whole '
            'level and defeats the falloff a dungeon relies on',
            where: 'lights[$i]',
          ),
        );
      }
    }

    if (!lit) {
      issues.add(
        const LevelIssue(
          LevelIssueSeverity.warning,
          'every light has zero intensity',
        ),
      );
    }
  }
}
