/// The particle simulation `flutter3d_particles` draws, headless.
///
/// [ParticleSystem] is one pool for a whole application: emission, ageing and
/// [ParticleAffector]s advance every particle in it, and [ParticleGlow] and
/// `LightEmitter` are read from the same buffer a renderer would draw rather
/// than a second generator running alongside it.
///
/// **No Flutter, no renderer.** `particle_contributor.dart` and
/// `mesh_particle_contributor.dart` are the two files in
/// `flutter3d_particles` that ever imported Flutter; everything else already
/// lived here, one `import` line away from the sibling packages this depends
/// on. That is what lets a headless caller — `flutter3d_model_core`'s own
/// `BakeParticleSystemCommand` — bake a system into a cache on the Dart VM,
/// the same way it already bakes a rigid body through `flutter3d_physics`.
library;

export 'src/flipbook.dart';
export 'src/light_emitter.dart';
export 'src/particle.dart';
export 'src/particle_affector.dart';
export 'src/particle_curve.dart';
export 'src/particle_emitter.dart';
export 'src/particle_random.dart';
export 'src/particle_system.dart';
export 'src/shown.dart';
