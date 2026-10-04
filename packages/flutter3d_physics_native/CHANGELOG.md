## Unreleased

- **Cloth, phase 10.** `f3d_cloth` holds points at their distances by
  constraints, each with its own compliance — XPBD in small steps, one
  pass a substep, so a compliance α is a spring of stiffness 1/α and a
  kilogram hangs α m g lower. Points fall on balls and a floor, drift in
  the wind and can be pinned and carried. The constraints are coloured
  when the cloth is made, no two of a colour sharing a point, and solved
  colour by colour; the GPU gets them from the core already coloured and
  solves a colour a dispatch, the colour picked by a uniform bound at an
  offset, so nothing is summed in an order it chooses. Where nothing folds
  the two agree point for point; a sheet hanging from two corners agrees
  to 2·10⁻⁵ m for half a second, until its wrinkles go their own ways,
  and then hangs as low to a hundredth of a millimetre. ABI 14, GPU ABI 3.

- **Debris, the visual bodies, read a frame late — phase 10.** Balls of
  any size and mass that fall, knock into each other, roll and settle on
  still planes and boxes: rubble and splinters nobody steers and the game
  never reads. `f3d_debris` in the core finds contacts through a hashed
  grid with a list per cell and solves them all at once from the same
  velocities, each body splitting its mass among its contacts; without the
  split a ball landing in a shallow groove is stopped twice over and hops
  two centimetres. A pair's impulse is always worked out from its lower
  slot, so both bodies get it to the bit and a free cluster keeps its
  momentum. The GPU runs the same passes in WGSL, building the grid with
  `atomicExchange`; a read without waiting gives the last step whose copy
  has come back, a frame behind the one queued. Until bodies meet the GPU
  agrees with the CPU to the bit; a poured heap of a thousand then goes
  its own way body by body, and settles to the same mean height within a
  part in a thousand. The GPU library is split into a file per pass, with
  the device, kernels and readback shared. ABI 13, GPU ABI 2.

- **Particles, and the first GPU pass, phase 10.** `f3d_particles` in the
  core steps sparks, spray and dust: gravity, a drift towards the wind,
  a floor they bounce off and slide on, a life that runs out, slots filled
  round and round with the oldest going first. The same step runs as a
  WGSL compute shader in `f3d_gpu`, a second library linked with
  wgpu-native; the build hook downloads a pinned release (v29.0.1.1) for
  the target, checks its sha256, and keeps it cached. Two seconds of a
  thousand bouncing particles on an M3 Pro come out within 3·10⁻⁵ m of the
  CPU's. No release, no network or a bad checksum builds the core alone,
  and `NativeGpu.open()` returns null; particles are visual, so the CPU
  ones stand in. ABI 12.

- **A body turns no more than an eighth of a turn a substep**, as Box2D v3
  holds it: π/4, 188 rad/s at four substeps of a sixtieth. A rod two metres
  by two centimetres struck at its end spins about its length — five
  thousand times easier to turn — at thousands of radians a second; turned
  tens of radians in a substep, the first-order turn read its momentum back
  through that tiny inertia and the rod flew off at hundreds of millions.
  Bounded before the turn and after it, it is thrown back and spins, and
  nothing blows up.

- **Queries and a character, phase 9.** Rays (`f3d_world_ray_cast`, the
  nearest; `f3d_world_ray_cast_all`, every one in order) walk the tree
  nearest box first and cut it at each hit; a ball and an unrounded box are
  met in closed form, a mesh triangle by triangle from its front, every
  other shape by conservative advancement of a point. Shape overlaps and
  shape casts ask the narrow phase, a cast by conservative advancement; a
  cast starting overlapping meets at nought. Every query takes a layer mask
  and a body to ignore, and none sees a shape its ray starts inside. A ray
  meets what `flutter3d_physics`' does, at the same distance.
  `f3d_world_move_character` moves a kinematic capsule by casting and
  sliding: ground no steeper than its slope is stood on, steeper is slid
  along and not climbed, a step up to its height is climbed by lifting,
  moving and setting down, and walking down a slope it keeps to the
  ground. A ball's ray is found by the ray's nearest distance to its
  centre, not b² − c, which cost two millimetres at thirty metres in
  floats.

