# flutter3d_physics_native

The physics core of flutter3d, written in C11 and reached through `dart:ffi`. In the browser it runs as a WebAssembly module built from the same sources. `flutter3d_physics`, the pure-Dart physics, is its reference and its fallback.

It is being built in phases (P9 in the 0.9 plan). Phase 0, which is here now, covers rigid bodies named by generational handles, gravity, a semi-implicit Euler step, and transforms read back in one flat buffer. Contacts, the solver, shapes, joints, CCD and the compute passes follow, each with its tests.

## Building

There is nothing to build by hand. The package's hook compiles `csrc/` with the C compiler the target already uses: Xcode's clang on Apple platforms, the NDK's on Android, MSVC or clang on Windows, the system's on Linux. A game that depends on this package needs no other toolchain.

The WebAssembly module is built separately, because hooks build for native targets only:

```sh
dart run tool/build_wasm.dart build/f3d_physics.wasm
```

That needs a clang with the wasm32 target, which Apple's has, and a wasm linker. Either `wasm-ld` on the path works, or the `rust-lld` that a Rust toolchain ships.

## Determinism

The deterministic mode uses the same bits on every platform. Every number is an f32, and the build turns off fused multiply-add contraction and fast math. The core also avoids the C library's transcendental functions. `test/wasm_test.dart` holds that promise to the bit: the WebAssembly module and the native library step the same scenario, and every float has to agree.

## Tests

```sh
dart test
```

The suite does four things:

- builds the C unit tests in `csrc/tests/` with the address and undefined-behaviour sanitisers and runs them;
- checks the hand-written bindings against the header;
- drives the world through `dart:ffi` and compares a free fall with `flutter3d_physics`. That comparison uses a tolerance, because the reference works in doubles;
- builds the WebAssembly module and runs it in node, so the bit-for-bit comparison above actually happens. This test is skipped where node, clang or a wasm linker is missing.
