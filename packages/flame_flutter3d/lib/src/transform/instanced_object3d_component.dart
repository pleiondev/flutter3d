import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'object3d_component.dart' show shownInFlame;
import 'plane.dart';

/// A Flame [PositionComponent] drawn as one instance of a shared
/// [InstancedMeshNode]: a shot, a spark, an invader in a row of fifty-five.
///
/// **What [Object3dComponent] is for many small things of one shape.** Each
/// [Object3dComponent] is a node and a draw; a hundred shots in the air were
/// a hundred draws of one rod. This one takes a slot in [batch] when it is
/// mounted, writes its Flame transform into the slot every frame the way
/// [Object3dComponent] writes a node's, and gives the slot back when it is
/// removed. The batch is one draw however many are in the air.
///
/// Flowing one way only, Flame to the scene: nothing but this component
/// writes the slot, so there is nothing to read back.
///
/// **[batch] sits at the scene's origin, unturned.** An instance's transform
/// is in the batch node's space, and this writes the scene position there
/// as it is. Add the batch to the scene's root and leave it.
///
/// **Hidden is collapsed.** An instance has no visibility of its own, so a
/// component Flame hides ([HasVisibility.isVisible]) writes a transform of
/// zeros into its slot, which draws nothing. Removed, it gives the slot up
/// at once rather than on Flame's next lifecycle pass, so it is not drawn
/// a frame after the game let it go.
class InstancedObject3dComponent extends PositionComponent with HasVisibility {
  InstancedObject3dComponent({
    required this.batch,
    required this.plane,
    this.elevation = 0.0,
    this.color,
    super.position,
    super.size,
    super.anchor,
    super.angle,
    super.scale,
    super.children,
    super.priority,
    super.key,
  });

  /// The batch this component takes a slot in.
  final InstancedMeshNode batch;

  /// The 2D↔3D axis mapping the transform is written through.
  final BridgePlane plane;

  /// Metres off [plane] along its normal, as [Object3dComponent.elevation].
  double elevation;

  /// The instance's tint, white when null. Read when the slot is taken.
  final Vector4? color;

  InstanceHandle? _slot;

  /// The slot this component draws through, while it is mounted.
  InstanceHandle? get slot => _slot;

  final Matrix4 _transform = Matrix4.zero();
  final Vector3 _scale = Vector3.zero();

  /// Where this component is in the scene: its absolute Flame position on
  /// [plane], lifted by [elevation].
  Vector3 get scenePosition =>
      plane.to3d(absolutePosition, at: plane.constant + elevation);

  @override
  void onMount() {
    super.onMount();
    _slot = batch.acquire(color: color);
    _write();
  }

  @override
  void removeFromParent() {
    _giveBack();
    super.removeFromParent();
  }

  @override
  void onRemove() {
    _giveBack();
    super.onRemove();
  }

  @override
  void updateTree(double dt) {
    super.updateTree(dt);
    _write();
  }

  void _giveBack() {
    final slot = _slot;
    _slot = null;
    if (slot != null && slot.live) batch.release(slot);
  }

  void _write() {
    final slot = _slot;
    if (slot == null) return;
    if (!shownInFlame(this)) {
      slot.setTransform(_transform..setZero());
      return;
    }
    final s = absoluteScale;
    final across = (s.x.abs() + s.y.abs()) / 2.0;
    switch (plane.axis) {
      case PlaneAxis.y:
        _scale.setValues(s.x, across, s.y);
      case PlaneAxis.z:
        _scale.setValues(s.x, s.y, across);
    }
    _transform.setFromTranslationRotationScale(
      scenePosition,
      plane.rotationFor(absoluteAngle),
      _scale,
    );
    slot.setTransform(_transform);
  }
}
