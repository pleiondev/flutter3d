## Unreleased

- **One rule for a jump that does not clear a platform solid from above:
  it falls back through.** The controller no longer pushes the body out of
  such a platform when it overlaps one, as the physics core does not.
  `CollisionWorld.mirrors` keeps a world's copies, such as the physics
  core's, up to date at the end of every `update`.

- **One-way platforms as a rule, rays elsewhere.**
  `CharacterController.fromAboveLayers` and `dropThrough` say one-way
  platforms as a rule the body keeps on either backend. They are a floor
  from above and nothing from below or the side. `CollisionWorld.rays`
  takes a `WorldRays` that answers every `raycast` not asking for
  triggers. `CollisionWorld.revision` counts colliders joining and leaving.
  A character moved by a mover is not pushed out of overlaps by its box:
  its volume is the mover's.

- **A world can say who moves its characters.**
  `CollisionWorld.characterMover` takes a `CharacterMover`. When one is
  set, `CharacterController` keeps everything its step decides: speed,
  friction, gravity, the jump, coyote time, being carried. It hands the
  mover only the geometry: sliding, the step, the slope, keeping to the
  ground. A body whose `solidFilter` asks about each contact keeps its own
  sweeps. Null, the default, is the controller as it was.

- **A character can be walked by its animation.**
  `CharacterController.step(drivenBy:)` takes a displacement along the
  floor in place of a wish to accelerate towards, such as root motion
  handed over by an animation graph. The body moves at that speed, swept
  as any move is: it stops at a wall, climbs a step, falls off an edge and
  jumps as before. Without it, nothing changes.

- **Bodies are stepped through `RigidDynamics`.** `WorldStep`, the games,
  the crates and the Flame bridge hold the interface, and `Dynamics`
  implements it unchanged. `flutter3d_physics_native`'s `NativeDynamics`
  is the other implementation. A character's push is `Pusher`, the same
  code `Dynamics.push` ran, now shared, so a crate is shoved the same
  whichever steps it. `CollisionWorld.movers` lists the moving colliders,
  as `statics` lists the still ones. `saveState()` and `restoreState()`
  carry what a backend holds beyond its bodies through a save: nothing
  for `Dynamics`.

- **Drops let go on top of each other spread instead of flying apart.**
  A stream lets go of its drops at one point step after step, so
  `ParticleFluid` laid each lump exactly on the last. A coincident pair
  counts whole in each other's density, but the kernel has no gradient at
  nought, so the constraint read heavily compressed with nothing to part
  along and λ = −C / |∇C|² ran away: the chemistry bench's overflowing flask
  threw thirty thousand particles eleven metres up. Coincident particles now
  part along a direction set by the pair, and each substep first takes the
  compression it starts with out of the positions alone (pre-stabilisation),
  so overlap is never turned into speed. `velocities` reads each particle's.

- **No wave stands steeper than Stokes' limit.** `FreeSurface` breaks a
  mode higher than a fourteenth of its wavelength: the linear modes knew no
  bound, and a vessel turned sixty-seven degrees in a step laid its old
  level out as a thirty-four millimetre wave that threw most of it over the
  lip.

- **An upright, overfull vessel runs over its edge, outwards.** Over every
  part of a level lip at once, the outward pulls cancelled: the spill left
  from the middle of the mouth with no speed and fell back in, round and
  round. It leaves over the stretch passing most, no wider than the mouth.

- **A body can turn, if it is built to.** `RigidBody` has an `orientation`,
  an `angularVelocity`, an inertia tensor in its own axes
  (`inertiaLocal`, `inverseInertiaLocal`) and one in the world's
  (`inverseInertiaWorld`), plus `applyImpulseAt` and `applyTorqueImpulse`.
  `inertiaFor(shape, mass)` gives the principal moments of a box, a sphere
  and a capsule; a wedge and a heightfield are taken as their bounding box.
  Only a body built with `canRotate: true` turns, because every shipped
  level was tuned against crates that do not tip. The others have an
  inverse inertia of zero and step exactly as before. A turning body
  keeps its angular momentum rather than its angular velocity, which is
  the gyroscopic term taken implicitly: a box spun off its principal axes
  for ten seconds holds L to within 1e-4. `angularDamping` is zero by
  default. No contact turns a body yet, and the collider stays
  axis-aligned. `save()` writes the orientation and spin only for a body
  that can turn, so saved levels and their digests do not change.
  `readQuaternion` reads one back.
- **The step has trigonometry it may call.** `src/portable_math.dart`
  holds `sin`, `cos`, `sinCos`, `atan`, `atan2`, `asin` and `acos` built
  from fdlibm's kernels out of IEEE arithmetic alone, for the hinge
  angles and cone limits that come next. It is not exported, because
  `flutter3d_sim` re-exports this package beside its own `Portable`.

