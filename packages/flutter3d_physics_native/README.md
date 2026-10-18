# flutter3d_physics_native

The physics core of flutter3d, written in C11 and reached through `dart:ffi`. In the browser it runs as a WebAssembly module built from the same sources. `flutter3d_physics`, the pure-Dart physics, is its reference and its fallback.

It is being built in phases (P9 in the 0.9 plan). What is here now:

- rigid bodies named by generational handles, so a handle kept past its body is refused;
- contacts between every pair of shapes, turned, with closed forms where there are some and GJK and EPA where there are not: manifolds of up to four points, events when a contact begins and ends, collision filters, and islands that sleep and wake together;
- a solver that keeps bodies apart: soft contacts in substeps with warm starting, friction and restitution, so crates rest, stack, slide, roll and bounce;
- a dynamic tree of boxes for the broadphase, which also answers box queries;
- triangle meshes for level geometry and terrain, one sided, that bodies slide across without catching on the seams;
- joints: fixed, spherical, hinge, slider and distance (rod, spring, rope), with limits, motors and springs, the ball joint's cone, twist limits and friction, swing limits ahead, behind and to either side, and viscous damping and soft limits, which a ragdoll is built from (give one eight substeps);
- continuous collision: contacts that reach as far as a body moves in a step, and bullets swept to their time of impact, turn and all;
- rays, shape overlaps and shape casts, and a kinematic character controller that slides, climbs steps and keeps to slopes;
- vehicles: a chassis on up to eight wheels, each a ray with a spring, a damper and a tyre that grips inside its friction circle, steered, driven and braked a wheel at a time;
- shapes (sphere, box, capsule, cylinder, cone, convex hull, and any of them rounded, and compounds of up to sixty-four of them placed and turned on one body) as inertia, surface and drag; the orientation stepped with the angular momentum kept, impulses, forces, torques, damping and sleep;
- the air and its wind, uniform or from a grid, and the drag it puts on a body;
- heat on every body, by convection, radiation and across its contacts, and fire: wood, paper and rubber catch, burn their fuel, lose mass and give off hot gas, and water puts them out;
- an origin held in doubles that the world can move to where the play is;
- events, and snapshots a world restores from to the byte;
- particles that fall, drift in the wind, bounce off a floor and die, on the CPU and, through the hardware layer, on a GPU.
- debris, the visual bodies: thousands of balls that tumble, heap and settle on still planes and boxes, on the CPU and, through the hardware layer, on a GPU, where they are read a frame or two late.
- cloth: sheets and ropes held by constraints of any stiffness, blown by the wind, on the CPU and, through the hardware layer, on a GPU. On the CPU a sheet can also drape over the same obstacles the Dart solver handles (balls, capsules, boxes, wedges and heightfields), with friction and self-collision. `usePhysics().cloth(mesh)` returns the core's cloth, or the Dart solver when the run is on the reference.
- water as particles in a tank that slumps, splashes and settles, on the CPU and, through the hardware layer, on a GPU.
- the liquids of `flutter3d_physics` — the spilt particles (position-based fluid with cohesion), a stream's parcels in the air (falling, running along and clinging to the glass) and the waves on a vessel's surface — stepped as the Dart reference steps them, against the planes and turned glassware a `FluidWorld` makes; and the liquid in pipes between vessels and the bodies floating in them. `usePhysics().fluid` is the core's solver, or the Dart one when the run is on the reference; a `FluidWorld` asks for it when it is made.

## Under CollisionWorld

`NativeDynamics` is a `RigidDynamics` from `flutter3d_physics`. Build it where a game built a `Dynamics`:

```dart
final dynamics = NativeDynamics(world: collisionWorld); // was Dynamics(world: collisionWorld)
final crate = dynamics.add(RigidBody(world: collisionWorld, shape: CollisionBox(Vector3.all(0.5)), position: at));
```

The bodies stay `RigidBody` objects on the `CollisionWorld`, so sweeps, queries and the character controller see them where the core put them. The rest of the world (level boxes, wedges, height fields, characters, doors, lifts) is mirrored into the core as fixed bodies each step. The core turns bodies built with `canRotate`, and `native` reaches its joints, bullets and air. It steps in f32 to bits of its own, the same on every platform, so a run's digests differ from the reference's. For rollback, use `snapshot()` and `restore()`: unlike a body's own `save()`, they carry the warm starts and sleep.

