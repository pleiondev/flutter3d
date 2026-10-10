/// An event that says where it happened.
library;

import 'package:vector_math/vector_math.dart';

/// An event that says where it happened, so an effect started by it knows
/// where to go off.
///
/// **The bus carries no positions of its own**: an event is a name and a
/// digest. An event class that has a place implements this, and every
/// effect document triggered by it lands there with no code in between —
/// `ElementExploded` does. Anything else is placed by the `EffectPlacer` the
/// effects were added with, or by the trigger's own `at`.
///
/// Here rather than beside the effects that read it (`flutter3d_particles`),
/// so an event of the simulation can say where it happened without the
/// simulation depending on what draws it.
abstract interface class PlacedEvent {
  /// Where, in scene space: the float32 offset from `Scene.origin` the
  /// effect is drawn at (see "Space" in `docs/CONTRACTS.md`).
  Vector3 get at;

  /// Which way an effect should lean — a surface normal, a blast's up — or
  /// null for the emitter's own shape.
  Vector3? get direction;
}
