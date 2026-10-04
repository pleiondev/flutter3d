# flutter3d_physics_native

The physics core of flutter3d, written in C11 and reached through `dart:ffi`. In the browser it runs as a WebAssembly module built from the same sources. `flutter3d_physics`, the pure-Dart physics, is its reference and its fallback.

It is being built in phases (P9 in the 0.9 plan). What is here now:

- rigid bodies named by generational handles, so a handle kept past its body is refused;
- contacts between every pair of shapes, turned, with closed forms where there are some and GJK and EPA where there are not: manifolds of up to four points, events when a contact begins and ends, collision filters, and islands that sleep and wake together;
- a solver that keeps bodies apart: soft contacts in substeps with warm starting, friction and restitution, so crates rest, stack, slide, roll and bounce;
- a dynamic tree of boxes for the broadphase, which also answers box queries;
- triangle meshes for level geometry and terrain, one sided, that bodies slide across without catching on the seams;
- joints: fixed, spherical, hinge, slider and distance (rod, spring, rope), with limits, motors and springs;
- continuous collision: contacts that reach as far as a body moves in a step, and bullets swept to their time of impact, turn and all;
- rays, shape overlaps and shape casts, and a kinematic character controller that slides, climbs steps and keeps to slopes;
- shapes (sphere, box, capsule, cylinder, cone, convex hull, and any of them rounded) as inertia, surface and drag; the orientation stepped with the angular momentum kept, impulses, forces, torques, damping and sleep;
- the air and its wind, uniform or from a grid, and the drag it puts on a body;
- heat on every body, by convection, radiation and across its contacts, and fire: wood, paper and rubber catch, burn their fuel, lose mass and give off hot gas, and water puts them out;
- an origin held in doubles that the world can move to where the play is;
- events, and snapshots a world restores from to the byte;
- particles that fall, drift in the wind, bounce off a floor and die, on the CPU and, through wgpu-native, on the GPU.
- debris, the visual bodies: thousands of balls that tumble, heap and settle on still planes and boxes, on the CPU and on the GPU, where they are read a frame late.
- cloth: sheets and ropes held by constraints of any stiffness, draped over balls and blown by the wind, on the CPU and on the GPU.
- water as particles in a tank that slumps, splashes and settles, on the CPU and on the GPU.

A fast mode, multibody chains and the remaining platforms follow, each with its tests.

## Building

There is nothing to build by hand. The package's hook compiles `csrc/` with the C compiler the target already uses: Xcode's clang on Apple platforms, the NDK's on Android, MSVC or clang on Windows, the system's on Linux. A game that depends on this package needs no other toolchain.

The GPU passes are a second library, `f3d_gpu`, built from `csrc/gpu/` and linked with wgpu-native. The hook downloads a pinned wgpu-native release for the target from GitHub, checks the archive against the sha256 written in `hook/wgpu_native.dart`, and keeps it in the hooks' shared output, so it is fetched once. Only the static library is used, so nothing extra has to be found at run time. If there is no release for the target, no network, or the checksum is wrong, the hook says so and builds the core alone; `NativeGpu.open()` then returns null and particles run on the CPU.

The Dart side reaches the core the same way natively and in the browser: through `lib/src/core/`, where every call is a function and every pointer an address. The calls and the layouts of the structs the Dart side fills are generated from `csrc/include/f3d_physics.h`; after changing the header, run

```sh
dart run tool/gen_core.dart
```

and `test/bindings_test.dart` fails until you do. In the browser there are no GPU passes: `NativeGpu.open()` returns null there, and the CPU systems run instead. Call `await loadPhysicsCore()` before making the first world; natively it does nothing. With `threads:` above one, on a page served cross-origin isolated (COOP and COEP headers), it loads `web/f3d_physics_threads.wasm` instead and starts that many Web Workers less one from `web/f3d_worker.js`; `physicsCoreThreads` then says how many threads a world can ask for. In the browser it fetches `web/f3d_physics.wasm`, which this package ships as an asset; after changing the core, rebuild it with `dart run tool/build_wasm.dart`, or `test/wasm_test.dart` fails.

The WebAssembly module is built separately, because hooks build for native targets only:

```sh
dart run tool/build_wasm.dart build/f3d_physics.wasm
```

That needs a clang with the wasm32 target, which Apple's has, and a wasm linker. Either `wasm-ld` on the path works, or the `rust-lld` that a Rust toolchain ships.

## Determinism

The deterministic mode uses the same bits on every platform. Every number is an f32, and the build turns off fused multiply-add contraction and fast math. The core also avoids the C library's transcendental functions; the square root it does use is rounded exactly by IEEE 754 on every target. `test/wasm_test.dart` holds that promise to the byte: the WebAssembly module and the native library step the same scenario, and their snapshots of the whole world afterwards have to be identical.

Built with `-DF3D_REAL_DOUBLE`, the core uses doubles throughout instead. That build is for C callers who want the precision and do not need the browser to agree; the Dart bindings refuse it.

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
dart test -p chrome -c dart2wasm test/web_core_test.dartdart test -p chrome_sab test/web_threads_test.dart
```

The last runs on Chrome asked for SharedArrayBuffer outright (`dart_test.yaml`), since the test runner's pages are not isolated.
