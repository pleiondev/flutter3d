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
export 'src/fire_exposure.dart';
export 'src/gpu.dart';
export 'src/gpu_unavailable.dart';
// The core's own ClothMesh and ClothSettings by the names CoreClothMesh and
// CoreClothSettings: flutter3d_physics, which a game imports beside this,
// has the plain names for the cloth every backend steps.
export 'src/native_cloth.dart'
    hide
        ClothMesh,
        ClothPacked,
        ClothSettings,
        createCoreCloth,
        packClothBalls,
        writeClothSettings;
export 'src/native_cloth_simulation.dart' hide packClothObstacles;
export 'src/native_debris.dart'
    hide packDebrisBodies, packDebrisStatics, writeDebrisSettings;
export 'src/native_dynamics.dart';
export 'src/native_fluid.dart' hide packFluidParticles, writeFluidSettings;
export 'src/native_force_fields.dart';
export 'src/native_liquid.dart' hide liquidWalls;
export 'src/native_particles.dart' hide packParticles, writeParticleForces;
export 'src/native_physics.dart';
export 'src/native_ragdoll.dart';
export 'src/native_world.dart';
