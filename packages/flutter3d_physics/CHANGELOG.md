## Unreleased

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
