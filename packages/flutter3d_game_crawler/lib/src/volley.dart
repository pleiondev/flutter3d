/// The heroes' shots in flight.
///
/// A shot is a point that moves in a straight line and stops at the first
/// thing it reaches: a wall, a door, a monster, a generator. It passes through
/// heroes — four players firing down one corridor would otherwise spend the
/// game shooting each other in the back — and it is swept, a ray the length
/// of one step's flight, so a fast one cannot step over a thin monster.
///
/// Kept by the crawl rather than by the engine's projectile system, which
/// carries the shooter's blasts and splash; a crawl's shot is a line and a
/// number, and it has to be in the crawl's save.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'hero.dart';

final class Bolt {
  Bolt({
    required this.owner,
    required Vector3 at,
    required Vector3 direction,
    required this.damage,
    required this.speed,
    required this.range,
  }) : at = at.clone(),
       direction = direction.clone();

  /// Who fired it, for the score its kill is worth.
  final Hero owner;

  final Vector3 at;
  final Vector3 direction;
  final double damage;
  final double speed;

  /// Metres it may still fly.
  double range;
}

/// What a bolt reached this step.
typedef BoltHit = ({Bolt bolt, Object? target});

final class Volley {
  Volley(this.collision);

  final CollisionWorld collision;

  /// How far a shot flies before it is gone, in metres.
  static const double reach = 30.0;

  final List<Bolt> _bolts = <Bolt>[];
  final List<BoltHit> _hits = <BoltHit>[];
  final RayHit _ray = RayHit();

  List<Bolt> get bolts => List<Bolt>.unmodifiable(_bolts);

  /// Fires one from [hero], from the middle of their body along their facing.
  Bolt fire(Hero hero) {
    final bolt = Bolt(
      owner: hero,
      at: hero.position,
      direction: hero.facing,
      damage: hero.kind.shotDamage,
      speed: hero.kind.shotSpeed,
      range: reach,
    );
    _bolts.add(bolt);
    return bolt;
  }

  /// Moves every bolt one step, and answers what each that stopped reached:
  /// the collider's owner, or null for a wall.
  ///
  /// The list is reused; read it before the next call.
  List<BoltHit> step(double dt) {
    _hits.clear();
    for (var i = _bolts.length - 1; i >= 0; i--) {
      final bolt = _bolts[i];
      final flight = bolt.speed * dt < bolt.range
          ? bolt.speed * dt
          : bolt.range;
      final struck = collision.raycast(
        bolt.at,
        bolt.direction,
        flight,
        _ray,
        mask: CollisionLayers.world | CollisionLayers.actor,
        includeTriggers: false,
      );
      if (struck) {
        _hits.add((bolt: bolt, target: _ray.collider?.userData));
        _bolts.removeAt(i);
        continue;
      }
      bolt.at.addScaled(bolt.direction, flight);
      bolt.range -= flight;
      if (bolt.range <= 0.0) _bolts.removeAt(i);
    }
    // Oldest first, so what a step reports does not depend on the removal
    // walk running backwards.
    return _hits.reversed.toList(growable: false);
  }

  List<Map<String, Object?>> save() => <Map<String, Object?>>[
    for (final bolt in _bolts)
      <String, Object?>{
        'owner': bolt.owner.slot,
        'at': <double>[bolt.at.x, bolt.at.y, bolt.at.z],
        'direction': <double>[
          bolt.direction.x,
          bolt.direction.y,
          bolt.direction.z,
        ],
        'damage': bolt.damage,
        'speed': bolt.speed,
        'range': bolt.range,
      },
  ];

  /// Puts back what [save] wrote. [heroes] finds a hero by slot; a bolt whose
  /// owner is not there is dropped.
  void restore(Object? from, Hero? Function(int slot) heroes) {
    _bolts.clear();
    if (from is! List) return;
    for (final row in from) {
      if (row is! Map) continue;
      final data = row.cast<String, Object?>();
      final slot = data['owner'];
      final owner = slot is num ? heroes(slot.toInt()) : null;
      if (owner == null) continue;
      final at = Vector3.zero();
      final direction = Vector3.zero();
      if (!data.vectorInto('at', at) ||
          !data.vectorInto('direction', direction)) {
        continue;
      }
      _bolts.add(
        Bolt(
          owner: owner,
          at: at,
          direction: direction,
          damage: (data['damage'] as num?)?.toDouble() ?? 0.0,
          speed: (data['speed'] as num?)?.toDouble() ?? 0.0,
          range: (data['range'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }
  }
}
