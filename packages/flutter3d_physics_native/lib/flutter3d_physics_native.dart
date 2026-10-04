/// The physics core of flutter3d in C11 — P9.
///
/// Rigid bodies owned and stepped by the core: natively a library this
/// package's hook builds with the C compiler the target already uses,
/// reached through `dart:ffi`; in the browser the same core as a
/// WebAssembly module, reached through `dart:js_interop` — one API over
/// both. `flutter3d_physics` is the pure-Dart reference it is held to, and
/// the fallback where it cannot run.
library;

export 'src/core/load.dart';
export 'src/gpu.dart';
export 'src/native_cloth.dart'
    hide ClothPacked, createCoreCloth, packClothBalls, writeClothSettings;
export 'src/native_debris.dart'
    hide packDebrisBodies, packDebrisStatics, writeDebrisSettings;
export 'src/native_fluid.dart' hide packFluidParticles, writeFluidSettings;
export 'src/native_particles.dart' hide packParticles, writeParticleForces;
export 'src/native_world.dart';
