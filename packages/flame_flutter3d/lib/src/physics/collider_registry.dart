import 'package:flame/collisions.dart' show CollisionCallbacks;
import 'package:flame/components.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';

import 'collision_bridge.dart';

/// Which Flame component each collider belongs to, for a [CollisionBridge]
/// to hand over as the other side of a contact.
///
/// **The map every game with contacts kept by hand.** A collider knows
/// nothing of Flame, so `resolveOther` had to be answered from a map the game
/// filled when it made a body and emptied when the body went, and a body
/// removed without emptying it was a contact reported against a component no
/// longer in the game. Here an entry leaves when its component is removed
/// from the game, on its own, and comes back if the component is added
/// again, a pooled ship say. A component moved to another parent keeps it:
/// Flame moves by removing and mounting at once, and the move dropped the
/// entry for good.
final class ColliderRegistry {
  final Map<Collider, PositionComponent> _components =
      <Collider, PositionComponent>{};

  /// Which registration of a collider is the live one: a watch left over
  /// from an earlier one, or from before [unregister], does nothing.
  final Expando<Object> _tickets = Expando<Object>();

  /// [collider] belongs to [component] while [component] is in a game,
  /// until [unregister] is called.
  void register(Collider collider, PositionComponent component) {
    final ticket = _tickets[collider] = Object();
    _components[collider] = component;
    _watch(collider, component, ticket);
  }

  void _watch(Collider collider, PositionComponent component, Object ticket) {
    component.removed.then((_) {
      if (!identical(_tickets[collider], ticket)) return;
      if (component.isMounted) {
        _watch(collider, component, ticket);
        return;
      }
      _components.remove(collider);
      component.mounted.then((_) {
        if (!identical(_tickets[collider], ticket)) return;
        _components[collider] = component;
        _watch(collider, component, ticket);
      });
    });
  }

  /// [collider] belongs to nothing any more.
  void unregister(Collider collider) {
    _tickets[collider] = null;
    _components.remove(collider);
  }

  /// The component [collider] belongs to, or null for level geometry and
  /// anything else nothing on the Flame side stands for.
  PositionComponent? componentFor(Collider collider) => _components[collider];

  /// Relays [collider]'s contacts to [component], the other side of each
  /// looked up here. [collider] is usually [component]'s body's, and may be a
  /// sensor riding on it.
  CollisionBridge bridge({
    required Collider collider,
    required CollisionCallbacks component,
  }) => CollisionBridge(
    collider: collider,
    component: component,
    resolveOther: componentFor,
  );
}
