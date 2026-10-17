import 'package:flame/components.dart' show Component;
import 'package:flame/effects.dart' show ComponentEffect;
import 'package:flutter3d/flutter3d.dart' show LinearColor;
import 'package:vector_math/vector_math.dart' show Aabb3;

import 'bridge_space.dart';
import 'plane.dart';

/// What a bridged component is to the parts of the bridge that find it or
/// draw round it: a tap, a debug outline of its hitboxes. Both
/// `Object3dComponent` and `InstancedObject3dComponent` are one.
///
/// **An instance is a bridged component too.** Taps and hitbox outlines
/// asked for an `Object3dComponent`, and an invader drawn as one instance of
/// fifty-five could neither be tapped nor have its hitbox seen.
///
/// **Mixed in, not implemented** (`extends PositionComponent with
/// Bridged3d`): a base mixin class, so a member a minor adds arrives with a
/// body and a component written against 1.0 keeps compiling. What it can
/// answer for itself it does: no [elevation], no [space], nothing drawn.
abstract base mixin class Bridged3d implements Drawn3d {
  /// The plane its Flame point is on.
  BridgePlane get plane;

  /// Metres off [plane] along its normal; none by default.
  double get elevation => 0.0;

  /// Where its Flame point is placed instead of flat on [plane], if bent;
  /// flat by default.
  BridgeSpace? get space => null;

  @override
  Aabb3? get drawnBounds3d => null;

  /// The linear colour what it draws is multiplied by: what a
  /// [TintEffect] moves.
  @override
  abstract LinearColor tint;
}

/// What a tap asks of anything drawn in the scene: where it is drawn, and
/// its colour. Every [Bridged3d] is one, and so is a `Node3dComponent`,
/// which stands in full 3D rather than on a plane.
///
/// **Mixed in, not implemented** (`extends Component with Drawn3d`): a base
/// mixin class, so a member a minor adds arrives with a body and a
/// component written against 1.0 keeps compiling.
abstract base mixin class Drawn3d {
  /// The box in the scene round what it draws, or null when it draws
  /// nothing: what a tap is tested against. Nothing by default.
  Aabb3? get drawnBounds3d => null;

  /// The linear colour what it draws is multiplied by, assigned whole.
  abstract LinearColor tint;
}

/// Moves a bridged component's [Bridged3d.tint] to a colour, as Flame's
/// `ColorEffect` moves a sprite's paint: a hit flash, a wreck charring.
///
/// **Flame's own `ColorEffect` cannot reach it.** That effect wants a
/// component with a paint, and a bridged component draws in 3D, with none;
/// a hit flash was a timer and two assignments in the game. This moves the
/// tint from wherever it is when the effect starts to [color], on any
/// `EffectController`: alternating for a flash, one way for a fade.
base class TintEffect extends ComponentEffect<Component> {
  /// An effect taking the tint to [color], linear.
  TintEffect(LinearColor color, super.controller, {super.onComplete, super.key})
    : _to = color;

  final LinearColor _to;
  LinearColor _from = LinearColor.white;

  Drawn3d get _drawn => switch (target) {
    final Drawn3d drawn => drawn,
    _ => throw UnsupportedError('A TintEffect is for a bridged component.'),
  };

  @override
  void onStart() {
    super.onStart();
    _from = _drawn.tint;
  }

  @override
  void apply(double progress) =>
      _drawn.tint = LinearColor.lerp(_from, _to, progress);
}