Multibodies (`createMultibody`) hold a tree of bodies in reduced coordinates, so a long chain with a heavy end keeps its joints together where separate joints would stretch.

## Building

There is nothing to build by hand. The package's hook compiles `csrc/` with the C compiler the target already uses: Xcode's clang on Apple platforms, the NDK's on Android, MSVC or clang on Windows, the system's on Linux. A game that depends on this package needs no other toolchain.

There are no GPU passes to build. The particles, debris, cloth and fluid tank are published as kernels in the engine's kernel language too (`particleKernels`, `debrisKernels`, `clothKernels`, `fluidKernels`, beside `shallowWaterKernels`), and `flutter3d_effects` hands each to a renderer as a compute workload (`ParticleCloudWorkload`, `DebrisWorkload`, `ClothWorkload`, `FluidWorkload`). Where it runs is the hardware layer's to say: on the GPU that draws the frame, on the compute sidecar beside it, or on this package's own CPU system. This package names no device and links no GPU library: the core alone is about 0.5 MB (`libf3d_physics`, macOS arm64, 2026-10-13).

The Dart side reaches the core the same way natively and in the browser: through `lib/src/core/`, where every call is a function and every pointer an address. The calls and the layouts of the structs the Dart side fills are generated from `csrc/include/f3d_physics.h`; after changing the header, run

```sh
dart run tool/gen_core.dart
```

and `test/bindings_test.dart` fails until you do. Call `await preparePhysics()` before making the first world. In the browser it loads the core; natively there is nothing to load. Either way it makes the core the run's `PhysicsBackend` if it starts, and the Dart reference if it does not, and `usePhysics()` returns that backend afterwards. `loadPhysicsCore()` is the lower-level call that `preparePhysics()` uses. With `threads:` above one, on a page served cross-origin isolated (COOP and COEP headers), it loads `web/f3d_physics_threads.wasm` instead and starts that many Web Workers less one from `web/f3d_worker.js`; `physicsCoreThreads` then says how many threads a world can ask for. In the browser it fetches `web/f3d_physics.wasm`, which this package ships as an asset; after changing the core, rebuild it with `dart run tool/build_wasm.dart`, or `test/wasm_test.dart` fails.

The WebAssembly module is built separately, because hooks build for native targets only:

```sh
dart run tool/build_wasm.dart build/f3d_physics.wasm
```

That needs a clang with the wasm32 target, which Apple's has, and a wasm linker. Either `wasm-ld` on the path works, or the `rust-lld` that a Rust toolchain ships.

## Determinism

The deterministic mode uses the same bits on every platform. Every number is an f32, and the build turns off fused multiply-add contraction and fast math. The core also avoids the C library's transcendental functions; the square root it does use is rounded exactly by IEEE 754 on every target. `test/wasm_test.dart` holds that promise to the byte: the WebAssembly module and the native library step the same scenario, and their snapshots of the whole world afterwards have to be identical.

`csrc/tests/test_digest.c` holds the same promise across machines: it steps seven scenes and fails unless they hash to the numbers written in it. Those numbers were taken on macOS arm64, and the same numbers come out on Linux (arm64, x86-64 and 32-bit ARM, with gcc and with clang), on the iOS simulator and on Android arm64. CI runs the test on Windows with MSVC. `tool/digest_platforms.sh` repeats the Linux, Android and iOS runs from a Mac. 32-bit x86 qualifies only with its arithmetic in SSE2. There, gcc and clang both match. On the x87, which gcc (and Debian's clang) use there by default, the results come out different. So the core refuses to build that way, and the hook passes `-msse2 -mfpmath=sse`.

Built with `-DF3D_REAL_DOUBLE`, the core uses doubles throughout instead. That build is for C callers who want the precision and do not need the browser to agree; the Dart bindings refuse it.

The core is the `deterministic` profile's engine. Under `SimulationProfile.accurate`, which promises double maths and adaptive steps rather than bits, a simulation runs the Dart engine in `flutter3d_physics`, and native cloth refuses a profile that is not bit-exact so its owner falls back to the Dart cloth. Two things are exact in doubles here under either profile: a body's place in the world, a `WorldPosition` with the origin added, and the laws and expressions the core evaluates.

## The liquid's pair loops as kernels

The loops over pairs of neighbours that a spilt liquid's substep is made of (its density, colour-field normals, cohesion and curvature, the density constraint and its correction, XSPH's viscosity) are written once in the kernel language, as `liquidPairKernels`, over flat buffers and compressed neighbour rows. `KernelLiquid` is a `FluidSolver` that steps the particles with them; the walls, the moves and the neighbour rows stay on the host, in Dart.

