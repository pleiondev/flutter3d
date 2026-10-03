## Unreleased

- **The world's core, phase 1.** Bodies turn: a sphere, box or capsule
  gives a body its inertia, surface and drag, and the orientation steps as
  `flutter3d_physics` steps it, the angular momentum carried through the
  turn, so a box spun off its axes wobbles the way the reference's does.
  Impulses through the centre or at a point, forces and torques held over a
  step, damping, a lock on rotation, and sleep with its events.
- **Wind, heat and fire are the world's.** The air has a temperature and a
  density, and a wind, uniform and from a grid read trilinearly. A body in
  it feels ½ ρ C A |u| u, taken implicitly, so a leaf in a gale is stable at
  any step and a ball falls at exactly its terminal speed. Every body has a
  material and a temperature; it loses heat by convection that grows with
  the wind past it and by radiation, in one implicit step that cannot
  overshoot. Wood, paper and rubber catch at their ignition point, burn
  their fuel at a rate per square metre, keep a share of the heat and give
  the rest off as hot gas, which `f3d_world_read_fires` hands to a smoke
  grid; a burning body loses mass and inertia. Water on a body lands at the
  air's temperature, holds the body at its boiling point until it has
  boiled off, and so puts a fire out. Heat, water, forces and torques reach
  a body through the same bus.
- **An origin in doubles.** Positions are relative to it, and
  `f3d_world_shift_origin` moves it to the play without moving anything in
  the world, so a body ten kilometres out keeps f32's precision.
- **Snapshots to the byte.** A world restored from one steps to the same
  bytes as the world it came from, and the WebAssembly module and the
  native library now agree on the whole snapshot after six hundred steps of
  turning, burning bodies in a wind grid, not only on their transforms.
- **`f3d_real`.** The core builds with doubles throughout under
  `F3D_REAL_DOUBLE`, and its C tests run in both precisions.

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
