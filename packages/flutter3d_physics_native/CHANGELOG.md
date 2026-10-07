## 0.9.0

- **The first publication, and the number skips from 0.1.0.** That number
  was carried inside the workspace and never reached pub.dev, so nobody
  outside saw the ones passed over. The shelf goes out on one number so
  that one number names one tree, and `^0.9.0` on any `flutter3d_*`
  package resolves against every other.

- **Fire spreads from one body to the next.** Every body gives the room
  εσA(T⁴ − Tₐ⁴) above what it would at the air's temperature, and each body
  near it catches its solid angle's share of that, as much as five rays find
  nothing in the way: a wall shades. What is caught was given up already,
  so no heat is made, a body at the air's temperature gives nothing, and a
  cold one draws heat from what sees it. A burning body sends its
  material's radiant share of its fire's heat the same way, and its flame
  stands over it as long as Heskestad says, as wide as a plume spreads, and
  leaning with the wind by the speed of its own buoyancy. A body standing in
  the flame is heated by its gas. A crate stacked on a burning one catches
  in under three minutes; under a wind along a row, the fire runs down the
  row. `NativeMaterial` carries its flame: the gas's temperature, what it
  passes to a surface in it, the radiant share and how strongly it absorbs,
  with presets for wood, paper and a sooty rubber. How far a source looks
  follows from how strongly it radiates; nothing else is cut.
  `F3D_ABI_VERSION` is 27.

- **Water left alone costs nothing, and water in use a ninth of what it
  did.** A shallow water whose flow stays under a millimetre a second for a
  second, with nothing in it, nothing feeding or draining it, no wind and
  nothing going over a lip, rests and is not stepped; a body reaching it,
  wind over it, a pour, a spring, a landing sheet or any change to it wakes
  it. The cube root the bed's friction asks for on every face of every
  substep took forty Newton steps from one; it now starts from the
  argument brought into [1, 8) by exact eighths and stops when a step no
  longer goes down, and a world with no wind field asks for its wind once
  a substep instead of once a face. A 96 × 96 ford with a car through it
  went from 7.6 ms a step to 0.8; one lying still, from 3.2 ms to a
  microsecond. Snapshots are version 21.

- **A fire grows from where it caught.** A body catches on a patch three
  centimetres across, and the flame's edge runs out over its surface at
  the opposed-flow rate, which goes as 1 / (T_ig − T_s)²: five millimetres
  a second over a cool surface, up to five centimetres over one already
  near catching. The burning share of the surface sets how fast mass
  burns, how much heat leaves and how wide the flame stands, so a fire
  from a spark grows as the square of the time, as measured fires do, and
  one on a body heated all round takes seconds to cover it. A flame still
  spreading over a dry body keeps its patch alight; water still puts it
  out. Snapshots are version 20.

- **The laws a body keeps, each held to its closed form.** A fall at g·t,
  a sum of forces accelerating at their sum over the mass, a torque about
  no principal axis changing the angular momentum by itself times the
  time, a glancing elastic collision keeping momentum, angular momentum
  and energy, a stone under water starting down at its weight less
  Archimedes' push over its mass and the water it carries, a ball of half
  water's density floating half under, a box on a slope staying below
  Coulomb's angle and sliding at g (sin θ − μ cos θ) above it, and a
  pendulum swinging at 2π √(L/g): `csrc/tests/test_laws.c`.

- **A bag of air lifts what it is tied to.** The water a body carries with
  it was taken into its own motion and nowhere else, so a rope or a
  contact pushing on a light body in water saw only its own mass: a bag of
  two kilograms and fifty of water round it passed what it held a
  twenty-sixth of its lift. Contacts and joints now push the water's mass
  too, and a stone of thirty kilograms on the bottom rises on a rope under
  113 litres of air.

- **A spring and a drain make a current.** A shallow liquid's spring now
  takes a negative rate and draws water off, as far as there is water to
  draw. One at each end of a closed sea at one rate moves water from the
  one to the other at Q over the section between them while the level
  stays where it was: a current a diver swims against, with no edge left
  open for the sea to run out of.

- **A village on fire costs a few milliseconds a step, not a hundred.**
  What a source sees of a body is now asked as a yes or no that the first
  thing in the way answers, past both bodies, rather than as every hit
  along the ray sorted; a ray that passes wide of a hull's ball misses it
  without the sixty-four distance queries that would show it; the tree is
  brought up to date once for all the rays of a step; a body that looks
  small is decided by the one ray to its centre; and a source does not
  trace to a body it would warm by less than a third of a kelvin an hour.
  Four burning huts in sectors, five red-hot stones and fifty bodies over
  a ground of 32 000 triangles step in 4 ms where they took 35.

