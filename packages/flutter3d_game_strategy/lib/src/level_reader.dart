/// A strategy map read from a [Level]: the vocabulary a map document uses,
/// and the pass that turns one into a [Match].
///
/// **In the package so that something other than the application can open
/// a map.** The reader was the strategy demo's own, and a tool that plays a
/// map blind — the simulation's MCP server, a farm of playtests — depends on
/// the genre and on no application. The demo's `level_document.dart` reads
/// the same documents the same way; its names stay its own so that the two
/// do not collide while it still has them.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'bot.dart';
import 'building.dart';
import 'economy.dart';
import 'match.dart';
import 'simulation.dart';
import 'unit.dart';

/// The entity types a strategy map names.
abstract final class StrategyLevelTypes {
  /// A side's hall: where its workers carry to and new ones come from.
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

/// A match opened from a map, and the units side nought starts with.
final class StrategyOpening {
  const StrategyOpening({required this.match, required this.mine});

  /// The sides, the ground under them and the finishing line.
  final Match match;

  /// The units side nought opened with.
  final List<StrategyUnit> mine;

  /// The crowd and the ground it walks on.
  StrategySimulation get simulation => match.simulation;
}

/// Where a match on [level] ends: the document's `goal` section, which the
/// level format carries through without knowing it. A map without one never
/// ends by a line; it still ends when the ground runs out.
MatchGoal strategyGoalOf(Level level) => MatchGoal(
  delivered: switch (level.toJson()['goal']) {
    {'delivered': final num line} => line.toDouble(),
    _ => double.infinity,
  },
);

/// Opens the match [level] describes, after checking it with
/// [strategyLevelValidator]; a level with no heightfield is refused with a
/// [LevelFormatException], since this genre is played on ground made of
/// samples.
///
/// [workers] overrides how many stand in each block. [seed] is the one the
/// dice start on. [goal] defaults to [strategyGoalOf]. Every side but
/// nought is played by a [Bot].
StrategyOpening openStrategyLevel(
  Level level, {
  MatchGoal? goal,
  int? workers,
  int seed = 1,
}) {
  final ground = level.heightfield;
  if (ground == null) {
    throw LevelFormatException(
      'the map "${level.name}" has no heightfield, and this game is played '
      'on ground made of samples',
    );
  }
  strategyLevelValidator.assertValid(level);
  final simulation = StrategySimulation(
    ground: ground,
    random: GameRandom(seed),
    sides: _sides(level),
  );

  // Halls first, then seams, then everything that points at one of them, so
  // the order entities are written in does not matter.
  final halls = <String, Building>{
    for (final EntityDef it in level.ofType(StrategyLevelTypes.camp))
      it.name!: simulation.build(
        Building(
          center: it.position,
          width: it.number('width')!,
          depth: it.number('depth')!,
          name: it.name!,
          side: it.integer('side') ?? 0,
        ),
      ),
  };
  final seams = <String, ResourceNode>{
    for (final EntityDef it in level.ofType(StrategyLevelTypes.resourceNode))
      it.name!: simulation.addResource(
        ResourceNode(at: it.position, amount: it.number('amount')!),
      ),
  };
  for (final EntityDef it in level.ofType(StrategyLevelTypes.producer)) {
    simulation.addProducer(
      Producer(
        building: halls[it.string('target')]!,
        cost: it.number('cost') ?? 25.0,
        seconds: it.number('seconds') ?? 4.0,
      ),
    );
  }
  for (final EntityDef it in level.ofType(StrategyLevelTypes.stockpile)) {
    simulation.stock[it.integer('side') ?? 0].amount = it.number('amount')!;
  }

  final mine = <StrategyUnit>[];
  for (final EntityDef it in level.ofType(StrategyLevelTypes.worker)) {
    final side = it.integer('side') ?? 0;
    final count = workers ?? it.integer('count')!;
    final across = it.integer('across') ?? count;
    final spacing = it.number('spacing')!;
    final digs = seams[it.string('digs')]!;
    final home = halls[it.string('home')]!;
    for (var i = 0; i < count; i++) {
      final unit = simulation.add(
        StrategyUnit(
          position: Vector3(
            it.position.x + (i % across) * spacing,
            0.0,
            it.position.z + (i ~/ across) * spacing,
          ),
          side: side,
        ),
      );
      // A job each: a `HarvestJob` remembers what its unit carries.
      unit.job = HarvestJob(node: digs, dropOff: home);
      if (side == 0) mine.add(unit);
    }
  }

  return StrategyOpening(
    match: Match(
      simulation: simulation,
      bots: <Bot>[
        for (final MapEntry<String, Building> it in halls.entries)
          if (it.value.side != 0) Bot(side: it.value.side, base: it.value),
      ],
      goal: goal ?? strategyGoalOf(level),
    ),
    mine: mine,
  );
}

/// The highest side named, plus one.
int _sides(Level level) =>
    1 +
    level.entities.fold(0, (int most, EntityDef it) {
      final side = it.integer('side') ?? 0;
      return side > most ? side : most;
    });

/// The entity kinds a strategy map may name.
const List<EntityKind> strategyLevelKinds = <EntityKind>[
  _CampKind(),
  _WorkerKind(),
  _ResourceNodeKind(),
  _StockpileKind(),
  _ProducerKind(),
];

/// What a strategy map must be to be played.
final LevelValidator strategyLevelValidator = LevelValidator(
  registry: EntityRegistry(strategyLevelKinds),
  rules: const <LevelRule>[
    AtLeastOne(
      StrategyLevelTypes.camp,
      because: 'a match with no camps has nobody in it',
      severity: LevelIssueSeverity.error,
    ),
    AtLeastOne(
      StrategyLevelTypes.resourceNode,
      because: 'a map with nothing to dig cannot be won',
      severity: LevelIssueSeverity.error,
    ),
  ],
);

final class _CampKind extends EntityKind {
  const _CampKind() : super(StrategyLevelTypes.camp);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _requireName(entity, scope, out, 'so nothing can be told to carry to it');
    _requireSide(entity, scope, out);
    _requirePositive(entity, scope, out, 'width');
    _requirePositive(entity, scope, out, 'depth');
  }
}

final class _ResourceNodeKind extends EntityKind {
  const _ResourceNodeKind() : super(StrategyLevelTypes.resourceNode);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _requireName(entity, scope, out, 'so nobody can be sent to dig it');
    _requirePositive(entity, scope, out, 'amount');
  }
}

final class _ProducerKind extends EntityKind {
  const _ProducerKind() : super(StrategyLevelTypes.producer);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    _requirePositive(entity, scope, out, 'cost');
    _requirePositive(entity, scope, out, 'seconds');
  }
}

final class _StockpileKind extends EntityKind {
  const _StockpileKind() : super(StrategyLevelTypes.stockpile);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _requireSide(entity, scope, out);
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
  const _WorkerKind() : super(StrategyLevelTypes.worker);

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
  final side = entity.integer('side');
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
  final value = entity.number(key);
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

void _requireNamed(
  EntityDef entity,
  LevelScope scope,
  List<LevelIssue> out,
  String key,
) {
  final named = entity.string(key);
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
