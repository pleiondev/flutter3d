import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../actors/actor.dart';
import '../actors/actor_system.dart';
import '../world/mechanism.dart';
import 'level.dart';

/// A piece of level geometry that an entity brought with it.
///
/// Doors, lifts, platforms, buttons and keys all place a box that the player
/// has to be able to see. The simulation places it; something has to draw it;
/// and the two must not be the same code, or the game engine ends up importing
/// the renderer. So the engine reports a fixture and the application decides
/// what a fixture looks like.
final class Fixture {
  Fixture({
    required this.entity,
    required Vector3 size,
    required this.material,
    this.collider,
    Vector3? at,
    this.mechanism,
  })  : size = size.clone(),
        _at = (at ?? collider?.position ?? Vector3.zero()).clone();

  /// What the document said, for anything the application wants that the
  /// engine did not think to pass on.
  final EntityDef entity;

  /// The body in the world, when there is one.
  ///
  /// Null for anything that is only looked at — a torch bracket, a stained
  /// window. Giving those a collider so the field could stay non-null would
  /// mean shapes in the broadphase that nothing ever tests, and a player
  /// catching on the scenery.
  final Collider? collider;

  final Vector3 _at;

  final Vector3 size;

  /// Name of an entry in the level's materials.
  final String material;

  /// What runs it, when anything does. Null for scenery.
  final Mechanism? mechanism;

  /// Where to draw. Follows the collider when there is one, because that keeps
  /// moving after this is reported — which is the whole point of a lift.
  Vector3 get position => collider?.position ?? _at;
}

/// What an entity is given when it is asked to become real.
///
/// Grows a field per system as the game does. A context rather than a long
/// parameter list because every [EntityKind.spawn] takes the same set and most
/// kinds use one of it.
final class SpawnContext {
  SpawnContext({
    required this.world,
    required this.actors,
    required this.mechanisms,
    this.onActorSpawned,
    this.onFixture,
  });

  final CollisionWorld world;
  final ActorSystem actors;
  final MechanismWorld mechanisms;

  /// Told about each actor as it appears.
  ///
  /// The hook exists because the simulation has no idea what anything looks
  /// like, and the application does: this is where a body gets a mesh. Keeping
  /// it a callback rather than having the spawner build one is what stops the
  /// game engine from needing the renderer.
  final void Function(Actor actor)? onActorSpawned;

  /// Told about each box an entity placed. See [Fixture].
  final void Function(Fixture fixture)? onFixture;

  /// Reports a fixture, reading its size and material off the entity.
  ///
  /// On the context rather than at each call site so the five kinds that place
  /// a box cannot disagree about which property holds the material.
  void reveal(
    EntityDef entity, {
    Collider? collider,
    Mechanism? mechanism,
    Vector3? size,
  }) {
    final hook = onFixture;
    if (hook == null) return;
    hook(
      Fixture(
        entity: entity,
        collider: collider,
        at: entity.position,
        size: size ?? entity.vector('size') ?? Vector3.all(1.0),
        material: entity.string('material') ?? 'default',
        mechanism: mechanism,
      ),
    );
  }
}
