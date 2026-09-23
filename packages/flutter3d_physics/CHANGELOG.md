## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

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
