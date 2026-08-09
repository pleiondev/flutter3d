import 'package:vector_math/vector_math.dart';

import 'collision_shape.dart';
import 'collision_world.dart';

/// How a collider takes part in the world.
///
/// The same three roles Flame's `CollisionType` names, with the meanings a 3D
/// game needs: what blocks movement, what moves under its own control, and what
/// only reports that something passed through it.
enum ColliderKind {
  /// Never moves, blocks movement. Level geometry.
  static,

  /// Moved by game logic rather than by physics, blocks movement, and carries
  /// anything standing on it. Doors, lifts, platforms.
  kinematic,

  /// Blocks nothing and reports overlap. Pickups, damage volumes, the button at
  /// the end of a corridor, the line that finishes the level.
  ///
  /// The reason this belongs in the collision system rather than beside it: a
  /// second system with its own broadphase and its own idea of what overlaps
  /// what is a second system that can disagree with the first one, and the
  /// disagreements show up as a pickup you cannot collect while standing
  /// visibly inside it.
  trigger,
}

/// Bit flags deciding which colliders see each other.
///
/// A collider takes part in a test when each side is in the other's mask. That
/// is what keeps a rocket from colliding with the player who fired it, a
/// monster from blocking a hitscan meant for the wall behind it, and a
/// player-only trigger from firing when a monster walks over it.
abstract final class CollisionLayers {
  static const int world = 1 << 0;
  static const int player = 1 << 1;
  static const int monster = 1 << 2;
  static const int projectile = 1 << 3;
  static const int pickup = 1 << 4;
  static const int trigger = 1 << 5;

  static const int all = 0xFFFFFFFF;

  /// Everything solid enough to stop a body.
  static const int solid = world | player | monster;
}

/// Told when colliders begin, continue and stop overlapping.
///
/// Attached to a [Collider], the way Flame attaches `CollisionCallbacks` to a
/// component. `self` is always the collider the listener belongs to, so an
/// implementation never has to work out which of the two it is.
///
/// A mixin class rather than an interface so a monster or a pickup can take the
/// three defaults and override only the one it cares about — which is almost
/// always [onCollisionStart].
abstract mixin class CollisionListener {
  void onCollisionStart(Collider self, Collider other) {}

  /// Called for every step the pair stays overlapping, the first one excepted.
  void onCollision(Collider self, Collider other) {}

  void onCollisionEnd(Collider self, Collider other) {}
}

/// A shape, somewhere, that takes part in collision.
final class Collider {
  Collider({
    required this.shape,
    Vector3? position,
    this.kind = ColliderKind.static,
    this.layer = CollisionLayers.world,
    this.mask = CollisionLayers.all,
    CollisionListener? listener,
    this.userData,
  }) : position = position?.clone() ?? Vector3.zero() {
    // Through the field rather than the setter: there is no world to notify
    // yet, and the setter would be a call into nothing.
    _listener = listener;
  }

  CollisionShape shape;

  /// Centre of the shape, in world space.
  final Vector3 position;

  ColliderKind kind;

  /// Which layer this collider is on.
  int layer;

  /// Which layers this collider tests against.
  int mask;

  /// The world this collider is in, once it has been added to one.
  ///
  /// Assigned by [CollisionWorld.add] and cleared by its remove. Public only
  /// because the two are in different files.
  CollisionWorld? world;

  CollisionListener? _listener;

  /// Told what this collider touches, if anything wants to know.
  ///
  /// Null for the overwhelming majority — every brush in the level — and the
  /// world only walks colliders that have one, so silence is free.
  CollisionListener? get listener => _listener;

  /// Attaching one after the collider is already in the world has to be heard.
  ///
  /// It is the normal case, not the exception: a mechanism wraps a collider the
  /// level reader placed a moment earlier, and before this was a setter that
  /// trigger never fired and nothing said so.
  set listener(CollisionListener? value) {
    if (identical(_listener, value)) return;
    _listener = value;
    world?.refreshReporter(this);
  }

  /// Whatever the game wants to find its way back to: a monster, a pickup, the
  /// definition of the door this collider belongs to.
  ///
  /// Untyped because the physics has no business knowing any of those types,
  /// and a generic parameter would spread through every query signature to buy
  /// one cast at the call site.
  Object? userData;

  /// How far this collider moved during the current step.
  ///
  /// Only meaningful for [ColliderKind.kinematic], and only the character
  /// controller reads it — to carry a player standing on a lift, which
  /// collision response alone cannot do.
  final Vector3 delta = Vector3.zero();

  /// True when this collider blocks movement.
  bool get isSolid => kind != ColliderKind.trigger;

  /// Whether [other] and this one should be tested at all.
  bool interactsWith(Collider other) =>
      (mask & other.layer) != 0 && (other.mask & layer) != 0;

  /// Moves the collider, recording the motion for anything riding it.
  void moveTo(Vector3 to) {
    delta.setFrom(to - position);
    position.setFrom(to);
  }

  void clearDelta() => delta.setZero();

  /// Cached bounds, refreshed by the world when it indexes this collider.
  final Aabb3 bounds = Aabb3();

  void refreshBounds() => shape.computeBounds(position, bounds);
}
