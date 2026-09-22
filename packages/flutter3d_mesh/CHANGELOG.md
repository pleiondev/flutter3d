## 0.7.0

**The first publication.** The 0.6.0 below calls itself the first release, and
it was the first inside the workspace: it never reached pub.dev. 0.7.0 is the
number the whole shelf goes out on, so that one number names one tree and
`^0.7.0` on any `flutter3d_*` package resolves against every other;
`doc/boundary-0.7.0.md` lists the thirteen packages that begin here. What
0.6.0 describes was a spike of three entries. The rest of the package is below.

* **Breaking against the spike.** `EditMesh.halfEdgesOf(face)` is gone; walk a
  face with `forEachHalfEdge`. `verticesOf` returns a `List<int>` where it
  returned an `Iterable<int>`. `vertexCount` and `faceCount` count live
  elements, and an id is a slot that may hold a deleted one. `toMeshData` was a
  flat-normal fan and now goes through `MeshLayoutPlan`, so the vertex count of
  the same mesh differs. `MeshData`, `Ray` and `TriangleBvh` come from
  `package:flutter3d_core/geometry.dart`; `flutter3d_geometry` was folded into
  `flutter3d_core`, which is the one sibling this package depends on.

* **`EditMesh` keeps a journal, and deletion is a tombstone.** Storage is
  `JournalledFloats` and `JournalledInts`, and `beginStep`/`endStep` bracket a
  `JournalStep` that covers all nine arrays or none, so positions and topology
  cannot be undone to different versions. `undo` and `redo` walk it,
  `abandonStep` drops a step without clearing redo, and `journalBytes` with
  `dropOldestJournalSteps` serve a history budget counted in bytes. A journal
  of previous values measured 2% of a full copy where chunked copy-on-write
  measured 92 to 100% on scattered edits. `deleteFace` and `deleteVertex` leave
  slots behind so ids stay stable, and `compact()` returns the packed mesh with
  an `IdRemap`. The mesh grows in place through `addVertex`, `addFace`,
  `splitEdge`, `splitFace`, `weldTwins` and `cutTwin`.

* **Attributes live in four domains and cost nothing until written.**
  `MeshAttribute` names `uv0`, `colour`, `weights`, `joints`, `crease`, `flags`
  and `materialSlot`. UVs are per corner, because a seam is two faces
  disagreeing about one vertex; `EdgeFlags.sharp` and `EdgeFlags.seam` are
  written to both halves of an edge; `FaceFlags.smooth` is per face. A layer
  nobody wrote answers a neutral value and is not allocated, and one created
  late is padded back to the journal's depth.

* **Conversion to and from `MeshData` is three decisions made in the open.**
  `importMeshData` welds by position within `max(diagonal * 1e-6, 1e-9)`,
  rebuilds polygons and returns the mesh, an `ImportReport` and the file's
  morph targets as `ShapeKey`s. Going back, `MeshLayoutPlan.build` ear-clips
  concave faces, splits normals at `MeshNormals.defaultSmoothAngle` of 30
  degrees, merges identical corners into one GPU vertex and keeps
  `gpuVertexToVertex`, `gpuVertexToCorner` and `triangleToFace`. A kept plan
  refills positions without rebuilding: at 200 thousand triangles the full
  conversion measured 102 ms, a refill 6.7 ms and a refill of 40 vertices
  1.5 µs. Import was quadratic, 6.6 s at 50 thousand triangles, and is 101 ms
  after the edge-key fix. `toBytes` and `fromBytes` are a little-endian tagged
  format that skips sections it does not know, and `editInIsolate` runs a
  `MeshWork` on another isolate, or inline on the web.

* **Normals.** `MeshNormals.build` weights by corner angle, without which a
  cube corner moves by 19 degrees depending on how the cube was triangulated,
  and breaks averaging at a face that is not smooth, a sharp edge or an angle
  past the threshold. `rebuildAround` recomputes only the fans around moved
  vertices. `flipNormals` and `makeConsistent` are on `EditMesh`;
  `makeConsistent` leaves an open island as it found it.

* **`Selection` is a value outside the journal**, so undo does not undo a
  click. It has an `ElementLevel` of vertex, edge or face, an edge id is the
  smaller of its two half-edges, and it offers `union`, `difference`,
  `intersection`, `toggle`, `convertedTo`, `grown`, `shrunk`, `linked`,
  `boundary`, `Selection.edgeLoop`, `Selection.edgeRing` and
  `Selection.byMaterialSlot`. A loop steps only through valence 4 and a ring
  only across quads.

* **Operations take `(mesh, selection, params)` and return an `OpResult`.** A
  refusal is `OpResult.refused` with a sentence. `translateSelection`,
  `rotateSelection`, `scaleSelection` and `transformSelection` pivot on
  `medianOf`; `extrudeFaces` builds no interior walls for a region; `loopCut`,
  `insetFaces`, `bevelEdges`, `bevelVertices`, `bridgeLoops`, `slideEdges`,
  `triangulateFaces`, `deleteSelection`, `duplicateSelection` and
  `splitSelection` are the rest of that shape. Others are shaped differently:
  `mergeByDistance` and `mergeAt` rebuild the mesh and return it with a
  `MergeReport`, `separateComponents` returns a mesh and an `IdRemap` per
  island, and `dissolveEdge` and `dissolveVertex` are methods on `EditMesh`.
  Extruding one face of a box gives 12 vertices, 20 edges and 10 faces with
  the Euler characteristic still 2. Not built: a bevel with more than one
  segment, which is refused in a sentence, a knife, and
  `insetFaces(individual:)`, which is accepted and has no effect.

