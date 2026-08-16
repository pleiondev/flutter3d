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

/// The one layer constant that means the same thing in every game.
///
/// A collider takes part in a test when each side is in the other's mask —
/// that rule is this package's, and it is what keeps a rocket from colliding
/// with the player who fired it and a player-only trigger from firing when
/// something else walks over it.
///
/// **Which bit means what is not this package's business.** This class used to
/// name `world`, `player`, `monster`, `projectile`, `pickup` and `trigger`,
/// which was three names too many the moment a collision world stopped being
/// part of one game. A game declares its own; see `CollisionLayers` in
/// `flutter3d_game`, which still names those five and forwards [all] here.
///
/// Two of the old six went nowhere: `projectile` and `solid` had no user
/// anywhere in the workspace, so they were deleted rather than moved.
abstract final class Layers {
  /// Every bit set. The default mask: see everything, and let the other side
  /// decide whether it wants to be seen.
  static const int all = 0xFFFFFFFF;
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
    // Bit zero, which a game usually calls its world. Written as a number
    // because naming it here is the mistake this package was extracted to
    // stop making.
    this.layer = 1 << 0,
    this.mask = Layers.all,
    CollisionListener? listener,
    this.userData,
  }) : position = position?.clone() ?? Vector3.zero() {
    // Through the field rather than the setter: there is no world to notify
    // yet, and the setter would be a call into nothing.
    _listener = listener;
    refreshBounds();
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

  /// How fast this collider's *surface* drags whatever stands on it, in m/s.
  ///
  /// Independent of [delta], and the difference is the whole point: a lift
  /// moves, so its transform changed and [delta] says by how much; a conveyor
  /// belt does not move at all and only its skin does. Both carry a passenger,
  /// and until this existed only the first could.
  ///
  /// A travelator, a river, a boost pad, an escalator and a rotating disc
  /// (roughly) are all this vector. The engine never learns which.
  ///
  /// Read by the character controller when it decides what is carrying it.
  /// Zero on everything by default, so nothing changes for a collider that
  /// never sets it.
  final Vector3 surfaceVelocity = Vector3.zero();

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

  /// Where the broadphase last saw this collider.
  ///
  /// [moveTo] moves [position] and nothing else — the grid is rebuilt once a
  /// step, and until it is, [bounds] describes where this was when it was last
  /// indexed. That is one step behind for anything that has moved this step,
  /// and it has to be, because a narrow phase testing a mover where it *is*
  /// while the grid answers for where it *was* misses it in whichever cell it
  /// has left: the collider is never handed to the test at all.
  ///
  /// So this is the position every query moves a body against, named rather
  /// than fished back out of the middle of [bounds].
  final Vector3 indexedAt = Vector3.zero();

  void refreshBounds() {
    shape.computeBounds(position, bounds);
    indexedAt.setFrom(position);
  }
}