## 0.8.2+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.2

* **A ball no longer shows through the cloth draped over it.** A sphere and
  a capsule pushed each particle to their radius plus
  `ClothSettings.collisionThickness`, and the flat triangles between the
  particles sagged back inside by their sagitta: a sheet of 0.09 m
  cells on a 0.2 m ball had its triangle edges 0.35 mm inside the ball, and
  the ball's facets showed through. Each particle is now pushed far enough
  that the widest of its own triangles, measured where the sheet stands at
  the start of the step, keeps its nearest point half a thickness clear of
  the surface, and never closer than a whole thickness as before. The
  nearest point is the circumcentre of an acute triangle and the middle of
  the longest edge of an obtuse one. On that sheet the edges now rest
  6.2 mm above the ball. Only spheres and capsules are measured for. `pushParticleOutside` and
  `pushOutsideObstacle` take the width as `span`; zero keeps the old answer,
  and boxes, wedges and heightfields ignore it.

## 0.8.1

* **A sheet resists shear.** `ClothMesh.grid` built edges along rows and
  columns and nothing across a quad, so every quad could fold flat into a
  rhombus. A square sheet dropped on a ball stretched its corners into strands
  that reached the floor, and what lay on the floor spread into a blot with no
  straight edge. The grid now carries both diagonals of every quad as
  `ClothMesh.shearPairs`, solved with `ClothSettings.shearCompliance` (5e-2 by
  default, soft enough that the sheet still follows a sphere). A `ClothMesh`
  built by hand without them shears as it did.
* **A sheet no longer passes through itself.** Nothing kept one part of a
  sheet out of another, so a square dropped on a ball folded its corners
  under itself on the floor and the two layers ran into each other, drawn as
  a flat grey triangle and flickering patches. Each particle is now a sphere
  of `ClothSettings.selfCollisionThickness` (the mesh's mean rest edge by
  default) that the others are pushed out of inside the iteration loop,
  except those already that close in the rest shape, which
  `ClothMesh.restPositions` keeps. The close pairs come from a spatial hash
  and are gathered again only once a particle has moved half a skin, so on
  an 80×80 sheet at 12 substeps and 4 iterations a step costs 7 to 9% more
  (33.6 to 35.9 ms falling, 37.4 to 40.6 folded). On by default;
  `ClothSettings.selfCollision: false` turns it off.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.4

- **Cloth meets a sphere and a capsule as themselves.** Every obstacle pushed a
  particle out through its `expandedPlanes`, which is exact for a box and a
  wedge and the bounding cube for a sphere and a capsule: a sheet dropped on a
  ball draped over a box. A heightfield answered no planes at all, and the
  plane walk pushed by nought times infinity — every particle NaN.
  `pushParticleOutside` is new and answers per shape, in doubles; a sphere and
  a capsule are their nearest surface point, a heightfield the ground under
  the particle. `pushOutsideObstacle` keeps its signature.
- **A draped sheet no longer blows up.** Contacts were resolved once after the
  constraint sweep, and with `iterations: 1` a sheet wrapped round a ball
  pumped itself from half a metre a second to NaN in about thirty steps —
  with or without wind. Contacts are solved inside the iteration loop now, as
  XPBD and Flex do, and `iterations` defaults to 2.
- **Wind is a force, relative to the cloth.** It was added to a position as a
  velocity — several hundred times its value at eight substeps, and growing
  with the substep count — and ignored the cloth's own velocity, so a sheet in
  a one-metre-a-second wind reached forty. It is `Δx = F·w·h²` on the air's
  velocity relative to each triangle, bounded so a drag cannot reverse it in a
  substep. A scene tuned against the old wind needs a `drag` in the ones where
  it had tenths.
- **`ClothSettings.friction`**, new: position-level Coulomb friction against
  obstacles, measured against a particle's push summed over the substep's
  iterations, so the iteration count does not decide how much it holds. Zero,
  the default, slides as before.
- A heightfield obstacle holds cloth only over its own footprint. Past the
  edge its height is the edge's, which a body walking off the map wants and a
  hem hanging over the side would catch on.
- **`damping` says what it does**: a fraction per substep, which it always was,
  not per step.
- A particle is no longer rounded to single precision through a `Vector3` for
  every obstacle, and the solver allocates nothing per substep.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**Breaking.** Accepted `flutter3d_cloth`, because a package that only ever