- **A red-hot stone lights the straw it lies in.** Where two bodies touch,
  both surfaces are at once at the temperature their effusivities √(kρc)
  weigh them to, however little the contact passes to either whole; a fuel
  catches when that spot reaches its ignition temperature, and burns on
  while it stays there. Granite at 1100 K on pine holds the pine at near
  1000 K where they meet, and a four-tonne beam is alight within a second
  under a stone it has barely warmed; a stone at 450 K lights nothing. A
  block pressed against a burning one now catches from the burning face
  in seconds rather than from its radiation in minutes.

- **A light car sits on its springs.** A wheel's damper is pushed whole at
  the step's end, so it now takes out of the closing at most what there
  is: the mass the wheel carries over the step, the chassis's as seen at
  the wheel's point and no more than its share of the whole. A damper set
  for a loaded car used to throw an empty one, or one burnt down to a fifth
  of its wood, higher every bounce; a chassis of forty kilograms on the
  dampers of a 1200 kg car now comes to rest at the height its springs give.
  The tyres settle the velocity the step will end on, gravity and the
  springs taken in, so a braked car on a slope stays where it stopped
  instead of creeping down by a step's pull every step.

- **A chain's motors hold it together.** A multibody's motors and limits
  are solved together, a pass over them all repeated until they agree, and
  each motor is a servo: it holds the joint to where it means it to be as
  well as to its speed, so the free fall of a step under the solver does
  not sag a held arm. A neck of four links of 200 kg held out level by its
  motors sags under two centimetres in two seconds, where it fell to its
  limits.

- **A shallow liquid keeps its momentum, and a body feels its slope.** Its
  velocities are carried as Stelling and Duinmeijer carry them, as the flux
  of hu that moves the liquid itself, so a patch of flow keeps its momentum
  to a twentieth of a per cent where tracing velocities back lost eight
  per cent in half a second, and a hydraulic jump stands where it should.
  A body is pushed down the surface's slope round it, ρgV·s (Froude and
  Krylov): a float slides off a wave's flank, and a body driven through
  the liquid feels the bow wave it raises.

- **A shallow liquid is any liquid, and a body moves through it as through
  one.** What used to be water over ground is `NativeShallowLiquid`
  (`f3d_shallow_*`), and `setShallowProperties` gives it a density,
  viscosity and surface tension — `NativeLiquidProperties.water`, `seawater`,
  `oil`, `honey` or `moltenBasalt`. A body in it is dragged as a ball is at its
  Reynolds number, Schiller and Naumann's 24/Re·(1 + 0.15·Re^0.687) up to
  Newton's 0.44: a steel ball sinks through honey at Stokes's 129 mm/s and
  a heavy one through water at Newton's 2.44 m/s. The liquid it must carry
  to speed up, half what it displaces, is on its inertia in the
  integrator, so a ping-pong ball let go under water starts up at
  15.5 m/s², not 112. The drag pushes the flow back as hard, and the
  water it shoulders aside keeps its flow, so a body driven through it
  leaves a wake and the pool takes up the momentum it lost. The viscosity
  mixes the flow and holds it to the ground as a laminar film where that
  holds harder than Manning's roughness, so a thick oil runs down a slope
  at Nusselt's gSh²/3ν; bubbles rise through it no faster than
  Hadamard and Rybczynski allow, and its spray breaks up by its own
  numbers. `F3D_ABI_VERSION` is 32.

- **Spray and bubbles can be read for one water.** `readSpray` and
  `readBubbles` take `of:`, so a world with a flooded hall and a fountain
  draws each one's falling water over its own surface.

- **A log catches at its surface while its middle is cold.** Heat used to
  be one temperature through a body, so a 55 kg log had to be heated
  through, 26 MJ, before it could catch: half an hour in a flame. Now heat
  reaches in from the surface over a layer that thickens as δ² = 6αt, with
  the parabola across it the heat balance integral gives, and the surface
  is what catches, goes out, radiates, meets other bodies and holds at
  boiling under water; once the layer is as deep as the body is thick the
  interior warms at its slowest mode's rate. The mean is still what the
  heat says, so no heat is made. A log on a burning one catches in fifteen
  seconds with its middle at 299 K; a copper ball still cools as Newton
  says, and a ball of Biot number a half cools within 3% of the series
  solution where one temperature was 9% off. A fire now runs along a row
  of crates as well as up a stack. `NativeWorld.surfaceTemperatureOf`
  reads it. `readFires` gives eight floats a fire: with the position and
  the watts, how far the flame reaches and the axis it leans along, the
  same flame the core heats with (`nativeFireFloats`).
  `F3D_ABI_VERSION` is 31.

- **What a waterfall drives into a pond spreads instead of crossing it as
  a stripe.** Water mixes its momentum sideways through its own eddies:
  those the grid can see, by Smagorinsky's viscosity off the flow's shear,
  and those as large as the water is deep, which a depth-averaged flow
  cannot, by Fischer's transverse mixing off the bed's friction velocity.
  What plunges in drags the water round it along and lands over a disc as
  wide as the pool is deep. A jet driven at two metres a second into a pool
  a metre deep slows to under one in a second, where unmixed it kept 1.55.

