import 'dart:math' as math;

import 'level.dart';

/// The entity types the game knows about.
///
/// A shared list rather than strings scattered across the loader, the editor
/// and the spawner: a typo in any one of them otherwise produces an entity that
/// silently never appears, which is the hardest kind of level bug to notice.
abstract final class EntityTypes {
  static const String playerSpawn = 'player_spawn';
  static const String monster = 'monster';
  static const String pickup = 'pickup';
  static const String key = 'key';
  static const String door = 'door';
  static const String lift = 'lift';
  static const String button = 'button';
  static const String trigger = 'trigger';
  static const String note = 'note';
  static const String exit = 'exit';
  static const String torch = 'torch';

  static const Set<String> all = <String>{
    playerSpawn,
    monster,
    pickup,
    key,
    door,
    lift,
    button,
    trigger,
    note,
    exit,
    torch,
  };
}

enum LevelIssueSeverity {
  /// The level will not play correctly. Loading should stop.
  error,

  /// The level will play, and somebody probably did not mean this.
  warning,
}

final class LevelIssue {
  const LevelIssue(this.severity, this.message, {this.where});

  final LevelIssueSeverity severity;
  final String message;

  /// Where to look: `entities[4] door "north"`, `brushes[17]`.
  final String? where;

  bool get isError => severity == LevelIssueSeverity.error;

  @override
  String toString() =>
      '${severity.name.toUpperCase()}${where == null ? '' : ' $where'}: '
      '$message';
}

/// Reads a level and says what is wrong with it.
///
/// ## Why this exists at all
///
/// Every check below is for a mistake that otherwise surfaces as a confusing
/// moment during play rather than as an error: a door that never opens because
/// its key is in no room, a button wired to a lift somebody renamed, a spawn
/// point that was deleted so the player starts at the origin inside a wall.
/// None of those throw. They are all cheap to find here, by name, before the
/// level ever loads.
final class LevelValidator {
  const LevelValidator({this.knownTypes = EntityTypes.all});

  /// Entity types the game can spawn. An unknown one is an error rather than a
  /// warning: it means an entity the author placed will not exist.
  final Set<String> knownTypes;

  List<LevelIssue> validate(Level level) {
    final issues = <LevelIssue>[];
    _checkBrushes(level, issues);
    _checkEntities(level, issues);
    _checkReferences(level, issues);
    _checkLighting(level, issues);
    return issues;
  }

  /// Validates and throws on the first error, listing every one.
  ///
  /// For loading: a level with a broken reference should refuse to start rather
  /// than start and be unfinishable.
  void assertValid(Level level) {
    final issues = validate(level);
    final errors = issues.where((LevelIssue i) => i.isError).toList();
    if (errors.isEmpty) return;
    throw LevelFormatException(
      'level "${level.name}" has ${errors.length} '
      '${errors.length == 1 ? 'error' : 'errors'}:\n'
      '${errors.map((LevelIssue e) => '  $e').join('\n')}',
    );
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
  /// z-fighting on coincident faces and hidden geometry that still gets drawn,
  /// so they are worth surfacing and not worth refusing.
  ///
  /// Compared pairwise against a cell grid rather than every pair, so a level
  /// with thousands of brushes does not take quadratic time to check.
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
          final pair = (math.min(ia, ib) << 32) ^ math.max(ia, ib);
          if (!reported.add(pair)) continue;

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

  void _checkEntities(Level level, List<LevelIssue> issues) {
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
      final entity = level.entities[i];
      final where = 'entities[$i] ${entity.type}'
          '${entity.name == null ? '' : ' "${entity.name}"'}';

      if (!knownTypes.contains(entity.type)) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'unknown type "${entity.type}", so nothing will spawn here',
            where: where,
          ),
        );
      }

      final name = entity.name;
      if (name != null) {
        final previous = names[name];
        if (previous != null) {
          issues.add(
            LevelIssue(
              LevelIssueSeverity.error,
              'name "$name" is already used by entities[$previous], so a '
              'reference to it is ambiguous',
              where: where,
            ),
          );
        }
        names[name] = i;
      }
    }
  }

  /// Checks that everything an entity points at exists.
  void _checkReferences(Level level, List<LevelIssue> issues) {
    final keysInLevel = <String>{
      for (final key in level.ofType(EntityTypes.key))
        if (key.string('color') != null) key.string('color')!,
    };

    for (var i = 0; i < level.entities.length; i++) {
      final entity = level.entities[i];
      final where = 'entities[$i] ${entity.type}'
          '${entity.name == null ? '' : ' "${entity.name}"'}';

      final target = entity.string('target');
      if (target != null && level.named(target) == null) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'targets "$target", which no entity is named',
            where: where,
          ),
        );
      }

      final requiredKey = entity.string('key');
      if (requiredKey != null && !keysInLevel.contains(requiredKey)) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'needs the "$requiredKey" key, and no ${EntityTypes.key} entity in '
            'this level provides one',
            where: where,
          ),
        );
      }

      if (entity.type == EntityTypes.button && target == null) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'has no "target", so pressing it would do nothing',
            where: where,
          ),
        );
      }

      if (entity.type == EntityTypes.lift) {
        final travel = entity.vector('travel');
        if (travel == null) {
          issues.add(
            LevelIssue(
              LevelIssueSeverity.error,
              'has no "travel" offset, so it has nowhere to go',
              where: where,
            ),
          );
        } else if (travel.length < 1e-6) {
          issues.add(
            LevelIssue(
              LevelIssueSeverity.warning,
              'travels nowhere',
              where: where,
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
