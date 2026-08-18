import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'blast.dart';

/// A rocket in flight: where it is, where it is going, and how long it has.
///
/// **The first component in this repository**, and the first thing to move out
/// of a hand-written pool. It was a `Projectile` with an `alive` flag in a
/// fixed array, which is a pool emulating what spawn and despawn already are.
///
/// Everything on it is saved, which is the rule a component earns its place
/// by: a type either writes itself down or says why it does not.
final class InFlight {
  InFlight({
    required Vector3 position,
    required Vector3 velocity,
    required this.blast,
    required this.life,
  })  : position = position.clone(),
        velocity = velocity.clone();

  final Vector3 position;
  final Vector3 velocity;

  /// What it does when it arrives.
  final Blast blast;

  /// Seconds left before it gives up and detonates.
  double life;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': <double>[position.x, position.y, position.z],
        'velocity': <double>[velocity.x, velocity.y, velocity.z],
        'life': life,
        'blast': <String, double>{
          'radius': blast.radius,
          'damage': blast.damage,
          'minimumFraction': blast.minimumFraction,
          'knockback': blast.knockback,
        },
      };

  static InFlight fromJson(Object? data) {
    final row = (data! as Map).cast<String, Object?>();
    final blast = (row['blast']! as Map).cast<String, Object?>();
    return InFlight(
      position: _vector(row['at']),
      velocity: _vector(row['velocity']),
      life: (row['life']! as num).toDouble(),
      blast: Blast(
        radius: (blast['radius']! as num).toDouble(),
        damage: (blast['damage']! as num).toDouble(),
        minimumFraction: (blast['minimumFraction'] as num?)?.toDouble() ?? 0.0,
        knockback: (blast['knockback'] as num?)?.toDouble() ?? 0.0,
      ),
    );
  }

  static Vector3 _vector(Object? value) {
    final row = value! as List;
    return Vector3(
      (row[0] as num).toDouble(),
      (row[1] as num).toDouble(),
      (row[2] as num).toDouble(),
    );
  }
}

/// Who fired it, so the sweep can ignore the muzzle it came out of.
///
/// **The example `EcsWorld.exclude` exists for.** A `Collider` is a live object
/// in one process's collision world; writing it into a save would mean
/// inventing an identity scheme for every body in the level to serve a field
/// that stops mattering the moment the rocket has cleared its own launcher.
/// So it is declared as not saved, with the reason, rather than quietly left
/// out of a codec — which is what the hand-written version did.
final class FiredBy {
  const FiredBy(this.collider);
  final Collider collider;
}

/// Where and what an explosion was.
final class Detonation {
  Detonation({
    required Vector3 position,
    required Vector3 normal,
    required this.blast,
    required this.damage,
    required this.owner,
  })  : position = position.clone(),
        normal = normal.clone();

  final Vector3 position;

  /// Surface the rocket struck, or the direction it came from when it timed
  /// out in the open. Effects need somewhere to face.
  final Vector3 normal;

  final Blast blast;

  /// Everything hurt, and by how much. Includes the shooter.
  final Map<Collider, double> damage;

  final Collider? owner;
}

/// Everything currently in the air.
///
/// ## Swept, not stepped
///
/// A rocket travels forty metres a second, which is two thirds of a metre
/// between one simulation step and the next — further than a wall is thick. A
/// projectile moved by adding velocity and then asked whether it is inside
/// something passes cleanly through thin geometry, and the faster the
/// projectile the more reliably it does so. Every move is a sweep.
///
/// ## Entities, not a pool
///
/// This held a fixed array of `Projectile` objects with an `alive` flag, which
/// is a pool emulating spawn and despawn. It holds entities now, and the
/// difference that matters is not the ceremony: **it no longer writes its own
/// save.** `EcsWorld.save()` writes every component on every entity, and
/// refuses to write a component type nobody registered — so the next thing
/// that flies through the air cannot be left out of a save file by omission.
///
/// The cap survives the move. Sixty-four rockets at once is already far past
/// anything the game produces, and something that grows without limit under
/// load grows during the exact frame that was already struggling.
final class ProjectileSystem {
  ProjectileSystem({
    required this.world,
    EcsWorld? entities,
    this.capacity = 64,
    this.radius = 0.12,
  })  : _resolver = BlastResolver(world),
        entities = entities ?? EcsWorld() {
    this.entities
      ..register<InFlight>(
        'inFlight',
        encode: (InFlight value) => value.toJson(),
        decode: InFlight.fromJson,
      )
      ..exclude<FiredBy>(
        'a collider is a live object in one process, and the field stops '
        'mattering the moment the rocket has cleared its own launcher',
      );
  }

