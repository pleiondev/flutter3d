/// An event that says where it happened.
library;

import 'package:vector_math/vector_math.dart';

/// An event that says where it happened, so an effect started by it knows
/// where to go off.
///
/// **The bus carries no positions of its own**: an event is a name and a
/// digest. An event class that has a place mixes this in (`extends BusEvent
/// with PlacedEvent`), and every effect document triggered by it lands there
/// with no code in between — `ElementExploded` does. Anything else is placed
/// by the `EffectPlacer` the effects were added with, or by the trigger's own
/// `at`.
///
/// **A `base mixin class`**, beside the `BusEvent` an event already extends:
/// what a minor adds here arrives with a body, as [direction] has one.
///
/// Here rather than beside the effects that read it (`flutter3d_particles`),
/// so an event of the simulation can say where it happened without the
/// simulation depending on what draws it.
abstract base mixin class PlacedEvent {
  /// Where, in scene space: the float32 offset from `Scene.origin` the
  /// effect is drawn at (see "Space" in `docs/CONTRACTS.md`).
  Vector3 get at;

  /// Which way an effect should lean — a surface normal, a blast's up — or
  /// null for the emitter's own shape, which it is by default.
  Vector3? get direction => null;
}
