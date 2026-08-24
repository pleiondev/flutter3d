import 'entity_kind.dart';
import 'level.dart';
import 'level_issue.dart';
import 'level_rule.dart';

export 'entity_kind.dart' show EntityRegistry, EntityTypes;
export 'level_issue.dart';
export 'level_rule.dart';

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
  /// [registry] is required, and that is a change worth noticing: it used to
  /// default to a roster that named this repository's own monsters, pickups
  /// and furniture, so a second game silently validated its levels against
  /// somebody else's vocabulary. There is no default a package can give.
  const LevelValidator({required this.registry, this.rules = const <LevelRule>[]});

  /// Which entity kinds this build can spawn.
  final EntityRegistry registry;

  /// What this game requires of a level as a whole. Empty is a valid answer:
  /// the checks below hold for any level in this format, and everything about
  /// *which* entities a level ought to contain is a game's own business.
  final List<LevelRule> rules;

  List<LevelIssue> validate(Level level) {
    final issues = <LevelIssue>[];
    final scope = LevelScope(level);

    _checkBrushes(level, issues);
    _checkTheSetOfEntities(level, issues);
    _checkEachEntity(level, scope, issues);
    _checkReachable(level, issues);
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
    for (final rule in rules) {
      rule.check(level, issues);
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

      _checkRamp(brush, where, issues);
    }

    _checkOverlaps(level, issues);
  }

  /// What a ramp has to be to be worth being one.
  ///
  /// **A ramp is the one brush whose numbers can contradict its purpose.**
  /// Every other property of a block is what it says it is; a ramp's steepness
  /// is implied by its proportions, so a size typed the wrong way round makes a
  /// slope nobody can stand on — and it still loads, still draws, and still
  /// looks like a ramp from a distance.
  ///
  /// Warnings rather than errors on purpose. A wall shaped like a wedge is a
  /// perfectly good thing to build — it is what the outside of a roof is — and
  /// refusing to load a level over one would be the validator deciding what a
  /// game means by its own geometry.
  void _checkRamp(Brush brush, String where, List<LevelIssue> issues) {
    final uphill = brush.ramp;
    if (uphill == null) return;

    final run = uphill.axis == 0 ? brush.size.x : brush.size.z;
    final gradient = brush.size.y / run;
    // The same sixty degrees the character controller calls the flattest a
    // contact may lean and still be a floor. Named here as a number rather than
    // imported, because a game may hold a different opinion and this package
    // must not be the one that decides.
    const walkable = 1.732;

    if (gradient > walkable) {
      issues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'ramp rises ${brush.size.y} over $run, which is steeper than sixty '
          'degrees — a body slides down this rather than walking up it',
          where: where,
        ),
      );
    } else if (gradient < 0.02) {
      // Two centimetres in a metre. Below that the wedge and the block it was
      // cut from are the same thing to a player, and the difference is a face
      // the mesh builder pays for and nobody sees.
      issues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'ramp rises ${brush.size.y} over $run, which is flat enough that a '
          'block would look the same and cost less',
          where: where,
        ),
      );
    }
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
  /// Nothing a player has to reach may be inside solid geometry.
  ///
  /// **The defect this project shipped twice and did not see either time.**
  /// Fourteen coins and a crate sat inside brushes across the two levels — a
  /// crate at the foot of a chimney, three coins in a crawlspace, four on top
  /// of pillars that were roofed after the coins were placed. Every one was
  /// authored by hand, every one is invisible in the document, and a coin you
  /// cannot take looks exactly like a coin you have not taken yet. The
  /// validator did not look and the autopilot walked past them.
  ///
  /// **The centre, not the whole box**, deliberately: a coin whose edge grazes
  /// a wall is fine and common, and a check that fails on that is a check
  /// people switch off. A centre inside solid is never right.
  ///
  /// Which kinds this applies to is [EntityKind.mustBeReachable] — the kind
  /// answers, so the engine never learns the words.
  void _checkReachable(Level level, List<LevelIssue> issues) {
    final solid = <Brush>[
      for (final brush in level.brushes)
        if (brush.solid) brush,
    ];
    if (solid.isEmpty) return;

    for (var i = 0; i < level.entities.length; i++) {
      final entity = level.entities[i];
      if (registry[entity.type]?.mustBeReachable != true) continue;
      final at = entity.position;

      for (final brush in solid) {
        final min = brush.min;
        final max = brush.max;
        if (at.x <= min.x + 0.01 || at.x >= max.x - 0.01) continue;
        if (at.y <= min.y + 0.01 || at.y >= max.y - 0.01) continue;
        if (at.z <= min.z + 0.01 || at.z >= max.z - 0.01) continue;

        issues.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'is inside solid geometry, so nothing can reach it',
            where: 'entities[$i]',
          ),
        );
        break;
      }
    }
  }

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
            // **A message from an engine package, so it says nothing about
            // anybody's fiction.** It used to end "the falloff a dungeon relies
            // on", which reads oddly to somebody writing a racing game and is
            // the same rule `no_genre_test` keeps everywhere else — a word list
            // that scans identifiers and not strings simply did not catch it.
            'is a point light with unbounded range, which lights the whole '
            'level through its own walls',
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