* **Checks, holes and picking.** `MeshChecks.all` reports n-gons, boundary
  edges, non-manifold vertices, isolated vertices, degenerate faces, duplicate
  vertices and inverted shells as `MeshIssue`s that each carry a `selection`.
  `fillHoles(mesh)` closes every boundary chain and returns how many it
  closed.
  `MeshBvh` answers `raycast`, `facesInAabb` and `facesInFrustum` and can
  `refit` without a rebuild: at 200 thousand triangles a rebuild measured
  55 ms, a refit 5 ms and one ray 0.5 µs, and 10 000 random rays agree with a
  brute-force scan. `MeshPicker` finds `faceAt`, `vertexNear` and `edgeNear`.

* **Parametric shapes, recipes and fixtures.** `ParametricShape` is sealed
  over `ParametricCuboid`, `ParametricPlane`, `ParametricLathe`,
  `ParametricSphere`, `ParametricCylinder` and `ParametricTorus`; each builds
  quads with sharp rings where the engine's primitives duplicate vertices, a
  flat cap is one n-gon, and the UVs match the engine's corner for corner.
  `recipes()` lists sixteen builders in four `RecipeCategory`s, from
  `floorLamp` to `window`, at real dimensions.
  `package:flutter3d_mesh/testing.dart` is a second library with eight fixture
  meshes.

* **Modifiers.** `Modifier` is sealed over `ArrayModifier`, `MirrorModifier`,
  `SmoothModifier`, `SubdivisionModifier` and `BooleanModifier`, each with
  `toJson`; `modifierFromJson` answers null for a kind it does not know.
  `ModifierStack.evaluate` is memoized on the identity of the base and of the
  operands, since an operand can change while the base does not.
  `catmullClark` honours semi-sharp creases and interpolates UVs per face so
  seams stay, and ten passes of `smoothVertices` with `preserveVolume` shrink
  a sphere's mean radius by 0.04% where plain Laplacian smoothing shrinks it by
  26%. `mirror(bisect: true)` throws `UnimplementedError`, and the array and
  mirror modifiers carry positions, topology and material slots and no UVs,
  colours, creases or skin.

* **Booleans.** `booleanUnion`, `booleanSubtract` and `booleanIntersect`
  return a `CsgResult` or null past `maxPolygons`, 200 000 by default, checked
  before the work and again on the result. The BSP runs on its own stack so a
  deep tree does not overflow the native one. Coplanar polygons are counted
  into `CsgResult.warnings`. The result can contain T-junctions, so it may not
  be watertight; its volume is right.

* **UV.** `projectUv` with `UvProjection.planar` or `.box`, `splitIslands`
  along seams, `lscm` solved by conjugate gradients with a Jacobi
  preconditioner, `unwrapMesh` with `onProgress` and `isCancelled`, `stretchOf`
  reading 1.0 for an isometry, and `packIslands`, a shelf packer that may
  rotate by 90 degrees.

* **Skin weights and shape keys.** `paintWeight`, `normalizeVertexWeights`,
  `pruneVertexWeights`, `mirrorWeights`, `smoothVertexWeights` and
  `gradientWeights` edit the `weights` and `joints` layers, and
  `limitInfluences` holds them to a count. A `ShapeKey` is a set of positions
  that `grownTo` and `remappedBy` keep in step with the mesh, and
  `shapeKeyMorphTargets` emits one delta per GPU row of a `MeshLayoutPlan`.

* **Simplification, remeshing and collision shapes.** `simplifyMesh` and
  `simplifyMeshWithAttributes` take and return `MeshData`, the second holding
  borders with `boundaryWeight`. `isotropicRemesh` and `retopologize` return
  an `EditMesh`; the remesher assumes a closed mesh and does not project back
  onto its source. `computeConvexHull`, `decomposeConvex` with a default of 12
  pieces, `fitBoxByInertia`, `fitSphereByInertia`, `fitCapsuleByInertia` and
  `staticMeshShape` make what a physics world needs. There is no LOD chain in
  this package; `LodSpec` is `flutter3d_model_core`'s.

* **Sculpting, multiresolution and baking.** `SculptMesh` stores a mesh in
  chunks of 1024 vertices with `dirtyChunks`, so a stroke re-uploads what it
  touched. `applyBrushStroke` takes a `Brush` of eight `BrushKind`s and three
  `BrushFalloff`s, with `symmetryX`. `Multires` keeps levels with `meshAt`,
  `displace` and `displacementMap`; a million vertices over four levels
  measured 4.1 s. `bakeNormalMap`, `bakeAmbientOcclusion`, `bakeCurvature` and
  `bakeThickness` fill a `BakedMap` through `rasterizeUv`, and `dilate` pads
  the islands. `projectBrush` maps a 3D brush to `UvSpan`s for texture paint.
  Dynamic topology is not built.

* Plain Dart. Dependencies are `flutter3d_core` `^0.7.0` and `vector_math`.
  The archive carries `skills/flutter3d-mesh-editing-topology/` for a coding
  agent, installed with `dart run skills@ get`.

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
