## Unreleased

- **The physics core in C, phase 0** — P9. A world of rigid bodies,
  dynamic or fixed, each named by a generational handle: the slot in the
  low 32 bits and the slot's generation in the high 32, so a handle kept past
  its body's destruction is refused rather than answered with whoever took
  the slot next. Gravity and a semi-implicit Euler step in the order
  `flutter3d_physics` steps, and every body's transform read back in one
  flat buffer with its handle. Built by the package's hook with the target's
  own C compiler, and as a WebAssembly module with no imports by
  `tool/build_wasm.dart`, from the same sources and flags. The two step the
  same scenario to the same bits.
