/// Re-fires flutter3d's own [CollisionListener] events as calls into
/// Flame's [CollisionCallbacks] surface, for one [Collider] at a time.
library;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';

import 'rigid_body_component.dart';

/// A plain Dart object, not a [Component] — it draws nothing and has no
/// per-frame update of its own. All it does is sit as [collider]'s
/// [CollisionListener] and translate what [CollisionWorld] tells it into
/// calls on [component]'s [CollisionCallbacks] methods.
///
/// Constructing one attaches it: `collider.listener = this` happens in the
/// constructor, so a caller wires a bridge into the world simply by building
/// it, the same way `RigidBodyComponent` needs no separate "activate" step
/// once it exists.
///
/// ## The reference mismatch, and why nothing here papers over it
///
/// flutter3d's [CollisionListener] reports a pair of [Collider]s.
/// [CollisionCallbacks] wants a [PositionComponent]. `flutter3d_physics`
/// does not know Flame exists, so a [Collider] never carries a component
/// back to hand one over — a caller has to say how to find it, and
/// [resolveOther] is that answer: a lookup into whatever registry of
/// collider-to-component the caller already keeps (one entry per bridged
/// [RigidBodyComponent], typically). **When [resolveOther] returns null —
/// the other side of the contact is level geometry, a physics-only body
/// with no Flame component, or anything else nothing on the Flame side
/// represents — this bridge calls nothing.** There is no
/// [PositionComponent] to hand [CollisionCallbacks] in that case, and
/// inventing one, or routing the event to [component] with a null other,
/// would tell Flame code something untrue: that it collided with something
/// that, from Flame's point of view, does not exist. This is the collision
/// contact shape mismatch flagged as a real design commitment rather than
/// an oversight — silence is the correct behaviour, not a gap to fill
/// later.
///
/// ## The contact shape mismatch
///
/// flutter3d's collision system reports overlap as a pair of colliders —
/// there is no manifold, and [Contact] (built by `contactBetween`, which
/// this class does not call) carries only a normal and a depth even when
/// something does compute one. Flame's own signature has no room for either:
/// [CollisionCallbacks.onCollisionStart] and `.onCollision` take a
/// `Set<Vector2>` of intersection points and nothing else. This bridge does
/// not try to synthesize a normal or a depth into that set — it has nowhere
/// to put them, and inventing a fake one would be worse than sending none.
/// What it sends instead is the cheapest honest stand-in for "roughly where
/// this touched": the midpoint of the two colliders' centres, projected
/// through [component]'s own [BridgePlane] via `plane.to2d`. For two
/// axis-aligned boxes that midpoint sits inside the overlap region along
/// whichever axis penetrated least, which is close enough to "where they
/// touch" for a callback whose real job is handing over a component
/// reference, not reporting physics. A caller that needs the actual normal
/// or depth reads [Collider.listener]'s own flutter3d-side callback
/// directly — this bridge relays the event onward, it does not replace the
/// flutter3d-side one.
final class CollisionBridge with CollisionListener {
  CollisionBridge({
    required this.collider,
    required this.component,
    required this.resolveOther,
  }) {
    collider.listener = this;
  }

  /// The flutter3d collider whose events this bridge relays. Bridged the
  /// moment this object is constructed.
  final Collider collider;

  /// The Flame-side component [collider] belongs to — the target every
  /// relayed callback lands on.
  final RigidBodyComponent component;

  /// Finds the [PositionComponent] bridged to the *other* collider in a
  /// contact, or null when nothing on the Flame side represents it.
  ///
  /// Typically a lookup into a `Map<Collider, PositionComponent>` the
  /// caller keeps — one entry per bridged component — since a bare
  /// [Collider] carries nothing back to whatever Flame component (if any)
  /// it belongs to.
  final PositionComponent? Function(Collider other) resolveOther;

  @override
  void onCollisionStart(Collider self, Collider other) {
    final target = resolveOther(other);
    if (target == null) return;
    component.onCollisionStart(_pointFor(self, other), target);
  }

  @override
  void onCollision(Collider self, Collider other) {
    final target = resolveOther(other);
    if (target == null) return;
    component.onCollision(_pointFor(self, other), target);
  }

  @override
  void onCollisionEnd(Collider self, Collider other) {
    final target = resolveOther(other);
    if (target == null) return;
    component.onCollisionEnd(target);
  }

  /// The midpoint of [self] and [other]'s centres, on [component]'s plane,
  /// as the one-element point set Flame's callback signature wants. See
  /// this class's own doc comment for why a midpoint and not a real contact
  /// point.
  Set<Vector2> _pointFor(Collider self, Collider other) => {
    component.plane.to2d((self.position + other.position) * 0.5),
  };
}
