/// The map, read from a document rather than worked out in code.
///
/// **What this file replaced was a formula.** The hillside was a sum of sines
/// in `staging.dart` and the camps were coordinates beside it, which is a fine
/// way to get a demo on the screen and a poor way to keep one: there was
/// nothing an editor could open, nothing a saved run could name, and nothing a
/// playthrough could point at when it said it had won on *this* map. Every
/// amplitude in the formula was also load-bearing without anybody being told
/// so, which is the kind of thing that is changed by a plausible edit and
/// noticed a fortnight later.
///
/// **The document is a [Level], not a format this genre invented.** A level
/// already carries a [Heightfield] for the ground and an [EntityDef] for
/// everything standing on it, entities are already a property bag, the editor
/// already edits them and [LevelValidator] already checks them. What is here is
/// the vocabulary — what a `camp` is, what a `worker` block means — and the
/// pass that turns those into a running match.
///
/// Written by `tool/make_map.py`. Edit that, not the JSON.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

/// The map the demo opens on.
const String mapAsset = 'assets/levels/map_a.json';

/// The words this game's documents use.
///
/// Constants rather than strings spelled out at each use, for the reason
/// `EntityTypes` gives next door: a document, a validator and an assembly all
/// have to agree about the spelling, and a typo in one of the three is a thing
/// that loads and then quietly contains nothing.
abstract final class StrategyEntities {
  /// A side's hall: where its workers carry to and where new ones come from.
  static const String camp = 'camp';

  /// A block of workers, and how many stand in it.
  static const String worker = 'worker';

  /// A seam worth digging.
  static const String resourceNode = 'resource_node';

  /// What a side opens its purse with.
  static const String stockpile = 'stockpile';

  /// A building that turns a stockpile back into workers.
  static const String producer = 'producer';
}

/// A map document: a level, and the finishing line the match on it is played
/// to.
///
/// The line is not in the level because it is not anywhere on it — this game is
/// won by having brought home more than the other side, which is a fact about
/// the match rather than about a place. The format carries a section it does
/// not know rather than losing it (see `writeThrough`), so the document keeps
/// both and the editor keeps the goal even though it has no idea what it is.
final class StrategyMap {
  const StrategyMap._({required this.level, required this.goal});

  /// Reads a document, and refuses one this build cannot play.
  ///
  /// **Validated here rather than at the first null.** Everything below assumes
  /// that a producer's `target` names a hall and that a block of workers names
  /// a seam, because the validator has already said so; without this the first
  /// symptom of a mistyped name is a null dereference four frames into the
  /// assembly, with nothing on the screen and nothing said about which entity
  /// was wrong.
  factory StrategyMap.parse(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    final level = Level.fromJson(json);
    if (level.heightfield == null) {
      throw LevelFormatException(
        'the map "${level.name}" has no heightfield, and this game is played '
        'on ground made of samples',
      );
    }
    strategyValidator.assertValid(level);
    final goal = json['goal'];
    return StrategyMap._(
      level: level,
      goal: MatchGoal(
        delivered: switch (goal) {
          {'delivered': final num line} => line.toDouble(),
          // A map with no line is playable and simply never ends by one — the
          // match still finishes when the ground runs out, which is what makes
          // that a default rather than a refusal.
          _ => double.infinity,
        },
      ),
    );
  }

  /// Reads the document out of the application's bundle.
  static Future<StrategyMap> load({String asset = mapAsset}) async =>
      StrategyMap.parse(await rootBundle.loadString(asset));

  /// The document itself, as the editor and the validator see it.
  final Level level;

  /// Where the match played on it ends.
  final MatchGoal goal;

  /// The ground. Never null: [StrategyMap.parse] refuses a map without one.
  Heightfield get ground => level.heightfield!;
}

/// A match assembled from a document, and nothing that draws it.
///
/// **The half of staging that needs no [GraphicsDevice], which is the point of
/// having a document at all.** A test of the simulation used to have to open a
/// software rasteriser to reach the game's own start, and a playthrough — a
/// match played to its end against a policy — should not be drawing frames it
/// never looks at.
final class StrategyStart {
  /// Holds the two halves a caller needs.
  const StrategyStart({required this.match, required this.mine});

  /// The sides, the ground under them, and the finishing line.
  final Match match;

  /// The units side nought commands, which in the application is the mouse.
  final List<Unit> mine;

