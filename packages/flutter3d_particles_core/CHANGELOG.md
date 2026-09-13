## 0.6.0

* **Extracted from `flutter3d_particles`, byte for byte.** `ParticleSystem`,
  its emission, ageing, affectors, curves and gradients moved here unchanged —
  only `particle_contributor.dart` and `mesh_particle_contributor.dart`, the
  two files that ever imported Flutter, stayed behind. `flutter3d_particles`
  depends on this package and re-exports it, so nothing that already imports
  `package:flutter3d_particles/flutter3d_particles.dart` has anything to
  change.
* No Flutter and no renderer in it, which is the boundary the package exists
  to keep: it runs under `dart test`, and `flutter3d_model_core`'s
  `BakeParticleSystemCommand` depends on it directly rather than on
  `flutter3d_particles`, so baking a particle system into a cache stays a
  headless operation.
