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
/// from the game, on its own.
final class ColliderRegistry {
  final Map<Collider, PositionComponent> _components =
      <Collider, PositionComponent>{};

  /// [collider] belongs to [component] until [component] is removed from
  /// its game, or [unregister] is called.
  void register(Collider collider, PositionComponent component) {
    _components[collider] = component;
    component.removed.then((_) {
      if (identical(_components[collider], component)) {
        _components.remove(collider);
      }
    });
  }

  /// [collider] belongs to nothing any more.
  void unregister(Collider collider) => _components.remove(collider);

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