- **A waterfall keeps to continuity, splashes, and drags air down.**
  Each face of a cliff's lip throws what went over it in a step as one
  piece of sheet, at the speed it went over with, falling freely; its
  thickness is not imposed but follows from continuity, the flow it left
  with over its speed now, so the sheet thins as it falls. Ripples on it
  grow at Weber's rate until, twelve e-foldings on, it breaks into drops
  of 1.89 times its thickness. Where a piece lands hard enough part of it
  splashes back up (Mundo's criterion), and a sheet plunging into water
  drags air down, Bin's Q_air/Q = 0.04·Fr^0.28·(H/e)^0.4 of it, as bubbles
  that rise at their terminal speed, ride the flow and are gone at the
  surface. A body coming into the water faster than a wave can carry it
  off throws the water it pushes aside up as a crown. Water that finds no
  room in the air stays on the lip instead of turning up below the cliff.
  `readSpray` gives each piece's kind, width, thickness and lip;
  `readBubbles` the bubbles. `F3D_ABI_VERSION` is 30, and a snapshot is
  format 16.

- **Water over ground: a stream, a pond, a waterfall into it.**
  `NativeWorld.createShallowLiquid` lays shallow water on a grid over the ground.
  In each column the water moves as one, its depth carried across the
  columns' faces by the flow, so none is made or lost but by springs,
  open edges and what is taken off. It runs down the slope of its
  surface, is held back by Manning's roughness of the bed, and is pulled
  by the wind. A lake stays still over a bumpy bed. Where the ground drops
  away steeper than forty-five degrees the flow leaves as spray, falls and
  lands in the water or on the ground below: a waterfall, and waves at its
  foot. A dynamic body pushes the water aside, so a stone dropped in makes
  waves. It is held up by the weight of what it displaces, measured
  exactly as the cap of its ball below the water round it, and the flow
  drags it along. `fillShallowLiquid`, `pourShallowLiquid`, `setShallowSource` and
  `setShallowBed` shape it; `readShallowSurface`, `readShallowFlow`,
  `sampleShallow` and `readSpray` read it for drawing. `F3D_ABI_VERSION` is
  29, and a snapshot is format 15.

- **A post burns upwards, a part at a time.** Each part of a compound
  has its own temperature, water, fuel and fire. A post stood on end and
  lit at the bottom catches a part at a time in the flame of the one below;
  a beam laid flat and lit at one end warms the part beside the fire and
  goes no further, as a log on its side does in still air. The parts pass
  heat to each other where they meet, a contact heats the part nearest it,
  and a fire is read at the part that burns. The body's temperature is its
  parts' weighed by what each holds, and it burns while any part does.
  `partTemperatureOf`, `setPartTemperature`, `isPartBurning` and
  `addHeatAt` reach a part. `F3D_ABI_VERSION` is 28, and a snapshot is
  format 14.

- **A box in a corner stands on both faces.** A mesh, or a compound,
  that meets another body with two faces at once gives each face its own
  manifold. A box in the corner of a room stands on the floor and stops at
  the wall, where before it kept only the deeper of the two and the other
  let it in. A mesh's edge contacts, on seams the face already holds, do
  not start a second manifold, so a crate still slides over a fine grid
  without a bump. A pair's contact begins and ends as one, whichever of its
  manifolds touches.

- **A wheel meets a kerb with its rim.** Beside the ray down its middle,
  each wheel casts itself, a cylinder of its radius on its axle, through
  its travel. Where the rim meets something higher than the ray does, the
  wheel stands on that, along the normal of what it met. A plank three
  centimetres wide, crossed at five metres a second, used to fall between
  two steps' rays; now the car rides up over it. On a road the ray decides
  as it did.

- **A cone on a ball joint of a multibody.** `NativeWorld.setLinkCone`
  holds a spherical link's axis within a swing of where its parent holds
  it, and its twist about that axis within a twist. The cone is held twice:
  the link's turn is brought back inside it after the solver, and any of
  its spin that would carry it further out is pushed back through the
  whole tree. `F3D_ABI_VERSION` is 26, and a snapshot is format 13.

- **Chains whose joints cannot come apart.** `NativeWorld.createMultibody`
  roots a tree of bodies at a fixed body (a fixed base: an arm, a crane, a
  chain from a ceiling) or a dynamic one (a floating base). `addLink` hangs
  a link under it on a fixed, revolute, prismatic or spherical joint. The
  joints are in reduced coordinates. After the solver has moved the links,
  contacts and all, each joint's angle or travel is read off where they
  stand, and every link is put back where its parent and that coordinate
  say. Their velocities are replaced with the nearest the joints allow,
  weighted by every link's mass and inertia, and motors and limits then
  push through the whole tree. A chain of twenty light links with a weight
  a hundred times heavier on the end keeps every joint within a tenth of a
  millimetre as it swings. Links do not collide with their parents.
  `F3D_ABI_VERSION` is 25, and a snapshot is format 12.

- **Vehicles on wheels that hang from springs.** `NativeWorld.createVehicle`
  puts up to eight wheels under a dynamic chassis. Each wheel is a ray cast
  down from where its suspension is fixed. Where the ray lands, its spring
  and damper hold the chassis up, its drive and brake push it along the
  road, and its tyre holds it from sliding sideways. The tyres are solved
  together, eight passes through the chassis's mass and inertia, inside
  each one's friction circle, so a car rounds a turn without its wheels
  fighting and slides when it is asked for more than the grip. `setWheel`
  steers, drives and brakes a wheel, and `wheelsOf` says where each wheel
  is, how hard its spring pushes and how far past its grip it is. The
  chassis is an ordinary body: it collides, rolls over, sleeps and goes
  into snapshots. `F3D_ABI_VERSION` is 24, and a snapshot is format 11.

- **Joints that break.** `NativeWorld.setJointBreak` gives a joint a
  force and a torque it lets go past: at the end of a step that held its
  second body harder, the joint is taken out, both bodies woken, and a
  `NativeEventKind.jointBroken` names them. `jointTorque` reads what its
  locked turns held with, beside `jointForce`. A shelf's bracket, a door
  kicked off its hinges, a rope that snaps. `F3D_ABI_VERSION` is 23, and a
  snapshot is format 10.

- **Several shapes on one body.** `NativeWorld.createCompound` takes up
  to sixty-four parts, each a sphere, box, capsule, cylinder, cone or hull
  placed and turned in the compound's frame, and `setCompound` shapes a
  body as it: a table's top and legs, a dumbbell, a hammer. The parts are
  one solid of even density, moved so the centre of mass is at the body's
  origin (`compoundOffset`), with the inertia each part adds about it. Its
  contacts are each part's, joined into the pair's manifold along the
  deepest part's normal; rays, overlaps, casts, bullets and snapshots see
  the parts. `F3D_ABI_VERSION` is 22, and a snapshot is format 9.

- **Pipes and floating bodies run on the core.** `NativeLiquid` drives a
  pipe's column with `f3d_liquid_pipes` and pushes floating bodies with
  `f3d_liquid_floats`, as the reference does: the column accelerated by the
  pressure across it over its inertance and held back implicitly by
  Hagen–Poiseuille's friction and its end losses, and a body lifted by the
  weight of what it displaces and dragged with White's sphere coefficient
  for its frontal area — a sphere's, a box's or an upright capsule's. A
  U-tube swings within a fiftieth of a millimetre of the reference's, and
  floating bodies stay within a tenth of one. `F3D_ABI_VERSION` is 21.

- **Liquids run on the core by default.** `NativePhysics.fluid` is a
  `NativeLiquid`, which steps `flutter3d_physics`' liquids as the reference
  does: `f3d_liquid_particles` the spilt particles (position-based fluid
  with Akinci's cohesion and curvature, pre-stabilised, the walls met in
  pieces, XSPH's viscosity), `f3d_liquid_parcels` a stream's parcels in the
  air (falling, running along a wall, clinging while slow, their ripples
  grown), and `f3d_liquid_modes` a surface's modes (each a damped
  oscillator stepped exactly, held under Stokes' limit). Walls are planes
  and the inside and outside of turned glassware, in one packed record
  format; a wall the core has no record for is stepped on the reference.
  Particles go to the core about their own middle, where single precision
  keeps the digits a velocity is read from. On every test scene the core
  stays within what the reference's own rounding spreads it by, and a
  whole pour fills the other tube to within half a per cent of the
  reference's. `F3D_ABI_VERSION` is 20.

- **Cloth runs on the core by default.** `NativePhysics.cloth` steps a
  `flutter3d_physics` `ClothMesh` with `f3d_cloth_solve`, which does what
  `stepCloth` does: XPBD with its multipliers kept across the iterations,
  damping by the substep, wind blowing on triangles along their normals,
  self-collision through a spatial hash, and friction against obstacles.
  Obstacles are spheres, upright capsules, boxes and wedges as their
  planes, and heightfields as their samples, all in one packed record
  format (`f3d_cloth_set_obstacles`). A sheet on the core ends within a few
  millimetres of the reference's after a second of draping; the two differ
  in the order the constraints are solved and in f32 rounding.
- **The core's own cloth types go by `CoreClothMesh` and
  `CoreClothSettings`** in the package's library, because
  `flutter3d_physics` uses the plain names for the cloth both backends step.
  `NativeCloth` and `GpuCloth` are unchanged.

- **Sweeps run on the core.** `NativeWorldSweeps` casts the shape's
  bounding box through the mirrored world, the same way the reference
  does. A shape that starts inside something hits nothing. With
  `castsRays`, a `NativeDynamics` provides the sweeps as well as the rays.
- **`choosePhysics(asked)`** picks the backend synchronously. A replay
  uses it inside an isolate of its own, which starts on the reference.
- **Dynamics made for an attached world take it over**, so each collision
  world has exactly one core world.

- **The core is the default, and the Dart reference is the fallback.**
  - `usePhysics()` picks the run's backend the first time something asks,
    and returns the same one after that.
  - The core is used unless the build asks for the reference
    (`FLUTTER3D_PHYSICS=dart`) or the core fails to start. Starting it is
    tested by actually making a world, so a missing library or an ABI
    mismatch becomes a fallback instead of a crash, and
    `physicsFallbackReason` explains it.
  - `preparePhysics()` first loads the module in the browser.
  - `NativePhysics` is the backend itself.

- **The character moves as the box the reference sweeps, and a run saves
  the same bytes however it was watched.**
  - `f3d_world_move_character` takes the character's shape. The core
    moves each controller as its bounding box, the same volume its own
    sweeps move and the one it stands as for everything else. A capsule
    inside it rolled off a ledge's edge before the box would leave it, and
    the platformer's route fell short of the blue key.
  - The world is mirrored into the core at the end of each step, through
    `CollisionWorld.update`. A query between steps only puts movers in
    place and never makes or removes a body, since slots order a step's
    pairs. A save puts every mover in place first.
  - A save also holds which core body stands for which collider. It is
    matched on restore by shape and place, so a world staged afresh and
    restored goes on as the run that saved it, save for save. Without it a
    replay that drew frames, or checked a fresh world against its own
    recording, parted from the run it recorded.

- **The character, reviewed against the reference.**
  - `f3d_world_move_character` first pushes the capsule out of whatever was
    moved into it, along the deepest overlap's normal, with the speed into
    it taken out.
  - It tries a step only when a wall stopped it, and gives up when the lift
    meets a ceiling. It says how far a step lifted it (`stepped_up`).
  - A body on a from-above layer is not met when the character starts
    inside it: a jump through a platform is no longer cut short there.
    One case parts from the reference: a jump that does not clear the
    platform falls back through it on the core, where the reference's box
    is pushed up onto the top.
  - The mirror writes a mover's place into the core only when it moved,
    so rays cast between steps no longer wake what lies against it, and a
    simulation's bytes no longer depend on how many there were. A collider
    that changes shape stands again as the new one; one that turned into a
    trigger stops standing at once.
  - `NativeRagdoll` and `SkeletonRagdoll` take a collision `layer` and
    `mask`.

- **ABI 19: the character as the reference moves one.**
  `f3d_world_move_character` takes the character's velocity in and out,
  with the speed into everything met taken away. It tries a step only for
  a body that stood (`F3D_CHARACTER_MAY_STEP`) and keeps it only when it
  got further than sliding did. It moves its skin off a surface along that
  surface's normal: backed off along the move, a move that grazed the edge
  of a step started the next cast touching it and stuck there. One-way
  layers are floors from above only. `NativeDynamics(castsRays: true)`
  answers the world's rays through `NativeWorldRays`, and `mirrorWorld`
  stands a level made since the last step before any query.

- **The core moves characters.** `NativeDynamics(movesCharacters: true)`
  sets the world's `characterMover` to a `NativeCharacterMover`. It moves
  each controller as the capsule inside its box through the world the
  dynamics mirror, with the lifts and the other characters put where they
  are this step first, and names the ground as its collider. `dispose`
  hands the characters back to their own sweeps. Also `mirrorWorld`,
  `standingOf` and `colliderOf`.

- **A fallen body gets up.** `SkeletonRagdoll.lying()` reads the pelvis
  against how it was bound. It says whether the chest faces up, where the
  pelvis is, and which way along the floor the head lies, with the yaw an
  actor faces that way by. A game picks the get-up clip by it and places
  the character there. `RagdollGetUp` then lays the ragdoll over the
  pose the clip makes each frame, all of it at first and none of it after
  its seconds. It takes the bodies out of the world when done.

- **Knees bend the way they bend.** `RagdollBend` is a hinge whose axis
  and sense come from the rest pose. A knee a rig binds a little bent
  bends about the axis across its bone and its parent's, the way it is
  already bent, from straight to `most`. Below `least` radians of rest
  bend it falls back to `otherwise`. The Quaternius profile's knees are
  hinges now. Its elbows, bound in a T-pose with a few hundredths of a
  radian of noise, stay balls. A hanging leg struck at the ankle bends
  further back and comes straight but never past straight when struck
  forward, measured in the world: the joint's own angle turns with its
  axis and could not tell a knee from one bending the wrong way.
  `NativeRagdoll.jointOf` and `heldAs` say how each bone is held.
- **A skinned character can go limp.** `NativeRagdoll` makes a capsule
  for each bone and a joint where each bone meets its parent, from bones
  given in world space. It builds them at rest, so a joint's cone and
  twist limits are the body's own and not those of the stride the
  character was caught in, and then moves them to the pose with the
  pose's velocities. `SkeletonRagdoll` makes one from a scene `Skeleton`
  by a `RagdollProfile` of joint names. Joints the profile does not name
  ride along with their animated local pose. Followers, such as the feet
  an IK rig hangs from the root, are carried by the body they name. Sizes
  are shares of the figure's measured height, so the hero, two
  centimetres tall under a hundredfold scale, comes out 1.8 m of body.
  `apply(weight:)` writes the bodies back into the joints, fully or
  blended with the animation's pose, which is how a character gets up.
  `RagdollProfile.quaternius` covers the dungeon's monsters, the hero
  and the robot. On that rig, elbows and knees are wide balls rather than
  hinges, because the rig does not promise the axes a hinge's sign would
  need. Its forearm reaches to the tip of the middle finger, so a hand lies
  inside the capsule. Ending at the knuckles, the dungeon runner's fingers
  went 8 cm into the floor. `NativeDynamics.keep` keeps a ragdoll's bodies through restores.
  *Found:* vector_math's `Quaternion.rotated` turns by the inverse of
  what `asRotationMatrix` means, while the core and flutter3d_physics
  mean the latter. A ragdoll placed with it had each body turned one way
  and moved the other, and flew apart on its first step. `turnBy` is the
  core's sense. The hull offset of a turned wedge in `NativeDynamics` had
  the same mistake.

- **The platformer runs on the core.** A rewind or a demo restored from a
  save made mid-level now steps on to the same bits as the run it was
  taken from. `NativeDynamics.saveState()` is the core's snapshot as
  text, and its restore puts right what came and went since: a body added
  since is made again, a collider standing since stands again, and a body
  or wall since gone is taken out. Generational handles tell a slot used
  again since apart from the old one. A save restored while a barge was
  elsewhere also read as the barge having jumped there in one step, and
  the mirror gave it that speed. Comparing every step's save after the
  restore with the live run caught it. The final states had agreed,
  since a crate stopped by friction ends in the same place whenever it
  falls asleep. A collider that stands in the core now resumes at its own
  position after a restore.

- **The core under `flutter3d_physics`' bodies.** `NativeDynamics` is a
  `RigidDynamics`, so a game builds one where it built a `Dynamics`, and
  its crates, sweeps and character controller stay as they were. The core
  holds the bodies. Before each step, whatever a game did to a body (an
  impulse, a push, a teleport, its own `restore`) is found by comparing it
  with where the mirror left it, and written in. After the step, every
  body is written back: its collider moved, its velocity, spin and
  orientation, asleep or awake. Level geometry, characters, doors and
  lifts stand in the core as fixed bodies, made, moved and taken out as
  their colliders are. A box, sphere or capsule becomes the same shape, a
  wedge becomes a hull, and a height field becomes a mesh split the way
  the field splits its quads. A moving collider is given the velocity it
  moved at, or a lift would leave the crate on it behind: 1.89 m instead
  of 2 after a metre's climb. The same scenes through both backends land
  crates where the reference does, stack and sleep them, push them, and
  rest them on a height field. Only the core rolls a ball down a wedge,
  because the reference meets a wedge as its box, and only the core tips
  a crate off an edge. `snapshot()` and `restore()` carry the warm starts
  and sleep for a rollback, and a restored world steps on to the same
  bits. In Chrome, under dart2js and dart2wasm, a scene of crates, a ball
  down a wedge, a lift and a push steps through `NativeDynamics` to the
  same hash as natively.
- **A fresh checkout no longer reads "Build must be rerun".** The hook
  unpacked wgpu-native's headers dated now, and since the GPU library is
  compiled against them, they counted as files modified during the build.
  They are now dated 2000.

- **The same bits on every platform, and a test that says so.**
  `csrc/tests/test_digest.c` steps seven scenes and fails unless each
  hashes to the number written in it: a world of every shape, the same
  world in the fast mode on three threads, the ragdoll down its stairs,
  debris, cloth, water and particles, every real of them. The numbers were
  taken on macOS arm64. They come out the same, in both precisions, on
  Linux arm64, x86-64 and 32-bit ARM with gcc and with clang, on the iOS
  simulator, and on Android arm64 in the emulator.
  `tool/digest_platforms.sh` runs all of these from a Mac.
  `test/c_unit_test.dart` now builds the C tests with MSVC on Windows too,
  and a CI job runs the whole package there with the library the hook
  builds. 32-bit x86 was the exception: gcc does its arithmetic on the x87
  there, in wide registers, and all seven scenes landed elsewhere. In SSE2 they
  match, under gcc and clang alike. The hook now asks for SSE2 on ia32,
  and the core refuses to build on the x87.

- **Ragdolls — the closing check of the native core.** A ball joint now
  takes a cone (`f3d_joint_set_cone`, `setJointCone`), which holds the
  swing of its second body's axis within an angle of the first's. Its
  twist about that axis takes the same limits as a hinge's angle, and it
  takes friction (`f3d_joint_set_friction`, `setJointFriction`): torque up
  to a set bound resisting the turn between its bodies. Without friction
  a ragdoll on the floor never sleeps, because a head rolls and a leg
  turns about its own length with nothing to slow them. `jointSwing` reads
  the swing, and `jointValue` now reads a ball joint's twist. The twist
  limit pushes along the axes' sum over one plus their cosine, which is
  how the twist actually changes. Pushed about the first axis alone, a
  shoulder swung a radian and a half went nearly half a radian past its
  limit on a flight of stairs; along the sum it goes 0.04 past. A ragdoll
  of eleven bodies on ten joints falls to a floor and sleeps within two
  seconds. A bullet of thirty grams at 300 m/s knocks it along, and it
  sleeps again. It tumbles down eight stairs to their foot. Throughout,
  the joints hold their points within 2.5 cm and their limits within five
  degrees, and at rest within a fraction of a millimetre. It steps to the
  same bits on four threads as on one, in either mode. It wants eight
  substeps: at four, an arm struck on a stair edge swings a quarter of a
  radian past its cone for a step. ABI 18, snapshot version 8.

- **Threads in the browser — phase 12 done.** A second module,
  `web/f3d_physics_threads.wasm`, is the core built with atomics on a
  shared memory its host makes. `loadPhysicsCore(threads: n)` on a page
  that can share memory — served cross-origin isolated, with COOP and
  COEP — loads it and starts n − 1 Web Workers from `web/f3d_worker.js`,
  each an instance of the module on that memory with a stack of its own,
  waiting in the core's `f3d_worker_main`; `physicsCoreThreads` says how
  many a world can then ask for. Elsewhere it loads the single-threaded
  module, and a world asked for more threads says no. The module cannot
  start a thread itself, so its pool takes workers its host started; they
  wait with `memory.atomic.wait`, and the page, which may not block, spins.
  The module's allocator is held by a spin lock, since workers allocate in
  the middle of a step. On four threads — four of node's workers, and in
  Chrome four Web Workers — the module steps a scene to the native
  library's bytes. Memory is read through a JavaScript DataView, which
  takes a SharedArrayBuffer as an ArrayBuffer.

- **The core runs in the browser.** `loadPhysicsCore()` fetches the
  WebAssembly module — shipped in the package as `web/f3d_physics.wasm`,
  an asset a Flutter web app serves — and the same `NativeWorld`, debris,
  cloth, water and particles run on it through `dart:js_interop`, compiled
  with dart2js or dart2wasm. A 64-bit handle crosses into the module as
  two 32-bit halves, through a shim `tool/gen_core.dart` writes beside the
  calls. In Chrome, a scene of boxes, balls, capsules, a hull, a hinge,
  wood and wind steps to the snapshot the native library steps it to,
  hash for hash; and `test/wasm_test.dart` holds the shipped module to the
  native library byte for byte, so a core changed and not rebuilt fails.
  A body's slot and generation are now taken from its handle by division:
  under dart2js Dart's shifts see 32 bits, and every generation read as
  nought.

- **One API over the core, natively and in the browser — phase 12.** The
  wrappers no longer hold `dart:ffi` pointers: they reach the core through
  `lib/src/core/`, where a call is a function and every pointer an
  address — natively a pointer, in the browser an offset into the
  WebAssembly module's memory — and blocks of the core's memory are read
  and written by element (`F32s`, `U64s` and their kin) and the structs it
  fills by offsets. The calls, both ways, and the structs' layouts are
  written by `tool/gen_core.dart` from `f3d_physics.h`, the one place a
  signature lives; a test runs it in check mode and holds every layout
  against the C compiler's own `offsetof`. The GPU passes stay native
  (`gpu_native.dart`); in the browser `NativeGpu.open()` is null and the
  CPU systems stand in. The GPU's settings are written as the core's,
  since they are laid out alike. `loadPhysicsCore()` fetches the module in
  the browser and does nothing natively. A world dropped without
  `dispose()` is freed by a `Finalizer`. Every native test passes as it
  did; the package compiles with dart2js and dart2wasm. `package:ffi` is
  no longer a dependency. Bodies' handles are 64-bit, and under dart2js an
  int holds 53 bits exact: a slot reused more than two million times
  would come out wrong there.

- **The fast mode solves contacts four at a time — phase 11 done.** A
  colour's contacts go in batches of four, a contact a lane of a vector
  (GCC's and Clang's vector types, NEON or SSE beneath; MSVC the same
  operations a lane at a time), every lane doing what one contact solved
  alone does, operation for operation: what a contact decides with a
  branch, a lane decides with a mask, and a lane with fewer points or a
  body that does not move is masked out, not skipped. So the fast mode
  lands on the bits it landed on before, with vectors or without, and a
  single contact still on the deterministic mode's. A colour's contacts
  are batched by how many points they have, which changes nothing. The
  contacts now read the bodies from a tight array of velocity, spin and
  how far each has moved and turned since the step began — the turn
  worked out once a body instead of once a contact — gathered from the
  slots before each stage and scattered back after; every bit of both
  modes is unchanged. On the heap of four thousand, the fast mode's solver
  on one thread went from 7.7 ms to 4.5. On several threads the numbers
  swung from 3.3 ms to 20 with the machine at load 8 to 49: a step meets
  at some 130 barriers, and a thread the system has set aside holds the
  rest there. One thread stays the default.

- **The pairs of overlapping leaves are kept from step to step.** Every
  awake body used to ask the tree what was near it every step; now the
  world keeps the pairs whose leaves overlap, drops those whose leaves
  parted and asks the tree only for the leaves that moved, and finds the
  step's pairs among them by the same tests the queries made — the boxes
  swept through the step overlapping. A leaf holds its body's swept box,
  so two swept boxes can only meet where two leaves do, and the pairs are
  the same: every body of a test scene moves to the same bits as before.
  Swept boxes are worked out once a step, not once a query. On the heap
  of four thousand the collision stage fell from 13.3 ms to 2.2 ms on one
  thread, and to 1.2 ms on six.

- **The fast mode.** `f3d_world_set_fast` (Dart: `NativeWorld.fast`)
  colours the contacts each step — greedily, in contact order, the lowest
  of 64 colours neither of its moving bodies has, the rest to an overflow
  solved on one thread — and solves a colour's contacts at once on every
  thread, the stages of a step met at a spinning barrier inside one pass
  of the pool, joints on one thread between them. Solved in another order,
  it lands on other bits than the deterministic mode, but on the same bits
  on any number of threads; a single contact, one colour, solves to the
  deterministic mode's bits exactly. Bodies that do not move are no longer
  written with nothing by a contact, in either mode, which changes no bit.
  A stack of ten walks 5.4 cm aside as it settles (1.4 cm deterministic)
  and sleeps upright. Kept in a snapshot (version 7). On a heap of four
  thousand, eight colours and some 124 barriers a step; the solver went
  from 8.4 ms to 4.9 ms on six threads with the machine at load 29, where
  a barrier waits on threads the system has put aside. ABI 17.

- **A world steps on threads, to the same bits — phase 11.**
  `f3d_world_set_threads` (Dart: `NativeWorld.threads`) gives a world a
  pool of up to 64 threads, POSIX or Windows', the caller one of them; the
  WebAssembly build has none and steps on the caller. The tree's queries
  and the narrow phase are shared out: each worker gathers its pairs in a
  lane of its own and the lanes are sorted together after, and each
  pair's manifold is made in a slot of its own and the slots closed up in
  key order, so a world of meshes, hulls, boxes, balls, capsules,
  cylinders and a hinged chain snapshots to the same bytes, every step,
  on one thread, two, three or eight. On four thousand bodies in a heap
  the collision stage fell from 13.3 ms to 3.8 ms on six threads; the
  solver, 8 ms, is still on one. The joined pairs' table is now built
  before the queries, not lazily inside one. ABI 16.

- **Water, phase 10.** `f3d_fluid` steps water as particles,
  position-based (PBF): each held near the density a lattice of its
  spacing has, a kernel twice the spacing wide, in a tank; only ever
  pushed apart, so nothing clumps (and there is no surface tension),
  with XSPH viscosity. A tank wall counts as the water going on past it:
  layers of still particles beyond it add to a particle's density and push
  it straight off. Without them the bottom layer had no neighbours below
  and the water pressed it flat: 325 particles where a layer holds 200,
  and the water too shallow; with them, 210, and a dam of a thousand
  settles with its centre of mass at half its 25 cm depth. The GPU runs
  the same passes, read a frame late; it agrees particle for particle
  until the dam splashes, then holds the same water.

- **A GPU pass that does not compile is refused, not fatal.** Kernels are
  built inside a validation error scope, so a WGSL module wgpu will not
  take makes the system's constructor throw instead of the device's
  default handler ending the process. Three tests passed a tolerance
  already scaled by its value, so they checked a kernel's rest density to
  8%, a pendulum's speed to 22% and a rolling ball to 2.2%; they now check
  to a part in 10⁵, 5% and 2%. ABI 15, GPU ABI 4.

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

Its `flutter3d_*` dependencies ask for `^0.9.0`.