- **A bullet's turn is swept too.** The path a bullet took through the
  step is recorded substep by substep, and the sweep follows it, place and
  turn, bounding how fast its turn closes a gap by its fastest point; so a
  bar two metres long spun at three hundred radians a second — five a step,
  which the step's first and last turns would read the short way round,
  backwards — stops at a wall beside it and is thrown back, instead of
  turning through. A turn of more than half a revolution in one substep is
  past what it follows.

- **Continuous collision, phase 8.** Soft, by default: a body's leaf in the
  tree covers where it will be after the step, and a pair's contact reaches
  as far as the two can close in it by their speeds and spins, so a ball at
  three hundred metres a second stops at a wall a centimetre thick instead
  of being past it before any contact sees it — and one going by close to a
  box at a hundred is not slowed. Hard, for a body made a bullet
  (`f3d_body_set_bullet`): after the solve it is swept along its path by
  conservative advancement against every body but another bullet and put
  back at its first impact; a bullet touching something where the step
  began, or moving away from it, is the contact solver's and not held.
  `f3d_world_set_speculative` turns the soft kind off.
- **A rolling ball stays on the floor.** The solver measured a contact's
  gap by carrying the point it touched round with the body; a ball rolling
  at ten metres a second turns a radian and a half a step, read a gap where
  it rested and sank two centimetres. The point's motion is taken to first
  order now, the body's turn crossed with its lever.

- **Joints, phase 7.** Fixed, spherical, revolute (a hinge), prismatic (a
  slider) and distance joints, in their own arena of generational handles,
  solved in the same soft substeps as the contacts and warm-started from
  step to step. A joint's locked directions — its point, its turns, its
  slide across the axis — are solved together as one block by Cholesky's
  factoring, so a light ball on a long lever holds its hinge's plane, which
  solving them one after another did not. Hinges and sliders take limits, a
  motor with a most force, and a spring; a distance joint is a rod, a spring
  between a least and a most length, or with no spring force a rope that is
  slack until it is taut. Joined bodies do not collide unless told to, and a
  joint joins its bodies' islands. A pendulum swings at its period, a spring
  at its, a rod holds a weight with m g; the core has its own arctangent for
  a hinge's angle. Joints are in snapshots. A distance joint changed from
  rod to rope or spring starts its impulses afresh, or what it held as a rod
  would hold on.

- **Triangle meshes, phase 6.** Level geometry, terrain and walls as
  indexed triangle meshes the world keeps (`f3d_world_create_mesh`) for
  fixed bodies (`f3d_body_set_mesh`), one sided, each with a tree of its
  triangles. A ball or capsule meets a triangle by its closest points — a
  capsule lying down rests on both ends — and every other shape by GJK and
  EPA against the triangle; the contacts of every triangle a body touches
  are merged into one manifold. An edge two triangles share across a flat or
  hollow fold is internal, and a contact on it takes the face's normal, so a
  ball rolling down a mesh of a thousand triangles rolls at 5/7 g sin θ
  instead of catching on their seams; a ridge keeps its edge. Meshes are in
  snapshots; their trees are built again.

- **Convex shapes, phase 5.** Cylinders, cones and convex hulls, and any
  shape rounded by a radius (`f3d_body_set_rounding`). A hull is built from
  points in the order given (`f3d_world_create_hull`), weighed as a solid
  from its tetrahedra and moved so its centre of mass is the body's origin;
  the world keeps its hulls in snapshots. Inertia is a full tensor now, so a
  hull's products of inertia turn with it and a hull spun off its axes keeps
  its angular momentum. Every pair without a closed form goes through GJK
  between the shapes' cores and EPA where the cores overlap, touching
  judged by the difference's own size, and its manifold comes from the
  features facing each other: a cylinder on its end rests on four points of
  its rim and on its side along its length, a cone on its base or its
  slant, a hull on its face, a rounded box on the flat of its face. Depth is
  measured from the reference face's own plane, so a slightly tilted normal
  over a wide floor does not invent five centimetres of overlap. A cylinder
  rolls down a slope at 2/3 g sin θ.

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
