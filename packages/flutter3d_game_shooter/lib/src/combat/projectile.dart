import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'blast.dart';
import 'projectile_types.dart';

export 'projectile_types.dart';

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
  }) : _resolver = BlastResolver(world),
       entities = entities ?? EcsWorld() {
    this.entities.components
      ..register<InFlight>(
        ComponentCodec<InFlight>.of(
          id: 'inFlight',
          encode: (value) => value.toJson(),
          decode: (data, _) => InFlight.fromJson(data),
        ),
      )
      ..register<FiredBy>(
        ComponentCodec<FiredBy>.of(
          id: 'firedBy',
          encode: (value) => _ownerKey(value.collider),
          decode: (data, _) => switch (_ownerNamed(data)) {
            final Collider owner => FiredBy(owner),
            null => null,
          },
        ),
      );
  }

  final CollisionWorld world;

  /// Where the rockets live.
  ///
  /// **Shared with the actors**: the staging hands the run's one world to
  /// both, which the shooter's plugin puts in the loop's snapshots (the run
  /// is a part) and its published worlds, so a rollback and the view cover
  /// the rockets with nothing more said. A caller that passes nothing gets a
  /// world of its own, which is for a test or a tool that steps the rockets
  /// alone.
  final EcsWorld entities;

  /// The most that may be in the air at once.
  final int capacity;

  /// How fat a rocket is, for the sweep. Not zero: a point squeezes through the
  /// seam between two brushes that meet exactly.
  /// In metres.
  final double radius;

  final BlastResolver _resolver;

  final Map<String, Collider> _named = <String, Collider>{};

  /// Gives [owner] a [name] a save can carry, for a launcher that is not an
  /// actor in [entities]: the player, a turret the game built itself.
  ///
  /// **Why a rocket's owner is saved at all.** It was excluded, as a live
  /// object in one process; a restore then cleared it, and after a rollback
  /// or a rewind a rocket in the air met its own launcher a step out of the
  /// muzzle and credited nobody, so the resimulated step was not the step
  /// that was recorded. An actor's collider is named by its entity, whose
  /// body a restore keeps in place; anything else is named here, and an
  /// owner with no name is still left out, as before.
  void nameOwner(String name, Collider owner) => _named[name] = owner;

  /// What a save writes for [owner]: `{"named": …}`, `{"entity": [index,
  /// generation]}`, or null for an owner nobody named.
  Object? _ownerKey(Collider owner) {
    for (final MapEntry(:key, :value) in _named.entries) {
      if (identical(value, owner)) return <String, Object?>{'named': key};
    }
    if (owner.userData case final Actor actor) {
      final body = entities.get<Body>(actor.entity);
      if (identical(body?.controller.collider, owner)) {
        return <String, Object?>{
          'entity': <int>[actor.entity.index, actor.entity.generation],
        };
      }
    }
    return null;
  }

  /// The collider [key], one [_ownerKey] wrote, names here, or null.
  Collider? _ownerNamed(Object? key) => switch (key) {
    {'named': final String name} => _named[name],
    {'entity': [final int index, final int generation]} =>
      entities.get<Body>(Entity.of(index, generation))?.controller.collider,
    _ => null,
  };

  /// Explosions produced by the last [step], for the game to react to.
  ///
  /// Reported rather than applied here: this knows how far a blast reaches, and
  /// nothing about health, death animations or sound.
  final List<Detonation> detonations = <Detonation>[];

  /// Rockets dropped because the air was full. Worth watching rather than
  /// hiding — a number that climbs means the cap is wrong.
  int get dropped => _dropped;
  int _dropped = 0;

  int get activeCount => entities.queryOf<InFlight>().length;

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
    entities.set(
      entity,
      InFlight(
        position: position,
        velocity: velocity,
        blast: blast,
        life: life,
      ),
    );
    if (owner != null) entities.set(entity, FiredBy(owner));
    return true;
  }

  void clear() {
    for (final entity in entities.queryOf<InFlight>()) {
      entities.despawn(entity);
    }
    detonations.clear();
  }

  void step(double dt) {
    detonations.clear();
    final shape = CollisionSphere(radius);

    for (final entity in entities.queryOf<InFlight>()) {
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
