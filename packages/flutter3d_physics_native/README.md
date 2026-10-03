# flutter3d_physics_native

The physics core of flutter3d, written in C11 and reached through `dart:ffi`. In the browser it runs as a WebAssembly module built from the same sources. `flutter3d_physics`, the pure-Dart physics, is its reference and its fallback.

It is being built in phases (P9 in the 0.9 plan). What is here now:

- rigid bodies named by generational handles, so a handle kept past its body is refused;
- contacts between every pair of shapes, turned: manifolds of up to four points, events when a contact begins and ends, collision filters, and islands that sleep and wake together;
- a solver that keeps bodies apart: soft contacts in substeps with warm starting, friction and restitution, so crates rest, stack, slide, roll and bounce;
- shapes (sphere, box, capsule) as inertia, surface and drag; the orientation stepped with the angular momentum kept, impulses, forces, torques, damping and sleep;
- the air and its wind, uniform or from a grid, and the drag it puts on a body;
- heat on every body, by convection, radiation and across its contacts, and fire: wood, paper and rubber catch, burn their fuel, lose mass and give off hot gas, and water puts them out;
- an origin held in doubles that the world can move to where the play is;
- events, and snapshots a world restores from to the byte.

The broadphase tree, the remaining shapes, joints, CCD and the compute passes follow, each with its tests.

## Building

There is nothing to build by hand. The package's hook compiles `csrc/` with the C compiler the target already uses: Xcode's clang on Apple platforms, the NDK's on Android, MSVC or clang on Windows, the system's on Linux. A game that depends on this package needs no other toolchain.

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
- builds the WebAssembly module and runs it in node, so the byte-for-byte comparison above actually happens. This test is skipped where node, clang or a wasm linker is missing.
