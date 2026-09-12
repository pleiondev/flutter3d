# flutter3d_cloth

An XPBD cloth solver — distance and cross-edge bending constraints, pins,
gravity, wind, damping, substeps, and collision against
[`flutter3d_physics`](../flutter3d_physics)'s own `CollisionShape`.

**No Flutter and no renderer in it.** A `ClothMesh` is a grid of particles as
flat typed arrays; `stepCloth` advances it by a fixed `dt`. Drawing it is
somebody else's problem — a caller reads `ClothMesh.positions` and
`ClothMesh.triangles` and builds whatever mesh its own renderer wants.

```dart
final cloth = ClothMesh.grid(cols: 20, rows: 20, spacing: 0.05);
const settings = ClothSettings();

void tick(double dt) => stepCloth(cloth, settings, dt);
```

## Why XPBD, not a spring-mass system

A spring-mass cloth needs a stiff spring to look inextensible, and a stiff
spring needs a tiny timestep to stay stable — the two pull against each
other. Position-based dynamics moves particles directly towards satisfying a
constraint instead, which cannot diverge the way an unstable spring force
can; XPBD adds back a physically meaningful compliance so a constraint's own
apparent stiffness does not silently change with the substep count.

## Collision

`pushOutsideObstacle` treats a `CollisionShape` as one convex solid — correct
for a box, a sphere, a capsule and a wedge, and only the bounding box of a
heightfield's own true, dented surface. Cloth draped over textured ground is
future work; nothing in this package's own test suite asks for it yet.