reacted to this one's own `CollisionShape`s and depended on nothing else had
no boundary left to justify standing apart — an XPBD solver, not a second
layer of physics. `ClothMesh`, `ClothSettings`, `ClothObstacle`,
`pushOutsideObstacle` and `stepCloth` now live under `src/cloth/` and export
through this package's own barrel; `flutter3d_cloth` itself is gone from the
workspace. It was never published, so there is nothing to discontinue on
pub.dev.

**What that is, for a reader who never saw the other package.**
`stepCloth(mesh, settings, dt, obstacles:)` advances a `ClothMesh` in place by
`ClothSettings.substeps` XPBD substeps, 8 by default: gravity, `WindSettings`
and damping go into a predicted position, the structural and bending
constraints are solved against it with multipliers reset each substep, and
particles are pushed out of each `ClothObstacle`. `ClothMesh.grid` builds a
rectangular sheet. An obstacle is a `CollisionShape` and a position, tested
through `expandedPlanes`, which is right for a box, a sphere, a capsule and a
wedge and gives a `CollisionHeightfield` its bounding box and not its surface.
Every loop walks a typed array by index, so the same state, settings and `dt`
give the same output.

**Nothing else moved.** Shapes, the broadphase, queries and the character
controller are byte for byte 0.6.0's, and the package still depends on
`vector_math` and no sibling. The archive carries a skill for a coding agent,
`skills/flutter3d-physics-walking-and-queries/`, installed with
`dart run skills@ get`.

## 0.6.0

* **No code, and no floor to move.** `lib/` is byte for byte 0.5.1's — the
  heightfield collision shape that arrived there is unchanged — and this package
  depends on no sibling, so nothing in its pubspec had to follow the set. It
  takes the set's number because `flutter3d_sim` and both games above it now
  floor at `^0.6.0`, and a floor is only worth stating if it names a
  combination that was built.
* Nothing added to the sealed hierarchy of collision shapes, so nothing
  downstream has a new `switch` arm to write.

## 0.5.1

**Ground is a collision shape, and the joins in it are not surfaces.**

* **`CollisionHeightfield`.** A field of samples a body walks on: the fifth
  shape, and the first that is not one convex solid. It comes in through
  `CollisionShape.partsIn`, which hands a query the convex pieces near it —
  one prism per triangle — so every sweep, push and ray is the closed-form
  plane walk the world already had, several times over. A sweep against ground
  costs four times a sweep against a brush and a step of a walking body nearly
  seven; `tool/ground_cost.dart` is the measurement.
* **`CollisionShape.partSeams`, which is what makes it walkable.** Where two
  triangles meet, each prism ends in a vertical face the other continues
  through. Reported, it is a wall nobody drew and a body that catches on the
  ground every metre. The shape names those faces and `CollisionWorld` refuses
  a contact on one.
* **A sweep's normal is no longer always an axis.** It stopped being one when
  the wedge arrived and the documentation had not caught up; ground makes it
  the ordinary case. Comparing `normal.y` against a walkable limit is still
  right, and treating the vector as an axis and a sign is not.
* **A capsule is swept as a capsule.** Growth is now the moving shape's own
  support function rather than the box around it, so a walking body no longer
  catches a shoulder on a corner it should round. Against the six faces of a
  box the two answers are identical, so nothing in a level of brushes moved.
* **Depenetration splits its push into components.** The deepest push in each
  of six directions is what stops a body on a seam being lifted twice, and it
  used to file a slanted normal's whole depth under one axis — so a body on a
  ramp was lifted short of the way out, every step, for as long as it stood
  there.
* **`contactBetween` knows about ground**, because the bounding-box fallback
  for a field of samples is the size of the map: every crate on the level would
  have been reported a hundred metres deep inside one solid.

## 0.5.0

**Breaking.** The contact filter takes one object.

* **`ContactFilter` is `bool Function(SweptContact)`.** A function type is
  frozen the day it is published, so telling a filter the contact point or how
  far along the sweep it happened would have broken every filter anybody had
  written. `tool/filter_cost.dart` says what it cost: 1.932 microseconds a step
  became 1.953, and the `late`-field version that would have cost 1.997 is what
  the object avoids. The number is written into the benchmark beside it.
* **`CharacterController.groundNormal`.** The probe that decides whether a body
  is standing on something reads a normal to do it and discarded it, so a
  caller that wanted to know which way the floor tilts had to sweep again for
  what this had just measured. Straight up while airborne rather than null, so
  arithmetic on it needs no branch.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* Collision shapes, a broadphase grid, ray and overlap queries, and a capsule
  character controller that walks slopes, steps and ramps.
* Rigid bodies with mass, gravity, impulses, pushing and rest — no rotation
  yet, and the character controller stays kinematic on purpose.
* No Flutter and no renderer in it, which is the boundary the package exists to
  keep: it runs under `dart test`.
