/// Every monster in the maze, where it came from, and how to write it down.
///
/// ## Why a crawl keeps its own list
///
/// A snapshot restores into a world that already exists: bodies and brains
/// are filled in, not rebuilt. That was enough for a level whose monsters are
/// all placed by the document, and it is not enough here, where nearly every
/// monster was born during play. Loaded afresh, a save would find none of them
/// to fill; rolled back past a birth, it would find one too many.
///
/// So the horde records, for each monster, what kind it is, which generator
/// made it and which entity it was, in the order the actor system steps them.
/// Restoring takes the current horde away, puts the entity allocation back,
/// builds each monster again under its own entity, and only then lets the
/// entity save pour the numbers in — see `EcsWorld.vacant`. Same entity, same
/// order, so the monsters think on the same beat as the run that was saved.
///
/// **The dead are removed, not left lying.** A corpse per kill is two hundred
/// corpses a minute, each a trigger in the broadphase for nothing.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'generator.dart';
import 'monster_kind.dart';

/// Walks at the hero the flow field gives it and bites, or strikes once.
///
/// Which hero to chase is the engine's answer each step and what kind of
/// monster it is is the horde's, so all it remembers is how much it has dealt
/// — which matters only to a kind with an [MonsterKind.appetite].
final class Chaser extends Brain {
  Chaser(this.kind);

  final MonsterKind kind;

  /// Damage dealt so far, before armour.
  double dealt = 0.0;

  /// How far past touching a blow still lands: a body stops a millimetre
  /// short of another, and a monster pressed against a hero must reach.
  static const double reach = 0.15;

  /// Half the width of whatever it chases. A hero's.
  static const double quarry = 0.35;

  @override
  void act(Mind it) {
    it.steerTowardsFocus();
    final heading = it.heading;
    it.turnTowards(heading.x, heading.z);
    if (it.distance > kind.radius + quarry + reach) return;
    if (kind.touch > 0.0) {
      if (it.hurtFocus(it.focusBody, kind.touch)) {
        it.system.hurt(it.actor, double.infinity);
      }
      return;
    }
    if (kind.bite <= 0.0) return;
    final amount = kind.bite * it.dt;
    if (!it.hurtFocus(it.focusBody, amount)) return;
    dealt += amount;
    // Had its fill: gone, and nobody gets the credit for it.
    if (dealt >= kind.appetite) it.system.hurt(it.actor, double.infinity);
  }

  @override
  Map<String, Object?> save() => <String, Object?>{'dealt': dealt};

  @override
  void restore(Map<String, Object?> from) =>
      dealt = (from['dealt'] as num?)?.toDouble() ?? 0.0;
}

final class Horde {
  Horde(this.actors, {this.kinds = MonsterKind.all});

  final ActorSystem actors;

  /// What a save may name, by [MonsterKind.name].
  final List<MonsterKind> kinds;

  final Map<Actor, ({MonsterKind kind, Generator? from})> _members =
      <Actor, ({MonsterKind kind, Generator? from})>{};

  /// Every monster alive, in the order they were born.
  Iterable<Actor> get monsters => _members.keys;

  int get count => _members.length;

  /// What [monster] is, or null for an actor that is not one of these.
  MonsterKind? kindOf(Actor monster) => _members[monster]?.kind;

  /// How many of [generator]'s monsters are alive.
  int countFrom(Generator generator) {
    var alive = 0;
    for (final member in _members.values) {
      if (identical(member.from, generator)) alive++;
    }
    return alive;
  }

  /// Brings a monster into the maze, standing at [at].
  ///
  /// [entity] is for [restore] alone: a monster built again under the entity
  /// it had when the save was taken.
  Actor spawn(MonsterKind kind, Vector3 at, {Generator? from, Entity? entity}) {
    final monster = actors.spawn(
      body: CharacterController(
        world: actors.world,
        shape: CollisionBox(
          Vector3(kind.radius, kind.height / 2.0, kind.radius),
        ),
        position: at,
        tuning: MovementTuning(walkSpeed: kind.speed),
        layer: CollisionLayers.actor,
      ),
      health: Health(kind.health),
      brain: kind.mind(kind),
      facing: Facing(),
      entity: entity,
    );
    _members[monster] = (kind: kind, from: from);
    return monster;
  }

  /// Takes the dead out of the world.
  void bury() {
    final dead = <Actor>[
      for (final monster in _members.keys)
        if (!monster.isAlive) monster,
    ];
    for (final monster in dead) {
      _members.remove(monster);
      actors.remove(monster);
    }
  }

  /// Each monster's kind, maker and entity, in the order they are stepped.
  List<Map<String, Object?>> save() => <Map<String, Object?>>[
    for (final actor in actors.actors)
      if (_members[actor] case final member?)
        <String, Object?>{
          'kind': member.kind.name,
          if (member.from?.name case final String name) 'from': name,
          'index': actor.entity.index,
          'generation': actor.entity.generation,
        },
  ];

  /// Builds the horde [rows] describe, and restores [entities] into it.
  ///
  /// [generators] finds a generator by the name a row gives. A row naming a
  /// kind this horde does not know, or an entity the allocation does not have
  /// free, is dropped: an older save with less in it still loads.
  void restore(
    Object? rows,
    Map<String, Object?>? entities, {
    required Generator? Function(String name) generators,
  }) {
    for (final monster in _members.keys.toList(growable: false)) {
      actors.remove(monster);
    }
    _members.clear();
    if (entities == null) return;
    actors.entities.restore(entities);
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final kind = _kindNamed(row['kind']);
        final index = row['index'];
        final generation = row['generation'];
        if (kind == null || index is! num || generation is! num) continue;
        final entity = Entity.of(index.toInt(), generation.toInt());
        if (!actors.entities.vacant(entity)) continue;
        final from = row['from'];
        spawn(
          kind,
          Vector3.zero(),
          from: from is String ? generators(from) : null,
          entity: entity,
        );
      }
    }
    // Again, now that there are bodies and brains for the numbers to go into.
    actors.entities.restore(entities);
  }

  MonsterKind? _kindNamed(Object? name) {
    for (final kind in kinds) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}
