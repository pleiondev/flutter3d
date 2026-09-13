# flutter3d_particles_core

The pooled particle simulation `flutter3d_particles` draws: emission, ageing,
affectors, curves and gradients.

**No Flutter and no renderer in it.** That is the boundary this package exists
to keep: it runs under `dart test`, and `flutter3d_model_core`'s
`BakeParticleSystemJobRequest` depends on it directly so baking a particle system
into a cache stays a headless operation, the same way baking a rigid body
already runs through `flutter3d_physics` rather than through a package that
needs a window.

```dart
final system = ParticleSystem(capacity: 256, seed: 7);
system.emit(
  #torch,
  ParticleEffect(
    count: 1,
    emitter: const SphereEmitter(speed: Range.exact(1.0)),
    lifetime: const Range.exact(0.6),
    size: const Range.exact(0.05),
    color: Vector4(1, 0.6, 0.1, 1),
  ),
  Vector3.zero(),
  perSecond: 40,
);

system.advance(1 / 60);
```

## Deterministic on purpose

The same `seed` and the same sequence of `advance` calls give byte-identical
particles — what a golden of a burning torch needs, and what
`flutter3d_model_core`'s own bake of a particle system into a
`SimulationCache` relies on rather than adds.

## `flutter3d_particles` depends on this, not the other way round

`ParticleSystem`, its emission and affectors moved out of
`flutter3d_particles` unchanged; only the two files that ever imported
Flutter — the pass contributor and the mesh contributor that draw a system —
stayed behind. `flutter3d_particles` re-exports this package's public API, so
nothing that already imports
`package:flutter3d_particles/flutter3d_particles.dart` has anything to change.