```dart
// flutter3d_effects, which speaks to devices; this package names none.
final liquid = await placeKernelLiquid(FrameCompute.of(device));
final world = FluidWorld(gravity: gravity, solver: liquid);
```

Where the loops run is the hardware layer's to say, and the simulation imports nothing that draws: `placeKernelLiquid` in `flutter3d_effects` asks `FrameCompute.placeHosted` and builds the solver on the executor the work landed on. Under a bit-exact profile (`SimulationProfile.deterministic`, the default) the work requires `ComputeRequirement.bitExact`: the kernels divide and take square roots, which a GPU computes only to within a tolerance, so a GPU is passed over and they run on the CPU kernel, their Dart translation rounded to f32 after every operation, which gives the same bytes on every machine and in the browser. Where the run need not replay, the device's or the sidecar's compute takes them if it reads back in the same turn.

Beside the kernels there is a native CPU executor, the work's own host code: the same loops in C (`csrc/lanes/`), summing two, four or eight neighbours at a time on the processor's NEON, AVX2 or AVX-512F lanes, chosen when first asked rather than when built. The hook builds it as a library apart from the core, with `-O3` and none of the core's deterministic flags, and builds nothing, without failing, where there is no C compiler. It runs in doubles and adds in another order, so it is held to the CPU kernel within `KernelLiquid.nativeTolerance` (one substep's positions within a part in ten thousand of the spacing, its velocities within a part in ten thousand of the fastest; on a squeezed block they are a few tenths of a nanometre apart) and is refused under a bit-exact profile. To the hardware layer it is a placement of its own, `ComputePlacement.nativeSimd`: `placeKernelLiquid` hands it over as `NativeLanes` with that tolerance, the rule decides when it runs, `KernelLiquid.native` builds it, and `KernelLiquid.isNativeLanes` says which ran. There is no native executor in the browser.

## Laws in the core

A body's material can follow its temperature. `NativeWorld.setMaterialLaws(body, material)` gives the core the specific heat, conductivity and emissivity laws of a `PhysicalMaterial`, tables and formulas alike, compiled to the expression language's bytecode. Each step begins by evaluating them at the body's temperature. `NativeExpression` runs any expression of the language in the core, such as a probe's derived quantity. The C interpreter (`csrc/src/f3d_expr.c`) computes in binary64 on the same portable maths as Dart's in both builds, and `test/law_parity_test.dart` holds the two to the bit on every expression fixture and every law of the catalogue. In the f32 core a body's temperature is an f32 and the value a law writes into its material is rounded to f32 once; the test holds that value to Dart's at the same f32 temperature, rounded the same way. A world that sets no law steps exactly as before.

## Tests

```sh
dart test
```

The suite does four things:

- builds the C unit tests in `csrc/tests/` with the address and undefined-behaviour sanitisers, in both precisions, and runs them;
- checks the hand-written bindings against the header;
- drives the world through `dart:ffi` and compares a free fall, a box spun off its axes and an impulse off the centre with `flutter3d_physics`. Those comparisons use a tolerance, because the reference works in doubles;
- burns, wets and blows on bodies through the binding, and holds unturned contacts against `flutter3d_physics`;
- drops a crate on a floor and holds where it comes to rest against `flutter3d_physics`;
- steps a thousand particles on the GPU and on the CPU and compares them. A GPU rounds its own way, so this is a tolerance too. The test is skipped where there is no adapter;
- pours debris on both and compares it: body for body where nothing chaotic happens, and as a heap where it does;
- hangs cloth on both and compares it the same way: point for point until it wrinkles;
- breaks a dam of water on both, particle for particle until it splashes;
- builds the WebAssembly module and runs it in node, so the byte-for-byte comparison above actually happens. This test is skipped where node, clang or a wasm linker is missing.

The browser has its own test, run in Chrome with both web compilers:

```sh
dart test -p chrome test/web_core_test.dart
dart test -p chrome -c dart2wasm test/web_core_test.dart
CHROME_EXECUTABLE=tool/chrome_sab.sh dart test -p chrome test/web_threads_test.dart
```

The last runs on Chrome asked for SharedArrayBuffer outright by `tool/chrome_sab.sh`, since the test runner's pages are not isolated; without it the test is skipped.