  final CollisionWorld world;

  /// Where the rockets live.
  ///
  /// Injected so that the next system to move across shares it and one
  /// `save()` covers both. While exactly one system has moved, a caller that
  /// passes nothing gets a world of its own and nothing is worse off.
  final EcsWorld entities;

  /// The most that may be in the air at once.
  final int capacity;

  /// How fat a rocket is, for the sweep. Not zero: a point squeezes through the
  /// seam between two brushes that meet exactly.
  final double radius;

  final BlastResolver _resolver;

  /// Explosions produced by the last [step], for the game to react to.
  ///
  /// Reported rather than applied here: this knows how far a blast reaches, and
  /// nothing about health, death animations or sound.
  final List<Detonation> detonations = <Detonation>[];

  /// Rockets dropped because the air was full. Worth watching rather than
  /// hiding — a number that climbs means the cap is wrong.
  int get dropped => _dropped;
  int _dropped = 0;

  int get activeCount => entities.query<InFlight>().length;

  final SweepHit _hit = SweepHit();
  final Vector3 _delta = Vector3.zero();
  final Vector3 _normal = Vector3.zero();

  /// Launches one. Returns false when the air was full.
  bool spawn({
    required Vector3 position,
    required Vector3 direction,
    required double speed,
    required Blast blast,
    Collider? owner,
    double life = 6.0,
  }) {
    if (activeCount >= capacity) {
      _dropped++;
      return false;
    }
    final velocity = direction.normalized()..scale(speed);
    final entity = entities.spawn();
    entities.set(entity, InFlight(
      position: position,
      velocity: velocity,
      blast: blast,
      life: life,
    ));
    if (owner != null) entities.set(entity, FiredBy(owner));
    return true;
  }

  void clear() {
    for (final entity in entities.query<InFlight>()) {
      entities.despawn(entity);
    }
    detonations.clear();
  }

  void step(double dt) {
    detonations.clear();
    final shape = CollisionSphere(radius);

    for (final entity in entities.query<InFlight>()) {
      final rocket = entities.get<InFlight>(entity)!;

      rocket.life -= dt;
      if (rocket.life <= 0.0) {
        _normal
          ..setFrom(rocket.velocity)
          ..normalize()
          ..scale(-1.0);
        _detonate(entity, rocket, rocket.position, _normal);
        continue;
      }

      _delta
        ..setFrom(rocket.velocity)
        ..scale(dt);

      if (!world.sweep(
        shape,
        rocket.position,
        _delta,
        _hit,
        ignore: entities.get<FiredBy>(entity)?.collider,
      )) {
        rocket.position.add(_delta);
        continue;
      }

      // Stop just short of the surface, so the explosion happens in the room
      // rather than inside the wall — which would put the geometry between the
      // blast and everything it should have hurt.
      final travel = _hit.fraction;
      rocket.position
        ..x += _delta.x * travel + _hit.normal.x * 0.02
        ..y += _delta.y * travel + _hit.normal.y * 0.02
        ..z += _delta.z * travel + _hit.normal.z * 0.02;

      _detonate(entity, rocket, rocket.position, _hit.normal);
    }
  }

  void _detonate(Entity entity, InFlight rocket, Vector3 at, Vector3 normal) {
    final owner = entities.get<FiredBy>(entity)?.collider;
    entities.despawn(entity);
    final damage = <Collider, double>{};
    _resolver.resolve(rocket.blast, at, damage);
    detonations.add(
      Detonation(
        position: at,
        normal: normal,
        blast: rocket.blast,
        damage: damage,
        owner: owner,
      ),
    );
  }
}
