## 0.6.0

**The first release, taking the set's number rather than a first of its own**,
because the whole workspace goes out together.

* **`EditMesh`: half-edge topology over `Int32List` and `Float32List`.** Faces
  of any valency, twins matched by the pair of vertices an edge runs between,
  boundaries answered as boundaries rather than as a face that is not there.

* **A cuboid as six quads, an extrusion, and the way back to `MeshData`.**
  Quads and not triangles, which is the point: a loop cut through a
  triangulated cube has nothing to cut along.

* **`validate()` and the Euler characteristic**, because every invariant here
  has been broken silently by an operation in some modeller — a `next` that
  leaves its face, a twin that is not mutual — and each is invisible until a
  loop walk runs forever.
