import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'plane.dart';

/// Which side of an [Object3dComponent] writes a frame's transform into the
/// other.
///
/// Nothing infers a direction from which value "changed more recently" —
/// two systems can each believe the other is the one reading, and a
/// transform that no caller ever explicitly wrote into would still look
/// changed to whichever side polled it first. A direction chosen once, at
/// construction, is one field instead of a heuristic.
enum SyncDirection {
  /// This component's flutter3d [SceneNode] is authoritative; its position
  /// and rotation are copied onto the Flame side every frame. What every
  /// existing flutter3d system already owns — a rigid body, an actor — is
  /// scene-authoritative, so [RigidBodyComponent] and [ActorComponent] both
  /// default to this.
  sceneToFlame,

  /// This component's Flame [PositionComponent] is authoritative; its
  /// position and angle are copied onto the flutter3d [SceneNode] every
  /// frame — a Flame-driven prop that should also draw as a 3D billboard,
  /// say.
  flameToScene,
}

/// A Flame [PositionComponent] and a flutter3d [SceneNode] kept at the same
/// place, on one [BridgePlane], one [direction] deciding who writes.
///
/// **Lifecycle follows Flame's.** [onMount] adds [node] to [scene]; [onRemove]
/// calls `node.removeFromParent()`. A [SceneNode] never outlives the
/// component that owns it, and never needs a caller to remember to detach
/// it by hand — the same guarantee `CameraNode.onAttachedToScene` already
/// gives a [Scene]'s own registries.
class Object3dComponent extends PositionComponent {
  Object3dComponent({
    required this.node,
    required this.scene,
    required this.plane,
    this.direction = SyncDirection.sceneToFlame,
    super.position,
    super.angle,
    super.scale,
    super.children,
    super.priority,
    super.key,
  });

  /// The flutter3d node this component is bridged to.
  final SceneNode node;

  /// The scene [node] is added to on mount and removed from on unmount.
  final Scene scene;

  /// The 2D↔3D axis mapping this component reads and writes through.
  final BridgePlane plane;

  /// Which side is authoritative each frame. See [SyncDirection].
  final SyncDirection direction;

  @override
  void onMount() {
    super.onMount();
    if (node.parent == null) scene.add(node);
  }

  @override
  void onRemove() {
    node.removeFromParent();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    switch (direction) {
      case SyncDirection.sceneToFlame:
        position = plane.to2d(node.readPosition());
        angle = plane.angleFor(node.readRotation());
      case SyncDirection.flameToScene:
        node.setPositionFrom(plane.to3d(position));
        node.setRotation(plane.rotationFor(angle));
    }
  }
}