  /// The crowd and the ground it walks on.
  StrategySimulation get simulation => match.simulation;
}

/// Builds the start [map] describes.
///
/// [workers] overrides how many stand in each block, for a caller that wants a
/// smaller crowd than the map's — a test drawing frames one at a time in
/// software, mostly. The document's own count is what the game plays.
///
/// [seed] is the one the dice start on. It is a number rather than a
/// [GameRandom] so that two callers cannot be handed the same generator and
/// step each other's rolls, and it has a default because a demo that staged
/// itself differently on every launch would be a demo whose screenshots are
/// not comparable and whose bug reports cannot be re-run. Nothing in the
/// simulation rolls it yet; see [StrategySimulation.random] for why it is here
/// before the first die.
StrategyStart openMatch(StrategyMap map, {int? workers, int seed = 1}) {
  final Level level = map.level;
  final simulation = StrategySimulation(
    ground: map.ground,
    random: GameRandom(seed),
    sides: _sides(level),
  );

  // Halls first, then seams, then everything that points at one of them.
  // Passes rather than one walk in document order, so that a document which
  // lists a producer above the hall it belongs to still loads: the order
  // entities are written in is an author's business, and an assembly that
  // depended on it would be a rule nobody was told.
  final halls = <String, Building>{
    for (final EntityDef it in level.ofType(StrategyEntities.camp))
      it.name!: simulation.build(
        Building(
          centre: it.position,
          width: it.number('width')!,
          depth: it.number('depth')!,
          name: it.name!,
          side: it.integer('side') ?? 0,
        ),
      ),
  };
  final seams = <String, ResourceNode>{
    for (final EntityDef it in level.ofType(StrategyEntities.resourceNode))
      it.name!: simulation.addResource(
        ResourceNode(at: it.position, amount: it.number('amount')!),
      ),
  };

  for (final EntityDef it in level.ofType(StrategyEntities.producer)) {
    simulation.addProducer(
      Producer(
        building: halls[it.string('target')]!,
        cost: it.number('cost') ?? 25.0,
        seconds: it.number('seconds') ?? 4.0,
      ),
    );
  }

  for (final EntityDef it in level.ofType(StrategyEntities.stockpile)) {
    simulation.stock[it.integer('side') ?? 0].amount = it.number('amount')!;
  }

  final mine = <Unit>[];
  for (final EntityDef it in level.ofType(StrategyEntities.worker)) {
    final int side = it.integer('side') ?? 0;
    final int count = workers ?? it.integer('count')!;
    final int across = it.integer('across') ?? count;
    final double spacing = it.number('spacing')!;
    final ResourceNode digs = seams[it.string('digs')]!;
    final Building home = halls[it.string('home')]!;

    for (var i = 0; i < count; i++) {
      final Unit unit = simulation.add(
        Unit(
          position: Vector3(
            it.position.x + (i % across) * spacing,
            0.0,
            it.position.z + (i ~/ across) * spacing,
          ),
          side: side,
        ),
      );
      // Both sides open at work rather than standing about. The far side's bot
      // would have sent its own out within a second anyway; the near side's
      // opening orders are the player's, and clicking the ground cancels them,
      // which is the same exchange either way round.
      //
      // **A job each, not a job shared.** A `HarvestJob` remembers what its
      // unit is carrying, so one handed to sixty units would have them filling
      // and emptying the same sack.
      unit.job = HarvestJob(node: digs, dropOff: home);
      if (side == 0) mine.add(unit);
    }
  }

  return StrategyStart(
    match: Match(
      simulation: simulation,
      // Side nought is the one somebody is holding a mouse for; every other
      // camp gets a policy. The two are given orders through the same handles,
      // which is the whole reason the bot was worth writing.
      bots: <Bot>[
        for (final MapEntry<String, Building> it in halls.entries)
          if (it.value.side != 0) Bot(side: it.value.side, base: it.value),
      ],
      goal: map.goal,
    ),
    mine: mine,
  );
}

/// How many sides the document stages: the highest side named, plus one.
///
/// Counted from what is written rather than from how many camps there are, so
/// that a map giving one side two halls is two sides and not three.
int _sides(Level level) =>
    1 +
    level.entities.fold(0, (int most, EntityDef it) {
      final int side = it.integer('side') ?? 0;
      return side > most ? side : most;
    });

// MARK: - What a map has to be

