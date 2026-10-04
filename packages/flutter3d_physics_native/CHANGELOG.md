## Unreleased

- **The broadphase tree, phase 4.** A dynamic tree of boxes, as Box2D's:
  each body with a shape has a leaf holding its box grown by ten
  centimetres, moved only when the body leaves it; a leaf goes in beside the
  node that costs least by surface area, and rotations keep every node's two
  sides within one level of each other, so a thousand boxes laid in a row
  are a tree twenty deep and not a list. Only awake bodies ask it what is
  near them; two bodies that cannot move keep last step's contact, and one
  moved by hand wakes what slept against it, so a crate on a plank lifted
  away falls. The tree is not in a snapshot — it is built again — and the
  restored world steps to the same bytes, since the contacts come out in
  slot order whatever shape the tree has. `f3d_world_query_box` finds the
  bodies a box overlaps, in slot order.

- **The solver, phase 3: bodies stand on what they touch.** Soft contacts
  solved in substeps (four by default, `f3d_world_set_substeps`): each
  substep integrates the velocities, warm-starts every contact from what its
  points pushed with last step — matched by the features that made them —
  solves with a soft bias, moves the bodies and solves again without the
  bias, so pushing overlap out does not leave it as speed; restitution after
  the last. The contact is a heavily damped spring at a quarter of the
  substep rate, at most thirty hertz, pushing overlap out no faster than
  three metres a second and leaving five millimetres of it alone. Friction
  inside Coulomb's circle on the geometric mean of the pair's coefficients,
  restitution the larger of the two, nothing bouncing below a metre a
  second (`f3d_body_set_friction`, `f3d_body_set_restitution`). A crate comes
  to rest and sleeps where `flutter3d_physics` rests it; ten stand stacked;
  a ball bounces back with its restitution's share; a crate slides down a
  slope at g(sin θ − μ cos θ) and holds when μ > tan θ; a ball rolls down it
  at 5/7 g sin θ with its spin matching its speed; collisions keep their
  momentum; a crate stood on its edge falls flat.
- **The step's order changed:** contacts where the bodies stand first, then
  the solver, then heat, so a body placed between steps is in the contacts
  the solver uses. Sleep is decided there too, a step after the sleep time
  is up. Touching now means within the solver's five millimetres, which is
  as close as it holds a body: a speculative contact that stopped a ball at
  the surface is a contact that began.

- **Contacts, phase 2.** Every pair of sphere, box and capsule, turned
  however they are turned, answers with a manifold: one normal and up to four
  points halfway between the surfaces, each with its depth and the features
  that made it. Two boxes are parted along the least of fifteen axes, a
  resting box keeps its whole face — the incident face clipped to the
  reference face and, when that leaves eight points, the four that span the
  most — a box on its edge keeps the edge, crossed edges meet at a point, and
  a capsule lying on a box or along another capsule keeps both ends. A sort
  and sweep finds the pairs, exactly those trying every pair finds, and
  collision layers and masks filter them.
- **What began and ended touching**, as events naming both bodies.
- **Islands.** Bodies joined by their contacts sleep when all of them have
  been still and wake together when one moves, so a crate knocked off a
  stack wakes the crate under it; two sleeping bodies keep their contact.
- **Heat across a contact**, by Holm's constriction over the contact's area —
  a face's polygon, or Hertz's circle where a curve presses in — taken
  implicitly for each pair. A fixed body of no thermal mass is a reservoir: a
  hot plate stays hot. Materials have a conductivity. Wood is an insulator,
  so a burning block warms the one it touches but does not light it; fire
  crossing by its flames waits for the smoke grid.
- **Nothing pushes touching bodies apart yet**: the solver is phase 3. The
  WebAssembly module and the native library agree to the byte on a scene
  that falls through a floor, contacts, events and heat included.

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
