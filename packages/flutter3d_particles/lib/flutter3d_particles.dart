/// Particles for flutter3d: a pooled simulation, and one draw call.
///
/// An extension rather than part of the engine. Nothing in `flutter3d` names a
/// particle now — the last thread was two shader handles `Renderer.create`
/// required and no code read, so an application that draws no particles could
/// not start a renderer.
///
/// **The shaders stay in `flutter3d_shaders`.** That package is already the
/// shared GLSL every backend compiles from — Impeller into a bundle, WebGL by
/// translation, and the CPU backend as Dart transcriptions — so `particle.vert`
/// living there while the simulation lives here is the arrangement that package
/// exists for, not a layering violation. Moving them is a five-package change
/// with no user-visible benefit and belongs to whenever a second extension
/// wants a shader of its own.
///
/// ## What is here
///
/// [ParticleSystem] is one pool for the whole application, not one per effect:
/// a system per effect is a draw call per effect, and on this engine a pipeline
/// change is the most expensive state change there is.
///
/// [ParticleGlow] and [LightEmitter] are the part worth having. A fire *is* its
/// particles, so the light it casts is measured from them rather than produced
/// by a second wobble running alongside — two generators of one quantity
/// disagree eventually, and the disagreement looks like a flame burning
/// brightly while the light it casts has gone out.
library;

export 'src/light_emitter.dart';
export 'src/particle.dart';
export 'src/particle_affector.dart';
export 'src/particle_contributor.dart';
export 'src/mesh_particle_contributor.dart';
export 'src/particle_curve.dart';
export 'src/particle_emitter.dart';
export 'src/particle_random.dart';
export 'src/particle_system.dart';