/// What this build can read, and what it requires of a whole map.
///
/// The registry is this game's own vocabulary rather than a default the engine
/// hands out — there is none, deliberately, because a racing game has no camps
/// and a dungeon has no seams.
final LevelValidator strategyValidator = LevelValidator(
  registry: EntityRegistry(<EntityKind>[
    const _CampKind(),
    const _WorkerKind(),
    const _ResourceNodeKind(),
    const _StockpileKind(),
    const _ProducerKind(),
  ]),
  rules: const <LevelRule>[
    AtLeastOne(
      StrategyEntities.camp,
      because: 'a match with no camps has nobody in it',
      severity: LevelIssueSeverity.error,
    ),
    AtLeastOne(
      StrategyEntities.resourceNode,
      because: 'a map with nothing to dig cannot be won',
      severity: LevelIssueSeverity.error,
    ),
  ],
);

final class _CampKind extends EntityKind {
  const _CampKind() : super(StrategyEntities.camp);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    // A camp is named because everything else points at it by name: the
    // producer that builds from it, the workers that carry to it.
    _requireName(entity, scope, out, 'so nothing can be told to carry to it');
    _requireSide(entity, scope, out);
    _requirePositive(entity, scope, out, 'width');
    _requirePositive(entity, scope, out, 'depth');
  }
}

final class _ResourceNodeKind extends EntityKind {
  const _ResourceNodeKind() : super(StrategyEntities.resourceNode);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _requireName(entity, scope, out, 'so nobody can be sent to dig it');
    _requirePositive(entity, scope, out, 'amount');
  }
}

final class _ProducerKind extends EntityKind {
  const _ProducerKind() : super(StrategyEntities.producer);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    _requirePositive(entity, scope, out, 'cost');
    _requirePositive(entity, scope, out, 'seconds');
  }
}

final class _StockpileKind extends EntityKind {
  const _StockpileKind() : super(StrategyEntities.stockpile);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _requireSide(entity, scope, out);
    // Zero is the usual answer and a perfectly good one, so this asks only
    // that the key is there: an opening purse nobody wrote is a purse whose
    // size is decided by whichever reader happens to have a default.
    if (entity.number('amount') == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "amount", so nothing says what this side opens with',
          where: scope.describe(entity),
        ),
      );
    }
  }
}

final class _WorkerKind extends EntityKind {
  const _WorkerKind() : super(StrategyEntities.worker);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _requireSide(entity, scope, out);
    _requirePositive(entity, scope, out, 'count');
    _requirePositive(entity, scope, out, 'across');
    _requirePositive(entity, scope, out, 'spacing');
    _requireNamed(entity, scope, out, 'digs');
    _requireNamed(entity, scope, out, 'home');
  }
}

void _requireName(
  EntityDef entity,
  LevelScope scope,
  List<LevelIssue> out,
  String because,
) {
  if (entity.name != null) return;
  out.add(
    LevelIssue(
      LevelIssueSeverity.error,
      'has no "name", $because',
      where: scope.describe(entity),
    ),
  );
}

void _requireSide(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
  final int? side = entity.integer('side');
  if (side != null && side >= 0) return;
  out.add(
    LevelIssue(
      LevelIssueSeverity.error,
      side == null
          ? 'has no "side", so nothing says whose it is'
          : 'belongs to side $side, and there is no such side',
      where: scope.describe(entity),
    ),
  );
}

void _requirePositive(
  EntityDef entity,
  LevelScope scope,
  List<LevelIssue> out,
  String key,
) {
  final double? value = entity.number(key);
  if (value != null && value > 0.0) return;
  out.add(
    LevelIssue(
      LevelIssueSeverity.error,
      value == null
          ? 'has no "$key"'
          : 'has a "$key" of $value, which is not a quantity',
      where: scope.describe(entity),
    ),
  );
}

/// Reports that [key] does not name an entity of this level.
///
/// The same duty [EntityKind.requireTarget] does for the key it happens to be
/// called `target`; a block of workers points at two things at once and needs
/// the check under both names.
void _requireNamed(
  EntityDef entity,
  LevelScope scope,
  List<LevelIssue> out,
  String key,
) {
  final String? named = entity.string(key);
  if (named != null && scope.level.named(named) != null) return;
  out.add(
    LevelIssue(
      LevelIssueSeverity.error,
      named == null
          ? 'has no "$key", so it has nowhere to go'
          : '"$key" names "$named", which no entity is called',
      where: scope.describe(entity),
    ),
  );
}
