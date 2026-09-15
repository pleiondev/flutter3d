# 3D model editor on flutter3d — the development plan

Compiled 2026-09-09. Assembled from eleven aspect plans (mesh core, document
and MCP, formats, rendering and viewport, shell, materials, animation,
professional modes, quality, phase 0, publishing), written on top of the
[doc/model-editor.md](model-editor.md) working-through and the design-handoff
README (since 2026-09-14 kept in the tree at
[doc/design/modeler-handoff/](design/modeler-handoff/README.md), with its
2026-09-11 supplement and the 27 screens). Package, screen, and decision
names come from there. Everything said
about the engine was checked by the aspects against the code at `239ccf8e`.

Notation in tables: **size** (S up to a week, M two to three, L a month or
more, for one person, as in the working-through §6); **phase**; **⚙** — an
engine change (`engineChange`); **⚠** — the item conflicts with the ROADMAP
or ARCHITECTURE, discussed in §8; **⇢ X** — the item merges into X during
synthesis, its id kept for references. Packages: `mesh` = flutter3d_mesh,
`core` = flutter3d_model_core, `mcp` = flutter3d_model_mcp, `app` =
apps/flutter3d_modeler, `engine` = flutter3d, `hw` = flutter3d_hardware and
the four backends, `geometry` = flutter3d_geometry and `formats` =
flutter3d_formats — two pure vocabulary packages (§3, 2026-09-09 decision;
before it, the plan held one working name for both), `rig` = flutter3d_rig,
`cloth` = flutter3d_cloth, `fbx` = flutter3d_fbx.

317 items total from the aspects, plus 3 added during synthesis (§3), 9 added
following the 2026-09-09 critique (`-n` suffix), and 5 added following owner
decisions on 2026-09-09 (`-d` suffix; history at the end of the file).

---

## 1. In short

1. **One blocker before the first line: the engine's vocabulary lives in a
   package with the Flutter SDK.** `packages/flutter3d/pubspec.yaml` declares
   `flutter: sdk`, so `flutter3d_model_core → flutter3d` from the
   working-through §5.1 passes the scanner but doesn't resolve under
   `dart pub get`. Five aspects reached the same conclusion independently
   (mesh-03, doc-00/01, qa-03, p0-09, rel-03): move `MeshData`/`VertexLayout`/
   `Shape`/`Ray`/`ModelDocument`/decoders/writers into pure packages that
   `flutter3d` re-exports. Owner decision 2026-09-09 (B1 closed): **two
   packages**, not one. `flutter3d_geometry` — `MeshData`, `VertexLayout`,
   `Shape`/`LatheShape` and derivatives, tangents, `morph_target`, `CpuMesh`,
   `math/intersections`, `Ray`, `TriangleBvh`; `flutter3d_formats` —
   `ModelDocument`, `SurfaceMaterial`, `MaterialDocument`/`MaterialHint`,
   `lighting_model`, the synchronous half of `model_loader`
   (`ModelFormat`, `ModelDecoder`, `sniffModelFormat`, `decodeModel`), gltf/
   obj/f3d/ktx2/stl decoders, writers `F3dWriter`, `GltfWriter`, `ObjWriter`.
   `formats` depends on `geometry`, `mesh` on `geometry`, `model_core` on
   both, `flutter3d` re-exports both; only the isolate wrapper and
   `convert_asset` stay in the engine from formats. Deadline 2026-09-25.
2. **The critical path is the geometry core, and the calendar is the sum.**
   `mesh-11` (a half-edge structure over persistent arrays, L) and a chain of
   eight Ms around it: ≈29 weeks from a green `main` to a tutorial passed by
   a cohort, if everything else ran in parallel. Recomputed 2026-09-09
   strictly against the "depends" column: the path runs through
   `mesh-13 → mesh-25` (not `mesh-14 → 19 → 23`) and, after `doc-07`, through
   `doc-20 → rel-09 → rel-16`. Owner decision 2026-09-09: **one** person, with
   agents, so the critical path sets the order and phase 1's timeline is the
   sum of the sizes of all its items: 73 S, 44 M, 3 L ≈ 198 weeks for one
   person; with agents on the format, overlay, platform, and localization
   tracks, roughly 172 (an estimate, §4.3).
2b. **Four platforms, and an equal-footing web from the first version.**
   Decision 2026-09-09: phase 1 ships on macOS, in-browser, on Android
   (tablet and phone), and iOS (iPad and iPhone); layouts 03/04, pen, touch,
   and platform configuration are phase-1 items (ui-05, ui-19, ui-21); an
   iPad and an Apple Developer account are bought by mid-phase (rel-19d). The
   web isn't "by measurement" — p0-02/p0-08 became quality gates, and an
   unmet threshold turns into a phase-1 item (a JS build as a recorded
   exception, chunks instead of an isolate, a web worker ui-34d for a freeze
   longer than 1 s). FBX is read by its own reader in Dart in
   `flutter3d_fbx` — a separate phase-2 track after phase 1 is in users'
   hands; no server-side conversion.
2a. **Phase 1 gets a "material" step.** The design plan puts basic materials
   in phase 1, and the core scenario is "clean the mesh, edit the material,
   export to GLB"; before the critique, the only path to a material in phase
   1 was an MCP command with no UI and no textures. Added: mat-04a-n (a
   panel: color, metallic, roughness, assignment, one texture) and
   `SetTexture`/`AddImage` into mat-01; phase-1 acceptance requires color and
   texture in the GLB.
3. **Phase 0 is numbers, not opinions.** Twelve measurements with recorded
   thresholds (p0-*): what the web needs to pass the gate (not "equal or
   view-only" — the web is equal footing per the 2026-09-09 decision),
   chunks or a log for the history snapshot, `DeviceMesh.overwrite` in phase
   1 or 4, an isolate or chunks on the web. Answer deadline: 2026-10-05.
4. **46 engine changes, and games need every one.** glTF/OBJ/STL writers,
   `TriangleBvh`, the `MeshOverlay` overlay, `overwriteGeometry`/
   `overwriteTexture`, `Pose` and IK, a triangle counter, LOD in
   `ModelDocument`, a texture encoder (already on the ROADMAP). Each verified
   through conformance or a golden frame (§6). The FBX reader is not an
   engine change: it's a separate package over `formats`.
5. **Thirty-seven divergences from the ROADMAP, ARCHITECTURE, the
   working-through, and the design**, each with a decision (§7); five main
   ones: "zero engine changes for the editor," `apply`/`revert`, "no
   node-graph materials," "eight lights is a ceiling," soft bodies
   "committed" with no line in Committed. Two added by critique: asset
   composition in a scene (#36, closed 2026-09-09 — placing assets is part
   of phase 2) and the viewport gradient (#37).
6. **Three duplicate implementations reduced to one**: a triangle BVH
   (mesh-20 / view-09 / p0-10), the project format (doc-09/10 / fmt-17),
   modifiers (mesh-40 / mat-18 / doc-23), the GltfWriter's skins
   (fmt-07 / anim-26), simplification and unwrapping (mesh-70/71 / pro-lod /
   pro-uv), weights (mesh-60 / anim-09). Where each one lives — §3.
7. **Phases 2–4 are estimated with a caveat.** Phase 2–4 items (modifiers,
   booleans, rigging, sculpting, simulations) were written before phase 0
   gave numbers; the L sizes there are an order of magnitude, dependencies
   are the best knowledge of the code available.
8. **63 open questions in ten groups after merging duplicates** (§8; of 87
   rows, B1, F2 [Ж2], and D4 [Г4] closed by the 2026-09-09 critique, 21 more
   — A2, B1 [Б1], B3, B8, B9, C3 [В3], C5, C8, D2 [Г2], D9, E7 [Д7], F1 [Е1],
   F2 [Е2], F5 [Е5], F8 [Е8], F11 [Е11], F12n [Е12n], G1 [Ж1], G4 [Ж4], H1
   [И1], K2 — closed by owner decisions on 2026-09-09, B1 rewritten); six of
   the remaining ones are needed before phase 1 starts (listed in §5.2), the
   rest before their own phase.

---

## 2. Aspects

### 2.1 Mesh core (`mesh-`)

A half-edge `EditMesh` over `Int32List`/`Float32List` with persistent
chunks, conversion to/from `MeshData`, selection, phase 1–2 operations,
modifiers, checks, parametric objects with quad topology, BSP booleans, a
BVH for CPU picking. The engine already has a triangle vocabulary, `Shape`
generators, Lengyel tangents, `rayTriangle`, a sphere-based `SceneBvh` —
there is no editable topology at all. Two code findings: `flutter3d` pulls
in the Flutter SDK (mesh-03), and `Shape.build()` returns a triangulated
soup with seam duplicates, unusable for loop cut and Catmull-Clark
(mesh-28).

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| mesh-00 | Package skeleton: pubspec `resolution: workspace`, a barrel, a test; registered in the workspace, `flatDartPackages`, `notARepeatableStep` (otherwise `math.sin` is forbidden), the §16 publishing order, the §3.2 table. ⇢ qa-02, rel-02/03 | mesh | S | 0 | — | `tool/structure.dart` and `tool/ci.sh` are green with the package |
| mesh-01 | Spike 0.2: `EditMesh` over Int32List, a cube, a face extrusion, a fan, output into arrays, a frame via `flutter3d_testing.renderFrame`. ⇢ p0-04 (thresholds from there) | mesh | M | 0 | mesh-00 | V−E+F=2, volume grew by area×h, frame `mesh-spike-extrude.png`, a `toMeshData` measurement at 50/200k in the doc |
| mesh-02 | Measurement 0.3: a chunked CoW vector (256/1024/4096) at 200k vertices, 1% in a row and 1% scattered; alternative — a sparse patch. ⇢ p0-05 | mesh | S | 0 | mesh-01 | a chunk × sample table → bytes/μs; a decision on chunk vs. patch |
| mesh-03 ⚙⚠ | Move `geometry/*` (mesh_data, vertex_layout, shape, lathe, tangents, morph, CpuMesh) and `math/intersections.dart` into a pure `flutter3d_geometry` package, `flutter3d` re-exports. 2026-09-09 decision: this is the first of two vocabulary packages, the second (`formats`) is doc-01 (§3) | engine + geometry | M | 0 | mesh-00 | scanner green, 4322 tests with no import edits, `bench_geometry.dart` builds AOT as a separate `main` with no `MeshGeometry` (the aggregate `bench.dart` pulls in `GraphicsDevice → Widget` and doesn't build AOT — ARCHITECTURE §14) |
| mesh-04 | An AOT package bench following `packages/flutter3d/tool/bench`'s pattern: `toMeshData`, a snapshot, `importMeshData`, BVH, extrusion ×1000 | mesh | S | 0 | mesh-01 | the binary prints ns/element, numbers in the doc, spread <5% |
| mesh-10 | Per p0-05's result — not CoW chunks, but a log of prior values: `JournalledFloats`/`JournalledInts` over a flat array, a history step is a `JournalStep` with indices and what was there (`journal.dart`). Persistent vectors were rejected by measurement: on a scattered selection, a step costs 92–100% of a full copy, because a thousand vertices touch nearly every chunk | mesh | M | 1 | mesh-02, p0-05 | a step ≤2% of a full copy under both distributions; undo returns the array to exactly its prior state |
| mesh-11 | `EditMesh`: origin/next/twin/face, outgoing, a face's halfEdge, faces of any valence, tombstones + `compact()`→`IdRemap`; `EditMeshBuilder` with Euler primitives; allocation-free iterators; `validate()` | mesh | L | 1 | mesh-10, mesh-01 | cube/torus/plane: χ, boundaries, `validate()` after every operation; a "don't update outgoing" mutation is caught |
| mesh-12 | Attribute layers: positions, joints/weights per vertex; uv0, color per corner; sharp/seam/crease per edge; materialSlot/smooth per face; inheritance rules on split in the builder. The `uv0`-fill rule for operations (added by critique): split — corner interpolation, extrude — copy the source face's corner onto the side quads, new faces with no source — zero UV flagged in `OpResult`. The `seam` flag closes pro-uv-01 | mesh | M | 1 | mesh-11 | split in the middle: UV averaged, weights normalized; a missing layer — a neutral value |
| mesh-13 | `EditMesh.fromMeshData`: welding by position (eps from bounds), twins, BFS orientation repair, non-manifold splitting, `ImportReport` | mesh | M | 1 | mesh-11, 12, 03 | `CuboidShape` → 8/12/6 (triangles); a sphere: the seam is welded; three faces on one edge → `splitNonManifold=1` |
| mesh-14 | `MeshLayoutPlan.build` (triangulation, per-corner normals, a GPU-vertex key → indices, `triangleToFace`, `gpuVertexToVertex`) + hash-free `fillVertices`; `toMeshData` by `materialSlot` | mesh | M | 1 | mesh-15, 16, 12, 03 | a sharp cube → 24 vertices/36 indices, normals = `CuboidShape`; `fillVertices` changes exactly the given rows |
| mesh-15 | N-gon triangulation: a quad along the shorter diagonal by planarity, Newell ear clipping, a fan on failure + a flag; no allocations | mesh | S | 1 | mesh-11 | an L-shaped hexagon → 4 triangles; a "bowtie" quad picks its diagonal by planarity |
| mesh-16 | `faceNormals`, `cornerNormals` split by sharp/angle/smooth, `flipNormals`, `makeConsistent` | mesh | S | 1 | mesh-12 | a sharp cube → face normals; a sphere within 6° of radial; flip changes the sign of the volume |
| mesh-17 | Tangents via `withGeneratedTangents`; a sign-of-`w` test against `CuboidShape`/`PlaneShape` and a mirrored island | mesh | S | 1 | mesh-14 | a sign test; frame `mesh-normal-map` in the app matches the engine's cube |
| mesh-18 | `toBytes`/`fromBytes`: sections aligned to 4, an unknown one skipped, determinism | mesh | S | 1 | mesh-12 | byte-exact round trip; an extra section is read; an "unaligned" mutation → RangeError |
| mesh-19 ⚠ | `Selection` (`ElementLevel`, a sorted Int32List, an active element), level conversions, `edgeLoop`, `edgeRing`, grow/shrink, linked, boundary, `Selection.byMaterialSlot` | mesh | M | 1 | mesh-11 | a torus 8×8: loop=ring=8; a cube: a loop stops at valence 3; a "ring with no quad check" mutation is caught |
| mesh-20 | `MeshBvh` over the plan's triangles, on top of `TriangleBvh` from view-09: `refit(positions)`, `rebuild(plan)`, `queryRay/Aabb/Frustum`. One `TriangleBvh` implementation shared by mesh-20/view-09/p0-10 (§3); the class's owner is view-09 | mesh | M | 1 | mesh-14, 03, view-09 | 10,000 rays = brute force; refit = rebuild; a 200k bench in the doc |
| mesh-21 | `MeshPicker`: `faceAt`, `vertexNear`/`edgeNear` within a radius with visibleOnly, `inFrustum` for a box | mesh | S | 1 | mesh-20, 19 | a click at a cube face's center — the face; a box around half the cube — 4 or 8 vertices |
| mesh-22 | `translate/rotate/scaleSelection` with a pivot; one signature, `op(EditMesh, Selection, Params) → OpResult` | mesh | S | 1 | mesh-19, 10 | round-trip byte-exact; scale 2 → volume ×8; topology 100% shared |
| mesh-23 | `extrudeFaces` (region/individual, side quads with UV), `extrudeEdges` (boundary only) | mesh | M | 1 | mesh-19, 11, 12 | a cube face: V=12, E=20, F=10, χ=2; two adjacent faces → 6 side quads; side-quad UVs confirmed by a test (corners 0..1 along extrusion height) |
| mesh-24 | `loopCut(edge, cuts, factor)` over `edgeRing`, `splitEdge`+`splitFace`, attribute interpolation | mesh | M | 1 | mesh-19, 12 | a 16-segment cylinder: +16 V, +32 E, +16 F, all quads; a torus — a closed loop |
| mesh-25 | `mergeByDistance`, `dissolveEdge`, `dissolveVertex`, `mergeAt` | mesh | M | 1 | mesh-11, 19, 13 | dissolving the diagonals of `fromMeshData(Cuboid)` → 6 quads; two cubes sharing a face merge |
| mesh-26 | `delete` by level, `separate` by component, `duplicate`, `split`; `IdRemap` | mesh | S | 1 | mesh-19, 11 | deleting a cube face → 6 boundary edges; separating two cubes → 2 meshes |
| mesh-27 | `MeshChecks`: ngons, nonManifoldEdges, boundaryEdges, isolatedVertices, degenerate, inverted, duplicateVertices, χ per component; `MeshIssue(kind, ids)` | mesh | S | 1 | mesh-11, 15, 13 | per-function test with a mutation; `signedVolume` confirms inverted |
| mesh-28 ⚠ | A sealed `ParametricShape` (Cuboid/Plane/Cylinder/Sphere/Torus/Lathe with engine specs) → `toEditMesh()` with quads, sharp instead of duplicates, n-gon caps; UV per corner matching `Shape.build()` (`VertexLayout.standard` carries `texcoord`) — otherwise a phase-1 cube can't take a texture in a GLB | mesh | M | 1 | mesh-11, 12, 16 | a 16-segment cylinder: `validate()`, `edgeRing` closed, volume >0; a "no sharp on a repeated point" mutation is caught by the normals; the `uv0` layer is filled for all six shapes |
| mesh-29 | A parity test, `ParametricShape.toEditMesh().toMeshData()` against `Shape.build()` (volume, bounds, triangle set, the cube's 24 GPU vertices, `texcoord` within 1e-6) | mesh | S | 1 | mesh-28, 14, 13 | six pairs, default and non-default parameters; texcoord matches per corner |
| mesh-30 | `EditMesh`/`Selection`/`OpResult` fit for `Isolate.run` (no closures), `TransferableTypedData` via mesh-18; documented "on the web — the main thread, chunked or a worker (ui-34d)" | mesh | S | 1 | mesh-11, 18 | extrusion in an isolate = in place; 200k transfer time in the doc |
| mesh-31 | Phase-1 measurements: fromMeshData, plan/fill, BVH build/refit, extrusion ×1000, loop cut ×256, a 1% snapshot; an AOT build in `tool/ci.sh` | mesh | S | 1 | mesh-04, 14, 20, 23, 24 | ≥8 rows in the doc, spread <5% |
| mesh-32 | Fuzzing: `Random(1234)`, 500 operations × 3 seeds, `validate()` + `MeshChecks.all()` empty + a round trip after each; minimization prints Dart code. ⇢ qa-07 | mesh | S | 1 | mesh-22..27 | <10 s; a mutation in `dissolveEdge` is caught within 50 steps |
| mesh-33 | `lib/testing.dart` with fixtures; frames `mesh-extrude`, `mesh-loop-cut`, `mesh-lathe`, `mesh-sharp-vs-smooth` in the app's tests, not among the 43 scenes | mesh + app | S | 1 | mesh-14, 23, 24, 28 | 4 PNGs, zero tolerance; a "no sharp" mutation changes the frame |
| mesh-40 | `sealed class Modifier { apply(base, ctx); toJson }`, `ModifierContext`, `ModifierStack.evaluate` = a fold memoized by the base's identity. The single place the `Modifier` type lives (§3) | mesh | M | 2 | mesh-11 | the stack is computed once across two evaluates; a JSON round trip |
| mesh-41 | `mirror(plane, mergeDistance, bisect, flipUv)` + `MirrorModifier` | mesh | S | 2 | mesh-40, 25, 16 | half a cube → a closed 8/12/6 cube; a "don't flip the copy" mutation is caught by the volume |
| mesh-42 | `ArrayModifier(count, offset, mergeDistance)` with deterministic ids | mesh | S | 2 | mesh-40, 25 | 4 cube copies → 32 vertices, volume ×4 |
| mesh-43 | `insetFaces(thickness, depth, individual)` with an angle correction | mesh | S | 2 | mesh-23 | a cube face: +4 V, +4 quads, area (1−0.2)²; a mutation with no correction is caught at 30° |
| mesh-44 | `bevelEdges/Vertices(width, segments, profile, clampOverlap)`, corner n-gons | mesh | L | 2 | mesh-11, 19, 12, 15 | 12 cube edges, segments=1 → 24 V, 26 F, χ=2; `boundaryEdges`=0 |
| mesh-45 | Catmull-Clark with creases (Pixar), UV per corner, `SubdivisionModifier(levels, viewLevels)`, `subdivideSimple` | mesh | M | 2 | mesh-11, 12, 40 | a level-1 cube → 26 V, 24 quads; crease=1 preserves volume |
| mesh-46 | `smoothVertices` (Laplacian + HC when preserveVolume), `SmoothModifier` | mesh | S | 2 | mesh-19, 40 | a sphere, 10 iterations: shrinkage <5% with HC; topology 100% shared |
| mesh-47 | BSP booleans (csg.js): `CsgPolygon`, `CsgNode` on an explicit stack, eps from bounds, a polygon budget, a coplanarity detector; input through the plan, output through `fromPolygons` | mesh | L | 2 | mesh-13, 15, 30, 27 | cube ∪ cube volume matches analytically; cube − sphere within 1%; the coplanar case warns, doesn't crash |
| mesh-48 | `BooleanModifier(operation, operandId, transforms)` via `ModifierContext`, cycles refused | mesh | S | 2 | mesh-47, 40 | the stack = the operation by volume; changing the operand's transform invalidates the cache |
| mesh-49 | Phase-2 frames: bevel, Catmull-Clark 2, cube − sphere, a mirrored vase | app + mesh | S | 2 | mesh-44, 45, 47, 41, 33 | 4 PNGs, zero tolerance |
| mesh-60 | Weights through operations: accumulate up to 8 pairs, prune to `maxInfluences`, renormalize; `normalizeWeights`, `limitInfluences`, `weightsOf`. Storage for anim-09 (§3) | mesh | M | 3 | mesh-12, 24, 44, 45 | a loop cut (1,0)/(0,1) → (0.5,0.5); 5 bones → 4, sum 1±1e-6 |
| mesh-61 | `ShapeKey(name, positions)` as full layers, split applies to every key, `blend(weights)` | mesh | M | 3 | mesh-12, 13 | importing 2 targets → 2 keys; loop cut preserves keys |
| mesh-62 | `toMeshData` with `morphTargets` via `gpuVertexToVertex` | mesh | S | 3 | mesh-61, 14 | delta round trip; a "by EditMesh vertex" mutation → an `ArgumentError` from MeshData |
| mesh-70 | QEM simplification with UV/seams/weights. ⇢ pro-lod-01/02 (one implementation, §4) | mesh | L | 4 | mesh-14, 60, 27 | see pro-lod-01/02 |
| mesh-71 | UV: islands, LSCM, packing, stretch. ⇢ pro-uv-02..05 | mesh | L | 4 | mesh-12, 19 | see pro-uv-* |
| mesh-72 ⚠ | `SculptSession` over `EditMesh` with a patch layer, brushes, refit. ⇢ pro-sc-02..07 (structure resolved 2026-09-09: `SculptMesh` with multiresolution, B8/B9; the id stays for references) | mesh | L | 4 | mesh-10, 20, 16, 31 | see pro-sc-* |
| mesh-73 | An isotropic remesh spike. ⇢ pro-rt-01 | mesh | M | 4 | mesh-20, 25, 46 | see pro-rt-01 |
| mesh-80n *(added 2026-09-10 by gap analysis)* | **Collision shapes from a mesh**: convex decomposition (V-HACD or a related Dart algorithm), fitting a box, sphere, and capsule by inertia, "the mesh itself" for statics. Gap analysis: every game asset needs a collision shape, and nobody sculpts it by hand; the plan had not one line on this, and the sole mention of collisions (pro-sim-01) is about cloth colliding with an already-finished `CollisionShape`. The engine handles shapes; nothing generates them from a model | mesh | L | 2 | mesh-11, mesh-27 | a 900-triangle chair gives ≤12 convex pieces, volume within 15% of the source; a capsule by inertia matches a hand-built one within 5%; deterministic for one seed |
| mesh-81n *(added 2026-09-10 by gap analysis)* | **Repair, not just diagnosis**: `fillHoles` (fan and boundary-based), `splitNonManifoldEdges`, `flipShells` alongside `MeshChecks`, which today finds all of this and fixes none of it. `ExportReadiness` says "won't fly" and leaves the artist alone with it — a report with no button is half a tool | mesh | M | 1 | mesh-25, mesh-27 | a cube with a face cut out is closed after `fillHoles`, χ = 2; a non-manifold edge splits into two, the face count doesn't change; each repair is a history step |

### 2.2 Document, commands, MCP (`doc-`)

Repeat the level editor's shape (a sealed command with
`name/says/arguments/apply/fromJson`, history with transactions, a session
and a tool table from the list of command names, a scenario through
`StreamChannelController`), but over an immutable `ModelProject` with
structural sharing instead of `level.toJson()` snapshots. Found in the code:
the scanner only looks for the text `package:flutter/`, it doesn't see a
transitive dependency through `flutter3d` (doc-00); the ROADMAP still writes
`apply`/`revert`, the code stores snapshots, and for meshes the plan is a
prior value (doc-29).

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| doc-00 ⚠ | A spike: an empty package depending on `flutter3d`, `dart pub get`/`dart test` from the directory; the result goes in doc §6 item 0.4. ⇢ p0-09, rel-04 | core | S | 0 | — | the outcome is recorded; on failure — doc-01; otherwise a rule on transitive SDK dependency (qa-03) |
| doc-01 ⚙⚠ | Move Flutter-import-free files into a pure package: geometry/*, assets/{model_document, model_node, surface_material, material_document, material_hint}, `render/lighting_model.dart` (imported by material_document and material_hint; itself has no imports — moved as-is), f3d/*, gltf/* (except resolvers), obj/*, fmat/*, animation/{clip, track}; `model_loader.dart` splits: the synchronous half (`ModelFormat`, `ModelDecoder`, `sniffModelFormat`, `decodeModel`) — into `formats`, `kIsWeb` → `const bool.fromEnvironment('dart.library.js_interop')`, the isolate half (`ModelLoadRequest` — into `formats`, since it describes a request rather than running one; `decodeModelInIsolate`) stays in the engine; the `ModelFormat` exemption path in `repository.dart` is updated. `flutter3d` re-exports; into `flatDartPackages`, the workspace, §16, §3.2, `ci.sh`. 2026-09-09 decision: two packages — `flutter3d_geometry` (mesh-03) and `flutter3d_formats` (this item: everything listed here except geometry/*), `formats` depends on `geometry`; publishing order geometry → formats → flutter3d | engine + geometry + formats | M | 0 | doc-00, mesh-03 | `dart test` in both packages is green; the 43 scenes and goldens unchanged; `publish_check.sh` accepts the order; `decodeModel` is callable from `formats`'s own `dart test` with no Flutter; the package count in README/§3.2/§16 shifts in the same commit (28 → 30) |
| doc-02 | The `flutter3d_model_core` skeleton: pubspec, barrel, LICENSE/CHANGELOG/README; registered in the lists. ⇢ qa-02, rel-02/03 | core | S | 1 | doc-00 | scanner and `ci.sh` green with an empty test |
| doc-03 ⚠ | `ModelProject {profile, objects, materials, images, skeletons, clips, nextId}`; `ModelObject` with stable ids and `version`; a sealed `Geometry`: Parametric / Edited(EditMesh) / Imported(MeshData); `withObject`/`copyWith` with structural sharing | core | M | 1 | doc-02, mesh-11 | `withObject` shares whatever it didn't touch (`identical`); an id is unique after delete+add |
| doc-04 ⚠ | `Selection {mode, submode, objects, level, elements}` with JSON and `says`; `ModelHistory` — a session over the document, every change through history | core | S | 1 | doc-03 | selection survives undo if the id still exists; JSON round trip |
| doc-05 ⚠ | A sealed `ModelCommand` (`name`, `says`, `arguments`, `toJson`, `fromJson` → null, `apply(project, selection) → Outcome?`), `modelCommandNames`; a test table per name | core | S | 1 | doc-04 | 100% of names covered by samples; incomplete JSON → null, not an exception |
| doc-06 | Object commands: `AddPrimitive`, `AddLathe`, `SetParametric`, `BakeToMesh`, `MoveBy/RotateBy/ScaleBy`, `SetTransform`, `Rename`, `SetParent`, `Delete`, `Duplicate`, `SetField`, `AssignMaterial`, `SetOrigin` (an object's pivot: bounds center / bottom / cursor) and `ApplyTransform` (bake a node's transform into geometry — added by critique, a frequent pre-export step); ids in the arguments, not from selection | core | M | 1 | doc-05 | a test per command with a mutation; `Duplicate` gives new ids; `SetField` refuses an invalid value; `ApplyTransform` gives the node an identity matrix and the same world positions |
| doc-07 | Mesh commands with `Selection` in the arguments: `TransformElements` (one command for move, rotate, and scale — they only differ by matrix), `Extrude`, `LoopCut`, `MergeByDistance`, `DissolveEdges`, `DeleteElements`, `Separate`, `Triangulate`, `RecalculateNormals`; refuses on Parametric | core | M | 1 | doc-05, mesh-22..26 | counters on a cube after each; JSON round trip; 100 `TransformElements` on 200k within the mesh budget |
| doc-08 ⚠ | `ModelHistory`: `run`, `transaction`, undo/redo, `undoSays`, `isDirty`, `amend(replacement)` for the operation card; depth 64 + a byte-based chunk limit | core | M | 1 | doc-05 | a 100-command drag — one step; `amend` doesn't grow the stack; a step after moving 1% of 200k <10% of a full copy |
| doc-09 | `project_format.dart`: magic, version, a 16-byte header, a section directory, 4-byte alignment; sections manifest/materials/editMeshes/importedMeshes/images/skins/animations/journal/history (the last — doc-31d, 2026-09-09 decision); an unknown one is skipped, a future version is refused. The `.f3dproj` extension (2026-09-09 decision, D2 [Г2]); the magic and the autosave location — D1 [Г1] | core | S | 1 | doc-03 | a test on the constants (a multiple of 4, not an enum index) |
| doc-10 ⚠ | `ProjectWriter`/`ProjectReader`: string interning, canonical JSON (sorted keys, one rounding), `warnings`, external `.fmat` by relative path. ⇢ fmt-17 (§3) | core | L | 1 | doc-09, doc-03 | write→read→write byte-exact on a project with three geometries; version+1 — refused; 200k vertices <100 ms |
| doc-11 ⚠ | `ModelProject.fromModelDocument(document, ImportOptions {scale, upAxis})` + `ImportReport {issues, counts}`: nodes→objects, surfaces→Imported, skins→skeletons, animations→clips, morphWeights; `ImportOptions` (added by critique): a unit multiplier (STL is usually in mm, OBJ has no units) and an up axis (Z-up → Y-up via a root rotation), default 1.0 / Y | core | M | 1 | doc-03, doc-13 | BoxAnimated/simple_skin: objects = nodes, triangles = `triangleCount`; decoder warnings verbatim; `scale: 0.001` gives bounds 1000× smaller, `upAxis: z` — the same cube rotated −90° around X |
| doc-11a-n ⁶ *(added by critique)* | Unconditionally (2026-09-09 decision, §7 #36 and F4 [Ж4] closed): `ImportInto(project, document, options)` — merging an imported document into an existing project (new objects, deduping materials and images by hash, skeletons as new), unlike doc-11, which builds a project from scratch. Placing several assets in "Scene" mode (mat-24) is built on this | core | M | 2 | doc-11, doc-06, mat-01 | two imports in a row → objects from both, one `SurfaceMaterial` for a matching material; undoing the second import returns the first project by `identical` |
| doc-12 ⚠ | `ProjectModelDocument extends ModelDocument` with a `MeshData` cache keyed by `(ObjectId, version)`; export — a session verb; `.f3d` today, GLB/OBJ through fmt | core | M | 1 | doc-03, doc-06 | project→document→`F3dWriter`→parse: equal; re-exporting returns `identical` MeshData |
| doc-13 | `ProjectProfile {name, target, maxTriangles, maxJoints ≤ 64, maxInfluences, maxTextureSize, maxTextureBytes, requireTriangles, requireManifold}` with presets and `profileHints` from `MaterialHint` | core | S | 1 | doc-02 | JSON round trip; a mirror test against `Skeleton.maxJoints` in the app |
| doc-14 ⚠ | `ExportReadiness.check(project) → List<Issue>` with a cache keyed by object version; budget, n-gon, manifoldness, bone, texture, slot, and name rules; a rule for "vertices with morph targets > the profile's `maxTextureSize`" (`MorphTexture` packs a column per vertex — added by critique, risk 28); a `headline` for the status | core | M | 1 | doc-13, 03, 15 | per-rule test with a mutation; after editing one object, only it is re-checked; an object with 5000 morphable vertices at `maxTextureSize: 4096` gives an Issue |
| doc-15 | `imageDimensions(bytes)` for PNG/JPEG/KTX2 with no decoder | core | S | 1 | doc-02 | three fixtures; a truncated file → null |
| doc-16 | `CommandJournal`: JSON Lines with transaction markers, `replay`; refuses with a line number | core | S | 1 | doc-08, doc-10 | 30 commands → journal → replay → the same `ProjectWriter` bytes |
| doc-17 ⚠ | `AutosavePolicy` and pure functions `shouldSave`, `recoveryPathFor`, `RecoveryDecision`; the timer, atomic write, and dialog — in the app (ui-18). ⇢ fmt-18 | core | S | 1 | doc-10, 08, 16 | interval boundaries; a clean document isn't saved; the freshest recovery is chosen |
| doc-18 | `contentsOf(project) → List<Listed>` in object order; `materialsOf`, `skeletonsOf`, `clipsOf` | core | S | 1 | doc-03 | stable across calls; each object exactly once |
| doc-19 ⚠ | The `flutter3d_model_mcp` skeleton: `ModelSession` (listing, select, run, undo, redo, check, save, export, import, journal), `ModelMcpServer`, `bin/model_mcp.dart` (a `--help` stub is set up in rel-02; here it's a real server) creates a project at a non-existent path | mcp | S | 1 | doc-08, 10, 18, 14 | `dart run flutter3d_model_mcp:model_mcp new.proj` answers `tools/list`; the same check in a container with no Flutter SDK (rel-04's script) |
| doc-20 | `ModelTool` from `modelCommandNames`, schemas `_vector/_ids/_selection`, session verbs; `tools_test`: every name is offered, anything extra is a named set, descriptions >40 characters | mcp | M | 1 | doc-19, 05, 06, 07 | adding a command with no tool — a red test |
| doc-21 ⚠ | An "agent builds a table" scenario over the real protocol: primitives, transforms, a material, check, save, export GLB and `.f3d`; a diff against `fixtures/table.proj`, `table.glb`, `table.jsonl`; refusals as `isError`. ⇢ qa-12 | mcp | M | 1 | doc-20, 12, 16 | green on ubuntu and macOS with the same bytes |
| doc-22 | Skills `project-document`, `editing-order`, `what-it-refuses`; a README with a tool table; CHANGELOG. ⇢ rel-14 (a test on skills in the archive) | mcp | S | 1 | doc-20 | every refusal line has a test with the same phrase |
| doc-23 ⚠ | Stack commands: `AddModifier`, `SetModifierField`, `ToggleModifier`, `ReorderModifier`, `RemoveModifier`, `ApplyModifier`; the `Modifier` type — from mesh-40, heavy work — through doc-24. ⇢ mat-19 | core | M | 2 | doc-06, doc-12 | `ApplyModifier` = export with the modifier enabled; a round trip through doc-10 |
| doc-24 ⚠ | `JobRequest` — a pure function over values; the app runs it through `Isolate.run` or chunked on the main thread; `ApplyJobResult` in one history step, refuses on a stale `version`. ⇢ pro-job-01, anim-25 (one runner, §4) | core | M | 2 | doc-23, doc-08 | a result against a stale version is refused; JobRequest is serializable |
| doc-25 ⚙⚠ | Material commands: `AddMaterial`, `SetMaterialField` via a JSON codec for `SurfaceMaterial`, `SetTexture`, `AddImage`, `LinkFmat`, `RemoveMaterial`. ⇢ mat-01 (phase 1, including `SetTexture`/`AddImage` — moved to phase 1 by critique) and mat-08 (`LinkFmat`, phase 2); the engine change (a public `SurfaceMaterial ↔ Map` codec in fmat.dart, S) stays | core + engine | M | 2 | doc-06, doc-15 | see mat-01/08 |
| doc-26 ⚠ | Skeleton and clip commands: `AddSkeleton`, `AddJoint`, `SetJointRest`, `BindSkin`, `AddClip`, `SetKey`, `SetInterpolation`… ⇢ anim-03, anim-04, anim-29 | core | L | 3 | doc-11, 12, 10 | see anim-* |
| doc-27 | Morph target and morph weight commands. ⇢ anim-19 | core | M | 3 | doc-26 | see anim-19 |
| doc-28 | Format migrations: `test/fixtures/v1/*.proj` fixtures kept forever; the version only rises on a meaning change; a CHANGELOG entry with every layout | core | S | 2 | doc-10 | every fixture reads; a bump with no fixture — a red test |
| doc-29 ⚠ | ARCHITECTURE §8.7 on the project format and the three undo models (§8.6 is taken by fmt-16, Writers; today ARCHITECTURE §8.1–8.5); §3.2, §16; the ROADMAP with no "apply and revert"; doc §5.1 on the scanner | docs | S | 1 | doc-08, doc-10 | scanner green; the ROADMAP has no `revert` in the editor paragraph |
| doc-30 | `tool/ci.sh` reads the `dart test` list from `flatDartPackages`. ⇢ qa-04 | tool | S | 0 | — | see qa-04 |
| doc-31d *(added following 2026-09-09 decisions)* | History in the project file (D2 [Г2] closed: history is written into the file): a `history` section in doc-09's container — a step list, each step = `says` + the command in JSON (the same shape the doc-16 journal uses) + references to prior values through chunks already sitting in the `editMeshes`/`materials` sections as blobs: an unchanged chunk is written once and addressed by index, so structural sharing moves from memory into the file; the depth/byte limit from D5 [Г5] (doc-08) also applies to the file; `ProjectWriter(includeHistory:)`; "save without history" — a project export option (ui-33d); the doc-16 journal stays | core | M | 1 | doc-08, doc-10, doc-16 | round trip: three commands → save → open → undo three steps → the project equals the original, untouched chunks `identical`; a file with history ≤ a file without it + Σ of changed chunks + the steps' JSON; a file with no `history` section opens with empty history; the D5 limit trims the tail on write |
| doc-32n *(added 2026-09-10 along the way)* | Selection commands: `SelectAll`, `SelectNone`, `InvertSelection`, `GrowSelection`, `ShrinkSelection`, `SelectLinked`, `SelectEdgeLoop`, `SelectEdgeRing`, `SelectByMaterial`. `flutter3d_mesh`'s `Selection` already does all of this (mesh-16), but it was never surfaced: selection changes bypass history, so it doesn't undo, doesn't get journaled, and an agent can't reach it. Refines the D-decision "every edit goes through a command" — selection is an edit too | core | S | 1 | doc-05, mesh-16 | `GrowSelection` on a cube face gives five; undo returns to one; every name is in `modelCommandNames` and round-trips |
| doc-33n *(added 2026-09-10 along the way)* | A pivot point and transform space: `TransformPivot {median, individual, cursor}` and `TransformSpace {global, local}` in the arguments of `RotateBy`/`ScaleBy`/`TransformElements`; `SetCursor(position)` and a 3D cursor in `ModelProject`. Today rotation and scale are always about the median and always in global axes — the right default, but it makes "rotate each one around itself" impossible, without which placing assets (mat-24) has to be done by hand | core | S | 1 | doc-06, doc-07 | two objects, `individual` → each rotates in place, centers unchanged; `local` on a rotated object moves along its own axis; a JSON round trip with both fields |
| doc-34n *(added 2026-09-10 by gap analysis)* | **Sockets and attachment points**: a `ModelObject` with no geometry gets a `socket` flag and shows in the viewport; export writes them as named nodes with no surfaces — something glTF already supports and `toModelDocument` already writes for groups. Gap analysis: a named point to hang a weapon, an effect, or a wheel off of exists everywhere (`Marker3D` in Godot, empties in Blender), and without it nothing composite can be assembled on the game side | core | S | 1 | doc-06 | a socket exports as a surface-free node and reads back as a socket; renaming — a history step; a socket doesn't count toward `triangleCount` and doesn't trigger a "no faces" readiness error |
| doc-35n *(added 2026-09-10 by gap analysis)* | **Texel density as a profile field**: `ProjectProfile.texelsPerMeter` and an `ExportReadiness` rule computing density from UV-island area and texture size. Gap analysis: one "pixels per meter" number across all assets is what most affects whether a scene reads as one piece, and a crate unwrapped four times coarser than its neighbor shows immediately. Sits on the profile next to `maxTextureSize`: a measurement, not an artist's memo | core | S | 2 | doc-13, doc-14 | an object twice as dense as the profile gives a warning with both numbers; an object with no UV stays silent |
| doc-36d *(added 2026-09-14 following owner decisions)* | **`SetRig`** — one journaled history step for an auto-rig: `SetRig(jointObjects, skeleton, skinObjectId, weights)` adds the joint objects (ids preassigned from `ModelProject.nextId`), appends the `ProjectSkeleton`, sets `skeletonIndex` and writes the skin layers through `EditMesh.setSkin` inside one `beginStep`/`endStep`; refuses a taken id, an object with no `EditedGeometry`, or a stale `baseVersion` (the `ApplyJobResult` rule). The MCP `autoRig` recipe builds a `SetRig` instead of the `ReplaceDocument` it commits today (`command.dart` keeps that one out of `modelCommandNames` on purpose, so today's auto-rig never reaches the journal); a `setRig` tool | core + mcp | M | 3 | anim-21, anim-22 | one `run(SetRig)` → `canUndo`; undo removes every joint and the skeleton and restores the skin bytes byte-exact; a stale version is refused; `tools_test` stays symmetric; `autoRig` through the session appears in the journal |

### 2.3 Formats (`fmt-`)

A glTF/GLB writer mirroring `F3dWriter` over the same `ModelDocument` — the
editor's only path out into the engine, and the only item useful to the
engine with no editor at all; next to it, an `ObjWriter` with `.mtl`, an
`StlDecoder`, a texture encoder from the ROADMAP. The repository has three
decoders, `F3dWriter`, a KTX2 reader, `convert_asset.dart` for `.f3d` only;
not one glTF/OBJ/STL writer in Dart. The `ModelDocument` vocabulary doesn't
store glTF mesh names, extras, `asset.generator`, image URIs, an
authored-attribute flag, the sampler's four mip variants,
`KHR_texture_transform` — without part of this, the round trip won't match.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| fmt-01 ⚙ | `compareModelDocuments(a, b)` moved from the converter's own `_compare` into lib, with categories (structure, bytes, materials, nodes, skins, clips, morphs) | formats | S | 1 | — | a test per category via breakage; the converter gives the same result |
| fmt-02 ⚙ | `PlainModelDocument` instead of `_FakeDocument` in tests; `sniffImageMimeType` (PNG/JPEG/KTX2/WebP) | formats | S | 1 | — | tests ported; sniff on four magic numbers and an empty buffer |
| fmt-03 ⚙ | `ModelSurface.authoredAttributes` from the decoders; `.f3d` section `surfaceAttributes` (kind 17); writers skip what's generated | formats | S | 1 | — | Box.glb → {position, normal}; an old `.f3d` reads as "all" |
| fmt-04 ⚙ | `ModelSurface.meshName`, `ModelDocument.asset`, `EncodedImage.sourceUri`; sections `meshNames` (18), `asset` (19), `imageUris` (20) | formats | S | 1 | — | BoxTextured → `meshName == 'Mesh'`; old `.f3d` files with null |
| fmt-05 ⚙ | `TextureSampling.mipLinear`, parsing 9984–9987, bit 7 in `F3dSamplingFlags`, `toGltfFilters()` | formats | S | 1 | — | 9985 → mipLinear=false; round trips to 9985; golden unchanged |
| fmt-06 ⚙ | `GltfWriter` + part files: de-interleaving via `floatOffsetOf`, u16 indices when `fitsIn16BitIndices`, deduping meshes/samplers/textures, nodes from `nodes`, materials with extensions, images in the GLB/files; `GlbContainer.encode` from `buildGlb`. Lives in the pure `formats` package, like `F3dWriter` after the move — otherwise `flutter3d_model_mcp` can't export a GLB (B1 closed 2026-09-09) | formats | M | 1 | fmt-01..05, doc-01 | 8 models: decode→writeGlb→decode, `compareModelDocuments` empty; alignment/min-max/quaternion mutations are caught; `formats`'s own `dart test` writes a GLB with no Flutter SDK |
| fmt-07 ⚙⚠ | `gltf_writer_animation.dart`: skins, animations (`AnimationInterpolation.toGltf`, CUBICSPLINE triples, weights), morph targets with `targetNames`. One writer shared by fmt-07/anim-26 (§3) | formats | M | 1 | fmt-06 | 7 rigged models round trip; a pose at t=0.5 through `AnimationPlayer` matches |
| fmt-08 ⚙ | `ObjWriter` + `.mtl`: v/vt/vn deduping, a V-flip, `MeshData.transformed`, a reverse Kd/Ns/Ks approximation, `map_Kd`, warnings about what's lost | formats | M | 1 | fmt-01, 02, 04, doc-01 | a teapot round trip by triangle set; Box.glb → 12 triangles with Kd |
| fmt-09 ⚙⚠ | `StlLoader implements ModelDecoder`: binary (`84 + 50·count` as the detector), ASCII, `StlNormals`, warnings; `ModelFormat.stl`, sniffed before OBJ; `convert_asset`. `ModelDecoder`/`ModelFormat`/`sniffModelFormat` live in `model_loader.dart`'s synchronous half, which doc-01 moves into `formats` | formats | M | 1 | fmt-03, doc-01 | five fixtures via `build_stl.dart`; `sniffModelFormat` on a binary STL → stl; sendable; decodes from `formats`'s own `dart test` with no Flutter |
| fmt-10 | Differential frames: the original against the re-read export via `renderFrame`, zero tolerance; not in `kGoldenScenes` | cpu | M | 1 | fmt-06, 07, 08 | green on every model; an offset-shift mutation on normals gives a difference |
| fmt-11 ⚙ | Export validation via the `gltf` package (Khronos, Dart) or `npx gltf-validator` in `ci.sh`, or a minimal checker. ⇢ qa-09 | engine + tool | S | 1 | fmt-06 | zero errors; a broken min/max gives an error |
| fmt-12 ⚙ | `warnings` on every writer (and `F3dWriter`), `ExportReport {files, writerWarnings, differences}` = write → re-read → compare | formats | S | 1 | fmt-01, 06, 08 | RiggedFigure to OBJ → a warning about the skin; Box.glb → empty differences |
| fmt-13 ⚙⚠ | `ModelWriteRequest`, `encodeModelInIsolate` with a `kIsWeb` fallback, a Timeline span — a wrapper over the writers in `formats`; the only piece of formats that needs Flutter | engine | S | 1 | fmt-06, fmt-08 | isolate bytes = synchronous ones; a 200k measurement in the doc |
| fmt-14 ⚙ | `convert_asset -f glb|gltf|obj|stl|f3d`, `--textures keep|external`, printing an `ExportReport` | engine | S | 1 | fmt-12, fmt-13 | `teapot.f3d -f glb` opens in the loader and the validator |
| fmt-15 ⚙⚠ | A Draco/meshopt primitive with no bufferView is skipped with a warning, rather than read as zeros; `hasBufferView` | formats | S | 1 | — | a hand-written glTF → 0 surfaces and a warning |
| fmt-16 ⚙ | Documents and the scanner: §8.1 the four decoders, §8.6 Writers (the project format — §8.7, doc-29), the README, `assets.md`, `boundaryEnumExempt` for `ModelFormat` on the new `formats` path, CHANGELOG | engine + docs | S | 1 | fmt-06, 08, 09 | scanner green after each writer |
| fmt-17 ⚠ | A sectioned project format with migrations. ⇢ doc-09, doc-10, doc-28 (one implementation; the idea of "an unknown manifest key is written through unchanged" via `json_write_through` — in doc-10) | core | M | 1 | — | see doc-10, doc-28 |
| fmt-18 ⚠ | An asset policy (a copy inside the container, an `.fmat` path + fallback, an optional `sources`) and `ProjectStorage.writeAtomic`. ⇢ doc-17 (the policy) and ui-18 (disk) | core | S | 1 | fmt-17 | see doc-17, ui-18 |
| fmt-19 ⚙⚠ | `extras` on a node/material/skin/clip/document, `TextureBinding.transform` from `KHR_texture_transform` passed through end to end; section `extras` (21) | engine | S | 2 | fmt-06 | byte-exact JSON fragments; a warning about an unapplied transform stays |
| fmt-20 ⚙⚠ | `StlWriter` (binary and ASCII) | engine | S | 2 | fmt-09 | Box.glb → stl → 12 triangles; size `84 + 50·count` |
| fmt-21 ⚙ | KTX2 through `GltfWriter` (`KHR_texture_basisu` for Basis only), `.f3d` as-is, OBJ — a warning | engine | S | 2 | fmt-06, fmt-12 | an etc1s fixture → GLB → the loader reads it; a BC file → a warning |
| fmt-22 ⚙⚠ | `Ktx2Writer` + BC1/BC3/ETC2 encoders in Dart, `--textures bc1|bc3|etc2` in the converter (a ROADMAP item). ⇢ mat-30 (one encoder, §4). 2026-09-11 decision: done as ap-07 in the asset-pipeline track ([asset-pipeline-plan.md](asset-pipeline-plan.md)), the KTX2 container moves into `formats` (ap-01) | engine | M | 2 | fmt-14 | PSNR ≥30 dB via a test unpacker; conformance on the encoder's own output |
| fmt-23 ⚙⚠ | Basis Universal ETC1S for glTF: a decision (a port / offline FFI / a server) + a spike | engine | L | 3 | fmt-22 | `doc/texture-encoding.md` with a measurement; transcode via the existing `etc1s_transcoder` |
| fmt-24 | A dedicated FBX reader in Dart (D7 [Д7] closed 2026-09-09): binary 7.x with a Dart inflate, ASCII, `FbxDecoder`, geometry/materials/hierarchy with pivots, UnitScaleFactor/UpAxis; fixtures from Blender against a glTF of the same scene. A separate phase-2 track, starting after rel-16 (phase 1 in hand); a candidate for an agent under ready-made fixtures | fbx | L | 2 | fmt-29d, fmt-01, fmt-03 | a binary and an ASCII cube = a glTF, down to floats; a hierarchy with pre-rotation gives the same world matrices |
| fmt-25 ⁵ | FBX: skins and animation (Deformer/Cluster, AnimationStack → linear keys, euler → quaternions) | fbx | L | 2 | fmt-24 | a pose at t=0.5 = a glTF export within 1e-4 |
| fmt-26 ⁷ | Dropped 2026-09-09: no server-side FBX conversion (`ConversionService`, an HTTP implementation, a server outside the repository) — its own reader instead (fmt-24/25). The id stays so references don't dangle | — | — | — | — | — |
| fmt-29d *(added following 2026-09-09 decisions)* | The `flutter3d_fbx` package skeleton: flat (`flatDartPackages`), `resolution: workspace`, depending only on `flutter3d_formats` (`geometry` transitively), a barrel, `FbxDecoder implements ModelDecoder` as a stub that refuses with a value; registered in the workspace, `notARepeatableStep`, §16 (after `formats`, independent of `flutter3d`), §3.2, `ci.sh`; the package count 33 → 34 in README/§3.2/§16 in the same commit | fbx | S | 2 | doc-01, rel-16 | scanner green; `dart pub get` in the package with no Flutter SDK (qa-03); `publish_check.sh` accepts the order |
| fmt-27 ⚙⚠ | USDZ, on demand: a spike (does Quick Look accept usda?), a `UsdzWriter` + an uncompressed zip | engine | M | 4 | fmt-06 | a Quick Look screenshot in the doc; byte-exact 64-byte alignment. Spike D8 [Д8] partially answered: `UsdzWriter(GltfLoader().load(Box.glb))` produced a real `.usdz`, served to the iOS 26 simulator (iPhone 17 Pro) over a local HTTP server with `Content-Type: model/vnd.usdz+zip` — Safari/Quick Look recognized the file and showed the system's "View in 3D" dialog (meaning: yes, Quick Look accepts a plain-text `.usda` inside an uncompressed zip). It didn't get past the dialog: this machine has no `Simulator.app` (no GUI app ships with the Xcode beta, only headless `simctl`) and no `idb` or other way to send a tap — so a real render of the cube in Quick Look was never photographed, only the acceptance dialog itself. The 64-byte alignment was already checked byte-exact in `usdz_writer_test.dart`, independently of this spike |
| fmt-28 ⚙⚠ | `ModelLight`/`ModelCamera` in the vocabulary, `KHR_lights_punctual` and `cameras` in the loader/writer, sections 22–23 | engine | S | 4 | fmt-06, fmt-19 | a round trip of a hand-written glTF with two light sources and a camera |
| fmt-30n ⚠ *(added 2026-09-10 by gap analysis)* | **Output geometry compression for glTF**: cache-friendly vertex order, attribute quantization, `EXT_meshopt_compression`. Gap analysis: a file a third the size and faster loading; the plan keeps compressed sections in its own container but not compression on the output side, into the format that feeds the rest of the world. `fmt-15` today is a "loud skip" on read; this is its write-side half. Cache-friendly vertex order (`flutter3d_geometry`'s `optimizeVertexCache`) and attribute quantization (`KHR_mesh_quantization` on NORMAL/TANGENT/TEXCOORD_0/COLOR_0) already existed, found on returning to this row — `EXT_meshopt_compression` itself was the only real gap. Closed 2026-09-13/14: `meshopt_vertex_codec.dart` (format version 0) and `meshopt_index_codec.dart` — each decoder is a direct line-by-line port of `meshopt_decoder_reference.js` (the only readable part of the `meshoptimizer` npm package — the real encoder only exists compiled to WebAssembly, nothing to port from), the encoder is a from-scratch design, verified not only against its own inverse but against a real reference decoder under Node (`meshopt_reference_check.mjs`/`meshopt_index_reference_check.mjs`, both green). Woven into `GltfWriter`/`GltfAccessorReader`: POSITION and already-quantized attributes compressed via the vertex codec, indices via the index codec; `GltfLoader`'s own `extensionsRequired` filter knows the extension's name. A full round trip through `compareModelDocuments` is green. Honestly left undone: the index codec doesn't reuse FIFO connectivity (only the always-correct fallback — LEB128 per vertex), version 1 of the vertex format (wider "channels") isn't implemented — so "a third smaller" isn't literally reached (2.70× measured, was 1.90× without EXT_meshopt_compression); the official Khronos validator (`gltf-validator@2.0.0-dev.3.10`, nothing newer on npm) doesn't know this extension at all and so misreads compressed bufferViews — "the validator is green" in the acceptance for a compressed file isn't something this tool can check; checked instead by an independent reference decoder and this repo's own reader | formats | M | 2 | fmt-06 | a GLB a third the size; the re-read document matches `compareModelDocuments` within quantization tolerance; the Khronos validator is green |

### 2.4 Rendering and viewport (`view-`)

Almost everything is already in the engine and needs stretching, not
writing: `DebugDraw` and `DebugLineVertex`/`DebugLine`, `PassContributor`,
`Renderer.pickPixel`, `Raycaster`, `OrbitController`,
`RenderView.viewportFraction`/`layerMask`, `EnvironmentMap.fromSky`, vertex
color in `surface.glsl`. Missing: partial buffer rewrites, points as a
primitive (the CPU rasterizer throws on point, WebGPU gives 1 px), thick
lines, depth offset, a triangle counter, a triangle BVH, wireframe outside
Impeller. A new shader costs the same across all four backends, so the plan
allows at most two vertex stages and no fragment ones.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| view-01-bench | Micro-measurements for the overlay on rig p0-01: (b) `bindVertexData` on 200k quads per frame, (c) a CPU offset of 200k vertices toward the camera. (a) `DeviceMesh.upload` per frame ⇢ p0-06; a 1M-triangle scene ⇢ p0-01/02/03 | engine example + `packages/flutter3d/tool/bench` | S | 0 | — | thresholds: (c) >2 ms → view-06 is required; (a) >8 ms → view-14 into phase 1 |
| view-02-viewport-skeleton ⚠ | `modeler_viewport.dart`: a `Renderer` through `flutter3d_backend`, a `Ticker`, a surface with `List<RenderView>`, the camera in `State`; background — flat `#0E1112` or a `SkySettings` sky (a decision); `frame_test` | app | M | 0 | view-01 | two `RenderView`s each half the screen; a GLB visible on macOS |
| view-03-orbit-gestures ⚙ | `OrbitGestures` (pure Dart): mouse/finger/trackpad/pen → `rotate/pan/zoom`; a stylus doesn't move the camera; the engine: orthographic zoom changes `height`, `frameBounds` for ortho, `animateTo(yaw, pitch)`. ⇢ ui-06 (gestures), ui-19 (input policy) | app + engine | M | 1 | view-02 | two fingers → `distance`/`target`; a stylus doesn't change `yaw`; an ortho-zoom test in the engine |
| view-04-display-modes | Perspective/ortho preserving framing, standard views, "Material/Normals/Wireframe" chips (wireframe as an overlay until view-07) | app | S | 1 | view-03 | a +Y face pixel in "Normals" = (128,255,128)±2; ortho doesn't depend on `distance` |
| view-05-mesh-overlay ⚙⚠ | `MeshOverlay extends PassContributor` with an `OverlayBatch` in a `positionColor` layout: thin lines, camera-facing point quads, ribbons and a 55% fill; a pipeline of `DebugLineVertex`+`DebugLine`, `lessEqual` + a CPU offset; a `mesh-overlay` scene in `kGoldenScenes`, 43 → 44. ⇢ qa-10 | engine | M | 1 | — | a batch of N edges — 3 draws; a quad doesn't depend on `distance`; 4 sets, 0 pixels; `#004F58` fill at 55% ±3 |
| view-06-overlay-shader ⚙ | Conditional (view-01(c) >2 ms): `overlay.vert` with `depth_bias`, a `DebugLine` fragment; the bundle, `kRequiredShaders`, the CPU stage, two tables, the site | shaders + 4 backends | S (conditional; by risk-9 cost — GLSL, `impellerc`, `naga`, CPU transcription, four tables — treat as M if the item fires) | 1 | view-05, view-01 | `mesh-overlay` within tolerance 8; `manifest_test`; `structure --only 'shader bundle'` |
| view-07-wire-edges ⚙⚠ | `MeshData.edgeIndices()`, `DeviceMesh.upload(withEdges)`, a `MeshWireVertex` stage, the renderer draws edges as lines wherever `supportsWireframe == false`; a `wireframe-edges` scene | engine + shaders + backends | M | 2 | view-06 | a cube → 18 edges; `wireframeDeclined` is never true |
| view-08-pick-objects ⚠ | `object_picking.dart`: `pickPixel` → `MeshNode` → `ModelObject`; Shift adds; service nodes are excluded; `RenderSettings.highlighted` until view-10 | app | S | 1 | view-02 | a click on a cube — the object; a click on a gizmo arrow — not the object beneath it |
| view-09-triangle-bvh ⚙⚠ | The `TriangleBvh` owner (clarified by critique): an implementation over `Float32List`/`Uint32List` with `refit`, in the `geometry` package (2026-09-09 decision); `Raycaster.intersectTriangles` over the tree when `MeshData.bvh` is registered. One implementation shared with mesh-20/p0-10 (§3): p0-10 measures a prototype of this class, mesh-20 builds `MeshBvh` on top | engine (geometry) | M | 1 | doc-01, p0-10 | 10k rays over a torus = brute force; a ray <0.2 ms, refit <5 ms, build <150 ms at 200k |
| view-10-pick-elements ⚠ | `element_picking.dart`: a face by ray, a vertex/edge by screen distance (8 lp mouse, 24 lp finger) with occlusion, a box by projection; the result — a `Selection` | app | M | 1 | view-09, view-08 | a face's center → the face, ±3 lp from an edge → the edge, 12 lp from a vertex → nothing; a back-facing vertex with no flag isn't picked |
| view-11-grid-orientation | A floor grid as a `MeshOverlay` batch with fade-out and `lessEqual`; a ⌀60 orientation gizmo — a `CustomPainter`, a click → `animateTo` | app | S | 1 | view-05, view-04 | grid pixels ≈ `#2A3234`; `−X` → yaw π/2 |
| view-12-transform-gizmo ⚠ | `transform_gizmo.dart`: `Shape`-built handles, `unlit`, `always`, a late bucket, a screen-space size; `GizmoHit`/`GizmoDrag` following `AxisDrag`'s pattern; Ctrl snapping; one transaction. ⇢ ui-06 (the manipulator) | app | L | 1 | view-08, view-03 | rays along X → a shift along X, one step; `steady_gizmo_test` two frames byte-exact; the X arrow `#FF6B8A`±2 |
| view-13-mesh-mode-app ⚠ | `mesh_overlay_builder.dart`: `EditMesh` + `Selection` → three batches, rebuilt by version, quads billboarded to the camera, thinning >100k | app | M | 1 | view-05, view-10 | a cube with one face: 12 lines, 4 ribbons, 2 triangles; 200k edges <20 ms on a selection change, 0 ms while rotating |
| view-14-overwrite-geometry ⚙⚠ | `GraphicsDevice.overwriteGeometry(target, offset, bytes)` with "visible from the next pass" semantics, four implementations + a fake; `DeviceMesh.overwrite` with bounds/version; a conformance check "a partial overwrite draws what a fresh upload draws," 33 → 34. ⇢ pro-eng-01, qa-11; phase 1 if p0-06 doesn't pass | hw + 4 backends + engine + conformance | M | 2 | view-01 | conformance across four; overwriting 1% of 200k <1 ms |
| view-15-multi-view ⚙ | `ViewportPane {view, orbit, layerMask}`, pointer routing by `viewportFraction`; `SceneSurface.views:` in the session | app + session | S | 3 | view-02, view-08 | a click in the right half gives a sphere on layer 2 |
| view-16-material-preview ⚠ | A separate `Renderer` and `Scene`, shapes, `EnvironmentMap.fromSky`, syncing `SurfaceMaterial → Material`. ⇢ mat-15 | app | M | 2 | view-02 | see mat-15 |
| view-17-game-preview ⚙⚠ | `FrameResult.triangles`/`instances` in `renderer_mesh_encode.dart`; a viewport with a "game" profile, a metrics overlay, budget bars, `AnimationPlayer`. ⇢ anim-24 (budgets), ui-28 (the shell). The engine half closed 2026-09-14: `FramePassState.triangles`/`instances` (`pass_contributor.dart`) accumulate at the one place every mesh draw in the frame already passes through — `_encodeNode`'s own `state.drawCalls++` in `renderer_mesh_encode.dart`, exactly the file this row names — and `FrameResult` carries both through. Checked directly: an empty scene draws neither, a lone cube draws 12 triangles and 0 instances, a cube plus a batch of N instanced cubes draws `12 + 12·N` triangles and `N` instances (`packages/flutter3d/test/frame_triangle_count_test.dart`), with the full `flutter3d`/`flutter3d_core`/`flutter3d_cpu` suites still clean. Deliberately excluded: the procedural sky's own full-screen triangle (`renderer_sky_pass.dart`, drawn every frame regardless of scene content) counts towards neither field — a screen-space background trick, not scene content, the scoping `FrameResult.culled`/`FrameResult.skinnedDraws` already use. The app half closed 2026-09-15 (`T5`/`S9`): `ui/game_preview_screen.dart` opens screen 19 as a full-screen route (`showGamePreviewScreen`, from the top bar's "Preview" entry, not the mode switcher) over a second `ModelerViewport` on the same live `ModelerStage`; `ui/metrics_overlay.dart` reads `FrameResult` for fps/draw calls/triangles and `ProfileBudgetReport.joints.used` for bones; `ui/budget_bars.dart` draws the four `ProfileBudgetReport` rows, `success`/`tertiary` per `BudgetUsage.over`. Checked directly: `budget_bars_test.dart` reproduces this row's own numbers — 28/64 triangles at fraction 0.4375 in `success`, 19/16 joints over budget in `tertiary` (`#FFB86B`) — and `game_preview_frame_test.dart` renders a golden (`game-preview.png`) where `triangles == 12`, the procedural sky excluded exactly as this row's engine half already scopes it. Deliberately not built: a fifth "Materials" bar the hand-over draws — `budget_bars.dart`'s own class comment says why: no `maxMaterials` field exists on `ProjectProfile` to measure one against; and "Show wireframe" ships permanently off and disabled, `ProfileBudgetReport.wireframeDeclined` always `true` | engine + app | M | 3 | view-02 | a cube + 3 spheres → `triangles == 12 + 3·N`; exceeding paints `#FFB86B` |
| view-18-weight-gradient ⚠ | A bone weight → a `color` attribute across five stops, `unlit`, `tonemap: false`; updated via overwrite; a legend — Flutter. ⇢ anim-11 | app | M | 3 | view-14 | a weight of 1 → `#FF3B5C`±3; a stroke only changes 1% of `source` |
| view-19-uv-view ⚠ | Seams as ribbons, per-corner stretch as color, a 2D panel on `CustomPaint`. ⇢ pro-uv-07 | app | M | 4 | view-13, view-18 | see pro-uv-07 |
| view-20-lod-views | Three `ViewportPane`s, labels with `triangleCount`, a distance slider → picking a `LodGroup` level by coverage. ⇢ pro-lod-04 | app | S | 4 | view-15 | see pro-lod-04 |
| view-21-brush-cursor-pressure ⚠ | A ⌀140 cursor as a Flutter overlay or a surface-hugging ribbon via `HitResult.normal`; `pressure` for a stylus only; strokes batched once per frame. ⇢ pro-sc-08, ui-29 | app | S | 4 | view-03, 09, 14 | pressure 0.5 → strength 0.5; a finger doesn't create a stroke |
| view-22-tests-numbers-ci | `test/viewport/*` in `ci.sh`; a draw-call guard test `1 + 3 + 1 + N`, `pipelines` doesn't grow; the app in `repository.dart`; numbers. ⇢ qa-14 | app + tool | S | 1 | view-13, 12, 11 | `ci.sh` green; an extra draw in `MeshOverlay` — red |
| view-23n *(added 2026-09-10 along the way)* | **A modal transform** — what basic operations rely on more than the gizmo: after `G`/`R`/`S`, dragging continues until `Enter`/a click (accept) or `Esc`/right-click (cancel, the transaction rolls back entirely); `X`/`Y`/`Z` constrain to an axis, pressing again — a plane, `Shift+X` — "everything but X"; numeric keyboard input replaces dragging (`G X 5 Enter`); `Ctrl` — snapping (a 0.1 grid / a 15° angle / a 0.1 scale step), `Shift` — fine adjustment. The status line shows the current value and constraint. Pure Dart in `transform_modal.dart`, a widget on top of it | app | M | 1 | view-03, doc-07 | `G X 5 Enter` moves exactly 5 along X; `Esc` restores the original positions by `identical`; a hundred frames + `Enter` is one history step; `Ctrl` snaps to multiples of 0.1 |
| view-24n *(added 2026-09-10 along the way)* | A selection box: dragging with the left button and no tool active draws a box overlay, releasing calls `pickElementsIn`/`objectsIn`; `Shift` adds, `Ctrl` subtracts; `A` selects all, `Alt+A` deselects, `Ctrl+I` inverts. `pickElementsIn` is written and tested (view-10), but has no caller | app | S | 1 | view-10, doc-32n | a box over two cube vertices gives two; a `Shift`-box adds; `A` in face mode selects six |
| view-25n *(added 2026-09-10 along the way)* | On-screen gizmos: `Shape`-built handles (arrows/arcs/cubes) in a late `always` bucket, a screen-space size, hover highlighting; dragging runs through the same `transform_modal.dart` as the keyboard — one path, not two. The `GizmoHit`/`GizmoDrag` arithmetic is already written (view-12) | app | M | 1 | view-12, view-23n | a ray along X → a shift along X in one step; frame `gizmo-handles`; the drag arithmetic matches `G X`'s |
| view-26n *(added 2026-09-10 by gap analysis)* | **Snapping to a vertex, edge, and face** during a transform: `Ctrl` today only gives a 0.1 grid, a 15° angle, and a 0.1 scale step — that's all. Gap analysis ranked this second by cost out of ten: with no snapping to geometry, two pieces can't be joined, a leg can't land in a tabletop's corner, and a modular kit can't be assembled so its seams line up. The target is found via `MeshPicker` within a radius, highlighted in the viewport; modes switch mid-transform | app | M | 1 | view-23n, mesh-20, view-10 | a vertex snapped to another vertex matches it byte-exact; the highlight shows the target before release; `Esc` rolls back entirely, same as without snapping |
| view-27d *(added 2026-09-14 following owner decisions)* | **`SkinSync`: the modeler's viewport actually skins.** Today `SceneSync.apply` uploads every object with `VertexLayout.standard` and never sets `MeshNode.skeleton`, so joints animate as sockets while the mesh stands still — which blocks the weight brush, the bend bar, retargeting and auto-rig alike. An object with a `skeletonIndex` uploads `VertexLayout.skinned`; after `_reparent` the sync builds an engine `Skeleton` over its own joint nodes (`nodeOf(id)` per joint, the project's `inverseBindMatrices`) and sets `node.skeleton`/`skinReach`, re-syncing when the joint list or `skeletonIndex` changes; more than 64 joints is `say`, not `throw`. `poseOf(project, skeleton)` gives a `Pose` from the joints' rest TRS. `DebugDrawOptions(skeletons: true)` while in animation mode | app | M | 3 | anim-03, anim-08 | `ModelerStage.fromProject` of a two-joint cube matches `skeleton-overlay.png` (today that golden builds the `Skeleton` by hand in the test); moving a joint node deforms the mesh; `buildPreviewPlayer` playing a clip moves vertices, not only sockets |

### 2.5 Shell and platforms (`ui-`)

Repeat the level editor's split: a Cubit holds the document, mode, status
phrase, last-operation parameters, export readiness; the camera, scene, and
gizmo live in the widget's `State`; every edit is a command; tests run
through `flutter3d_cpu`. The repository has not one line of localization, no
reading of `PointerDeviceKind.stylus` or `pressure`; `documents.dart` pulls
in `dart:io`; on the web the backend draws at a fixed size
(`kFixedResolution`).

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| ui-00 ⚠ | A shell spike: `openDevice` from `flutter3d_app`, a GLB from `--dart-define`, `SceneSurface` + `OrbitController`, `FrameTimingLog`; macOS and web runners. Measurement 0.1 ⇢ p0-01/02/03; the files become `staging.dart`/`viewport.dart` | app | S | 0 | — | `flutter build web --wasm` builds; the model rotates on macOS |
| ui-01 | Registration: the workspace, `applications`, README/LICENSE/analysis_options, an `Info.plist` with `FLTEnableFlutterGPU`/`FLTEnableImpeller`, `staging.dart` as the world's only build. ⇢ qa-02 | app | S | 0 | ui-00 | scanner 30/30; `ci.sh` green |
| ui-02 ⚠ | An M3 theme from a token table with an explicit `ColorScheme.dark` (not `fromSeed`), a `ModelerColors` extension, TextTheme 400/500, `VisualDensity.compact`, component themes; an icon set — the SDK's `Icons` with a mapping table against the handoff README's Material Symbols glyphs (F12n [Е12n] closed 2026-09-09; not taking the external `material_symbols_icons` package) | app | S | 1 | ui-01 | every role = the table's hex; a 32-tall status bar, a 36 rail button; icons with no external dependency, or the dependency recorded in the pubspec with a license |
| ui-03 ⚠ | `ModelerState` = Opening / Choosing / Ready(project, mode, submode, said, activeOperation, viewport, readiness, jobs) / Failed; `ModelerCubit` built from proposals; the camera and scene aren't in the Cubit | app | M | 1 | ui-01 | a mode switch doesn't clear the selection; `ran()` refreshes readiness; undo after a transaction — one step |
| ui-04 | The shell: a 52-tall TopBar with two `SegmentedButton`s, a 52-wide Rail, a 250–330 Properties panel, a 30-tall StatusBar; the mode-table content (ui-07) swaps wholesale | app | M | 1 | ui-02, ui-03 | at 1440×900, heights/widths via `RenderBox`; phase 2–4 modes are present, disabled |
| ui-05 ⚠ | `LayoutClass.of(width)`; tablet — a 48-wide palette, a sheet ~200 tall with a handle; phone — an 80-tall `NavigationBar`, a 56 FAB, a 130-tall sheet | app | M | 1 | ui-04, ui-07 | boundaries 599/600/1199/1200; identical tool keys across the three shells |
| ui-06 ⚠ | The app viewport: a `Listener` only on the image, `SceneSurface`, `scene_sync.dart` (ModelObject ↔ MeshNode), coalescing GPU updates once per frame. Gestures ⇢ view-03, picking ⇢ view-08/10, the manipulator ⇢ view-12, orientation gizmo ⇢ view-11 | app | M | 1 | ui-03, ui-00 | `pick_test` on a CpuDevice 128×96; `manipulator_drag_test` — one step |
| ui-07 | `ModelerTool` (id, icon, a label key, a shortcut, mode, group, command) and `toolsFor(Mode)` — one source feeding the rail, palette, sheet, and hotkeys | app | S | 1 | ui-03 | unique ids and shortcuts; the three shells share one id set |
| ui-08 ⚠ | Screen 01: an object list, a 3×3 `NumberField` grid, a modifier stack with a toggle and drag-and-drop; `section_label.dart` | app | M | 1 | ui-04, ui-03 | "1,5" and "1.5" both accepted; entering a value in X emits `SetTransform` |
| ui-09 ⚠ | Screen 02: `operation_card.dart` built from the top history entry's command parameters (`ParamHint` from syn-01), `history.amend` with no confirmation; a selection summary | app | S | 1 | ui-08, ui-06, doc-07, syn-01 | a slider calls amend with no new step; the close button doesn't touch history |
| ui-10 ⚠ | The status line: mode metrics, the first `Issue` from `ExportReadiness` (green/orange), a click → the export dialog; locale-aware `NumberFormat` | app | S | 1 | ui-04, ui-03 | an n-gon → orange text; 1240000 → "1,240,000" |
| ui-11 ⚠ | Undo/redo across three layouts, a tooltip with `undoSays`, ⌘Z/⇧⌘Z, every drag inside a transaction | app | S | 1 | ui-03, ui-06 | 40 events → one step; undo restores the mesh via `identical` |
| ui-12 ⚠ | `Shortcuts`/`Actions` from `ModelerTool.shortcut` plus shared ones; a Blender-like set — G/R/S/E/I, 1/2/3, Tab — wherever it doesn't conflict with the platform (F5 [Е5] closed 2026-09-09); meta/control by platform; focus inside `NumberField` intercepts | app | S | 1 | ui-07, ui-11 | "E" on a face starts an extrusion; inside a field it types the character |
| ui-13 ⚠ | Screen 09: `profile_editing.dart` (pure Dart: points, curve segments — quadratic/cubic Bézier with a flattening tolerance into a polyline for `LatheShape`, which only accepts a polyline; an axis, a ⌀12 hit target, a snap of 40), `profile_editor.dart` (`CustomPainter`), `lathe_dialog.dart` at 720 with a second `RenderView`; "Point / Curve / Axis" chips per the handoff README; `AddLathe` stores the curve, not the polyline (clarified by critique) | app | M | 1 | ui-06, ui-08 | a hit inside ⌀12; changing segments from 24→12 updates the summary; the preview frame = a golden; a curve of 3 points gives N segments, the sum of chord lengths ≈ the curve's own length within the flattening tolerance |
| ui-14 ⚠ | `ProjectFiles` with a conditional export: native (`file_selector` + writing per p0-13n's result — `getSaveLocation` and a direct write with no rename under the sandbox, or security-scoped directory access; `writeFileAtomically` only where the directory is reachable), web (Blob → `<a download>`); `documents.dart` with no `dart:io`. Spike 0.5 ⇢ p0-08, the sandbox spike ⇢ p0-13n | app | M | 0 | ui-00, p0-13n | under `--wasm` a GLB opens and a `.f3d` downloads; both halves pass analysis; on macOS with the sandbox on, "Save As" writes the file |
| ui-15 | A start screen: "Open File," recent files via `defaultStorage('flutter3d_modeler')` (`Storage` — an abstract interface with a text `write(name, contents) → bool`; built through `defaultStorage`, like `SaveFile`/`SettingsFile`), "New Project" with a profile | app | S | 1 | ui-14, ui-03 | 8 entries, no duplicates, broken JSON — an empty list |
| ui-16 ⚠ | The import screen: `warnings` as a list, metrics against the profile, checkboxes (weld, normals, triangulate), units (mm/cm/m → an `ImportOptions.scale` multiplier) and an up axis (Y/Z) with a bounds preview; input limits (file size on the web, morph-target vertices against `maxTextureSize`, triangles against the mobile preset) shown before the button; progress replaces the button; on the web, decoding on the main thread. Units and limits added by critique | app | M | 1 | ui-14, ui-03, doc-11 | `import_plan_test` with no Flutter; on a samples file the dialog shows the warning count; STL in mm with "mm" chosen gives bounds in meters; a file over the web limit is refused before decoding |
| ui-17 ⚠ | The export screen: format, an `Issue` list with "show," budget bars, checkboxes (including "bake node transforms" via `ApplyTransform` from doc-06 — added by critique); `toModelDocument()` → a writer → `saveAs`; ⌘E. On an error-level `Issue`: a warning and export after explicit confirmation, refusal only on empty geometry (D9 [Г9] closed 2026-09-09) | app | M | 1 | ui-10, ui-14 | round trip cube + vase → GLB → decode: the same mesh and triangle counts, frame = golden; with the checkbox, GLB nodes carry identity matrices; an object with an n-gon exports after confirmation, an empty project — refused |
| ui-18 ⚙⚠ | Autosave: 2 s debounce / ≤1× per 15 s, background serialization, `Storage.write('autosave/<id>')`, a recovery prompt; `BinaryStorage`/IndexedDB in flutter3d_screens (a repository-package change). ⇢ fmt-18 (atomic write) | app + screens | M | 1 | ui-03, ui-14 | three commands → one write (FakeAsync); a `write() == false` is reported once |
| ui-19 | `InputPolicy` (pure Dart): mouse — everything; stylus — draws, `pressure` normalized; touch — camera/long-press; inverted — an eraser; a 48-tall tap target on touch | app | S | 1 | ui-06 | touch in sculpt mode → camera; mouse → strength 1.0 |
| ui-20 ⚙⚠ | macOS: `CFBundleDocumentTypes`, the sandbox on with `user-selected.read-write` (compatible with writing per p0-13n; the level editor turned the sandbox off precisely because of a `PathAccessException` on write), its own icon; web: index.html with no soloud, a manifest, `--base-href=/modeler/`; `kFixedResolution` — recreate the device on a class change or resize `WebGlDevice` | app + webgl | S | 1 | ui-01, ui-14, p0-13n | the GPU rule is green; `flutter build macos` and `web --wasm` in CI; saving under the sandbox passes in `flutter test` on the macOS runner |
| ui-21 ⁴ | Android (`EnableFlutterGPU`, no orientation lock, an intent filter), iOS (document types, `UISupportsDocumentBrowser`, `file_selector_ios`, `FLTEnableFlutterGPU`); debug builds in CI (qa-17); a physical-iPad and Galaxy A55 check. Phase 1 per the 2026-09-09 decision: four platforms from the first version | app | S | 1 | ui-20, ui-05, ui-19, rel-19d | scanner over both directories; pressure 0..1 with a Pencil on an iPad; the app opens a GLB on an iPad and a Galaxy A55 |
| ui-22 ⚠ | `flutter_localizations` + `intl`, an `app_ru.arb` template, `app_en.arb`, every string through l10n; Russian and English from the first version (F2 [Е2]), the language of `says` — English (D4 [Г4]); both closed 2026-09-09 | app | S | 1 | ui-04 | the ru/en key sets are equal; under `Locale('en')` there's no Cyrillic |
| ui-23 ⚠ | Semantics/tooltips, focus order, contrast (an 11 px outline on a face), a 1.3 textScaler, a 48-tall tap target on touch | app | S | 1 | ui-05, ui-02 | `textContrastGuideline`, `androidTapTargetGuideline`; no overflow at 1.3 |
| ui-24 | `PopScope` with an unsaved-changes dialog, a marker in the title, `beforeunload` on the web | app | S | 1 | ui-14, ui-03 | a dialog appears when isDirty; a failed write doesn't close |
| ui-25 | A `Job` in `ModelerReady.jobs`, `Isolate.run` on native, chunked with yielding on the web, a `JobButton` with an indicator. The runner for doc-24 (§3) | app | S | 1 | ui-03 | 10 chunks → progress 0.1…1.0; canceling at chunk 3 gives no result |
| ui-26 ⚠ | `frame_test` (the picture follows the document), `mesh_overlay_frame_test`, all through `staging.dart`; numbers in README/ARCHITECTURE/the site. ⇢ qa-15 | app | M | 1 | ui-06, 09, 13, 17, doc-07 | `flutter test` with no GPU; a "scene isn't rebuilt" mutation fails |
| ui-27 ⚙⚠ | `flutter3d_editor_widgets` (new): `FieldRow`, hint controls, `NumberField`; both editors depend on it; screen 05's material panel built from hints. The `.fmat`-write gate ⇢ mat-03 | editor_widgets (new) | M | 2 | ui-08 | the level editor's tests are green after the move; §16 and the package count in README/§3.2/§16 shift in the same commit |
| ui-28 ⚠ | The phase-3 shell: a 270-tall timeline (a 44-tall transport bar, 180-tall bones, tracks, a playhead), `playback` in the state, ticked via an `AnimationPlayer` in `State`; screen 19's overlay and budget panel; screen 15's form rows. ⇢ anim-07 (the timeline), view-17/anim-24 (the preview) | app | L | 3 | ui-04, ui-06 | clicking a track sets a key; 28/64 — a 44%-green bar |
| ui-29 ⚙⚠ | A panel-free sculpting layout, a brush palette, a 250-wide card, a ⌀140 cursor, strength from `InputPolicy`; a stroke — a transaction. ⇢ pro-sc-08, view-21 | app | M | 4 | ui-19, ui-05 | no Rail/Properties; touch doesn't create a stroke |
| ui-30n *(added by critique)* | Uncaught exceptions: `FlutterError.onError` and `runZonedGuarded` in `main`, an emergency autosave write (ui-18) before showing the error, a "what happened" window with a "Report a problem" button (rel-15) and a local log of the last N commands from the doc-16 journal; no telemetry | app | S | 1 | ui-18, rel-15, doc-16 | an exception thrown inside `apply` → the autosave is written, the window shows, the form URL carries the command name; tested through `FlutterError.onError` in a widget test |
| ui-31n *(added by critique)* | Drag-and-drop a file onto the window (macOS via `desktop_drop` or a custom channel, web — `dragover`/`drop` via `package:web`) → the same path as "Open File" (ui-14/16); F7 [Е7] only covers Finder/intent in phase 2 | app | S | 1 | ui-14, ui-16 | dropping a GLB opens the import screen; an unknown extension gives a status message; on the web, tested via a synthetic event |
| ui-32n *(added by critique)* | In-app help: a menu item/`?` with a hotkey table from `ModelerTool.shortcut` (ui-07, the F5 [Е5] set) and a link to the rel-09 tutorial; no second source of truth for keys | app | S | 1 | ui-07, ui-12 | the table contains every `shortcut` from `toolsFor(Mode)` exactly once; the link leads to the site page |
| ui-33d *(added following 2026-09-09 decisions)* | A "Save without history" checkbox in "Save As" and in project export (ui-17) → `ProjectWriter(includeHistory: false)` from doc-31d; autosave (ui-18) always writes with history | app | S | 1 | doc-31d, ui-17, ui-14 | with the checkbox, no `history` section in the file; without it, undo is available three steps after reopening |
| ui-34d ⁸ *(added following 2026-09-09 decisions)* | A web worker for indivisible operations on the web (F11 [Е11] closed: a freeze with progress in the button's place is acceptable, the worker is a phase-1 item, conditional, not phase 2): the isolate compiles into a worker under wasm/JS, transferred via `TransferableTypedData`/`postMessage`, in phase 1 — import (decodeModel + fromMeshData) and export (`toMeshData` + a writer), through the same `Job` from ui-25. Trigger condition: p0-07/p0-08 show a freeze longer than 1 s on a reference operation (a 30 MB import or a 200k export). Half the condition checked in real headless Chrome: `bench_isolate.dart`'s own 316×316 grid (199,712 triangles — p0-07's own reference) with no `dart:isolate`, compiled both `dart compile js` and `dart compile wasm`, gave `toMeshData` in 353.5 ms (JS) and 427.4 ms (wasm) on the single-threaded path — well under the 1 s threshold. The export-200k half of the condition is closed: it didn't fire. The import-30MB half was also measured: a real `.glb`, exactly 30.0 MB (625,681 vertices, 1,248,200 triangles, built by `flutter3d_formats`'s `GltfWriter` and checked by its own round trip, not superficially), served to that same headless Chrome via `fetch` and parsed by `GltfLoader().load()`, compiled with `dart compile js` — parsing takes ~10 ms, two orders of magnitude under the 1 s threshold. Both halves of the p0-07/p0-08 condition are closed and neither fired: by its own wording, `ui-34d` doesn't get built — a web worker isn't needed for these two operations | app | M | 1 (conditional) | ui-25, p0-07, p0-08, mesh-30 | a 30 MB import in Chrome doesn't hold a frame longer than 100 ms; the result through a worker = on the main thread, byte-exact; if the condition never fires, the item isn't built, and that's recorded in doc §6 |
| ui-35n *(added 2026-09-10 along the way)* | The full transform panel: position, rotation (Euler angles XYZ, degrees), and scale — three sets of three `NumberField`s each, plus chips for the pivot point (median / individual centers / cursor) and space (global / local). Today only position is in the panel, and there's nowhere to enter rotation or scale | app | S | 1 | ui-08, doc-33n | "45" in the Y rotation gives a quaternion ±0.3827; changing the pivot point changes the rotation result for two objects; "1,5" and "1.5" both accepted |
| ui-36n *(added 2026-09-11 during review)* | Opening a model from several files: `.gltf` together with a neighboring `.bin` and images. Today `openModel` takes exactly one file, and on the web, where there's no neighboring directory, a `.gltf` has nothing to open with — a gap found during p0-08's review | app | S | 1 | ui-14, fmt-19 | a `.gltf` with an external `.bin` opens on the web and on macOS and gives the same document as a `.glb` of the same mesh |
| ui-37d *(added 2026-09-14 following owner decisions)* | **Split `main.dart` with zero behaviour change.** 3514 lines, one `State` holding file I/O, autosave, the transform modal, picking, tool dispatch, the animation preview and the whole screen assembly, and not one test pumps `ModelerScreen`. Pure logic → `tool_commands.dart` (`commandFor(id, selection:, mesh:)`), `selection_rules.dart`, `open_report.dart`; cohesive units → `TransformSession` (the nine modal/gizmo/snap fields, no `setState` among them), `ElementPickerCache` (one `forget()` for today's five `_picker = null` sites), `MeasurementRuns`, `TimelinePreviewWiring`; widgets with no `State` access → `ui/properties/*`, `ModelerKeys`, `TopBarActions`, `MeasurementReportOverlay`; what reads `context`/`mounted`/`setState`/`_device` → `screen/{device,files,close_and_recovery,ready_parts}.dart` as `part of 'main.dart'` with `extension … on _ModelerScreenState` (the `renderer.dart` precedent; there is no `mixin on State` anywhere in the tree). "Built once, handed to three shells" becomes a type: `ScreenParts{actions, status, properties, viewport}` + `ShellForWidth`. `_onTick` keeps its unconditional `setState` — it is what repaints the panel after a drag. The one behaviour-adjacent change, last and in its own commit: the unsaved-changes and restore-autosave dialogs become widgets reading the ARB keys that already exist for them (`recovery_dialog.dart` answers a different question and stays). Two latent quirks move verbatim and get their own rows: `_handleDroppedFile` discards the import result; `_otherPickers` is never cleared on open | app | L | 3 | ui-04 | `main.dart` ≤ 400 lines; the 828 tests and 18 goldens pass untouched; `git diff -M --color-moved` shows moves, not rewrites; ≈57 new tests on the extracted parts; under `Locale('ru')` the two dialogs are Russian |
| ui-38d *(added 2026-09-14 following owner decisions)* | **Theme tokens to the handoff table**: `onSurface #E1E3E3`; `secondary #FF458E` (today no token — `uv_unwrap_layout.dart` and `profile_editor.dart` hard-code it); `tertiaryContainer #3A2118` / `onTertiaryContainer #FFD9B0`; a `ModelerColors.success #7EE081` (absent today); a global `sliderTheme` (track 4, thumb ⌀16 — today 3/⌀12 per widget); section labels 11/400, `letter-spacing 0.08em`, colour `outline` (today 12/500); a 14/500 panel title style; rail button 40×36 r10 (today 36×36); gizmo Y `#7EE081`, Z `#6AA8FF`; `scene_shadows_panel.dart`'s raw `Colors.orange` → `colorScheme.tertiary` | app | S | 2 | ui-02 | `theme_test` holds every role's hex; no `#FF458E`/`#7EE081` literal outside `theme.dart`; `modeler-timeline.png` rechecked |
| ui-39d *(added 2026-09-14 following owner decisions)* | **`ModelerMode.ready`** admits material, animation and scene — today `isReady => phase <= 1` keeps six of eight modes disabled while their panels are built and tested; `uv`/`sculpt`/`render` stay refused (pro). The phone `NavigationBar` follows the handoff: Object / Mesh / Material / Scene | app | S | 2 | ui-04 | the switcher enables three more modes; `sculpt` is still refused (`shell_test`); the phone bar lists four |
| ui-40d *(added 2026-09-14 following owner decisions)* | **`AnimationSubmode {pose, weights, retarget, morphs}`** (digits 1–4, the `MeshSubmode` shape); `toolsFor(mode, {animation})` and `sectionsFor(mode, {animation})` with `PropertiesSection.{weightPaint, retarget, morphs}`; `ModelerReady.animationSubmode`; the second `SegmentedButton` is always the current mode's submode (mesh → element level, animation → these four, otherwise none — handoff frame rule 2). Tools only where a command stands behind them: pose `select/key (PoseJoint on three paths)/deleteKey`, weights `paint/assign/mirror/normalize`, retarget `import/autoMap/apply`, morphs `add/key/delete`; `kStrokeTools` beside `kDragTools` | app | M | 3 | ui-04, ui-39d | digits 1–4 switch the submode in animation mode; object mode shows no second switcher; every tool id unique and every `kStrokeTools` id exists |
| ui-41d *(added 2026-09-14 following owner decisions)* | **A bottom slot in the desktop shell**: `ModelerShell.bottom`/`bottomHeight` under the viewport, between the rail and the properties panel (the handoff's "viewport + the mode's lower area"); `ModelerMetrics.timeline 270 / transport 44 / timelineRows 180 / bendBar 74`. Tablet and phone keep the sheet | app | S | 3 | ui-04 | at 1440×900 with a 270 slot the viewport is 545 tall; with none, `shell_test`'s existing numbers hold |

### 2.6 Materials and modifiers (`mat-`)

The core exists in the engine and is test-covered: `SurfaceMaterial`/
`TextureBinding`, `.fmat` with `MaterialHint`, `bindMaterial`,
`uploadEncodedImage`, `EnvironmentMap`, eight sources with per-object
selection, shadows, `ProceduralTexture`. A panel built from hints and the
`.fmat`-write gate are already in
`apps/flutter3d_editor/material_panel.dart`. Missing: a material in the
editor's document, slot metadata, a compositor graph and evaluator, a
pure-Dart PNG deflate encoder, `.hdr`, modifiers, light as part of the
project, a texture budget. The graph stays inside the ROADMAP's rules: nodes
are computed on the CPU and baked into five PBR slots, the shader doesn't
change.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| mat-01 | `ProjectMaterial {surface, images, fmatPath, version}`, `ModelObject.materialSlots`; commands `AddMaterial`, `RemoveMaterial`, `SetMaterialField` (`writeFmat` keys), `AssignMaterial`, `DuplicateMaterial`, `SetTexture(materialId, slot, imageId, sampling)`, `AddImage(bytes, name)` (both moved from doc-25 into phase 1 by critique — without them an imported texture can't be assigned); `toModelDocument()` with image deduping. Absorbs doc-25 | core | M | 1 | doc-03, doc-05 | a command round trip; two objects with one material → one `SurfaceMaterial`; `AddImage` + `SetTexture` → a `TextureBinding` in the exported document |
| mat-02 | `TextureInfo(width, height, format, bytesOnDevice, hasOwnMips)` from PNG/JPEG headers (doc-15) and `Ktx2Texture.parse`; weight including mips and `blockLayout` | core | S | 2 | mat-01 | dimensions = `TextureHandle` after loading; an IHDR byte-order mutation |
| mat-03 ⚠ | Move `materialWith`, `materialDocumentFields`, `materialDocumentHint`, `_fits`, `_sameJson` into `flutter3d_editor_core/lib/src/material_edit.dart`; both editors import it. `editor_core` is a flat package (`flatDartPackages`) depending only on `flutter3d_sim`, and the library takes a `MaterialDocument`/`MaterialHint` from `flutter3d` — so the move is only possible after doc-01, and `editor_core` picks up a dependency on `flutter3d_formats` (the §16 tier shifts — rel-03). Clarified by critique | editor_core | S | 1 | doc-01 | tests move over green; `flutter analyze` clean; `dart pub get` in `editor_core` with no Flutter SDK passes (qa-03) |
| mat-04 ⚙ | The full "Material" panel: an object's material list, properties from `builtInMaterialHints` via `HintRow` in M3 tokens, "Advanced," inactive sliders per `LightingModel`; a drag is a transaction. Phase 1 got a trimmed mat-04a-n version. Done: alpha (mode + cutoff), emissive (color + strength), all five texture slots, "Advanced" (emissive strength, normal scale, and occlusion strength — only once its own map is already bound — and double-sided), and the shader picker itself. `SurfaceMaterial` got a `lightingModel` field (a sixth bit on top of `unlit`, not replacing it); `_fieldSet`/`SetMaterialField` understand `'lightingModel'` by the shader name from `LightingModel.builtIn`; `.fmat` writes and reads it as a separate `lightingModel` key (not to be confused with `MaterialDocument.lighting` — the same shader name, the same `_readLighting`/`_writeLighting`, but a whole-file field rather than a single material's); `.f3dproj` carries it as an optional key, absent meaning "not chosen" rather than a refusal (`_lightingModelNamed`, the same trick `fmat`/`graph` already use); `bindMaterial`/`bindSurfaceMaterial` in `material_loader.dart` read it before the `unlit` fallback; `lightingModelOf`/`material_panel.dart`'s dropdown follow the same path. What's left undone are two separate items, not a side effect of this panel: glTF and OBJ have no concept of "one of six built-in shaders" at all (only `KHR_materials_unlit`'s presence), so it shouldn't appear there either — neither format's decode/encode needed touching; and the binary `.f3d` (not `.f3dproj`) has byte-fixed material records with no room for a new field — a separate format change with a version bump, not a five-minute one | app + formats + core + engine | M | 2 | mat-01, mat-03, mat-04a-n | metallic is inactive under lambert; hex `#5FD4E4` → (0.373, 0.831, 0.894); three events — one step |
| mat-04a-n *(added by critique)* | The phase-1 "Material" panel — the design plan puts "Basic materials" in phase 1, and the core scenario "clean the mesh, edit the material, export to GLB" doesn't work without it: the project's material list, assigning to an object (`AssignMaterial`), color / metallic / roughness from `builtInMaterialHints` following `apps/flutter3d_editor/lib/src/material_panel.dart`'s pattern, a `baseColorTexture` slot via `file_selector` (`AddImage` + `SetTexture`) with no sampler parameters; a drag — a transaction | app | S | 1 | mat-01, mat-03, ui-08 | changing the color → `SetMaterialField`, one step per drag; the chosen PNG appears in the GLB as `baseColorTexture`; a `mesh-material-colour` frame in the app's tests |
| mat-05 | Texture slots: a 26×26 preview from a thumbnail, a name, `w×h`, weight; `file_selector` with `TextureHint.extensions`; `TextureSampling` parameters; `texCoordSet` fixed to 0 | app | M | 2 | mat-02, mat-04 | a 256×128 PNG → "256×128", "170 KB"; a BC7 KTX2 → a format badge |
| mat-06 | `ColorField`: a swatch, hex, HSV, alpha when `channels == 4`, a `linear` flag for emission | app | S | 2 | mat-04 | linear (0.214…) → `#808080`; a 3-channel hint with no alpha |
| mat-07 | `MaterialBinder`: a `Material` cache keyed by version, textures keyed by byte hash via `ResourceCache`, field updates with no object replacement; warnings into the status | app | S | 2 | mat-01 | 100 roughness edits — `createTextureFromPixels` = the number of distinct images |
| mat-08 | An external `.fmat`: `LinkMaterialFile`, `EmbedMaterial`, `MaterialFileWriter.write` through the mat-03 gate; disk in the app; export unfolds paths | core + app | M | 2 | mat-01, mat-03 | link → edit → write → `readFmat` with no warnings; an unfound shader — a warning |
| mat-09n *(added by critique)* | A pure-Dart image decoder for the Image node: PNG (inflate, filters, 8/16-bit, palette) and baseline JPEG; a from-scratch one or `package:image` in core — a decision alongside D6 [Г6]. The repository has not one pure decoder: golden tests read PNG via `dart:ui`, `cpu_png.dart` is a stored-deflate-only writer. Fallback if a decoder isn't taken: bake in the app via `dart:ui`, while core holds a pixel-free graph — then `bakeTextureGraph` from mat-32 becomes impossible in MCP, and that's recorded | core | M | 2 | mat-01 | PNG fixtures (RGB/RGBA/palette/16-bit) and JPEG decode byte-exact against `dart:ui` in the app's test; a truncated file → a refusal value |
| mat-10 ⚠ | `TextureGraph` (immutable): fixed nodes Image/Color/Blend/Channels/Levels/Invert/UvTransform/Checker/Noise/NormalFromHeight/Output with `hints`; cycle and type checks. This is "a texture compositor" with a fixed node set, not a shader graph (G1 [Ж1] closed 2026-09-09; the ROADMAP gets reworded at the September 28 review) | core | M | 2 | mat-01 | a JSON round trip; a cycle is refused, naming the node; an input's type is checked |
| mat-11 | `bakeTextureGraph` on the CPU in linear space, a cache keyed by a structural subtree hash, a chunked 256² preview, full resolution via `Isolate.run`/chunks; no `Random` | core | M | 2 | mat-10, mat-09n | two runs byte-exact; editing `factor` doesn't re-decode Image; a 6-node 2048² measurement in the doc |
| mat-12 ⚠ | `BakeTextureGraph(materialId)` → images into slots, a "baked at version N" tag; PNG with deflate (a homemade LZ77+Huffman or `package:archive` — a question); raw RGBA in the project | core | M | 2 | mat-11, mat-01 | the PNG decodes via `flutter3d_cpu`; a 1024² gradient <25% of stored |
| mat-13 | `TextureGraphPanel` at 250 (collapsed), an `InteractiveViewer`, nodes 170–210, `primary` Bézier of degree 2, `HintRow` from `node.hints`, 64² thumbnails, commands `AddNode`/`Link`/`Unlink`/`SetNodeField`/`MoveNode`, "Bake 2048²" with progress | app | L | 2 | mat-10, 11, 04 | a Color→mask link is refused with no command; deleting a node — one step |
| mat-15 | `MaterialStudio`: its own `Scene`, bodies (sphere/cube/teapot/this object), two `LightNode`s, a floor, three `SkySettings` presets → `EnvironmentMap.fromSky(size: 32)`, `OrbitController`. Absorbs view-16 | app | M | 2 | mat-07 | a `material-studio` frame on the CPU; switching presets disposes the old handle |
| mat-16 ⚠ | `equirectToCubeFaces` (an LDR panorama, face order per `_directionFor`) → `prefilter(size: 128)`; a "Custom panorama" preset | core | S | 2 | mat-15 | white top/black bottom → +Y/−Y; a 128² measurement, levels 4 |
| mat-17 ⚙⚠ | A Radiance `.hdr` decoder (RGBE RLE), `prefilterFloat`, a cube in `r16g16b16a16Float`, float-cube conformance, a `ibl-hdr` frame | engine + conformance | M | 4 | mat-16 | Khronos fixtures with provenance; conformance across four backends |
| mat-18 ⚠ | `ModelObject.modifiers`, `evaluatedMesh` cached by `(geometryVersion, modifiersHash, targetVersion)`; the `Mirror/Array/Smooth/Boolean` values come from mesh-40..48, only `hints` and wrappers live here (§3) | core | M | 2 | — | a seam-stitched mirror; a disabled one doesn't change the hash; a material change doesn't invalidate it |
| mat-19 | Stack commands and MCP tools. ⇢ doc-23 (commands), mat-32 (tools) | core | S | 2 | mat-18 | see doc-23 |
| mat-20 ⚠ | The stack in the "Object" panel: a 32-tall row, drag-and-drop, a four-item menu, a parameter card on `surfaceContainerHigh` with `HintRow`, "Apply"/"Delete," warnings; heavy work through `jobs` | app | M | 2 | mat-19, mat-18 | the array's `count` — one `SetModifierField`; frame `modifier-mirror-array` |
| mat-22 ⚠ | `ExportReadiness` rules: n-gons after a boolean, non-manifold after a mirror, blend mode with opaque alpha, `texCoordSet != 0`, `extraTextures`/`parameters` under glTF, a texture over budget, an `.fmat` with no copy | core | S | 2 | mat-18, 01, 28 | per-rule test with a mutation; cached by object version |
| mat-23 ⚠ | `SceneLighting {lights, environment, ambientIntensity, shadows, exposure, post}`; light/environment/shadow commands; `LightingSync` → `LightNode`/`RenderSettings`; presets as values | core + app | M | 2 | mat-16 | `SetLightField('intensity', 'a lot')` refused; `RemoveLight` detaches the node |
| mat-24 ⚠ | "Scene" mode v1: light sources as pickable markers with gizmos, light/environment/shadow/post panels, a status "N sources · M of 6 shadowed," a warning by `lightsDropped`/`shadowsDenied`. Extended by the 2026-09-09 decision (G4 [Ж4], §7 #36): placing several assets in one project — "Import into scene" via `ImportInto` (doc-11a-n), moving objects with the view-12 gizmo, exporting the scene as one GLB via `toModelDocument()` (every object as a node) | app | L | 2 | mat-23, 25, 06, doc-11a-n, view-12 | frame `scene-lit`; a ninth source → an orange status; two imports + moving the second → a GLB with two nodes and different matrices, one `SurfaceMaterial` for a shared material |
| mat-25 ⚠ | `LightGizmos` over `DebugDraw`: an arrow, range spheres, a cone; a marker billboard in the id pass | app | S | 2 | mat-23 | cone pixels in place; rotating the node moves the arrow |
| mat-28 ⚠ | `ProjectProfile.textures: TextureBudget(maxSide, maxBytesOnDevice, targetFormat, requirePowerOfTwo)` with presets; `measure(project) → TextureUsage` recomputed for the format | core | S | 2 | mat-02 | one image on two materials counted once; bc7 = 1/4 of RGBA8; 3000² in `overs` |
| mat-29 | `resizeRgba` (box/bilinear), `toPowerOfTwo`, `FitTexturesToProfile` preserving the source; a "shrink on export" option | core | S | 2 | mat-28, mat-12 | a 4×4 checkerboard → 2×2 gray; 1000×600 → 512×512 |
| mat-30 ⚙ | A BC1/BC3/ETC2/ASTC 4×4 encoder → KTX2, an export option; PNG in glTF. ⇢ fmt-22 (one implementation in the engine). All four encoders and `planExport`'s `textureEncoding` already existed (`fmt-22`, `exporting.dart`); the missing piece was the toggle itself in `export_screen.dart` — now a "Compress textures (KTX2)" checkbox appears only for `.f3d` (`TextureEncoding` is read nowhere else) and resets to PNG when the format is switched back | engine + core | L | 2 | mat-28 | see fmt-22; an `.f3d` export with `.ktx2` loads with no warnings |
| mat-31 | Frames `material-studio`, `modifier-mirror-array`, `scene-lit` at 320×200 in the app's `test/goldens`; numbers | app | S | 2 | mat-15, 20, 24 | three PNGs green on ubuntu |
| mat-32 ⚠ | MCP: `listMaterials`, `setMaterialField` (a schema from `MaterialHint`), `assignMaterial`, `linkMaterialFile`, `bakeTextureGraph`, `addLight`/`setLightField`, `setEnvironment`, `setShadowField`; a "the agent paints the table and sets up light" scenario | mcp | S | 2 | mat-01, 19, 23, 12 | every aspect command has a tool; the scenario reproduces |
| mat-33d *(added 2026-09-14 following owner decisions)* | **Screen 05 and its 2026-09-11 supplement, closed against the shipped panel**: a colour dot in the material list (today a checkbox); texture slots through the shared `TextureSlotRow` with a thumbnail, `w×h · weight` and a format badge (built as `ui/texture_slot_row.dart`, wired nowhere — production draws the text-only private row); the texture-graph strip at 44 (today 32) and `TextureGraphPanel` actually mounted under the material panel, collapsed by default; the status line gains texel density in `tex/cm` (the number `readiness.dart`'s `_texelDensityIssue` computes and throws away — exposed as `texelDensityOf(project, object)`; the profile unit stays `texels/m`, shown ÷100) and texture weight against `profile.textures` from `texture_budget.dart`'s `measure`; vertex and material counts; status text 11/400. What the app has and the handoff doesn't — "Advanced", the shader picker, `Cutoff`, the material studio — stays | app + core | M | 2 | mat-04, mat-13, mat-28, ui-27 | a 256×128 PNG row reads "256×128 · 170 KB"; the status shows `tex/cm` from `texelDensityOf` and "N MB of M"; the graph strip measures 44 collapsed |
| mat-34d *(added 2026-09-14 following owner decisions)* | **Scene mode wired.** `mat-24` closed with four tested panels (`SceneSourcePanel`, `SceneShadowsPanel`, `SceneEnvironmentPanel`, `ScenePostPanel`) that `_Properties` never routes to and a mode the switcher refuses: `sectionsFor(scene)` → the four; the status reads `computeSceneStatus` ("N sources · M of 6 shadowed", orange on `lightsDropped`); light markers already pick (`scene_light_picking.dart`) | app | S | 2 | mat-24, ui-39d | switching to Scene shows the four panels; a ninth light turns the status orange; frame `scene-lit` unchanged |
### 2.7 The animation pipeline (`anim-`)

The runtime half is in the engine: `Skeleton` (64 bones), an
`AnimationTrack` with three interpolations, `AnimationPlayer` with layers,
`MorphTarget`/`MorphBlend`, `BakedPoses`, a glTF decoder, and a full `.f3d`
writer; the software rasterizer transcribes the skinned stage,
`skinned-figure`/`morph-*` golden scenes exist. There is nothing that edits.
The main addition is "a pose with no scene" (`Pose` + FK over typed arrays),
which IK, retargeting, drivers, baking, and parity tests all stand on. Rig
algorithms are proposed for a fourth pure package, `flutter3d_rig` — a
question for the owner.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| anim-01 ⚙ | `Pose`: local TRS in a `Float32List` indexed by `nodes`, `parents`, `restOf`, `sampleClip`, `worldMatrices`, `jointMatrices` by `Skeleton.update`'s own formula | engine | M | 3 | — | RiggedSimple/BoxAnimated: matrices = `Skeleton.matrices` after `seek` (1e-5) |
| anim-02 ⚙ | `SkinBlend(MeshData)`: CPU skinning by `joints/weights` with the same normalization as `mesh_skinned.vert`, skipped when the matrices are unchanged | engine | S | 3 | anim-01 | positions = `MeshSkinnedVertexShader` from cpu (1e-4) |
| anim-03 ⚠ | `ProjectSkeleton`, `ProjectClip` in core; `fromModelDocument` reads skins/animations/targets; `toModelDocument` assembles `ModelSkin`/`AnimationClip`; project sections. Absorbs doc-26 (types) | core | M | 3 | — | RiggedFigure/BoxAnimated/AnimatedMorphCube round trip: joints, inverseBind within 1e-6, tracks byte-exact |
| anim-04 | `KeyTable`: `setKey`, `moveKeys`, `deleteKeys`, `setInterpolation` (linear↔cubic), `setTangent`; `to/fromAnimationTrack`; commands `SetKey`, `MoveKeys`, `DeleteKeys`, `SetInterpolation`, `SetTangent`. Absorbs doc-26 (clips) | core | M | 3 | anim-03 | `sample(t)` after edits; a round trip on InterpolationTest byte-exact |
| anim-05 ⚠ | `PoseJoint(joint, path, frame)` — an auto-key from the pose, a key on release, a transaction | core | S | 3 | anim-04 | three `PoseJoint`s in a transaction — one step, one key |
| anim-06 | `curveSamples`, `tangentHandles`, `valueRange`; Euler for display only | core | S | 3 | anim-04 | step is piecewise-constant; cubic = `AnimationTrack.sample` (1e-6) |
| anim-07 | Screen 07 assembled: `AnimationPanel` (`apps/flutter3d_modeler/lib/src/ui/animation_panel.dart`) composes `ActionsList`, `TimelinePanel`, `SkeletonTree`, and `ConstraintsList` into one `ModelerMode.animation`; the selected clip/track/key/joint and playhead position are the panel's own local state, not `ModelHistory`; only `MoveKeys` and `AddClip` go outward. Absorbs the timeline from ui-28. The live pose preview is built on the already-finished `AnimationPlayer` (the engine) and `TimelinePlayback` (`timeline_playback.dart`) — only a wire between them and the scene was missing: `buildPreviewPlayer` builds one `AnimationPlayer` over every `project.clips`, redirecting `ProjectTrack.objectId` into an index via `SceneSync.nodeOf` (the same technique `ProjectModelDocument.toModelDocument` already uses for export, only against a live scene instead of a fresh node list); `AnimationPanel` got `onSelectClip`/`onTimeChanged` — reporting the same clip selection and scrubber position it used to keep only to itself, out to the caller; `main.dart` holds one `TimelinePlayback` in `_ModelerScreenState` (not in `ModelerCubit` — like `_lens`/`_shading`/`_orbit`, this is frame state, not document state), rebuilding it only when `project.clips` or `SceneSync` change identity, and ticking it from the already-existing `_onTick`. Selecting a clip pauses on its first pose — the scrubber, not a player, moves it; there is no play button yet, `TimelinePlayback.play`/`pause` are already ready to receive one the day it appears | app | L | 3 | anim-04, 06, 08 | dragging a diamond — `MoveKeys`; frame `modeler-timeline`; selecting a clip + `seek` moves the real `SceneNode`, not a copy |
| anim-08 | A skeleton overlay via `DebugDraw.addLine` (octahedra, crosses, `#FF458E` for problems); joint picking by screen projection, an 8 lp radius | app | S | 3 | anim-01 | frame `skeleton-overlay`; clicking joint 7 selects 7 |
| anim-09 ⚠ | `VertexWeights`, persistent; `paint`, `normalize`, `pruneTo`, `mirror`, `smooth`, `gradient`, `assignSelection`. Storage — mesh-60's layers, operations — in `flutter3d_mesh/skin/` (§3) | mesh (rig?) | M | 3 | — | sum 1±1e-6, ≤n influences; a mirrored cube; a 1% stroke ≤10% of a copy |
| anim-10 ⚠ | `PaintWeights(joint, samples, strength, mode, mirror, normalize)` with a vertex list; hit-testing against `SkinBlend` positions via BVH; pressure → strength | core | M | 3 | anim-09, anim-02 | a stroke on a bent pose hits the elbow; one drag — one step |
| anim-11 | Weights shown as a vertex-color gradient. ⇢ view-18 | app | S | 3 | anim-09 | see view-18 |
| anim-12 | A 74-tall bar: a bend slider turns the `SceneNode` with no history, "Reset pose" via `Pose.restOf` | app | S | 3 | anim-01, anim-03 | the slider changes `poseVersion`, the stack doesn't grow |
| anim-13 ⚠ | `rigIssues(project, profile)`: joints > the profile / > 64, influences, zero sums, unnormalized, unused, uneven scale, tracks pointing at a missing node, unbaked IK/drivers; cached | core | S | 3 | anim-03, anim-09 | per-rule test with a mutation |
| anim-14 ⚙ | `TwoBoneIk.solve` (law of cosines, a pole), `FabrikIk.solve` over `Pose`; `Pose.writeTo(targets)` | engine | M | 3 | anim-01 | a reachable target within 1e-4; the pole sets the bend side; FABRIK ≤10 iterations |
| anim-15 | `IkConstraint` in `ProjectSkeleton.constraints`, applied after FK; `BakeIk(clip, fps)`; export always bakes | core | M | 3 | anim-14, anim-04 | after `BakeIk` the effector is within 1e-3 of the target |
| anim-16 ⚙⚠ | `ExtractRootMotion`, `BakeRootMotionIntoClip`; export "in the animation"/"in code" (extras `flutter3dRootMotion`); the engine: `AnimationPlayer.rootMotionDelta` | core + engine | M | 3 | anim-04, anim-26 | the root stays put, the sum of deltas per cycle = 2 m; byte-exact round trip |
| anim-17 | `BoneMap` with `autoMap` by a humanoid dictionary and L/R; `retargetClip` in a rest-relative form, hip scaling by height, foot planting via `TwoBoneIk`; the first item of the `flutter3d_rig` package | rig | L | 3 | anim-01, anim-14 | the same skeleton — identity; height ×2 — the foot ≤1 cm off the floor; the package count in README/§3.2/§16 shifts in the same commit |
| anim-18 | Screen 14: a clip library, two `RenderView`s, blend tracks via `crossFadeTo`/`layers`, a mapping table, `RetargetClip` | app | M | 3 | anim-17, 03, 16 | importing with no skin — a warning; frame `modeler-retarget` |
| anim-19 ⚠ | `SetShapeWeight`, `KeyShape` (a weights track), `AddShapeFromMesh`, `RenameShape`, `DeleteShape` with index shifting, `ShapeSet`; screen 15's rows. Absorbs doc-27. Screen 15's rows closed 2026-09-15 (`T5`/`S6`): `ui/morphs_panel.dart` — a slider per shape key inside a `SetShapeWeight` transaction, a key-point (`radio_button_checked` when keyed, `radio_button_unchecked` otherwise) tapping `KeyShape`, driver rows over `T4`'s `AddShapeDriver`/`SetShapeDriverField`; shape points draw through `MeshOverlayBuilder`. Deliberately not built: live morph-shape deformation in the viewport — `SceneSync` has no morph pipeline (`main.dart:1073` at the time this was checked), so only the shape-key markers move, never the mesh under them (`shape_points_overlay.dart`'s own class comment, `ready_parts.dart:291-295`) | core + app | M | 3 | anim-04, anim-03 | `KeyShape` frame 10 → sample; `DeleteShape` doesn't break `AnimationTrack`; frame `modeler-morphs` |
| anim-20 ⚠ | `ShapeDriver(shape, joint, axis, from, to, curve)`, evaluated from `Pose`, additive through `MorphSink`; `BakeDrivers(clip)` | core | M | 3 | anim-01, anim-19 | an elbow at 90° → 1.0, 45° → 0.5; baked = live (1e-5) |
| anim-21 | `RigTemplate.humanoid/quadruped`, `buildSkeleton(template, markers, bounds, options)` → a `ProjectSkeleton` with symmetry, ≤64 deforming bones | rig | M | 3 | anim-03 | bone count per the table; L/R mirrored within 1e-6; `inverseBind·worldRest = I` |
| anim-22 ⚠ | `bindWeights`: envelopes by distance to segments, visibility via BVH, smooth/mirror/prune/normalize; heat diffusion — later | rig | L | 3 | anim-09, anim-21 | a cylinder with two bones: a 0.5/0.5 seam; two "legs" don't pull on each other |
| anim-23 | Screen 16: a silhouette in `RenderView`, 8 markers, a template/composition/binding step, `SetSkeleton` + `SetWeights` as a transaction | app | M | 3 | anim-21, 22, 25 | RobotExpressive → a skeleton ≤64 bones, one history step; frame `modeler-autorig` |
| anim-24 ⚙⚠ | Screen 19: profile budgets (triangles, bones, textures, influences), `wireframeDeclined` reported honestly. `FrameResult.triangles` ⇢ view-17. The measurement half closed 2026-09-14: `ProfileBudgetReport.of(project)` (`packages/flutter3d_model_core/lib/src/profile_budget_report.dart`) reads triangles against `ExportReadiness`'s own `_budget` math, joints and influences against the same `ProjectSkeleton`/`weightsOf` walk `rigIssues` already does, and texture bytes against `mat-28`'s `measure` — nothing here re-derives a number a check already owns. `BudgetUsage.fraction`/`.over` are the bar's own width and colour, computed once rather than by the panel; `wireframeDeclined` is a field, always `true`, matching `RenderShading`'s own material/normals-only honesty. Checked directly: 19 joints against a 16-joint profile reads `joints.over == true` without the `Skeleton` constructor's own 64-joint hard cap ever firing (`packages/flutter3d_model_core/test/profile_budget_report_test.dart`). `Screen 19` itself closed 2026-09-15 (`T5`/`S9`, ⇢ view-17's own row for the screen and its tests) — the bars, the panel and the declined wireframe toggle all draw against this row's own `ProfileBudgetReport` with no second number computed anywhere in `apps/flutter3d_modeler` | app | M | 3 | anim-13, anim-03 | `skinnedDraws` = 1; maxJoints=16 on 19 joints — an orange bar |
| anim-25 ⚠ | `RigJob` (bindWeights, retargetClip, bakeIk, bakeDrivers, bakeRootMotion) through the doc-24/ui-25 runner with `TransferableTypedData` | core | M | 3 | anim-09 | through a job = directly, byte-exact; canceling doesn't change the document |
| anim-26 ⚙⚠ | GltfWriter: skins/animations/targets. ⇢ fmt-07 (phase 1)² | engine | M | 3 | — | see fmt-07 |
| anim-27 ⚙ | `.f3d` round trip of an edited rig; a shape name in `F3dRecord.morphTarget` (a new revision of section 15, if there isn't one) | engine | S | 3 | anim-03, anim-19 | documents equal; a zeroed name — red |
| anim-28 | Parity: `Pose.sampleClip` = `AnimationPlayer.seek` = `BakedPoses.of`; frame `modeler-edited-clip` | core | S | 3 | anim-01, anim-04 | all three paths within 1e-5; a tangent mutation is caught by all three |
| anim-29 | `AddJoint`, `RemoveJoint` (weights go to the parent + normalize), `ReparentJoint`, `RenameJoint`, `SetRestPose` recomputing inverseBind, `MirrorJoints`; track renumbering. Absorbs doc-26 (the skeleton) | core | M | 3 | anim-03, 09, 04 | after `RemoveJoint` the sum is 1 and `Skeleton` builds; tracks renumbered |
| anim-30 ⚠ | MCP: `setKey`, `paintWeights`, `autoRig`, `retargetClip`, `bakeIk`, `bakeDrivers`, `extractRootMotion`, `addShape`, `validateRig`; a "RobotExpressive with no skin → auto-rig → weights → keys → GLB" scenario | mcp | M | 3 | anim-13, 21, 26 | the scenario passes; a GLB with a clip and a skeleton |
| anim-31 | A phase-0 measurement — only what already has code: FK `Skeleton.update` 64 × 1000 (`scene/skeleton.dart`); the rest — anim-31a-n (narrowed by critique: a stroke, `SkinBlend`, and `bindWeights` measure phase-3 code) | rig | S | 0 | — | a number in the doc, with a date and a machine |
| anim-31a-n *(added by critique)* | Phase-3 startup measurements: a 1% stroke on 200k (over the mesh-60/anim-09 layers), `SkinBlend` at 200k, `bindWeights` at 100k; an 8 ms threshold for an isolate | rig | S | 3 | anim-02, anim-09, anim-22 | numbers in the doc; (a) >10% of a copy — reconsider the chunk before anim-10 |
| anim-32 ⚠ | `maxInfluences ∈ {1..4}`, `maxJoints ≤ 64` with a refusal message; the brush and auto-rig read the limit | core | S | 3 | anim-09, anim-13 | a profile with 8 influences is refused; a brush at 2 leaves ≤2 |
| anim-31n ⚠ *(added 2026-09-10 by gap analysis)* | **Inverse kinematics for posing**, an analytic two-bone plus a look-at with angle constraints. 2026-09-10 decision: IK lives in the modeler, not the engine — needed to plant a foot on a step and turn a head during auto-rigging and pose editing, while in a game the pose comes from a clip. Gap analysis named it among four things a close-up hero is missing. This row's own literal acceptance closes 2026-09-14 against work `anim-15` already did: `resolveIkConstraint` (`flutter3d_model_core/lib/src/ik_constraint.dart`) is analytic — no loop, no iteration count, `zero iterations per frame` by construction — reaches a target within reach to 1e-3, the `pole` decides which side the knee bends to, and a target past full extension gives a finite, fully-extended answer rather than `NaN`. Added this session: a sweep of the target across the reach boundary (1.0 to 3.0 on a unit-length chain, 0.05 steps) showing the elbow moves continuously rather than jumping, `ik_constraint_test.dart`'s own literal check for "doesn't jitter." The look-at half of this row's own description is not built — no member of `ik_constraint.dart` or `inverse_kinematics.dart` (`flutter3d_core`) names a look-at or an angle constraint — and the acceptance text itself never tests for one either | core | M | 3 | anim-21, anim-22 | the foot reaches the target, the knee faces the pole hint's direction; a target farther than the chain's total length — the chain extends and doesn't jitter; zero iterations per frame |
| anim-33d *(added 2026-09-14 following owner decisions)* | **`RigBuildOptions` beyond the mirror axis** — screen 16's composition switches get a backend: `spineCount 1..3`, `fingers` (three phalanges × five per hand), `toes`, `faceBones` (jaw, eyes), `ikChains`, `controllers`. `_BoneSpec` gains `deforming` and a `derive(markers)` for bones placed from other *left/centre* markers (phalanges along wrist→(wrist−elbow), spine segments by lerp hips→chest, jaw/eyes off head/neck) — the right side is still only ever a mirror, so symmetry stays by construction; `_humanoidBones(options)` becomes a generator; `previewRig(template, options) → {jointCount, deformingCount, controllerCount, ikChainCount}` for the result card; `buildSkeleton` refuses `deformingCount > 64`; `BuiltRig.constraints` carries arm/leg `IkConstraint`s when asked, controllers are socket parents of `hips` and not in `joints`. `requiredMarkers` stays the eleven left/centre keys. `boneSegmentsOf(project, skeleton)` for `bindWeightsJobRequestFor`; the MCP `autoRig` schema gains the flags | core | M | 3 | anim-21, anim-15 | counts per the option table (humanoid 17; +fingers 47; +spine 3 → 49; +toes 51; +face 54; quadruped 15); every left joint has its mirror within 1e-6 for every option combination; `inverseBind·worldRest = I`; `previewRig` equals `buildSkeleton(…).skeleton.jointCount` |
| anim-34d *(added 2026-09-14 following owner decisions)* | **`ShapeDriver` persisted on the object**: `ModelObject.shapeDrivers` beside `shapeSet` (a driver's `shapeIndex` indexes that object's own keys); `AddShapeDriver`, `RemoveShapeDriver`, `SetShapeDriverField` (`from`/`to` in radians, hinted in degrees); `DeleteShape` shifts drivers in the same command; an optional `shapeDrivers` key in the per-object `.f3dproj` JSON, no format version bump; `BakeDriversJobRequest` reads the object, the `bakeDrivers` tool's `drivers` argument becomes optional; three MCP tools. Shape *sets* (the handoff's "Face · 12 / Body · 3" chips) are not built — there is no such thing in the model | core + mcp | M | 3 | anim-19, anim-20 | a file round-trips its drivers; an old file reads `[]`; `DeleteShape(2)` drops drivers on 2 and shifts 3 → 2; baking from the persisted list equals baking from an explicit one within 1e-5 |

### 2.8 Professional modes (`pro-`)

Of the seven phase-4 screens, the engine only closes the raw material: UV in
the vertex format, `LodGroup` by screen fraction, a frame graph with a
version-0 external resource, bloom/SSAO/composite nodes, `readback`, the
software rasterizer, a non-rotating `RigidBody`. Nothing that writes
geometry or a texture exists. Almost everything runs on the CPU in pure Dart
and is tested with `dart test`; the engine gets three contract changes (a
buffer, a texture region, an external HDR input) plus LOD in the document.
An honest boundary: LSCM + projection, multiresolution, retopology
"simplify → quadrify → project," CPU baking, XPBD cloth, a rasterizer
snapshot, QEM with UV and weights, layered painting — in phase 4; ABF++,
dyntopo, quadriflow, GPU baking, cloth self-intersection, body rotation, a
path tracer — after.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| pro-job-01 ⚠ | `Job<T>` with `progress`/`cancel`, an isolate on native, `step()` chunked on the web. ⇢ doc-24 + ui-25 (one runner)¹ | core | S | 2¹ | — | 100 steps monotonic; a cancel mid-way; another microtask between steps |
| pro-eng-01 ⚙⚠ | `overwriteGeometry` + `DeviceMesh.overwriteVertices(firstVertex, count)`. ⇢ view-14 | hw + backends | M | 2 | — | see view-14 |
| pro-eng-02 ⚙⚠ | `overwriteTexture(texture, region, rgba)`, RGBA8 base level only; Impeller — the whole level from a CPU copy; conformance "the region reads back correctly" | hw + backends | M | 3 | — | readback of a region gives the same bytes; refuses on compressed/mip>0 |
| pro-eng-03 ⚙ | `Renderer.renderPost(hdr, settings)` with a version-0 external resource, `keepHdr: true`; a `post-only` scene. Built: `FrameGraph.addExternal(FrameResourceIds.hdrColour)` registers the passed HDR buffer as a version-0 external resource, `bloom` is its only reader (`hdr_colour@0` → `bloom@1`), the composite is called directly over its own `_ldrColor` target rather than as a graph node. `keepHdr: true` returns the bloomed but not-yet-tonemapped buffer for a second call with the same buffer, with no scene recompute. Both halves of the acceptance are green: `renderer_post_standalone_test.dart` (13 tests) — version 0 reads, version 1 is rejected at `compile`, not at runtime; a `post-only` scene (bloom off/on, composite with no AO/reflections) gives the same frame as a full `render` with those same two effects disabled; `frame_graph_test.dart` (44 tests) holds the node versioning itself | engine | M | 4 | — | a full frame = a scene with no post + `renderPost`; version 1 is rejected by the graph |
| pro-eng-04 ⚙ | A shifted-perspective `TiledProjection(base, tileX, tileY, tilesX, tilesY)` for a tiled snapshot | engine | S | 4 | — | 2×2 tiles of 240×180 stitched = a 480×360 frame, byte-exact |
| pro-eng-05 ⚙ | `FrameResult.passes: (name, active, micros)` from `CompiledFrameGraph.order` | engine | S | 4 | — | with bloom off, `bloom` is absent from `passes` |
| pro-eng-06 ⚙⚠ | `ModelNode.lods: ModelLod(surfaceIndices, maxScreenFraction)`, section `LODS` (kind 24 — today's max is 16, fmt-03/04/19/28 take 17–23) in `.f3d`, `LodGroup` in `ModelAsset`, `MSFT_lod` in glTF; a `lod-asset` scene | engine | M | 4 | — | a round trip through `.f3d` and GLB; the old `.f3d` loads |
| pro-eng-07 ⚙⚠ | Fixed-width ribbons in the overlay (screen-space extension of a segment) for 3.5 lp seams, a 1.6 retopology grid, a 2 outline. Extends view-05 (where ribbons are already assembled on the CPU) | engine | S | 4 | — | scene `overlay-ribbon`; the width doesn't depend on depth |
| pro-uv-01 ⚠ | A `seam` flag in `EditMesh` ⇢ mesh-12 (phase 1); `MarkSeamCommand(selection)` and the overlay — here | mesh + core | S | 4 | — | seams survive extrusion; a flag snapshot copies one chunk |
| pro-uv-02 | `splitIslands(mesh, seams)`, `lscm(island)` — a sparse system over CSR, conjugate gradients, two pinned vertices; UV per corner; a `Job` per island. Absorbs mesh-71 | mesh | L | 4 | pro-uv-01, pro-job-01 | a flat 10×10 grid maps to itself (1e-4); a cylinder into a rectangle; 50k faces <2 s AOT |
| pro-uv-03 | `projectUv(island, planar|box)` — a second chip instead of ABF++ | mesh | S | 4 | pro-uv-01 | a cube → 6 islands with no stretch |
| pro-uv-04 | `stretchOf(island)` by Sander (L2 through the Jacobian's singular values) | mesh | S | 4 | pro-uv-02 | isometry 1.0±1e-6; halving compression — a known number |
| pro-uv-05 | `packIslands(islands, margin, allowRotate90)` — shelves/skyline, a binary search on scale, `fillRatio` | mesh | M | 4 | pro-uv-02 | AABBs don't overlap given the margin; 100 rectangles ≥60% |
| pro-uv-06 ⚠ | `UnwrapCommand(selection, method, margin, autoPack)` with reapplication; UV into `texcoord` through seam splitting; MCP `unwrap` | core + mcp | S | 4 | pro-uv-02, pro-uv-05 | `toMeshData().layout.has(texcoord)`, vertices grew by seam corners; an MCP scenario cube → GLB with UV |
| pro-uv-07 | Screen 06: `RenderView` with seams on the left, a 400×400 `CustomPainter` on the right (a 32-cell checkerboard, islands, color by stretch, a click), a method/margin/list panel. Absorbs view-19 | app | M | 4 | pro-uv-06, pro-eng-07 | three islands, a `#FF458E` stretched one; seams visible in 3D |
| pro-sc-01 | A 1.2M-triangle stroke measurement on macOS/Chrome/A55: a 38 MB upload, a frame, editing 20k vertices + normals + overwrite, a BVH build/raycast, per-event garbage; thresholds 8/16 ms, 3 s. Two of three platforms measured: macOS (opening+BVH 3.3–5.7 s, a stroke 294–1005 ms) and Chrome (opening+BVH 24.2–24.4 s, a stroke 7.58–7.71 s) — both thresholds missed on both, the same bottleneck (`MeshNormals.build` recomputes the whole mesh). `sculpt_budget_benchmark_test.dart`'s own conclusion about Chrome turned out to be wrong: the browser doesn't need a foregrounded tab or `profile_web.py` since the test never asks for a frame — `flutter test --platform chrome` runs headless, like any other platform. The A55 still hasn't been measured — needs a phone in hand | core + tool/bench | S | 4 | pro-eng-01 | numbers in doc §6; a decision for pro-sc-09 |
| pro-sc-02 ⚠ | `SculptMesh`: 1024-vertex CoW chunks, `triangles`, CSR adjacency, a per-vertex grid, `EditMesh ↔ SculptMesh` conversion at mode entry/exit. One chunk type shared with mesh-10; the structure was chosen 2026-09-09 (B8 [Б8] closed): `SculptMesh`, not mesh-72's patch layer; pro-sc-01 measures it, doesn't choose it | mesh | L | 4 | pro-sc-01 | a 1% stroke copies ≤2% of the chunks; a radius search = brute force; the conversion preserves positions and UV |
| pro-sc-03 | Brushes draw/clay/smooth/flatten/inflate/grab/pinch/crease, `Brush(kind, radius, strength, falloff)`, X symmetry, local normals | mesh | M | 4 | pro-sc-02 | per-brush test with a mutation; symmetry mirrored within 1e-6 |
| pro-sc-04 ⚠ | A `SculptMesh` triangle BVH with `refit(dirtyTriangles)`. The same `TriangleBvh` (§3) | mesh | M | 4 | pro-sc-02 | a raycast = brute force; refit = a rebuild |
| pro-sc-05 | Dirty chunks → `DeviceMesh.overwriteVertices`, no more than once per frame; falling back to a fresh `DeviceMesh` per frame | app | S | 4 | pro-eng-01, pro-sc-03 | the frame only differs inside the brush area; measurement (c) within threshold |
| pro-sc-06 ⚠ | `SculptStrokeCommand(brush, points, pressures)` — one step, `historyBudgetBytes` 512 MB; MCP `sculpt_stroke` | core | S | 4 | pro-sc-03 | 100 strokes at 1% on 200k <10% of 100 copies; undo byte-exact |
| pro-sc-07 ⚠ | `Multires(base, levels)`: phase-2 subdivision, deltas in a local basis, descent for export with a displacement map; dyntopo — later (B9 [Б9] closed 2026-09-09: multiresolution) | mesh | L | 4 | pro-sc-02, pro-sc-03 | a 5-level cube; descend/ascend preserve displacement within 1e-4; up to 1.2M <5 s |
| pro-sc-08 | Screen 08: a panel-free layout, a 48-wide palette, a 250-wide card, a ⌀140 cursor, `pressure`, touch — orbit; a "Subdivide" button (a `Multires` level) instead of "brush density" in the mockup — a consequence of B9 [Б9] (2026-09-09 decision), screen 08's design is amended. ⇢ ui-29 (the shell), view-21 (the cursor) | app | M | 4 | pro-sc-05, pro-sc-06 | see ui-29, view-21 |
| pro-sc-09 | Web: `ProjectProfile.sculptTriangleLimitWeb` by measurement, a BVH that yields to the frame | app + core | S | 4 | pro-sc-01, pro-sc-08 | a number in the profile; a 300k stroke <16 ms on wasm |
| pro-lod-01 | Garland–Heckbert QEM over `MeshData`: quadrics, a heap on `Float64List`/`Int32List`, a flip check, a `Job` per 1000 collapses. Absorbs mesh-70 | mesh | L | 4 | pro-job-01 | a sphere 20k → 2k, Hausdorff <1% of radius; 200k → 20k <3 s AOT |
| pro-lod-02 | Attribute quadrics (Hoppe): a seam/boundary penalty, carrying `joints/weights` over with renormalization and a profile limit | mesh | M | 4 | pro-lod-01 | seams ⊂ the source; weight sum 1; frame `lod-uv` |
| pro-lod-03 | `ModelObject.lods: List<LodSpec(ratio, maxScreenFraction)>` cached by version; `AddLod`, `SetLodRatio`, `RegenerateLods`; meters ↔ screen fraction in the editor | core | S | 4 | pro-lod-02, pro-eng-06 | editing the base invalidates the cache; a round trip |
| pro-lod-04 | Screen 17: three `RenderView`s by thirds with `layerMask`, labels, a 96-wide bar with zones. Absorbs view-20 | app | M | 4 | pro-lod-03 | the three thirds differ; a widget test of the slider |
| pro-rt-01 | `retopologize(source, targetQuads)`: simplify → greedy quadrification → BVH-based shrink-wrap; quadriflow — later. Absorbs mesh-73 | mesh | L | 4 | pro-lod-01, pro-sc-04 | ≥70% quads on a sphere and torus; distance <0.5% of the diagonal |
| pro-rt-02 ⚠ | `DrawQuadCommand(4 × world)` with raycasting and snapping; the active quad — reapplication; vertices with a projection | core | M | 4 | pro-rt-01 | four points on a sphere → a quad on the surface |
| pro-rt-03 | A retopology overlay: the source with `alpha`, a 1.6 grid as ribbons, an active quad `#FF458E` at 22% | app | S | 4 | pro-eng-07, pro-rt-02 | frame `retopo-overlay` at two transparencies |
| pro-rt-04 | `bake/`: a low-mesh UV rasterizer, rays ±a shell against the high-mesh BVH → a tangent-space normal map, dilation; the GPU path — later | mesh | L | 4 | pro-sc-04, pro-job-01 | sphere→cube: the face center matches analytically (<2/255); 1024² over 100k <10 s |
| pro-rt-05 | AO (Halton, cosine-weighted), curvature, thickness on the same rasterization | mesh | M | 4 | pro-rt-04 | a plane gives AO=1; a 90° angle ≈0.5 |
| pro-rt-06 ⚠ | `BakeCommand(source, target, maps, resolution, shell)` → an `EncodedImage` and `TextureBinding`; MCP `bake_maps` | core + mcp | M | 4 | pro-rt-05, pro-rt-01 | scenario: sphere → sculpt → retopo → bake → GLB; frame `bake-relief` |
| pro-rt-07 | Screen 10: a 290-wide two-block panel, progress in the button's place | app | S | 4 | pro-rt-06, pro-rt-03 | a Job swaps the button for an indicator; a cancel |
| pro-sim-01 ⚠ | A flat cloth solver, phase 4 (C3 [В3]/H1 [И1] closed 2026-09-09): XPBD (distance, cross-edge bending, pinned points, gravity, wind, damping, substeps), collisions against physics' own `CollisionShape`; determinism as in sim. Used to be its own `flutter3d_cloth` package; merged into `flutter3d_physics` (`doc/package-merge-plan.md` §3.1) — this row's solver code didn't change, only the package | physics | L | 4 | — | a 20×20 cloth settles within 300 steps; length error <1%; byte-exact for one seed; the package count in README/§3.2/§16 shifts in the same commit |
| pro-sim-02 ⚠ | A rigid body via `Dynamics`/`RigidBody` (no rotation, with a label), particles via a `ParticleSystem` into the cache | core | S | 4 | pro-sim-03 | a cube falls and stops; particles are deterministic |
| pro-sim-03 | `SimulationCache(frames, vertexCount)`, `BakeClothJobRequest` as a Job, a project section, a cache progress bar | core | M | 4 | pro-sim-01, pro-job-01 | 120×400 — the expected size; canceling at frame 50 leaves 50 |
| pro-sim-04 | Playing back the cache through a full `overwriteVertices`, collisions via `DebugDraw` | app | S | 4 | pro-sim-03, pro-eng-01 | frames 0 and 60 differ; 4k vertices <2 ms |
| pro-sim-05 ⚠ | Simulation export: (a) ≤8 morph targets, (b) a `.f3d` vertex-animation section + node, (c) preview only; recommendation (a) | core | M | 4 | pro-sim-03 | cloth → 8 targets → GLB → frame = the cache (`cloth-morph`) |
| pro-sim-06 | Screen 11: type chips, parameters, interactions, a 150-wide bar with a transport and the cache | app | M | 4 | pro-sim-04, pro-sim-02 | widget tests; pinning through phase-1 selection |
| pro-rn-01 | A `flutter3d_cpu` measurement at 1080p and 4K with shadows/SSAO/bloom, AOT and wasm; a threshold: 4K SSAA×2 <3 min on an M3 | cpu | S | 4 | — | numbers in doc §4.2 |
| pro-rn-02 ⚠ | `RenderSnapshotJob(project, RenderPreset)`: a snapshot from the same renderer — its own `CpuDevice`, tiles, SSAA ×1/×2, frame-graph passes (pro-eng-05), PNG; an isolate on native, a tile per frame on the web; a path tracer is out of scope, the "samples" wording from screen 12's mockup goes away (2026-09-09 decision) | core | M | 4 | pro-rn-01, pro-eng-04, pro-job-01 | 480×360 = a golden byte-exact (×1); ×2 <1% of pixels |
| pro-rn-03 ⚠ | `CompositeGraph` — a fixed DAG Scene → SSAO → Reflections → Bloom → Tonemap → Look → Output ↔ `RenderSettings`; post edits through `renderPost` | core | M | 4 | pro-eng-03, 05, pro-rn-02 | a round trip; editing bloom marks only the post branch |
| pro-rn-04 ⚠ | Screen 12: a pass panel from `passes`, a 760×428 result with tile progress, a 260-wide graph (a widget from mat-13); MCP `render_snapshot` | app + mcp | M | 4 | pro-rn-03 | a 96×64 snapshot = `renderFrame` |
| pro-pt-01 | `PaintLayer` + `PaintStack.flatten`, normal/multiply/add/overlay/screen modes, 64×64 CoW tiles | core | S | 4 | — | known numbers per mode; layer order |
| pro-pt-02 | `projectBrush(mesh, bvh, hit, radius) → List<UvSpan>` via the pro-rt-04 rasterizer, a 3D falloff | mesh | M | 4 | pro-rt-04, pro-sc-04 | a stroke across a seam paints both islands; texels outside the 3D radius are untouched |
| pro-pt-03 | `PaintStrokeCommand`, `overwriteTexture` over a dirty rectangle once per frame, mips on completion, AO/curvature masks; MCP `paint_stroke` | core + mcp | M | 4 | pro-pt-01, 02, pro-eng-02 | the frame only differs inside the area; an AO=0 mask suppresses it; undo byte-exact |
| pro-pt-04 ⚠ | Flattening layers into `baseColorTexture` on export, layers into a project section, an imported texture as the background layer | core | S | 4 | pro-pt-03 | frame `paint-export` |
| pro-pt-05 | Screen 18: a ⌀96 cursor, a 300-wide unwrap panel with a `ui.Image` from flatten, layers/palette/masks | app | M | 4 | pro-pt-03, pro-uv-07, pro-sc-08 | the canvas updates after a stroke |
| pro-doc-01 ⚠ | Sections `SEAM`, `UVIS`, `MRES`, `BAKE`, `SIMC`, `PNTL`, `LODS`, `RNDR` with versions; a phase-1 project reads | core | M | 4 | pro-uv-01, sc-07, rt-06, sim-03, pt-01, lod-03, rn-03 | a round trip for each; a phase-1 file opens |
| pro-test-01 | Eight phase-4 frames, an MCP scenario "cube → … → GLB," numbers | app + mcp | M | 4 | pro-uv-07, sc-08, rt-07, sim-06, rn-04, lod-04, pt-05 | `ci.sh` green; the scenario reproduces |
| pro-after-01 | An "after phase 4" section in the doc with a reason for each deferred item; a separate line — "collaborative work" from phase 4 of the design plan and the handoff README ("groundwork for future collaboration"): not part of the plan, groundwork — the `doc-16` command journal and commands as values (added by critique) | doc | S | 4 | pro-sc-01, pro-rn-01 | agreed with the owner; the collaborative-work line references doc-16 |
| pro-pt-06n *(added 2026-09-10 by gap analysis)* | **Vertex-color painting**: the layer already exists (`mesh-12` holds `color` per corner), there's no brush or display. The brush is the same `projectBrush` used for textures, only writing into the vertex layer. Gap analysis: masks for wind, grime, wear, and texture blending in games live in vertex color, because it's free and travels with the mesh | mesh + app | M | 4 | mesh-12, pro-pt-02 | a stroke paints vertices within the 3D radius and leaves neighbors untouched; the color survives a glTF export and reads back; undo in one step |
| pro-uv-08n *(added 2026-09-10 by gap analysis)* | **An atlas across objects**: packing several objects' islands into one texture and re-pointing their materials at a shared one. Gap analysis: nine props with one texture is one draw call instead of nine. Half the work already exists — `pro-uv-04` packs islands within an object; packing across object boundaries is missing | mesh + core | M | 4 | pro-uv-04, mat-01 | nine objects → one material and one atlas; atlas fill ≥60%; per-frame draw calls drop from nine to one |
| pro-rt-08n *(added 2026-09-10 by gap analysis)* | **Manual surface-hugging retopology**: new vertices stick to another object's surface. Auto-retopology (`mesh-73`) gives an even grid and never the right edge flow around an eye or a joint; for a character this is done by hand. The same snapping as `view-26n`, only against a different mesh — hence coming after it | app | L | 4 | view-26n, mesh-20 | a vertex placed over a high-poly model lands on it within 1e-4; drift from the surface as the camera turns doesn't accumulate |
| pro-lod-05n *(added 2026-09-10 by gap analysis)* | **Impostors and billboards**: baking several angles into an atlas and a card instead of a mesh at the far LOD. Gap analysis: a tree at three hundred meters is two triangles with a baked picture, not five thousand. Deliberately last: with no scene where it's noticeable, there's nothing to optimize | app + core | L | 4 | pro-rt-06, pro-rn-02 | eight angles into a 1024² atlas; the silhouette at 300 m differs from the mesh by less than 3% of pixels |

### 2.9 Tests, CI, structure (`qa-`)

The infrastructure is strict and already exists: 30 scanner rules,
`tool/ci.sh`, `flutter3d_testing`, 33 conformance checks, a sample agent
scenario in CI. Checked: `main` is red for three reasons from the HANDOFF —
a phase-0 blocker. A detector probe: `brush`, `bone`, `face`, `bevel`,
`loop`, `manifold` pass; `dashed`, `reload`, `spike`, `oneWay`, `lap`,
`boss`, `magazine` don't. The scanner's numeral lists stop at twenty-eight
(packages) and forty-five (scenes).

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| qa-01 | A green `main`: `dart format` on four files, 4322 → 4327 across four documents, a WebGPU guard via `requestAdapter()` | repo | S | 0 | — | 30 of 30; format is silent; three green runs in a row; a date in the HANDOFF |
| qa-02 | Three packages, `geometry`, `formats`, and the app under the scanner: the workspace, `flatDartPackages` with reasons, `applications`, `notARepeatableStep`, numerals up to forty (28 today + geometry/formats/mesh/core/mcp = 33 by end of phase 0, up to 37 with editor_widgets/rig/cloth/fbx; the `rules.dart` list is extended ahead of the directory existing, as its own comment requires), §16, README, `packages.md`, `testing.md`, Info.plist, CHANGELOG/LICENSE/README. Shared with mesh-00, doc-02, ui-01, rel-02/03 | tool/structure + docs | S | 0 | qa-01 | scanner green with six directories; `publish_check.sh` is satisfied |
| qa-03 ⚠ | The rule "a flat Dart package resolves without the Flutter SDK": walking `dependencies` down to `flutter: sdk`; a detector proof; the rule count 30 → 31 in six places | tool/structure + docs | S | 0 | qa-02 | green on three flat packages; red on a mutation and on model_core → flutter3d |
| qa-04 | `ci.sh` reads the `dart test` list from `flatDartPackages` (`--flat-dart`); `-p chrome` for mesh; a process test `dart run bin/model_mcp.dart`. Absorbs doc-30 | tool | S | 0 | qa-02 | removing a name from the list changes the command with no script edit |
| qa-05 | A forbidden-word dictionary in the doc and CONTRIBUTING (`dashed` → `dotted`, `reload` → `reopen`, `spike` → `peak`); examples in `proveDetectorsWork` | tool/structure + docs | S | 0 | — | `dashedAxis` fires, `bevelWidth` stays silent |
| qa-06 | An enum and public-member policy: `ElementLevel`, `IssueSeverity` — enums with an exemption; content — sealed; a test as a caller | tool/structure + docs | S | 1 | qa-02 | a skeleton with an enum and a sealed class passes; a table in the doc |
| qa-07 ⚠ | A half-edge invariant audit, χ across operations, manifoldness, a round trip, seeded fuzzing, persistence ≥90% of chunks. ⇢ mesh-11 (`validate`), mesh-32 (fuzzing), mesh-10 | mesh | M | 1 | qa-02, qa-04 | see mesh-11/32; green on the VM and under `-p chrome` |
| qa-08 ⚙⚠ | Writer round trips and STL fixtures with provenance in `flutter3d_samples`'s own `assets/ATTRIBUTION.md` (where provenance is already recorded today, per file, with author and source; `LICENSES.md` only lives under `apps/*/assets/`), bump samples 0.4.2 → 0.4.3. ⇢ fmt-06/07/08/09/10 (the tests live there) | engine + samples | M | 1 | qa-01 | see fmt-*; a 1e-6 tolerance, not byte-exact |
| qa-09 | The glTF Validator in `ci.sh`. ⇢ fmt-11 | tool | S | 1 | qa-08 | see fmt-11 |
| qa-19n *(added by critique)* | Checking export against an external engine automatically, as the design plan requires ("the exported file opens in Godot and Unity" via an autotest): headless Godot (`godot --headless --import` + a script printing mesh/triangle/material counts) on the doc-21 and rel-09 fixtures, in its own CI job; Unity and Blender — a manual checklist before release (K2 closed 2026-09-09; there's no headless Unity license in CI) | tool + ci | S | 1 | fmt-11, doc-21 | the job is green on `table.glb` and the tutorial's GLB; mesh and triangle counts match `compareModelDocuments`; the step's time is in `ci.yml` |
| qa-10 ⚙⚠ | Scenes `mesh-overlay` (⇢ view-05) and `material-preview` (⇢ mat-15 in the app, not among the 43 scenes); budgets, `_provisional`, forty-three → forty-four | engine example + backends | M | 1 | qa-01 | see view-05; `_provisional` is empty by merge time |
| qa-11 ⚙⚠ | A buffer-overwrite conformance check, 33 → 34. ⇢ view-14³ | conformance + hw | M | 2³ | qa-01 | see view-14; an Impeller run with a date in the HANDOFF |
| qa-12 ⚠ | The "agent builds a table" scenario and a `tools_test` round trip. ⇢ doc-20, doc-21 | mcp | M | 1 | qa-02, qa-04 | see doc-21 |
| qa-13 ⚠ | A CI bench artifact `bench-mesh` (⇢ mesh-04/31), a stress scene and `FrameTimingLog` (⇢ p0-01/02/03), a table in the HANDOFF and the doc | mesh + engine + ci | M | 0 | qa-02 | the artifact is on every `check`; a table with the machine |
| qa-14 | `draw_count_baseline_test` on the CPU with exact numbers. ⇢ view-22 | cpu | S | 1 | qa-01 | see view-22 |
| qa-15 ⚠ | App tests through the rasterizer. ⇢ ui-26 (+ `scaffold_test`, `theme_test` from ui-05/ui-02) | app | M | 1 | qa-02, qa-14 | see ui-26 |
| qa-16 | Documents catch up with the tree: README, `packages.md`, `testing.md`, §3.2/§13/§16, skills, the "a new test → `structure.dart` → four documents" recipe. Shared with rel-07, fmt-16 | docs + site | S | 1 | qa-02 | scanner green after every merge; 33 packages and 7 applications |
| qa-17 ⚠ | The editor's web build (wasm), `flutter build macos`, iOS `--no-codesign`, an Android CI matrix; step times recorded | tool + ci | S | 1 | qa-02, qa-13 | builds green; before/after times in `ci.yml` |
| qa-18 ⚠ | Tests for the project format, commands, history, `ExportReadiness`. ⇢ doc-05/08/10/14 (the tests live there) | core | M | 1 | qa-02, qa-07 | see doc-*; the same fixture on ubuntu and macOS |

### 2.10 Phase 0: measurements (`p0-`)

Measurement tools already exist, but scattered: a `Timeline` around passes,
`FrameResult.cpuMicros/submitMicros/drawCalls`, `FrameTimingLog`, the
example's HUD, `bench_util.dart`; the record format is set by ARCHITECTURE
§14 and `tool/webgpu_spike/README.md` ("The answer"). Five working-through
items are laid out across twelve units; half of §7's decisions are made by a
numeric threshold, and each records the threshold and the action for every
outcome.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| p0-01 ⚠ | The rig: the load is built into `staging.dart` (`kStress`, `kStressObjects`, `kOrbit` from `--dart-define`), an orbit over 600 frames, a HUD with `FrameTimingLog` and load time, a 1M-triangle `.f3d`/GLB generator, an Android example runner with `EnableFlutterGPU`. The rig lives in the modeler, not the engine example: the right thing to measure is the path a document actually opens through. Shared rig for view-01, qa-13, ui-00 | modeler + tool/model_spike | S | 0 | — | a profile run on macOS prints timings; wasm builds; a 10k-triangle test via a golden |
| p0-02 | Measurement 0.1: macOS Metal, Chrome WebGL2/WebGPU, JS and wasm; one 1M-triangle mesh and 1000×1000 draws; build/raster mean/worst, `cpuMicros`, load time, memory; three runs | doc | S | 0 | p0-01 | a quality gate (2026-09-09 decision: the web is equal footing, the measurement doesn't choose "view-only"): ≤16.6 ms → a 1M web-profile budget; 16.6–33 → a ≤300k profile budget; >33 or a >10 s load → phase 1 gets whatever is needed to pass — a JS build as ARCHITECTURE §1's recorded exception, chunks instead of an isolate (p0-07), ui-34d; by 2026-10-05 |
| p0-03 | Measurement 0.1 on a Galaxy A55 (200k/500k/1M, an isolate load, memory) and an iPad after rel-19d | doc | S | 0 | p0-01 | a value ≤16.6 ms → the "mobile" profile preset; 200k >33 ms → the mobile preset shrinks to a passing budget, the phone stays a phase-1 platform (2026-09-09 decision) |
| p0-04 ⚠ | An `EditMesh` spike (cube → extrusion → toMeshData → a frame) with a 50/200k bench. ⇢ mesh-01 (in the package, not `tool/`); thresholds: ≤8 ms → a full in-frame rebuild; 8–33 → `writePositions(into:)` in 1.2, and p0-06 is required; >33 → reconsider the structure | mesh | M | 0 | p0-09 | see mesh-01; an answer by 2026-09-25 |
| p0-05 ⚠ | Persistence: `ChunkedFloat32` (128/256/1024) versus `PatchedFloat32` (a log of prior values), clustered and scattered distributions, RSS over 64 steps. ⇢ mesh-02 | mesh | S | 0 | p0-04 | ≤10% of a copy and ≤2 ms in both → a chunk is chosen; clustered-only → a flat array + a log; neither → a snapshot per transaction |
| p0-06 ⚙⚠ | `DeviceMesh.upload` per frame against an `overwriteGeometry` prototype (Impeller `DeviceBuffer.overwrite`, WebGL `bufferSubData`, WebGPU `writeBuffer`) at 200k with a 1% edit; the prototype in a branch | engine example + hw (branch) | M | 0 | p0-01 | (a) ≤16.6 ms → overwrite moves to phase 4; (b) passes → view-14 into phase 1; neither → an overlay preview |
| p0-07 ⚠ | `Isolate.run` (with/without `TransferableTypedData`) versus chunks yielding on wasm for fromMeshData+toMeshData at 200k | mesh + engine example | S | 0 | p0-04 | overhead ≤20% / ≤50 ms; chunks: a worst case ≤50 ms and +≤25% → operations are step-based from day one; otherwise a freeze with progress in the button's place (F11 [Е11]), and a freeze >1 s on a reference operation → ui-34d in phase 1 |
| p0-08 ⚠ | A web file spike under `tool/`: `openModel` → `readAsBytes` → `decodeModel` → a frame; downloading via `package:web`; `--wasm`; Chrome/Safari/Firefox; 30 MB. The code moved into ui-14 (`project_files_web.dart`) — no separate spike remains. Opening a `.gltf` with a neighboring `.bin` isn't done: `openModel` takes one file, and that's a recorded gap ⇢ ui-36n | modeler | S | 0 | — | a quality gate: (1)–(3) pass → 1.15 takes the code; doesn't build under wasm → a JS build as a recorded exception; no Safari/Firefox → a custom wrapper over `package:web` in ui-14 (the web is equal footing, 2026-09-09 decision); a freeze >1 s on 30 MB → ui-34d |
| p0-09 ⚙⚠ | Three package skeletons under the scanner + a check in a Flutter-free `dart:stable` container + a rule on transitive SDK dependency. ⇢ doc-00 (the spike), qa-02 (registration), qa-03 (the rule), rel-04 (the container) | packages + tool/structure | S | 0 | — | see doc-00/qa-03; an answer by 2026-09-25 |
| p0-10 ⚠ | A `TriangleBvh` prototype (becomes view-09's implementation) + vertex projection/box picking at 50k/200k/1M against `Raycaster` by brute force. ⇢ mesh-20 / view-09 (one implementation, §4); here — the measurement | mesh | S | 0 | p0-04 | a ray ≤1 ms/200k, ≤3 ms/1M, build ≤100 ms, projection ≤4 ms → picking stays on the CPU; otherwise a half-edge neighborhood search / a face id pass in phase 2 |
| p0-11 ⚠ | An end-to-end drag pipeline over 600 frames: edit → snapshot → toMeshData → buffer → frame; GC pauses, allocations, the slow-frame fraction | mesh + engine example | S | 0 | p0-01, 04, 05, 06 | no pauses >8 ms and ≤5% slow → an API on values; 8–16 → `toMeshData(into:)`, a per-transaction snapshot; >16 → a mutable working mode inside the transaction |
| p0-12 | A README for the spikes, "The answer"; a §6 table with measured values (date, machine, Dart), a §7 "resolved" column, duplicates in ARCHITECTURE §14 | doc | S | 0 | p0-02..11, p0-13n | not one phase-0 row without a number; §7 has no "the measurement decides"; deadline 2026-10-05 |
| p0-13n ⚠ *(added by critique)* | A "saving under the macOS sandbox" spike: `file_selector.saveFile` + a direct write with no rename, against `writeFileAtomically` (a temp file + rename — under `user-selected.read-write` a rename into the chosen file's directory isn't permitted; the level editor turned off the sandbox with exactly this wording in `Release.entitlements`), against security-scoped directory access. The answer closes F4 [Е4] and ui-14's native branch | app (a spike under `tool/`) | S | 0 | ui-00 | a "method × sandbox → wrote / `PathAccessException`" table; the chosen method is recorded in ui-14 and F4 [Е4] |

### 2.11 Publishing and product (`rel-`)

The release infrastructure is almost entirely automatic: `publish_check.sh`,
building the API reference by directory, `llms.txt` from NAV, `demos.sh`, CI
builds an unsigned iOS binary and a signed Android one. The 0.6.0 set, 27 of
28 on pub.dev; the names `flutter3d_mesh`, `flutter3d_model_core`,
`flutter3d_model_mcp`, `flutter3d_modeler` are free (checked 2026-09-09), as
are `flutter3d_geometry`, `flutter3d_formats`, `flutter3d_fbx`,
`flutter3d_cloth`. Friction points — manual lists; the site doesn't show a
fourth game, so "next to four games" rests on an unclosed ROADMAP item.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| rel-01 | Lock in the names (2026-09-09 decision, C5 [В5]: mesh / model_core / model_mcp, geometry / formats, app `flutter3d_modeler`, bundle `dev.flutter3d.modeler`; code in this monorepo) in doc §7 with the check's date | doc + ARCHITECTURE | S | 0 | — | a "Name" line with a date; the same names in §16 |
| rel-02 | The skeleton for three packages, green in `publish_check` (version = the set, `resolution: workspace`, `^0.6.0` on siblings, LICENSE/CHANGELOG); in mcp — a `bin/model_mcp.dart` stub answering `--help` (needed by rel-04 in phase 0; the real server is doc-19). Shared with qa-02 | mesh, core, mcp | S | 0 | rel-01, mesh-00 | `publish_check.sh` prints `ready` for all three; `dart run flutter3d_model_mcp:model_mcp --help` prints usage |
| rel-03 ⚠ | The scanner, §16 (`geometry` before `formats`, `formats` before `flutter3d`; mesh after `geometry`, core after `formats`, `flutter3d_editor_core` after `formats` — a new mat-03 dependency, mcp a tier lower; the order per the 2026-09-09 decision), `ci.sh`, numerals. ⇢ qa-02/qa-04 | tool + ARCHITECTURE | S | 0 | rel-02 | see qa-02 |
| rel-04 | A `setup-dart` job with no Flutter: a temporary pubspec with `dependency_overrides`, `dart pub get`, `dart run …:model_mcp --help` (the stub from rel-02; `tools/list` in the container — doc-19's acceptance); the same script for `editor_mcp`. ⇢ doc-00/qa-03 (the container half). The doc-19 dependency was dropped by critique: a phase-0 item waited on a phase-1 item | mcp + ci | S | 0 | rel-02, rel-03 | green on a clean SDK; red with `flutter: sdk` |
| rel-05 | A slot in the train: §16 "carries X and does not go out" for five new packages until the set rel-06 ships in (after rel-16; C8 [В8] — December 27 is not the target); a CHANGELOG under the next set's number along the way; one tag per set | ARCHITECTURE + CHANGELOG | S | 1 | rel-02, rel-03 | §16 names who's shipping; the version rule is green |
| rel-06 | The first publish, in §16 order (geometry → formats → flutter3d → mesh → core → mcp), checking the archive against the tree (skills/ in the archive), README/`index.md`/`packages.md`, `deploy-docs.sh`. 2026-09-09 decision (C8 [В8]): only once phase 1 is in the hands of its first users — after rel-16; December 27 is not the target | mesh, core, mcp, geometry, formats + site | S | 1 | rel-05, rel-14, rel-16, doc-10, doc-14 | pub.dev answers 200; pub points ≥150; /docs/ shows 33 packages |
| rel-07 | README "What is here," §3.2, `packages.md`, `testing.md`, `quickstart.md`, counters. Shared with qa-16 | docs + site | S | 0 | rel-02, rel-03 | scanner green; `rg 'twenty-eight'` only in §16 |
| rel-08 | The `Modeler` site section (badge `tool`): `index.md`, `tutorial.md`, `demo.md`; a homepage card; pictures from the app's own tests in `site/assets/modeler/` or a `goldenSets` extension | site | M | 1 | rel-07, ui-04 | three pages in the sidebar and `llms.txt`; the pictures exist |
| rel-09 | A "an asset from import to engine in 15 minutes" tutorial, step by step; the same scenario as a `tutorial.jsonl` through MCP in CI with a GLB diff and a frame; the measured time with a date; `first-project.md` — four templates | site + app + mcp | M | 1 | rel-08, ui-16/17, doc-20, fmt-06 | the scenario runs in CI; `GltfLoader` with no warnings; the time and machine on the page |
| rel-10 ⚠ | `"modeler:apps/flutter3d_modeler"` in `demos.sh`, `demo.md` with an iframe and full screen; built with the same compiler the site itself ships (dart2js, no wasm); check COOP/COEP in Safari; the web demo edits, not only shows — if the p0-02 gate isn't met, whatever closes it is built first (2026-09-09 decision) | site + app | M | 1 | rel-08, ui-14, p0-02 | /demo/modeler/ opens a GLB and downloads one in Chrome and Safari |
| rel-11 | `flutter build macos --release` in the `macos` job, `upload-artifact`, a GitHub Release on tag; signing and notarization aren't in phase 1, the release opens via "right-click → Open" (F8 [Е8], 2026-09-09 decision) | ci + app | S | 1 | rel-03, ui-20 | the artifact opens on a clean Mac via "right-click → Open"; the Release carries a zip |
| rel-12 ⚠ | A ROADMAP entry at the September 28 review: an "A modeller, and the same agent driving it" track with an Acceptance line; an edit to "After this quarter" about the exporter, to "Not doing" about the graph, and `apply and revert` (⇢ doc-29) | ROADMAP | S | 0 | rel-01, rel-17 | the ROADMAP, dated to the review, contains the track; agreed with doc §4 |
| rel-13 ⚙⚠ | Level-editor template models from model-editor documents: sources under `tool/models/`, `dart run flutter3d_model_core:export`, `git diff --exit-code`; requires a deterministic `GltfWriter`; an option — a fifth `showcase` template | tool + level-editor templates + core | M | 2 | rel-09, fmt-06, doc-10 | `make_templates.py && git diff --exit-code` green on macOS and ubuntu |
| rel-14 | Skills `editing-order`, `model-document`, `what-it-refuses` + `skills_test` (and for `editor_mcp`). ⇢ doc-22 | mcp | S | 1 | rel-02, doc-20 | see doc-22; `--dry-run` shows skills/ in the archive |
| rel-15 | `modeler_report.yml` (label `modeler`), a "Report a problem" button with a pre-filled URL and no telemetry, `bug_report.yml` with four backends | .github + app + site | S | 1 | rel-08, doc-14 | in the issue chooser; a widget test of the URL |
| rel-16 | A 5–10 person cohort, the task — a timed tutorial run, a paragraph in "Where it stands" with numbers; phase 2 doesn't start without it | ROADMAP + doc | S | 1 | rel-09, 10, 11, 15 | ≥5 timed runs; the "15 minutes" line confirmed or rewritten |
| rel-17 | The platform answer (2026-09-09 decision): phase 1 — macOS, browser, Android (tablet and phone), iOS (iPad and iPhone), all four on equal footing; Windows/Linux — after a ROADMAP track; the site doesn't promise a platform with no CI build; measurements p0-02/03/08 are gates, not a choice | doc §7 + ROADMAP + ci | S | 0 | p0-02/03, p0-08 | a table in §7 and on the page; each of the four platforms has a CI step (qa-17) |
| rel-19d *(added following 2026-09-09 decisions)* | Purchase: a physical iPad with a Pencil and an Apple Developer account by mid-phase-1 (A2, F8 [Е8]); owner — Dmitrii; after purchase, p0-03 is re-measured on the iPad, ui-21 and qa-17 get a device for manual checking; macOS signing and notarization stay "right-click → Open" through phase 1 | owner | S | 1 | — | the iPad row in the p0-03 table is filled with a number and a date; ui-21's build stands on an iPad and a Galaxy A55; the account is recorded in the HANDOFF with no secrets |
| rel-18 | SECURITY.md: STL, the project format, writers in scope; `config.yml` → the form | SECURITY + .github | S | 1 | rel-15, fmt-06/08/09 | listed; agreed with ARCHITECTURE §8 |

### 2.12 Footnotes for changed phases

Sizes didn't change. The phase changed for three items during synthesis
(¹–³) and five more by 2026-09-09 owner decisions (⁴–⁸), each with its own
reason:

¹ pro-job-01 — from phase 4 to 2: merged with doc-24 (phase 2), because a
task runner is already needed by phase 2's boolean modifiers and graph
baking (mat-11, mat-20), not only by phase 4.

² anim-26 — from phase 3 to 1: merged with fmt-07, because a glTF writer
with no skins silently drops an imported model's rig, and fmt itself puts
skins in phase 1 (⚠ against the ROADMAP, §7 item 7).

³ qa-11 — from phase 1 to 2: merged with view-14, whose default phase is 2
and phase 1 only by p0-06's outcome; the conformance check travels with the
contract change, not ahead of it.

⁴ ui-21 — from phase 2 to 1: decision 3 (phase 1 ships on macOS, web,
Android, and iOS), platform configuration is needed for the first version;
§7 #34 amended.

⁵ fmt-25 — from phase 3 to 2: decision 18 (a dedicated FBX reader), skins
and animation follow fmt-24 down the same track rather than waiting for the
character pipeline.

⁶ doc-11a-n — same phase (2), the "per §7 #36" condition dropped: decision
10, placing assets is unconditionally part of "Scene" mode.

⁷ fmt-26 — dropped: decision 18, no server-side conversion.

⁸ ui-34d — a new phase-1 item, conditional, whereas F11 [Е11] had put the
web worker in phase 2: decision 2, if p0-07/p0-08 show a freeze longer than
1 s.
### 2.13 An agent that can see the model (`mcp-`)

Aspect added 2026-09-10. `doc-19`…`doc-22` set up a server, a session of ten
verbs, and a tool table from `modelCommandNames` — and not one of the ten
verbs is visual. The agent edits the model blind: it knows
`ExportReadiness`'s numbers and never sees the silhouette. The only picture
in the plan is `render_snapshot` from `pro-rn-04`, phase 4, behind the
offline renderer.

**Why the picture can't be handed over today.** `flutter3d_model_mcp` is a
flat Dart package: a rule `tool/structure.dart` and `tool/flat_dart_check.sh`
both hold, with the reason recorded in its own pubspec — "`dart run` won't
resolve a package depending on the Flutter SDK, so one Flutter import in
this graph isn't a heavier process, it's a server that won't start." The
level editor already hit this wall: its own `screenshot` tool exists and
**refuses** (`editor_tools.dart:389`), because `GraphicsDevice.present`
returns a Flutter widget.

**The untangling is cheaper than it sounds, and this is a finding from
investigation, not a hope.** In `packages/flutter3d/lib/`, Flutter is named
in **four files**, and all four are about loading assets: `asset_source.dart`
and `gltf_resolvers.dart` (`rootBundle`), `model_loader.dart` (`kIsWeb`),
`texture_upload.dart` (`dart:ui` for decoding). `Renderer`, `Scene`,
`CameraNode`, `DeviceMesh`, `RenderView`, and the whole pass graph don't name
Flutter. Same story in `flutter3d_cpu`: drawing is pure, Flutter is only
needed by `present()` and image decoding; `encodePng` is **already** pure
Dart. The obstacle is three points, not something woven throughout.

**The path from a project to a picture already exists.**
`ModelerStage.fromProject` → `renderFrame` → `encodePng` is exactly what
`frame_test.dart` already does, drawing 160×100 frames with no GPU. What's
missing is making it reachable from a process with no Flutter.

This round's decisions: the consumer is an agent working alongside a human;
the server lives in both homes (headless by default, GUI behind a flag);
transport — stdio for headless, local HTTP for GUI; the agent gets every
command plus composite recipes; addressing — numeric ids, as internally;
history is shared, but the agent only undoes its own; a journal underneath
it all.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| mcp-01n ⚠ | **the contract**: `GraphicsDevice.present() → Widget` leaves `flutter3d_hardware` for a separate `DevicePresenter`, implemented by a Flutter wrapper sitting next to each backend. The hardware layer stops naming Flutter — the same way it already doesn't name a graphics API | hw + 4 backends + conformance | L | 1 | — | `flutter3d_hardware` and `flutter3d_conformance` are in `flatDartPackages`; 33 conformance checks are green on all four backends; a new scanner rule "the hardware layer names no Flutter". `present()` is gone from `GraphicsDevice` (`presentFrame` lives in `flutter3d_app`'s own conditional halves instead — a prior session's own work, confirmed by reading the current tree rather than assumed from this row), and both `flutter3d_hardware` and `flutter3d_conformance` are in `flatDartPackages` today, closing two of three acceptance clauses literally. The third is not literally true: there is no rule named "the hardware layer names no Flutter" — but `flutter3d_hardware`'s own membership in `flatDartPackages` already means `tool/structure.dart`'s "a flat Dart package resolves without the Flutter SDK" rule checks exactly that fact continuously, under the name that rule already had before this row existed, rather than a second rule checking the same thing twice |
| mcp-02n | `flutter3d_cpu` becomes a flat package: `cpu_device.dart` drops `package:flutter/widgets.dart`, `cpu_frame_widget.dart` moves into a wrapper. `encodePng` is already pure and travels for free | cpu | M | 1 | mcp-01n | `dart test` (not `flutter test`) runs `flutter3d_cpu`'s suite; the package is in `flatDartPackages`; `tool/dump_fixture.dart` becomes a script — its own comment today explains why it's a test. `cpu_device.dart` names no Flutter import at all; the widget moved to `flutter3d_app/lib/src/cpu_frame_presenter.dart`; `flutter_test` and the `flutter:` environment constraint are gone from the package's own pubspec entirely, and `cross_backend_test.dart` (mcp-04n) decodes its golden PNGs with no Flutter SDK behind the call. Closed 2026-09-14: the package's last real blocker was `shader_names_test.dart` and `conformance_test.dart` dev-depending on `flutter3d_shaders`/`flutter3d_conformance`, both of which resolved the Flutter SDK — but neither actually needed to. `flutter3d_shaders`' own `flutter: sdk` dependency was vestigial (`lib/`'s only file is a plain `const` list; its one test needed nothing from `flutter_test` that `package:test` does not give), and `flutter3d_conformance` named no Flutter import of its own either — both are flat now, `flutter3d_cpu` is in `flatDartPackages`, and every backend's own `conformance_test.dart` (`flutter3d_webgl`, `flutter3d_webgpu` included) resolves the Flutter SDK through one fewer hop than before |
| mcp-03n ⚙ | A Flutter-free rendering core: `rootBundle` moves behind an injectable reader (extend `AssetSource`/`AssetUriResolver`, don't invent one), `kIsWeb` behind an environment constant, image decoding behind an `ImageDecoder` interface with a Flutter implementation as the default. The rendering engine becomes a flat package, `flutter3d` re-exports it and keeps the widgets for itself. The same operation as `doc-01`, one layer up: that one moved out the vocabulary, this one moves out the renderer | engine → a new flat package | L | 1 | mcp-01n | `dart run` in the package with no Flutter SDK builds a `Renderer` and draws a frame; 4322 tests with no import edits |
| mcp-04n | A pure-Dart PNG decoder as an `ImageDecoder` implementation for the headless path. PNG only; JPEG is a separate item, if needed. ⇢ mat-09n (one implementation: that item says `bakeTextureGraph` from mat-32 is impossible in MCP without it) | core | M | 1 | mcp-03n | every PNG from `test/goldens` decodes pixel-for-pixel the same as `dart:ui`. `decodeImagePure` in `flutter3d_formats` wraps the PNG decoder the merge already moved there (and the baseline-JPEG one beside it, for free) behind `ImageDecoder`'s own shape with no import of the typedef needed; `flutter3d_cpu`'s `cross_backend_test.dart` now calls it instead of `dart:ui`, and all 45 of its scene comparisons pass unchanged under plain `dart test` — the same numbers, decoded with no Flutter SDK in the call at all |
| mcp-05n | `renderProject(RenderRequest {project, view, width, height, shading, selection}) → PNG` in `flutter3d_model_core`. Closed 2026-09-14, with one real deviation from this row's own one-liner: `renderProject` takes a `GraphicsDevice Function(int, int) deviceFactory` rather than building a `flutter3d_cpu` device itself — `flutter3d_cpu`'s own pubspec still dev-depends on `flutter3d_conformance` and `flutter3d_shaders` for two of its own test files, and this workspace's shared lock resolves a dev dependency the same as a real one, so a direct dependency would have carried the Flutter SDK straight into `flutter3d_model_core` and `flutter3d_model_mcp` above it (`tool/structure.dart`'s "a flat Dart package resolves without the Flutter SDK" rule caught this empirically, not by inspection). `RenderProjectView`/`RenderShading` are final classes with const instances rather than enums, per "an enum in a published package is machinery or is not an enum" — `LightingModel`'s own shape. `RenderShading` ships two members, `material` and `normals`, not the four `mcp-08n` eventually names: `wireframe` waits on `view-07`'s own edge-drawing, and a member that drew the same picture `material` does under that name would be a lie the type system could not catch. `RenderRefusal` names the size limit. PNG comes from `flutter3d_formats`'s own `encodeCompressedPng` (`mat-12`), not a second encoder. Tested two ways: `flutter3d_model_core/test/render_project_test.dart` proves the refusal without ever calling `deviceFactory`; `flutter3d_cpu/test/render_project_test.dart` (a new dev dependency running the opposite direction, harmless since nothing requires `flutter3d_cpu` itself to stay flat) draws a real cube on a real `CpuDevice` and checks pixels for every named view, for `normals` against `material`, and for a selected object against an unselected one | core | M | 1 | mcp-02n, mcp-03n, doc-12 | the picture matches `frame_test`'s own frame for the same scene; size capped at 1024×1024, a refusal names the limit |
| mcp-06n | A `render` tool: views `front/back/left/right/top/bottom/iso`. The PNG is returned as MCP image content, not base64 in text. Closed 2026-09-14, after its own real blocker (`flutter3d_cpu` needing the Flutter SDK to actually draw, which would have cost `flutter3d_model_mcp` its own place in `flatDartPackages`) was resolved at the root — `flutter3d_shaders` losing a vestigial `flutter: sdk` dependency closed mcp-02n and this in the same stroke. `render_tool.dart` (new file): `renderTool`, an `OfferedTool<ModelSession, PictureAnswer>` built directly on `flutter3d_mcp_kit`'s own `PictureAnswer`/`pictureResultOf` (already used by `flutter3d_render_mcp`/`flutter3d_sim_mcp`) and `flutter3d_cpu`'s `CpuDevice`. `model_server.dart` wraps every other tool in `modelTools` (still plain `Answer`) into a `PictureAnswer` with a null `png` at the one seam the server owns, rather than touching the other hundred-odd tool bodies. An empty project refuses before `renderProject` is ever called; a `view` outside the schema's seven names is refused by the protocol itself, before this tool's own code runs at all | mcp | S | 1 | mcp-05n, doc-19 | `render` on the doc-21 project gives a non-empty image; on an empty project a refusal names the reason |
| mcp-07n ⚠ | A `renderSheet` contact sheet: four views in one picture with labels. An agent more often needs the whole silhouette than one view. Closed 2026-09-14 against this row's own literal acceptance, with one honest gap: no labels. `renderSheet` (`flutter3d_model_core`) calls `renderProject` once per quadrant (front, right, top, iso) and composites the four RGBA buffers into one PNG — checked pixel-for-pixel in `flutter3d_cpu/test/render_sheet_test.dart` against `render` itself for the same view, which is exactly this row's own acceptance text. Labels are real, undone work: nothing in this workspace draws text into a raster with no `dart:ui` behind it, and a bitmap font is its own small project rather than a corner of this one. `renderSheetTool` in `flutter3d_model_mcp` wraps it the same way `renderTool` wraps `renderProject` | mcp | S | 1 | mcp-06n | a 2×2 sheet; each quarter is the same frame `render` gives for its own view |
| mcp-08n ⚠ | Modes for the agent: `material / wireframe / normals / selection`. The agent sees flipped normals and n-gons with its own eyes, not only as a number in a report. Closed 2026-09-14 against this row's own acceptance, three modes of four: `render`'s and `renderSheet`'s own new `mode` argument (`render_tool.dart`) reads `material` (default), `normals` (`RenderShading.normals`), or `selection` (the session's own current `select`ion, tinted, rather than an id list a caller repeats). `wireframe` is not built — the same honest gap `RenderShading` itself already names, since `view-07`'s edge-drawing has not landed. `packages/flutter3d_cpu/test/render_modes_test.dart` builds an inverted shell with `EditMesh.cuboid()..flipNormals()` and checks `normals` differs from `material` on more than 20% of the frame's own pixels, not merely `> 0` the way `mcp-05n`'s own test settled for | mcp | S | 1 | mcp-06n, view-13 | `normals` on an inverted shell differs from `material` by more than 20% of pixels |
| mcp-09n | Composite recipes as session verbs: `cleanup()` (weld, drop degenerate faces, flip the right way out), `makeGameReady(profile)` (triangulation, normals, budget), `buildFrom(spec)` (a batch of primitives with a hierarchy in one call), `inspect()` (metrics, issues, and a picture in one answer). An agent assembles this badly and expensively from twenty-eight commands; a recipe is one history step, undone by a human with one ⌘Z | mcp | M | 1 | doc-20, doc-14, doc-07 | each recipe is one history step; `cleanup` on a GLB with duplicate vertices reduces their count and doesn't change the triangle count |
| mcp-10n | Authorship on history steps: `HistoryStep.author {person, agent}`; an agent's `undo` refuses if someone else's step is on top, and says whose | core | S | 1 | doc-08, doc-19 | the agent takes a step, the human takes a step, the agent's `undo` refuses with a clear message; a human's ⌘Z undoes both in order |
| mcp-11n | An agent call is one transaction: a batch of commands is undone with one ⌘Z, not nine. Most useful when the agent got it wrong | mcp | S | 1 | doc-08 | mcp-09n's nine-edit recipe undoes in one step |
| mcp-12n | The journal is written and replayable: everything the agent does lands in the `CommandJournal` with transaction markers and an author; `replay` gives a byte-exact `.f3dproj` | mcp | M | 1 | doc-16, mcp-11n | session → journal → `replay` in a clean process → `writeProject` matches byte for byte |
| mcp-13n | The GUI serves the same session over local HTTP: `--mcp-port`, 127.0.0.1 only, a token in the session file. Headless stays on stdio; `ModelSession` doesn't know about the transport | app + mcp | M | 1 | doc-19, ui-03 | the doc-21 scenario passes over both transports and gives the same file |
| mcp-14n | One document, two writers: the GUI redraws once the agent commits a step; a command doesn't land mid-drag — a modal transform holds a lock until `endTransaction` | app | M | 1 | mcp-13n, ui-03 | an agent command during a drag is queued and applied afterward; the document never diverges from the picture |
| mcp-15n | Import and export as session verbs: `import(path, options)`, `export(path, format)` gated by `ExportReadiness` — an error requires `force: true` and names what will be lost | mcp | S | 1 | doc-19, ui-17, fmt-06 | an export with an n-gon refuses with no `force`, naming the object; with `force` it writes and reports what was trimmed |
| mcp-16d *(added 2026-09-14 following owner decisions)* | **UI tools beside `--mcp-port`, GUI build only**: `ModelHttpServer.start(…, extraTools:)` (the server is already built from an explicit tool list), and the modeler registers `ui.setMode`, `ui.setSubmode`, `ui.setTool`, `ui.standardView`, `ui.frameSubject`, `ui.openDialog(export|lathe|autorig|preview)`, `ui.say`. Same localhost socket, same session token. What they are for: the tutorial's screenshots (`tut-00`) are driven, not clicked | app + mcp | S | 3 | mcp-13n | the tools answer in the GUI build; a headless `flutter3d_model_mcp` server does not list them; `ui.setMode('animation')` changes `ModelerReady.mode` |

### 2.14 Game graphics (`gfx-`)

Aspect added 2026-09-10. These are **engine changes**, not editor ones: each
goes into §6 and is checked by conformance, a golden frame, or a round trip,
like any engine change. They're here because the editor is what made these
gaps visible: it assembles an asset, and the game shows it.

**This track runs alongside the modeler's twenty tasks** and is numbered
with its own phases G1–G3, so as not to pretend to be part of the §5
milestones.

**Priority is set by observation, not taste.** The target budget is 60
frames on a MacBook at 1440p; a typical scene is one close-up hero, one or
two characters on screen; the engine needs to carry both a stylized look and
a physical one. Four things are named as seen with one's own eyes: light
popping, jagged edges, distant objects with no shadows, aliasing on the
floor and on far textures. The list starts with them.

**Order inside G2 is set by one finding.** Filling the surface buffer turns
off MSAA for the whole scene, so SSAO and reflections today cost the game
its anti-aliasing — not a missing feature, a mutual exclusion between two
existing ones. FXAA removes it and unlocks both "jagged edges" and "contact
shadows" at once, so it comes first.

**What isn't in this track, and why.** A sort key, occlusion culling,
streaming, and geometry compression are about scene scale, and "one close-up
hero" on desktop doesn't hit that wall; the web matters to the modeler, not
to games. Vertex-shader skinning — with one or two characters, the CPU keeps
up. Decals, water, terrain, and atmospheric scattering are genre-specific,
and with no game that needs them there's nothing to optimize. Inverse
kinematics moved into the `anim-` aspect: it's needed for posing during
auto-rigging, and in a game the pose comes from a clip. Everything under the
ROADMAP's "Not doing" — TAA, motion blur, an ECS renderer, terrain clipmaps,
node-graph materials, OIT beyond alpha hashing, quality presets — isn't
proposed again.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| gfx-01n | **A frame profiler**: per-pass counters (time, draw calls, triangles, pipeline switches) in `FrameResult`, a panel over the viewport, a draw-call baseline in CI. First item by owner decision: with no numbers, any next item is an impression, not a result | engine + qa | M | G1 | — | a regression of +10 draw calls breaks the build; the panel shows four passes separately |
| gfx-02n | **An anisotropy measurement.** `RenderSettings.anisotropy` defaults to 1, and no demo raises it; the level-editor bridge gives bricks `min(8, maxAnisotropy)`, an imported model gets 1. Capture one frame at 1 and at 8 on a scene with a floor receding into the distance, and decide whether to change the default | engine | S | G1 | gfx-01n | two frames and the number of differing pixels; the decision is recorded in the plan |
| gfx-03n | **A distant-shadow measurement.** Three options — raise `viewDistance` with a recomputed split, a fourth cascade, a separate, rarely-updated far map — on one scene, with a frame cost from gfx-01n | engine | S | G1 | gfx-01n | three frames and three costs; the chosen option is named in gfx-06n |
| gfx-04n | **FXAA in the pass graph.** Removes the mutual exclusion: today a game chooses between shadows in the corners and smooth edges, because the surface buffer turns off MSAA for the whole scene | engine + shaders | M | G2 | gfx-01n | SSAO is on and edges are smooth; frame `ao-with-aa` across three sets; a pass cost from the profiler |
| gfx-05n ⚙⚠ | **Light by importance, not by count.** Today eight sources for the whole scene in a `vec4[8]`: a ninth lamp displaces the first, visible as a pop when the camera moves. CPU-side selection by contribution to the object, with a soft fade at the list's edge so there's no pop at all; the shader doesn't change — who lands in those same eight slots does | engine | L | G2 | gfx-01n | a 40-source scene draws correctly; camera movement gives no jump — two neighboring frames differ by less than 2%; frame `many-lights` |
| gfx-06n | **Shadows past 60 meters** — with the option chosen in gfx-03n | engine | M | G2 | gfx-03n | an object at 200 m casts a shadow; the frame cost stays within what the measurement named |
| gfx-07n | **Anisotropy on by default** — if gfx-02n showed that's the cause | engine | S | G2 | gfx-02n | moiré on the receding floor is gone; golden frames are recaptured in one commit |
| gfx-08n | **SSAO brought to on-by-default**: it exists today, off, and it was exactly gfx-04n that blocked turning it on | engine | S | G3 | gfx-04n | frame `ambient-occlusion-corner` with anti-aliasing on; the pass cost is named |
| gfx-09n | **Depth-based contact shadows**: a short screen-space ray where the shadow map is too coarse — under a foot, in folds, under a chin. A different technique from SSAO, needed where the hero is close up | engine + shaders | M | G3 | gfx-08n | frame `contact-shadow`; the foot stands on the ground, not floating |
| gfx-10n | **An additive pose layer.** Promised in the ROADMAP; needs a reference pose with nowhere to live in glTF — so its own field on `AnimationClip` | engine | M | G3 | — | breathing over walking; zero changes to existing clips; `animation_mask_test` green |
| gfx-11n | **A ray hits the pose, not the base shape.** Today a raycast hits the unanimated mesh: a shot at a running character misses, and `skinReach` only widens the bounds | engine | M | G3 | mesh-20 | a hit on a raised arm registers; a miss past it doesn't; the query cost is measured |
| gfx-12n | **Light channels**: a mask on the source and on the object — a hero's flashlight doesn't light the sky, an interior lamp doesn't leak outside | engine | S | G3 | gfx-05n | an object outside the channel gets no contribution; zero changes to frames with no channels |
| gfx-13n | **Physical light units**: lumens and candela, converted into today's dimensionless intensity | engine | M | G3 | gfx-05n | an 800-lumen lamp gives the same illuminance as today's tuned number |
| gfx-14n | **`KHR_lights_punctual`** in the loader and writer: light from glTF is entirely lost today | formats | S | G3 | fmt-06 | round trip: light from Blender opens and exports back |
| gfx-15n | **Soft disc shadows with five taps**: promised in the ROADMAP, today it's a 3×3 PCF with an edge that's always equally hard | shaders + engine | S | G3 | — | frame `soft-shadow`; the penumbra is wider for a farther occluder |
| gfx-16n | **Alpha hashing**: foliage and nets today are either hard-cut by a threshold or need sorting | shaders + engine | S | G3 | — | frame `foliage`; zero changes in opaque scenes |
| gfx-17n | **LUT grading and a filmic curve**: `LookSettings` exists, no table does | engine | S | G3 | — | a neutral LUT doesn't change the frame by even a pixel |

### 2.15 The tutorial (`tut-`)

Aspect added 2026-09-14 by owner decision. `rel-09` promised one tutorial —
"an asset from import to engine in 15 minutes" — on the documentation site.
This is the bigger thing it grows into, and it moves house: the modeler's
tutorial is published on **models.pleion.dev** (`cloud/server`), where the
reader has an account, a cabinet to put the result into, and the modeler's
own web build at `/app/` to open it in. The documentation site keeps a card
pointing there (`rel-08` retargeted, not duplicated).

**Six cases, each a real job, not a feature tour.** A prop from a scan
(`teapot.stl` in millimetres → clean → material → GLB → cabinet); a vase from
a profile (lathe, mesh edits, the modal transform and snapping, modifiers, a
texture); a lit corner (two assets in one scene, lights, shadows, environment,
post, one GLB with two nodes); a character from a bare mesh
(`RobotExpressive.glb` without its skin → auto-rig → weights → pose and keys →
morphs → the game preview → GLB → a game template); borrowing a walk
(retargeting a clip); an agent beside you (`--mcp-port`, the first case done
by an agent, the journal, undoing only the agent's steps). Cases 1–3 are
possible after `ui-37d`/`mat-33d`/`mat-34d`; 4–6 need the animation screens.
The first draft of 1–3 is written **as soon as those land**, not at the end —
writing a case is how the gaps show up.

**Screenshots are driven, not clicked.** The app runs with `--mcp-port` and
the `mcp-16d` UI tools; `tool/tutorial/shoot.dart` reads the session file,
replays a case step by step, and captures the window with `screencapture -l`
(the window id from a ten-line `window_id.swift` over
`CGWindowListCopyWindowInfo` — no third-party tool). `MainFlutterWindow.swift`
learns a `--window=1440x900` argument so every picture is the same size.
Pictures of the result alone (no chrome) come from the headless `render`/
`renderSheet` tools and are reproducible in CI. Regenerating every picture is
one command.

**The tutorial is a test** (the `rel-09` shape): each case is a
`test/fixtures/tutorial/<case>.jsonl` journal in `flutter3d_model_mcp`, replayed
in CI against a reference `.f3dproj`, a GLB (`compareModelDocuments`) and a
frame. A step that cannot be written as document commands is a gap by
definition.

**The gap journal.** `doc/modeler-tutorial-gaps.md`: case · step · what was
expected · what is there · kind (feature / consistency / UX) · the plan row it
became. Known candidates before a single case is written: a dropped file is
decoded and then thrown away (`main.dart`'s `_handleDroppedFile`); `.gltf`
beside its `.bin` (`ui-36n`); the cabinet has no preview picture; a model
opened from the cabinet cannot be saved back; the status line has no vertex
or material count.

*(Checked during T6's close-out, 2026-09-15: `ui-36n` is done — a `.gltf`
beside its `.bin` opens on the web and on macOS — and the status line has
carried vertex/material counts since `mat-33d`; neither needed a fresh row.
The other three were still real and became `tut-17`/`tut-19`/`tut-20` below,
alongside `tut-18`, a second latent quirk `ui-37d`'s own text had already
promised "its own row" for.)*

Language: English, per the 2026-09-02 decision on the community; a Russian
version is its own later row.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| tut-00 | The modeler tutorial on models.pleion.dev: `/learn/modeler/` and `/learn/modeler/<slug>` (Markdown under `cloud/server/content/learn/modeler/`, rendered through `package:markdown` into a `LearnPage` in the site's own `Page` layout, a "Learn" link in the nav); pictures under `web/assets/learn/modeler/<case>/`; the six cases above; times measured with a date and the machine on the page; the driven screenshot pipeline; the `.jsonl` scenarios in CI; the gap journal | cloud + app + mcp + doc | L | 3 | ui-37d, mat-33d, mat-34d, mcp-16d, rel-09 | six pages live with their pictures and working `/app/` links; six scenarios green in CI; every case timed; `doc/modeler-tutorial-gaps.md` is empty or every line names a `tut-NN` row with a decision |
| tut-01 *(found writing case 1, 2026-09-15)* | Case 1 found two gaps: (a) `ModelSession.import`/the `import` MCP tool took only a path, with no `ImportOptions` — so an agent could not choose a unit or an up axis the way the app's own import screen lets a person; case 1's own fixture worked around this by building its starting project directly from `fromModelDocument`/`importMeshData` rather than through `session.import`. (b) `readiness.dart`'s `MeshChecks` only run on `EditedGeometry`; a freshly imported, unwelded `ImportedGeometry` object reads "ready to export" even when its mesh has real problems `MeshChecks` would catch once welded. **(a) closed 2026-09-15**: `ModelSession.import` now takes an optional `ImportOptions` plus `weld`/`fixNormals`/`triangulate` flags, all defaulting to exactly today's own no-options behaviour (unscaled, up axis `y`, every object left `ImportedGeometry` byte-for-byte); the `import` MCP tool's schema gained matching `unit`/`upAxis`/`weld`/`fixNormals`/`triangulate` fields, so an agent gets the identical choice `import_plan.dart`'s own import screen already offers a person, restricted to only the objects a given import itself just added (the same `only`-set discipline `tut-08`'s own `_applyImportCleanup` already uses). Threading real options through surfaced a genuine, separate bug in `importInto` (`flutter3d_model_core`): its own object-rebuild loop reconstructed each re-numbered `ModelObject` from scratch, silently resetting `version` to the constructor's default of `1` — invisible for as long as every import ran with the default, unscaled `ImportOptions()` (nothing ever bumped a root's version, so resetting it to `1` was a no-op), and real the moment one does not (`fromModelDocument`'s own scale/up-axis adjustment bumps a root's version via `copyWith` before `importInto` ever sees it, and that bump was being thrown away). Fixed by carrying `object.version` across in the same loop. Case 1's own fixture (`case1_scenario.dart`) now builds its starting project through `session.import(stlPath, options: ImportOptions(scale: 0.001), weld: true)` instead of calling `fromModelDocument`/`importMeshData` directly, now that the tool supports it; regenerating (`tool/make_case1_fixtures.dart`) produced byte-identical `case1.f3dproj`/`case1.glb`/`case1.jsonl` to what was already committed, confirming the two paths agree. New coverage: `import_test.dart`'s own two new cases — `unit: mm` reaches the exact project `fromModelDocument`/`ImportOptions(scale: 0.001)` already reaches directly, and a call with no options at all still behaves exactly as it did before. (b) is unchanged and still open — **откладываем**, left for its own pass; a freshly imported, unwelded object still reads "ready to export" regardless of real mesh problems `MeshChecks` would catch once welded | core + mcp | S | 3 | doc-11a-n, mcp-13n | (a) done — an agent can choose a unit, an up axis and weld/fixNormals/triangulate on import, the identical choice the app's own screen offers a person; a no-options call is unchanged. (b) not scheduled this pass — `readiness.dart`'s `MeshChecks` still skip `ImportedGeometry` |
| tut-02 *(found writing case 1, 2026-09-15)* | `render_project.dart`'s own `_frame` floors its fitted bounding radius at `0.05` (5 cm); a small scanned prop below that size — case 1's own teapot, correctly imported at millimetre scale, is about 8 mm across — renders as a handful of pixels in the middle of the frame instead of filling it, unlike `OrbitController.frame` (the interactive viewport's own fit, floored at `1e-4`), which a person driving the real GUI would get. Case 1's own two renders work around this with a render-only 20× scale-up (`tool/make_case1_fixtures.dart`), never applied to the exported fixtures. **Decision (this pass, pending owner confirmation): откладываем** — worth a real fix (lower the floor, or make it a fraction of the fitted radius rather than an absolute), but the workaround is honest and documented, and a shared render function used by both the render/renderSheet MCP tools is not a change to make inside a tutorial-content pass | core | S | 3 | — | not scheduled this pass — a fix here also helps `render`/`renderSheet` on any small real-world prop, not only this tutorial |
| tut-03 *(found writing case 2, 2026-09-15)* | `ModelSession` had no `amend` method — the operation card's own slider called `_history.amend(to)` directly on the app's own `ModelHistory` (`apps/flutter3d_modeler/lib/src/screen/interactions.dart`), bypassing `ModelSession`/`CommandJournal` entirely. Case 2's own tests confirmed `amend` itself worked (it re-runs a mesh edit against the document before it, not on top of it), but an agent over MCP had no way to reach it, and a session's own recovery journal never learned the adjustment happened — the file still named the *original* argument on that step after an amend. **Closed 2026-09-15**: `ModelSession.amend(to)` (`packages/flutter3d_model_mcp/lib/src/model_session.dart`) calls through to the same `ModelHistory.amend`, then records `to` itself to `_journal` in place of the step it replaces via a new `CommandJournal.amend` — forgetting the line(s) the original step wrote (the whole `begin`/`…`/`end` bracket when the step being adjusted was a `transaction`, not only its own last line) and writing `to` in their place, so a cold `journal` replay lands on the adjusted state directly rather than the original followed by an adjustment nothing on disk remembers. Offered over MCP as the `amend` tool (`model_tools.dart`), which takes a whole command object the same shape `run`/the journal already use. New coverage: `tutorial_scenarios_test.dart`'s own case-2 group now asserts the journal names the *adjusted* extrude distance rather than the original, plus a second, selection-independent test (`addPrimitive`, which needs no `session.select` the way `Extrude` does) proving a cold replay of a journal ending on an amend reaches the adjusted state byte-for-byte — isolated on purpose from `tut-05`'s own separate, still-open mesh-selection gap | mcp + core | S | 3 | mcp-10n, mcp-12n | closed — an agent over MCP can amend the top of the undo stack the same way the operation card's own slider does, and a session's own recovery journal now names the adjusted step, replaying cold to the adjusted state rather than the original one |
| tut-04 *(found writing case 2, 2026-09-15)* | The plan's own case 2 asks for "extrude/loop cut/bevel"; `flutter3d_mesh` has real `bevelEdges`/`bevelVertices` functions, but no `ModelCommand` wraps either one — `apps/flutter3d_modeler/lib/src/ui/tools.dart`'s own comment already says "Inset, bevel and merge are" not tools. Case 2 exercises extrude and loop cut only, honestly, rather than inventing a "bevel" command that does not exist at this layer. **Closed 2026-09-15**: `BevelEdges` (`packages/flutter3d_model_core/lib/src/mesh_commands.dart`) wraps both functions behind one command, reading the selection's own level to choose between them — a vertex selection walks `bevelVertices`' own per-vertex edge fan rather than the edges `Selection.convertedTo` would give, which keeps only an edge with both ends selected. Registered in `command.dart`'s reader table, offered over MCP as the `bevelEdges` tool (`model_tools.dart`), and given a real rail button (`mesh.bevel`, key `B`, `tools.dart`/`tool_commands.dart`) — the tools panel's own comment no longer names bevel among what this repository does not have. New coverage: `commands_test.dart`'s own `BevelEdges` tests — matches `bevelEdges`/`bevelVertices` called directly on an identical cube byte-for-byte, undo restores the pre-bevel mesh byte-exact, a single-vertex selection dispatches to `bevelVertices` rather than converting to the empty edge set `bevelEdges` alone would see, and a partial selection is refused the same sentence the functions themselves refuse it with — plus `tool_commands_test.dart`'s own `mesh.bevel` pair and the reader/MCP-tool round trip every other command already gets. Case 2's own scenario and fixtures are untouched on purpose: adding a bevel step there is a separate, tutorial-content change, not folded into this one — `tut-04`'s own row is what tracks that it is now possible | core | S | 3 | mesh-33 | closed — `BevelEdges` wraps `bevelEdges`/`bevelVertices` behind one undoable, journaled command, reachable over MCP and from the modeler's own mesh-mode rail |
| tut-05 *(found writing case 2, 2026-09-15)* | `Extrude`/`LoopCut`/`TransformElements` all act on "whatever is currently selected", and selecting mesh elements is `ModelSession.select`, not a `ModelCommand` — its own doc comment already names this cost for object-level picking. Case 2 is the first case whose edits depend on it at *mesh*-element level too: its own `.jsonl`, replayed through `CommandJournal.replay` from a cold `ModelProject`, refuses at the first `extrude` with "no faces are selected to extrude" (asserted directly in `tutorial_scenarios_test.dart`). A live session — a person clicking through the app, or an agent calling `select` then `run` over MCP — reaches the case's own fixture without trouble; only a *crash recovery* replaying the file alone cannot. **Resolved 2026-09-15, together with `tut-15`.** `ModelSession.select` now builds a new, non-mutating `ModelCommand` — `SelectElements` (`packages/flutter3d_model_core/lib/src/selection_commands.dart`), covering both the object-list and the one-object/level/elements shape `select` always took — and runs it through `ModelHistory.run` instead of assigning `ModelHistory.selection` directly; it is registered in `modelCommandNames`/`modelCommandFromJson` the same as every other command. Paired with `tut-15`'s own fix to `ModelHistory` itself (below), a pick made through `select` now lands on whichever recovery journal is attached the same as any edit, so a cold replay of case 2's own `case2.jsonl` no longer refuses at the first extrude for want of a selection nothing was recorded — it rebuilds the identical document a live session reaches. Checked directly: this is the same code path cases 3 and 4's own journals hit too (object-level `MoveBy`/`RotateBy` and mesh-vertex level respectively), and both close the same way without a row of their own, since neither test file ever named a separate root cause — both already pointed at this one. New coverage: `history_journal_test.dart`'s own `SelectElements` group (object mode and mesh mode, both replaying cold, plus a refusal for an unrecognised level); `commands_test.dart`'s own journal-sample round trip gains an entry; `tutorial_scenarios_test.dart`'s case-2, case-3 and case-4 cold-replay tests now assert success and a document byte-identical to each case's own `.f3dproj`, and their `.jsonl` fixtures are regenerated (via each case's own `tool/make_caseN_fixtures.dart`) to carry the `selectElements` lines a live session always made | mcp + core | M | 3 | mcp-12n | closed — `ModelSession.select`'s own pick is a real, replayable `ModelCommand` now; a cold `CommandJournal` replay of any case whose edits depend on a specific object or mesh-element pick reaches the identical document a live session does |
| tut-06 *(found writing case 2, 2026-09-15)* | Adding a modifier and expecting to see its effect somewhere — the viewport, a headless render, or an export. Nothing read `ModelObject.modifiers` except the properties panel's own list and `ApplyModifier`, which bakes the stack into the base mesh and removes it: `SceneSync._dataOf` (the live viewport) read `object.geometry` directly, and neither `render_project.dart` nor `render_sheet.dart` mentioned `modifiers` at all. A mirror or an array modifier was invisible everywhere until "Apply" was pressed, which also threw the non-destructive stack away — the opposite of what a modifier is for. Case 2's own page worked around this only for its own picture, evaluating the stack by hand (`tool/make_case2_fixtures.dart`'s own `_withModifiersBaked`) rather than through anything a person driving the real app would see. **Closed 2026-09-15**: `SceneSync.apply` now routes an object's mesh upload through `ModifierEvaluationCache` (`mesh-40`/`mat-18`, built earlier and never called from the app) whenever it has at least one enabled modifier slot, and tracks `ModelObject.modifiers` by identity alongside `geometry` so a toggled or edited stack re-uploads even though the base mesh's own identity never moved — a modifier command touches only `.modifiers`, never `.geometry`. `render_project.dart`'s own `renderProject` reads the same cache (a fresh instance per call) for its own mesh-gathering pass; `render_sheet.dart` inherits the fix for free, since `renderSheet` only ever calls `renderProject` per quadrant. `ApplyModifier` itself is untouched — baking still folds the stack into the base mesh and empties it, now simply baking what was already visible rather than what nobody could see. Case 2's own fixture tool no longer hand-evaluates anything: `_withModifiersBaked` is gone, replaced by `_withModifiersDisabled` (a real, live toggle — every slot's own `enabled` flipped off, the same field `ToggleModifier` flips) for the "before" picture, and the "after" picture is now the saved project rendered exactly as `renderProject` draws it — regenerating `tool/make_case2_fixtures.dart` produced byte-identical PNGs to what was already committed, confirming the live cache folds a stack the same way the old hand-rolled evaluation did. New coverage: `scene_sync_test.dart`'s own `tut-06` group (a mirror doubles the uploaded vertex count with no `Apply`, an array multiplies it by its own count, toggling a disabled modifier back on reuploads with `identical(geometry)` still true, and `ApplyModifier` still bakes to the same vertex count the live preview already showed) and `flutter3d_cpu`'s own `render_project_test.dart` `tut-06` group (mirror and array each visibly change a headless render with no `Apply`, and `Apply` changes zero pixels from what was already drawn) | app + core | M | 3 | mesh-40 | closed — a mirror or an array modifier is visible in the live viewport and in both headless render tools the moment it is added, with no `Apply` needed |
| tut-07 *(found writing case 3, 2026-09-15)* | Case 3 ("A lit corner") sets a real point light, a shadow request, a studio environment and bloom through `AddLight`/`SetLightField`/`SetLightTransform`/`SetEnvironment`/`SetSceneLightingField`, then asks for a headless "expected result" picture the way every earlier case gets one. `render_project.dart`'s own `renderProject` builds its `Scene` from two hardcoded directional lights and never reads `ModelProject.lighting`, and the live viewport's own `ModelerStage.fromProject` never called `LightingSync` either (`mat-23`'s still-unfinished wiring; checked directly, `grep -rn "LightingSync(" apps/flutter3d_modeler/lib/` found exactly one call site, a throwaway `lightOverflowOf`, never drawn). **Closed 2026-09-15**: `LightingSync` moved from `apps/flutter3d_modeler` into `flutter3d_model_core` (`lighting_sync.dart`) — its own `Scene`/`LightNode`/`RenderSettings` types are `flutter3d_core`'s, re-exported unchanged by `flutter3d`, and this package already depended on `flutter3d_core` for `render_project.dart` itself, so nothing about the move needed the Flutter SDK. One class now serves all three call sites: `ModelerStage.fromProject` syncs a project's own lights onto the scene *additively*, over the fixed key/fill pair (`LightingSync.sync`'s own doc comment explains why the pair stays — a project with no lights of its own still renders exactly as it always did), `modeler_cubit.dart`'s `_synced` re-syncs on every command, and `ready_parts.dart`'s own `viewportRenderSettings` folds exposure/shadows/bloom in through `LightingSync.apply`; `render_project.dart` and `flutter3d_render_job`'s `scene_from_project.dart` do the same, with light gizmos deliberately left off in a headless picture (an editing overlay, not part of "what the project draws"). `ambientIntensity` and `environment` stay unwired on purpose — their defaults do not match the engine's own (0.3 vs 0.06 ambient), so folding them in would rebrighten every existing golden for a field no case or test asks to see; a real fix is future work, not this row's. Verified empirically, not just reasoned about: the full `apps/flutter3d_modeler` frame-test suite (`autorig_frame_test.dart`, `retarget_frame_test.dart`, `game_preview_frame_test.dart`, `frame_test.dart`'s own `skeleton-overlay` golden, `flutter3d_render_job`'s own byte-for-byte snapshot goldens) all still match their committed reference images unchanged, because every one of them renders a project with an empty `SceneLighting` — case 3's own fixture is the first to actually exercise the wiring. New coverage: `flutter3d_model_core/test/lighting_sync_test.dart` (moved, plus a new case: `sync` is additive over a scene's own pre-existing lights), `flutter3d_cpu/test/render_project_test.dart`'s own `tut-07` group (a point light measurably brightens a headless render; `exposure` measurably dims one), `flutter3d_render_job/test/scene_from_project_test.dart` (a project's own light joins the fixed pair, `scene.lights` reads 3 not 2) | core + app + mcp | M | 3 | mat-23, mesh-40 | closed — a project's own `AddLight`/shadow request/bloom toggle now reach the live viewport, the game-preview route and both headless render tools alike, additively over the fixed key/fill baseline; `ambientIntensity`/`environment` remain a real, separate gap |
| tut-08 *(found writing case 3, 2026-09-15)* | Case 3 asks for a second file merged into a project already open, the way `mat-24`'s own extended scope (2026-09-09 decision, "Import into scene" via `ImportInto`) names for a person clicking through the real app. Checked directly: `grep -rn "\.import(\|ImportInto" apps/flutter3d_modeler/lib/` finds no call site at all — the toolbar's only file action, **Open** (`_openBytesWithImportScreen`'s own `openDocument`), always replaces the whole document, the identical path case 1's own import already uses. `mat-24` is recorded closed via `mat-34d` (2026-09-14), but `mat-34d`'s own text only wires the four Scene-mode panels (`SceneSourcePanel`/`SceneShadowsPanel`/`SceneEnvironmentPanel`/`ScenePostPanel`); it never mentions an import action, and none exists — `mat-24`'s own "Import into scene" half of its extended scope shipped at the command layer only (`import_into_test.dart`, `scene_multi_asset_export_test.dart`), reachable by an agent through `ModelSession.import` today, not by a person in the GUI. Case 3's own scenario drives `importInto` directly against the session for exactly this reason. **Closed 2026-09-15**: `TopBarActions` (`apps/flutter3d_modeler/lib/src/ui/top_bar_actions.dart`) gained an `onImport` sibling to `onOpen`, wired in `ready_parts.dart` to a new `_importFile` extension method (`screen/files.dart`) that reuses `_openFile`'s own picker and `_openBytesWithImportScreen`'s own import screen (`showImportScreen`, the same unit/axis/cleanup choices a second file gets asked too) but runs `importInto` against the document already open instead of `openDocument`'s wholesale replacement, landing the merged project through `ReplaceDocument` — the same undo-recorded, not-journaled command `ModelSession.import` itself already runs, for the identical reason (`command.dart`'s own doc comment on `ReplaceDocument`). The cleanup checkboxes are scoped to the ids `importInto` just appended (`_applyImportCleanup`'s own new `only` parameter), so choosing weld/normals/triangulate for a second file never reaches back and rebuilds an object that was already open and left untouched on purpose. New coverage: `top_bar_actions_test.dart`'s own "tapping Import calls onImport", and a new `file_import_test.dart` — a widget test driving `ModelerScreen` end to end through a faked `FileSelectorPlatform` (the same pattern `flutter3d_editor`'s own `timeline_attach_screen_test.dart` already uses), proving Import merges a second `.f3d` file's objects in beside the startup cube while Open still replaces the whole document, as before. Case 3's own tutorial page (`03-a-lit-corner.md`) now says the button exists; its own fixture script stays command-layer-driven on purpose, since that is what keeps `case3.f3dproj`/`case3.glb` byte-for-byte reproducible without a live renderer, and the reason it originally bypassed `ModelSession.import` (`ReplaceDocument` not being journalable) was never about the missing button in the first place | app | M | 3 | mat-24, mat-34d, doc-11a-n | closed — a person can now merge a second file into the document already open through the toolbar's own Import button, the same `ImportInto` seam `ModelSession.import` already used over MCP; Open still fully replaces the document exactly as before |
| tut-09 *(found writing case 4, 2026-09-15)* | Case 4 needs to bend a joint the way the weights sub-mode's own bend slider does, from an agent over MCP (and from this case's own headless test). `ui/bend_slider_bar.dart`'s own doc comment says outright that a bend turns the joint's live `SceneNode` directly and "never touches `ModelHistory`" — by design, so sixty frames of a drag cost nothing on the undo stack — which means there is no `ModelCommand` an agent or a headless case could call to reach that same live-preview effect. The document-level equivalent case 4's own scenario actually uses is `select` + `RotateBy` on the joint's own persisted `ModelObject.transform`, then `PoseJoint` to key it — reaching the identical document state a person's slider drag would once *keyed*, just through a different door than the live preview. **Decision (this pass, pending owner confirmation): откладываем** — this is a real, checked distinction, but not a defect: the bend slider's own live-only design is deliberate (its doc comment explains why), and the document-level path already reaches every state a keyed pose needs. Worth a line for whoever writes an agent-facing "bend" tool later, not a fix this pass owes | app + mcp | S | 3 | anim-12, mcp-16d | not scheduled this pass — an agent already reaches every *keyed* pose state through `select`/`RotateBy`/`PoseJoint`; only the live, unkeyed preview has no agent-facing equivalent |
| tut-10 *(found writing case 4, 2026-09-15)* | Case 4 rigs, weight-paints, poses and morphs a character, then asks for a headless "expected result" picture the way every earlier case gets one. `render_project.dart` never mentioned "skin" or "skeleton" anywhere in it — every mesh drew at its raw bind-pose position regardless of `ModelObject.skeletonIndex` or any joint's own transform, and it never mentioned `shapeSet` either, so a shape key's own weight never reached the picture. **Closed 2026-09-15**: `_meshDataFor` now folds in a shape-key blend (`_withShapeBlend`, `ShapeKey.blend`'s own delta formula run through `shapeKeyMorphTargets` so the deltas line up with the mesh's own GPU rows) and a skin pose (`_withSkin`), both read straight off `session.project` — the object's *current* `shapeSet.weights` and every joint's *current* `ModelObject.transform` via `worldTransformOf`, not any animation curve, since nothing in this build poses a mesh through time for a still picture. `_withSkin` is a CPU bake, not the engine's own `MeshNode.skeleton`/GPU pipeline `SceneSync` uses live: checked directly against the real `RobotExpressive.glb` fixture, the GPU pipeline's own `jointMatrix = inverse(meshWorld) * jointWorld * inverseBind` formula assumes `inverseBind` undoes a *local*-space bind (glTF's convention), but `buildSkeleton`'s own auto-rig measures both joint placement and mesh vertices in *world* space, so its own inverse-bind matrices undo a world-space bind instead — fed through the GPU formula, the torso collapsed to a hundredth of its own size and vanished. `_withSkin` composes an extra `* meshWorld` onto each joint's own matrix (undone again by the leading `inverse(meshWorld)`, the same cancellation the GPU formula already relies on) so the two conventions agree, confirmed against the real fixture's own torso rendering at its correct size and place again. This is a real, separate latent bug in the auto-rig's own bind-matrix convention for a mesh whose own object transform is not the identity — not introduced by this fix, only the first thing to actually render its result and so the first to notice it; fixing the bind convention itself (or the live GPU pipeline to match it) is its own row, not this one's. New coverage: `flutter3d_cpu/test/render_project_test.dart`'s own `tut-10` group (a wholly-skinned quad turned edge-on by its own joint covers far fewer lit pixels than the same quad at bind pose; a shape key's own weight visibly blends in) | core | M | 3 | tut-07 | closed — `renderProject` poses a skinned mesh through its skeleton's current joint transforms and blends a shape set's own current weights, both confirmed against case 4's own real auto-rigged, posed, morphed character; case 4's own reference render now shows the bent elbow and the puffed chest |
| tut-11 *(found writing case 4, 2026-09-15)* | Case 4's own weight-paint step wants to show the weight-gradient shading S4 built (`weight_gradient.dart`'s five colour stops over an unlit material) in a headless picture, the way `render`'s own `mode` argument already offers `material`/`normals`/`selection`. `RenderShading` (`render_project.dart`) had exactly two members, `material` and `normals` — confirmed by reading the class directly, and `render_tool.dart`'s own `renderModes` list agreed. **Closed 2026-09-15**: a third member, `RenderShading.weights`, plus a `RenderRequest.weightsJoint` (an object id, the same vocabulary `PaintWeights`/`SetRig` already name a joint with) — `flutter3d_model_core/lib/src/weight_gradient_colors.dart` restates `weight_gradient.dart`'s own five-stop sRGB gradient (a dozen lines, the same "third copy, deliberate" trade this package already accepts for a mesh-data switch it cannot share with the application), and `_withWeightGradient` bakes it into the vertex `color` channel of whichever object is bound to the requested joint's own skeleton, using `weightsOf` (already a `flutter3d_mesh` dependency, no app-layer path needed at all). Every other object — unskinned, or bound to a different skeleton — falls back to `material` rather than drawing blank. Tonemap and exposure are pinned off for this mode (`weightGradientSettings`'s own reasoning: a vertex colour named by hex is not scene-referred light). `render`/`renderSheet` (`render_tool.dart`) gained `'weights'` in `renderModes` and a `joint` argument; `make_case4_fixtures.dart`'s own `02-weight-paint-gradient.png` is now a real render (the left elbow's own weight, over the torso) rather than a placeholder. New coverage: `flutter3d_cpu/test/render_project_test.dart`'s own `tut-11` group — a pixel-level check that both the gradient's own no-influence (`#2A3A7A`) and full-influence (`#FF3B5C`) stops actually appear in the picture, and that an object not bound to the requested joint still draws instead of going blank | core + mcp | S | 3 | anim-11 | closed — `render`/`renderSheet` can draw the weight-paint gradient for a named joint, confirmed pixel-for-pixel against the gradient's own two extreme stops |
| tut-12 *(found writing case 5, 2026-09-15)* | Case 5 retargets `RiggedFigure.glb`'s own walk cycle onto case 4's character with `lockFeet: true` (`RetargetClipJobRequest`'s own default, screen 14's own "Lock feet" toggle). This exact pair of rigs used to throw a `RangeError` instead of correcting anything — confirmed directly: `tutorial_scenarios_test.dart`'s own case-5 group called the same request with `lockFeet: true` and asserted the crash. Root cause, read directly out of `flutter3d_rig`'s own `retarget.dart`: `RiggedFigure.glb`'s own clip animates every joint's translation, rotation *and* scale, not only the root's (the doc comment `retargetClip` inherited assumed only a root/hips track ever carries translation); `_lockFeet`'s own `tracksByNodeId` was a plain `Map<int, RigTrack>`, one entry per target joint, so building it for a joint carrying three retargeted tracks kept only the last one built — the scale track — silently dropping the rotation track the foot-lock math actually reads; the per-key indexing that follows then treated that three-floats-per-key buffer as four-floats-per-key quaternions and ran past its own end. **Closed 2026-09-15**: `_lockFeet` now keys its own lookup by node *and* path (`Map<int, Map<AnimationPath, RigTrack>>`, and a `(int, AnimationPath)` record key over `replaced`/`newTrackKeys`), so a joint's translation, rotation and scale tracks all survive retargeting rather than collapsing onto whichever was built last — checked directly against every other caller of the old `tracksByNodeId`, and there was exactly one, this function's own. Case 5's own scenario now retargets with `lockFeet` at its own default (`true`) instead of the `lockFeet: false` workaround; its own fixtures (`case5.f3dproj`/`.glb`/`.jsonl`) are regenerated and its own tutorial page no longer describes the crash as a known limitation. New coverage: `flutter3d_model_core/test/retarget_test.dart`'s own tut-12 case builds a hip joint carrying translation, rotation *and* scale at once and asserts both that retargeting no longer throws and that the foot still lands within 1cm of the ground — the real correction, not only the absence of a crash; `tutorial_scenarios_test.dart`'s own case-5 group asserts the same real fixture's every mapped joint keeps all three of its own tracks after retargeting | core | S | 3 | anim-17 | closed — `retargetTracks`/`retargetClip` with `lockFeet: true` no longer throws for a joint carrying translation, rotation and scale at once, and the foot lock still corrects the ankle to within 1cm of `groundY` |
| tut-13 *(found writing case 5, 2026-09-15)* | Case 5's own screen 14 "Auto-map" step (`looseAutoMap`) is asked to map `RiggedFigure.glb`'s own nineteen joints onto `RigTemplate.humanoid`'s seventeen. It mapped nothing at all — confirmed directly by calling `looseAutoMap` on the file's own joint names and reading back an empty `BoneMap`. `looseAutoMap`'s own two rig-family conventions (Mixamo's `mixamorig:LeftUpLeg`, 3ds Max Biped's `Bip01_L_Thigh`) both put the side marker at the very start of a bone's own name once its prefix is stripped; `RiggedFigure.glb`'s own names (`leg_joint_R_1`, `arm_joint_L_2`) put the side in the *middle*, a shape `_looseSide` was never written to read. **Widened 2026-09-15, `RiggedFigure.glb` itself still unmapped**: `_looseSide` now also reads a side marker as a delimited token anywhere in the name — split on `_`/`.`/`-`/space and camelCase boundaries, each token checked against the same `l`/`r`/`left`/`right` vocabulary the start-anchored shapes already used, not only at position zero — while the two prior conventions are unchanged (`loose_auto_map_test.dart`'s own Mixamo/Biped groups still pass byte-for-byte). Checked directly: `looseAutoMap` now maps rigs it used to refuse outright whose side marker sits mid-word beside a dictionary-recognised body word (Blender's own `UpperArm_L`/`Hand.R`/`Thigh_R` dot- or underscore-suffixed convention). `RiggedFigure.glb` itself turns out to need the *other* option this row's own prior text named, not this one: read directly, its own joint words (`torso`/`arm`/`leg`/`neck`) are generic placeholders in neither synonym table at all, and `arm_joint_L_1`/`_2`/`_3` differ from each other only by a trailing chain index (shoulder/elbow/wrist) — a distinction no word lookup can make regardless of where the side marker sits, so the marker's own position was never the only thing standing between this file and a real map. `looseAutoMap` over this file's own nineteen names still returns an empty `BoneMap`, now guarded by its own canary test in `loose_auto_map_test.dart` so a future change is caught rather than silently assumed; case 5's own scenario and hand-typed seventeen-row correction are unchanged, no fixture regeneration needed. **Decision (this pass): first option closed, second откладывается** — the side-anywhere reading is done and tested; a Khronos-sample-specific synonym table keyed on this file's own generic words plus their chain index is the only path to a non-empty map for it, and stays out of scope | core | S | 3 | anim-17 | side-anywhere widening closed and tested (`loose_auto_map_test.dart`); `RiggedFigure.glb`'s own auto-map remains open, now for a word-coverage reason rather than a marker-position one — not scheduled this pass |
| tut-14 *(found writing case 5, 2026-09-15)* | Case 5's own retarget lands through `ApplyClipResult(clipIndex: null)` — a real `ModelCommand` (`rig_job_commands.dart`): it records to the journal, and undoes/redoes through `ModelHistory` like any other. Its own doc comment said outright it was deliberately outside `modelCommandNames`/`modelCommandFromJson`, "the same as `ReplaceDocument`, for a different reason of its own" — wiring an MCP tool an agent could call it under was later, app-integration work. The practical effect, confirmed directly: `tutorial_scenarios_test.dart`'s own case-5 group replayed `case5.jsonl` cold from case 4's own saved project and got refused on line 1 with "names a command this build does not know" — a *different* shape than cases 2–4's own `tut-05` (a command this build already knows, refused only for want of a selection nothing recorded): here the build could not even name the command at all, selection or not. **Closed 2026-09-15**: `ApplyClipResult` is now registered in `modelCommandNames`/`modelCommandFromJson` (`command.dart`, reading a clip back through new `rig_job_commands.dart` helpers — `_clipFromJson`/`_trackFromJson`, the exact inverse of the file's own `_clipToJson`/`_trackToJson`, reusing `keyframe_commands.dart`'s own `_pathFrom`/`_interpolationFrom`/`_doubleListFrom`). `ApplyJobResult`, checked directly, was already registered — only its sibling needed the row. Offered over MCP as the `applyClipResult` tool (`model_tools.dart`), the same "land a result computed or received some other way" shape `applyJobResult`/`applySimulationCache` already offer — no background-job start/poll tooling existed to extend instead. New coverage: `tutorial_scenarios_test.dart`'s own case-5 group now asserts a cold replay of `case5.jsonl` succeeds and rebuilds the identical document a live session reaches, byte-for-byte against `case5.f3dproj`, instead of asserting the refusal | mcp + core | S | 3 | mcp-12n, anim-25 | closed — `ApplyClipResult` is a real, replayable `ModelCommand` now, reachable over MCP as `applyClipResult`; a cold journal replay past a retarget/IK-bake/shape-driver-bake step succeeds instead of refusing for want of a name this build did not know |
| tut-15 *(found writing case 6, 2026-09-15)* | Case 6 puts an agent's own `--mcp-port` session and a person's own live edit on one shared `ModelHistory` — `mcp_bootstrap_io.dart`'s own doc comment says outright this binds "over ... the same document a person already has open" — and asks whether a session's own recovery `.jsonl`, replayed cold, still rebuilds the document the way case 1's own journal does. It does not, silently. A person's own edit lands through `ModelHistory.run` directly (`ModelerCubit.run`'s own door, no author named, `StepAuthor.person`), never through `ModelSession.run`/`CommandJournal.record` — so it is never on the session's own journal at all. Confirmed directly: `tutorial_scenarios_test.dart`'s own case-6 group replays `case6.jsonl` cold and gets `replay.ok == true`, no refusal — but the replayed material's own roughness reads `SetMaterialField`'s own default (`0.5`), not the real project's `0.35` a person actually set. A quieter shape than every earlier case's own `tut-05`/`tut-14` (both of which at least refuse outright): a crash-recovery file that looks entirely successful and is silently missing every edit made beside the agent's own session. **Resolved 2026-09-15, together with `tut-05`.** `ModelHistory` (`packages/flutter3d_model_core/lib/src/history.dart`) now carries an optional `recoveryJournal` — a plain mutable `CommandJournal?` field, distinct from the existing `journal` getter (`_done`'s own commands, for `doc-31d`'s file writer) — that `run`/`amend`/`beginTransaction`/`endTransaction` write to on every success, regardless of which caller reached them: `ModelSession.run` (always `StepAuthor.agent`) and a plain `now.history.run(command)` from `ModelerCubit` (defaulting to `StepAuthor.person`, unchanged) now record to the identical journal when one is attached, each under the author it was actually given. `ModelSession`'s own constructor attaches a fresh `CommandJournal` to whichever `ModelHistory` it is handed (`recoveryJournal ??= CommandJournal()`, so one already there survives) instead of keeping a private journal only `ModelSession.run`/`amend` ever wrote to — so `--mcp-port`'s own shared history (`mcp_bootstrap_io.dart`) now journals a person's own edit exactly where it happened, not only the agent's. `ReplaceDocument` stays off the journal on purpose: a new `ModelCommand.isJournaled` flag (true by default, false only there) carries the "a whole `ModelProject`, no honest line for it" exemption `ModelSession.import` always relied on onto the command itself, so it holds regardless of which door a caller runs it through — the exemption used to work only because `import` called `history.run` directly rather than through `ModelSession.run`'s own `_journal.record`, an accident this row's own fix would otherwise have broken. New coverage: `history_journal_test.dart`'s own attached-journal group (author threading through `run`/`amend`, a transaction bracketing the same way live undo does, `ReplaceDocument` staying invisible to the journal through either door); `tutorial_scenarios_test.dart`'s own case-6 cold-replay test now asserts the person's own `0.35` roughness survives, under `StepAuthor.person`, instead of the silent `0.5` default | mcp + core | M | 3 | mcp-12n, mcp-13n, mcp-10n | closed — any edit run against a shared `ModelHistory`, by a person or an agent, lands on the same recovery journal when one is attached, with the correct author either way; a cold replay after a mixed agent/person session reproduces every edit, not only the agent's own tool calls |
| tut-16 *(found writing case 6, 2026-09-15)* | Case 6 asks for the design handoff's own screen 26, "Agent session" (`doc/design/modeler-handoff/README-дополнение.md`, row 26): a tool-call feed, a history list with "You"/"Agent" badges, undo restricted to the agent's own steps shown visibly, and a six-view contact sheet under the viewport. Confirmed directly by reading `apps/flutter3d_modeler/lib/src/mcp_ui_tools.dart`: `mcp-16d` built exactly the seven `ui.*` tools it scoped (`setMode`, `setSubmode`, `setTool`, `standardView`, `frameSubject`, `openDialog`, `say`) and nothing else — there is no tool-call feed, no author-badged history list, and no contact sheet anywhere in the app. `--mcp-port` itself and the undo restriction underneath it (`mcp-10n`) are both real and working, confirmed directly by case 6's own test — only the screen the design handoff describes to make either one visible to a person watching is unbuilt, so a person sharing a document with an agent today has no in-app way to see whose step is whose beyond reading the status line's own undo sentence. **Resolved 2026-09-15.** `flutter3d_mcp_kit`'s own `ToolTableServer` grew an `onCall` hook — run after every call answers, whichever of its own tools it was — threaded through `ModelMcpServer`/`ModelHttpServer.start` (`flutter3d_model_mcp`) and wired at `mcp_bootstrap_io.dart`'s own `startMcpServer` call site (`screen/files.dart`) into a new `ModelerCubit.agentToolCalled`, which appends to a bounded `ModelerReady.agentCalls` feed and resyncs the scene — the one place the screen ever learns an agent's own edit (run straight against the shared `ModelHistory`, never through `ModelerCubit.ran`) actually landed. `ModelerShell` (`apps/flutter3d_modeler/lib/src/ui/shell.dart`) grew an `agentPanel` slot, appended after the ordinary properties panel rather than replacing it, holding the new `AgentSessionPanel` (`apps/flutter3d_modeler/lib/src/ui/agent_session_panel.dart`): the tool-call feed, and an author-badged history list reading `ModelHistory.steps`' own `HistoryStep.author` ("You"/"Agent", newest first), with an "Undo agent steps" button wired to a new `ModelerCubit.undoAgentSteps` — `mcp-10n`'s own `topStepAuthor`/`onlyIfAuthoredBy` restriction, finally offered a button rather than only a status-line sentence. The contact sheet — `AgentContactSheet`, in `ModelerShell.bottom`, screen 26's own "under the viewport" slot — reads the pictures a `render`/`renderSheet` call actually drew this session, most recent first, rather than standing up a second, parallel six-camera renderer nothing else in this app has: `agent_session_panel.dart`'s own library comment says why that is the truer reading of the handoff's own "what the agent gets instead of numbers" than a literal six fixed views nothing renders live. New coverage: `apps/flutter3d_modeler/test/mcp_bootstrap_test.dart` gains a case proving `onToolCall` actually fires over the real HTTP socket, carrying the tool name, its arguments and whether it did anything; `modeler_cubit_test.dart`'s own new group covers `agentToolCalled` (appends, bounds the feed at 50, never clobbers an important `said`, resyncs the project) and `undoAgentSteps` (takes back only the agent's own top step, refuses a person's cleanly, "nothing to undo" with an empty stack); `agent_session_panel_test.dart` pumps the panel directly with a fake/mock tool call landing live and a mixed person/agent history, confirming the feed updates, the two badges read distinctly, and the undo button's own enabled state follows `topStepAuthor` | app | M | 3 | mcp-16d, mcp-10n | closed — screen 26's own tool-call feed, author-badged history and contact sheet are real, appended beside the ordinary shell while `--mcp-port` is open; case 6's own tutorial page no longer describes it as missing |
| tut-17 *(found closing out tut-00, 2026-09-15)* | The plan's own known candidate: does a file dropped onto the window ever become the open document? `_handleDroppedFile` (`apps/flutter3d_modeler/lib/src/screen/files.dart`) awaits `_openBytesWithImportScreen` and discards the returned `FileOpened` — confirmed directly by reading the function next to `_openFile`'s own call to the same method a few lines below, which switches on the result and calls `_installOpened`. A person drags a file onto the window, answers the import screen's unit and up-axis questions, and the document on screen never changes — the whole feature is a no-op past the dialog. This is the first of the two latent quirks `ui-37d`'s own text named when the handler moved into `screen/files.dart` verbatim ("`_handleDroppedFile` discards the import result") and promised "its own row" for. **Closed 2026-09-15**: `_handleDroppedFile` now calls `_openBytes` — the same shared helper `_openFile` already calls a few lines above, which runs the import screen when the file needs one and then `_installOpened`'s own switch (`_cubit.opened`, `setState`) — instead of awaiting `_openBytesWithImportScreen` and discarding what came back. A dropped project file replaces the open document immediately; a dropped model does once the import screen's unit and up-axis questions are answered — either way the same as choosing it through **Open** already did. New coverage: `file_drop_io_test.dart`'s own `tut-17` group pumps the real `ModelerScreen` widget end to end — a real device open, a real drop through the `desktop_drop` channel, project-file bytes that skip the import screen — and checks that the top bar's own document-name label changes to the dropped file's own name; confirmed directly that the test fails without the fix (reverting `_handleDroppedFile` to its old body leaves the label reading the startup document's own name) | app | S | 3 | ui-37d | closed — a drop now actually opens as the document, the same as `_openFile` already does |
| tut-18 *(found closing out tut-00, 2026-09-15)* | The second of `ui-37d`'s own two named latent quirks, found fresh while reading `TransformSession` for the row above: opening a new document should forget every mesh-picking cache keyed by the previous document's object ids, the way `_installOpened` already forgets `_elementPickerCache` for exactly that reason (its own doc comment: "ids start again in the new project and a picker held against the old one could match a version and answer about a mesh that is gone"). `TransformSession._otherPickers` (`Map<int, ({int version, MeshPicker picker})>`) is a second such cache, and nothing clears it — confirmed directly, no call site outside its own lazy-build path touches it. A new document whose object ids and versions collide with a stale entry could snap or gizmo against a mesh that is gone. **Closed 2026-09-15**: `TransformSession` now has its own `forget()`, clearing `_otherPickers`, called from `_installOpened` right beside `_elementPickerCache.forget()` — the same place, for the same reason. New coverage: `transform_session_test.dart`'s own `tut-18` group builds two documents whose "other" object shares an id and a version but not a mesh, and checks that after `forget()` a geometry-snap search against the second document's own (tiny) cube finds nothing near the first document's own corner; a second test in the same group, with no `forget()` call, confirms the same search *does* still answer with the first document's own stale corner — proving the collision is a real, reachable bug rather than a search that always comes back null | app | S | 3 | ui-37d | closed — opening a new document now forgets `TransformSession`'s own other-object picker cache too |
| tut-19 *(found closing out tut-00, 2026-09-15)* | The plan's own known candidate: the cabinet has no preview picture. Still true, and already tracked elsewhere, not a fresh finding: `cloud/README.md`'s own "What is not here yet" says outright the schema and repository have a place for a preview picture but nothing makes one yet, pending a browser-side capture the viewer cannot read back yet. The plan's own "out of scope" list already calls this "a separate `cloud` row". **Decision: откладываем** — already an owner-acknowledged `cloud` roadmap item; this pass only confirms it is still true and gives it a `tut-NN` name so the gap journal's own acceptance rule has something to point at | cloud | — | — | — | not scheduled this pass — tracked by `cloud/README.md` already; a real row lives with `cloud`'s own plan, not `model-editor-plan.md` |
| tut-20 *(found closing out tut-00, 2026-09-15)* | The plan's own known candidate: a model opened from the cabinet cannot be saved back. Still true, and already tracked elsewhere, not a fresh finding: the same "What is not here yet" section says editing from the cabinet is real (the viewer opens a model) but saving it back, with revisions, is its own next stage. **Decision: откладываем** — same reasoning as `tut-19`, and the same source names both in one breath | cloud | — | — | — | not scheduled this pass — tracked by `cloud/README.md` already; a real row lives with `cloud`'s own plan, not `model-editor-plan.md` |
| tut-21 *(found fixing tut-10, 2026-09-15)* | `tut-10`'s own row named this outright and left it open on purpose: `buildSkeleton` (`packages/flutter3d_model_core/lib/src/rig_template.dart`) computed every joint's `inverseBindMatrices` as `inverse(worldRest)` alone — correct only for a mesh object whose own world transform happens to be the identity, and silently wrong for anything else, since every marker `buildSkeleton` reads is a world-space pick but the engine's own skinning convention (`Skeleton.update`'s own doc comment, `packages/flutter3d_core/lib/src/engine/scene/skeleton.dart`: `jointMatrix = inverse(meshWorld) * jointWorld * inverseBind`) needs `inverseBind` to undo a bind-time position in the mesh object's own *local* space, not world space. Confirmed directly against the real `RobotExpressive.glb` fixture (a genuine ~100× scale and an axis swap, both from the file's own node hierarchy, not a synthetic case): fed through the unmodified GPU formula, the torso collapsed to about 1% of its real size. `render_project.dart`'s own `_withSkin` (`tut-10`'s fix) worked around this at render time only, by composing an extra `* meshWorld` onto each joint's own matrix; the live viewport's GPU pipeline (`SceneSync`/`Skeleton.update`) and the shadow and object-pick passes had no such workaround and simply skinned every non-identity mesh transform wrong — a real bug in every rig `T4.2`/`T4.3`'s auto-rig (`anim-21`/`anim-33d`) or screen 16 ever built for a mesh object that was not sitting at the identity. **Closed 2026-09-15**: `buildSkeleton` gains an optional `meshWorld` parameter (the mesh object's own world transform at bind time, defaulting to the identity when nothing is being skinned yet) and bakes it into `inverseBindMatrices` itself — `worldRest⁻¹ · meshWorld`, composed once at rig-build time rather than worked around per-consumer — so every reader of a `ProjectSkeleton` (the live viewport, the shadow and pick passes, `render_project.dart` alike) now gets a correct bind matrix regardless of the mesh's own transform. Its three real call sites — `autorig_markers.dart`'s `createRig` and `model_session.dart`'s `autoRig` (both read the skinned object's own `worldTransformOf` when a `skinObjectId` is given) and `case4_scenario.dart`'s own `RobotExpressive.glb` scenario — now pass it through. `render_project.dart`'s `_withSkin` no longer composes its own extra `* meshWorld`: the two corrections were mathematically the same composition, reassociated, so removing the workaround leaves `render_project.dart`'s own rendered pictures numerically the same (case 4's own `case4.f3dproj`/`.glb` and case 5's own `case5.f3dproj`/`.glb`, which starts from case 4's committed project, are regenerated — the skeleton's raw `inverseBindMatrices` bytes differ, the rendered pictures do not beyond floating-point-reassociation-level anti-aliasing at a silhouette edge, confirmed by rendering both before and after and diffing the PNGs directly). New coverage: `rig_bind_convention_test.dart`, driving the *real* engine `Skeleton.update` (not a reimplementation) against a rig built through a genuinely non-identity `meshWorld` (a ~100× scale plus a 90° axis swap, mirroring `RobotExpressive.glb`'s own real shape) and asserting a posed vertex lands at the correct world position — confirmed to fail against the pre-fix code (the vertex lands at about 1% of its expected position, reproducing this row's own "torso collapses" finding exactly) and to pass against the fix. Every prior `buildSkeleton` test (`rig_template_test.dart`, `retarget_test.dart`, `autorig_frame_test.dart`'s own `modeler-autorig.png` golden, `frame_test.dart`'s own `skeleton-overlay.png` golden) used an implicit identity `meshWorld` throughout — checked directly, every mesh object those tests build carries `Matrix4.identity()` — which is exactly why none of them caught this before, and why they stay green unchanged by this fix | core + app + mcp | M | 3 | tut-10 | closed — `buildSkeleton`'s own `inverseBindMatrices` are correct in the engine's expected convention regardless of the skinned mesh's own world transform, confirmed against a real non-identity transform through the actual `Skeleton.update` GPU formula, not only reasoned about; `render_project.dart`'s own render-time workaround is gone, its render output unchanged; every `buildSkeleton` caller with a mesh to skin now supplies its own world transform |

---

## 3. Dependencies between aspects

Text references from the plans ("mesh: EditMesh.toMeshData") are resolved
into ids. Where several aspects wrote the same thing, the table below says
whose implementation stays and whose id is marked "⇢" in the tables.

### 3.1 One implementation instead of several

| Thing | Who wrote it | Where it lives | Who becomes a consumer |
|---|---|---|---|
| Pure engine vocabulary packages | mesh-03 (`flutter3d_geometry`), doc-01 (the earlier working name for one shared package), p0-09 (`flutter3d_model`), qa-03, rel-03 | **two packages** (B1 [В1] closed by the 2026-09-09 owner decision): `flutter3d_geometry` — mesh-03 (`MeshData`, `VertexLayout`, `Shape`/`LatheShape`, tangents, `morph_target`, `CpuMesh`, `math/intersections`, `Ray`, `TriangleBvh`); `flutter3d_formats` — doc-01 (`ModelDocument`, `SurfaceMaterial`, `MaterialDocument`/`MaterialHint`, `lighting_model`, `model_loader`'s synchronous half, gltf/obj/f3d/ktx2/stl decoders, writers `F3dWriter`/`GltfWriter`/`ObjWriter`); `formats → geometry`, `mesh → geometry`, `model_core → both`, `flutter3d` re-exports both | mesh-13/14/17/20 (geometry), doc-11/12/19 (formats), fmt-01..09/12/15 (writers in `formats`; only fmt-13 and fmt-14 stay in the engine), mat-03 (formats), fmt-29d (`fbx → formats`) |
| Registering packages in the scanner/CI/documents | mesh-00, doc-02, ui-01, qa-02, qa-04, doc-30, rel-02, rel-03, rel-07, qa-16 | qa-02 (the lists), qa-04 (`ci.sh`), rel-02 (pubspec), rel-07 (documents); mesh-00/doc-02/ui-01 — one package each | everything |
| The `EditMesh` and persistence spike | mesh-01/02, p0-04/05 | mesh-01/02 in `packages/flutter3d_mesh` (not `tool/model_spike`), thresholds from p0-04/05 | mesh-10/11 |
| The triangle `TriangleBvh` | mesh-20, view-09, p0-10, pro-sc-04 | the class lives in the `geometry` package (after mesh-03), so both `Raycaster` and `flutter3d_mesh` can see it; **owner — view-09** (implementation + `Raycaster` integration, depends on doc-01 and p0-10); mesh-20 = `MeshBvh` over it with refit (depends on view-09); p0-10 — the prototype's measurement | view-10, mesh-21, anim-10, pro-rt-04, pro-pt-02 |
| Partial buffer overwrites | view-14, pro-eng-01, qa-11, p0-06, mesh-72, ui-29 | view-14 (the contract + qa-11's conformance); p0-06 decides the phase | pro-sc-05, pro-sim-04, view-18 |
| The project format | doc-09/10/28, fmt-17/18 | doc-09/10/28; fmt-17 contributes write-through for unknown manifest keys, fmt-18 contributes the asset policy (into doc-17) and `ProjectStorage` (into ui-18) | pro-doc-01, anim-03 |
| `Modifier` | mesh-40..48, mat-18, doc-23, mat-19 | the type and functions — mesh-40..48; `ModelObject.modifiers` and the cache — mat-18; commands — doc-23 | mat-20, mat-32 |
| The material in the document | mat-01, doc-25 | mat-01 (phase 1, including `SetTexture`/`AddImage`); the `SurfaceMaterial ↔ Map` codec in fmat.dart (an S engine change from doc-25) — into doc-10 | mat-04a-n (phase 1), mat-04..08, doc-12 |
| GltfWriter skins/animations/morphs | fmt-07, anim-26 | fmt-07 (phase 1) | anim-16, anim-30 |
| Background tasks | doc-24, ui-25, pro-job-01, anim-25 | doc-24 (`JobRequest` in core), ui-25 (the runner in the app); pro-job-01 → phase 2¹; anim-25 — `RigJob` on top | mat-11/13, pro-* |
| Skinning weights | mesh-60, anim-09 | layers — mesh-12/60; brush operations — anim-09 in `flutter3d_mesh/skin/` (the `rig` package is only for retargeting and auto-rigging) | anim-10, anim-22, pro-lod-02 |
| Morph targets | mesh-61/62, doc-27, anim-19 | storage — mesh-61/62; commands and UI — anim-19 | anim-20, anim-27 |
| Skeleton and clips in the document | doc-26, anim-03/04/29 | anim-03 (types), anim-04 (keys), anim-29 (the skeleton) | anim-07, anim-18 |
| Simplification (QEM) | mesh-70, pro-lod-01/02 | pro-lod-01/02 over `MeshData` | pro-lod-03, pro-rt-01 |
| UV unwrapping | mesh-71, pro-uv-02..05, view-19, pro-uv-07 | pro-uv-02..05 (the core), pro-uv-07 (the screen) | pro-pt-05 |
| Seams | mesh-12, pro-uv-01 | the `seam` flag in mesh-12 (phase 1); the command and overlay — pro-uv-01 | pro-uv-02 |
| Sculpting | mesh-72, pro-sc-02..07 | pro-sc-* (`SculptMesh` with multiresolution — B8/B9 [Б8/Б9] closed 2026-09-09; pro-sc-01 measures, doesn't choose) | pro-sc-08, view-21, ui-29 |
| Remeshing | mesh-73, pro-rt-01 | pro-rt-01 | pro-rt-02 |
| Weights as a gradient | view-18, anim-11 | view-18 | anim-10 |
| An "in-game" preview | view-17, anim-24, ui-28 | `FrameResult.triangles` and the viewport — view-17; budgets — anim-24; the shell — ui-28 | rel-09 |
| Material preview | view-16, mat-15 | mat-15 | mat-31 |
| Brush cursor and pen | view-21, ui-19, ui-29, pro-sc-08 | `InputPolicy` — ui-19; the cursor — view-21; the layout — ui-29 | pro-pt-05 |
| The viewport: gestures, picking, gizmo | ui-06, view-03/08/10/12 | view-*; ui-06 — integration and `scene_sync.dart` | ui-09, ui-13 |
| Golden scenes and draw-count | qa-10, qa-14, view-05, view-22 | view-05 (scene `mesh-overlay`), view-22 (the baseline) | — |
| App and core tests | qa-15, qa-18, ui-26, doc-* | ui-26 and the tests of core's own items | — |
| The MCP scenario and skills | qa-12, doc-21, doc-22, rel-14 | doc-21, doc-22 (+ `skills_test` from rel-14) | rel-09 |
| The measurement rig | p0-01, view-01, ui-00, qa-13 | p0-01 (the engine example); ui-00 — the app skeleton; view-01 — only (b)(c); qa-13 — the CI artifact | p0-02/03/06/11 |
| Web files | p0-08, ui-14 | p0-08 (a spike under `tool/`), ui-14 (the full version) | rel-10, ui-15 |
| The texture encoder | fmt-22, mat-30 | fmt-22 in the engine; mat-30 — the editor's own export on top | mat-28 |

### 3.2 Allowed cross-aspect references

| From | Reference in the plan | Allowed in |
|---|---|---|
| doc-03 | "mesh: EditMesh as an immutable value with identity equality and structural sharing" | mesh-10, mesh-11 |
| doc-06 | "mesh: primitive and Lathe builders, `EditMesh.transformed`" | mesh-28, mesh-22 |
| doc-07 | "mesh: pure operation functions; stable element ids" | mesh-22..26; tombstones + `IdRemap` in mesh-11 |
| doc-10 | "mesh: `EditMesh.encode/decode` with chunks" | mesh-18 |
| doc-11 | "design: STL import" | fmt-09 |
| doc-12 | "mesh: `toMeshData(VertexLayout)`; the modifier stack as a function; engine: deterministic GltfWriter/ObjWriter" | mesh-14, mesh-40; fmt-06, fmt-08 |
| doc-14 | "mesh: n-gon/manifoldness/normal checks by id" | mesh-27 |
| doc-17 | "app: a timer, atomic write, dialog, recent" | ui-18, ui-15 |
| doc-19 | "import/export under `dart run` only after doc-01" | doc-01 |
| doc-21 | "engine: a GltfWriter deterministic on two OSes" | fmt-06 (quantization — see the libm risk) |
| doc-23 | "mesh: mirror/array/smooth/boolean" | mesh-41, 42, 46, 47 |
| doc-26 | "mesh: joints/weights with renormalization" | mesh-60 |
| fmt-06/07/08 | "the base for anim-26, export for doc-12" | — |
| fmt-17 | "model_core: the ModelProject schema; mesh: EditMesh serialization" | doc-03, mesh-18 |
| view-02 | "app: the shell, Cubit, ModelObject → MeshNode" | ui-03, ui-06 |
| view-08 | "app: a ModelObject ↔ MeshNode map" | ui-06 (`scene_sync.dart`) |
| view-10 | "mesh: Float32List positions, edges as pairs, a triangle → face map" | mesh-11, mesh-14 (`triangleToFace`) |
| view-12 | "model_core: a transform command and `history.transaction`; mesh: moving a selection" | doc-06, doc-08, mesh-22 |
| view-13 | "mesh: Selection and EditMesh versions" | mesh-19, mesh-11 (identity = version) |
| view-16/17 | "app/model_core: SurfaceMaterial, a material command; ProjectProfile" | mat-01, doc-13 |
| view-18 | "mesh/model_core: weights and a brush with renormalization" | mesh-60, anim-09/10 |
| view-19 | "mesh: unwrapping, islands, stretch, separate corners in toMeshData" | pro-uv-02/04, mesh-14 |
| view-20 | "mesh: simplification" | pro-lod-01 |
| view-21 | "mesh: brush operations" | pro-sc-03, pro-pt-03 |
| ui-03 | "model_core: ModelProject, commands with says, history with amend, ExportReadiness" | doc-03, 05, 08, 14 |
| ui-06 | "mesh: Selection and BVH; flutter3d: overlays (1.10)" | mesh-19/20/21, view-05 |
| ui-08 | "model_core: SetTransform, Rename, AddModifier…; phase-1 modifiers (mirror)" | doc-06, doc-23; the phase-2 mirror is mesh-41 (the phase-1 stack is empty) |
| ui-09 | "model_core: ParamHint and `history.reapplyTop`; mesh: phase-1 operations" | `amend` in doc-08; ParamHint — **added during synthesis: syn-01**; mesh-22..26 through doc-07 |
| ui-10 | "model_core: ExportReadiness, ProjectProfile; mesh: checks" | doc-14, doc-13, mesh-27 |
| ui-13 | "mesh: a parametric Lathe; model_core: AddLathe/SetLatheParams" | mesh-28, doc-06 (`AddLathe`, `SetParametric`) |
| ui-16 | "design: the import screen's mockup; model_core: fromModelDocument; flutter3d: StlLoader" | **added during synthesis: syn-02**; doc-11; fmt-09 |
| ui-17 | "design: the export mockup; flutter3d: GltfWriter/ObjWriter; model_core: toModelDocument, ExportReadiness" | syn-02; fmt-06/08; doc-12/14 |
| ui-26 | "flutter3d: the edge overlay (1.10)" | view-05 |
| ui-28 | "model_core: clips, keys, ProjectProfile" | anim-03/04, doc-13 |
| ui-29 | "flutter3d_hardware: DeviceMesh.overwrite; mesh: brushes" | view-14, pro-sc-03 |
| mat-03 | "the model editor depends on editor_core for one library" | В4; the move only happens after doc-01 (editor_core is flat, and the library takes types from `flutter3d`) |
| mat-18 | "mesh: mirror/array/smooth/subdivide/booleanBsp, toMeshData" | mesh-41/42/46/45/47, mesh-14 |
| mat-19 | "model_core: the shared command hierarchy; mcp: table generation" | doc-05, doc-20 |
| mat-20/24 | "shell: the right-hand panel, jobs, the card; viewport: the manipulator, marker picking" | ui-08, ui-25, ui-09; view-12, view-08 |
| mat-22/28 | "model_core: ExportReadiness, ProjectProfile; mesh: checks" | doc-14, doc-13, mesh-27 |
| mat-25 | "viewport: a marker id pass, a shared DebugDraw" | view-08, view-05 |
| mat-32 | "mcp: the server, session, schemas" | doc-19, doc-20 |
| anim-03 | "core: a persistent ModelProject, from/toModelDocument" | doc-03, doc-11, doc-12 |
| anim-05 | "app: a joint-rotation gizmo" | view-12 |
| anim-07 | "app: the shell, theme, layouts, modes" | ui-04, ui-02, ui-05 |
| anim-09 | "mesh: joints/weights as attributes, adjacency, BVH" | mesh-12/60, mesh-11 (`vertexRing`), mesh-20 |
| anim-10 | "mesh: a BVH updated from a position array" | mesh-20 (`refit`) |
| anim-11 | "mesh/hardware: DeviceMesh.overwrite" | view-14 |
| anim-13 | "core: ExportReadiness accepts providers; ProjectProfile with fps" | doc-14; fps in the profile — **added during synthesis: syn-03** |
| anim-19 | "mesh: editing a vertex-position copy with no topology change" | mesh-61 (`ShapeKey` as a position layer) |
| anim-22 | "mesh: BVH and adjacency for MeshData" | mesh-13 + mesh-20 (via `fromMeshData`) |
| anim-24 | "core: ProjectProfile with texture bytes and a target engine" | doc-13, mat-28 |
| anim-25 | "core: job state, a result as a command" | doc-24, ui-25 |
| anim-26 | "fmt: the GltfWriter core with a part structure" | fmt-06 |
| anim-30 | "mcp: the server and a table from commands" | doc-19, doc-20 |
| pro-eng-07 | "viewport: a phase-1 contributor" | view-05 |
| pro-uv-01 | "mesh: edge attributes and index remapping" | mesh-12, mesh-11 (`IdRemap`) |
| pro-uv-06 | "mesh: toMeshData with corner attributes" | mesh-14 |
| pro-sc-02 | "mesh: a shared chunk type" | mesh-10 |
| pro-sc-04 | "mesh: the phase-1 picking BVH" | mesh-20 |
| pro-sc-06 | "model_core: history with persistent values" | doc-08 |
| pro-sc-07 | "mesh: phase-2 Catmull-Clark" | mesh-45 |
| pro-rt-02 | "mesh: adding a face, merging by distance" | mesh-11 (`addFace`), mesh-25 |
| pro-rt-06, pro-pt-04, pro-eng-06 | "export: a GltfWriter with images / phase 1" | fmt-06 |
| pro-rn-04 | "materials: screen 05's graph widget" | mat-13 |
| pro-doc-01 | "model_core: the sectioned format" | doc-09/10 |
| qa-07 | "mesh: validate/audit, to/fromMeshData, chunks" | mesh-11, 13/14, 10 |
| qa-08 | "formats: GltfWriter, ObjWriter, StlLoader" | fmt-06/08/09 |
| qa-10 | "render: the overlay's PassContributor" | view-05 |
| qa-11 | "hardware: `writeGeometry`/`DeviceMesh.overwrite`" | view-14 |
| qa-12 | "model_core: commands with arguments/fromJson, quantization in the format" | doc-05, doc-10 |
| qa-13 | "mesh: spike 0.2, chunks 0.3" | mesh-01, mesh-02 |
| qa-15 | "app: EditorState/Cubit, the manipulator, layouts; mesh: BVH" | ui-03, view-12, ui-05, mesh-20 |
| rel-02 | "mesh: an empty library with one export" | mesh-00 |
| rel-04 | "model_mcp: a bin answering tools/list" | rel-02 (a `--help` stub in phase 0); `tools/list` in the container — doc-19's acceptance |
| rel-06 | "model_core: phase 1 closed (1.7, 1.8); mesh: a stable API" | doc-10, doc-14; mesh-31/33 |
| rel-08 | "app: Object and Mesh modes (1.11)" | ui-04, ui-08, ui-09 |
| rel-09 | "app: import/export (1.15); model_mcp: the table (1.17); engine: GltfWriter (1.9)" | ui-16/17, doc-20, fmt-06 |
| rel-10 | "app: disk on the web (1.15, spike 0.5); perf: measurement 0.1 in Chrome" | ui-14, p0-08, p0-02 |
| rel-11 | "app: builds on macOS (1.11)" | ui-20 |
| rel-13 | "engine: a deterministic GltfWriter; model_core: a format and bin/export" | fmt-06, doc-10 (+ `bin/` — a §8 question) |
| rel-17 | "perf: measurement 0.1; app: spike 0.5" | p0-02/03, p0-08 |

### 3.3 Added during synthesis

Three references didn't resolve into any item; items were created for them.
Nine items with an `-n` suffix (mat-04a-n, mat-09n, doc-11a-n, anim-31a-n,
p0-13n, ui-30n, ui-31n, ui-32n, qa-19n) were added by the 2026-09-09
critique, five with a `-d` suffix (doc-31d, ui-33d, ui-34d, rel-19d,
fmt-29d) — by 2026-09-09 owner decisions; all sit in their own aspect's
tables.

| id | what | package | size | phase | depends | acceptance |
|---|---|---|---|---|---|---|
| syn-01 *(added during synthesis)* | `ParamHint` — its own sealed type in core (Int / Double / Bool / Enum / Vector3, with `step`, `unit`, a range) for the operation card; `ModelCommand.hints` on commands with parameters (Extrude, LoopCut, MergeByDistance, MoveElements, AddPrimitive, AddLathe). Without it ui-09 can't build controls, and doc-05 only talks about `arguments`. The type was decided by the 2026-09-09 critique (D4/F2 [Г4/Ж2]): `MaterialHint` doesn't fit — it only has `RangeHint(double, step)`/`ColorHint`/`TextureHint`/`EnumHint`, no integers (`LoopCut.cuts`), no flags (`Extrude.individual`), no units, and the file pulls in `LightingModel` | core | S | 1 | doc-05 | every command with a numeric argument has a hint; test: `hints`' keys ⊂ `arguments`' keys; `LoopCut.cuts` is an `IntHint`, `Extrude.individual` a `BoolHint` |
| syn-02 *(added during synthesis)* | Mockups for the two phase-1 screens missing from the handoff: import with checks and export with checks (the handoff README itself requires them before the phase starts; ui-16/17 and fmt-12 describe the data, not the look). The same `.dc.html` style, the same token table | design | S | 0 | — | two screens in the handoff archive; ui-16/17 reference them |
| syn-03 *(added during synthesis)* | `ProjectProfile.fps` and `frameSnap` — a time base for animation in the profile (anim-04 rounds a frame as `round(time·fps)`, anim-13 reads fps); doc-13 doesn't have the field | core | S | 3 | doc-13 | a JSON round trip; `KeyTable` reads fps from the profile |
---

## 4. The critical path and tracks for agents

Computed from `dependsOn` after merging duplicates. Weights: S = 1 week, M =
2.5, L = 5 — midpoints of the §6 working-through intervals, for one person.
After the 2026-09-09 owner decision (one executor, with agents), the
critical path sets the order of work, and phase 1's calendar is computed in
§4.3 as a sum of sizes.

### 4.1 The critical path

Recomputed 2026-09-09 by critique: edges §4 implied but the tables didn't
carry were added to the "depends" column (doc-03 ← mesh-11; doc-07 ←
mesh-22..26; ui-09 ← doc-07, syn-01; ui-26 ← doc-07; mat-01 ← doc-03, doc-05),
and the path was derived strictly from them. The earlier chain ran through
mesh-14 → mesh-19 → mesh-23, but mesh-19 only depends on mesh-11, and doc-07's
longest predecessor is mesh-25 (dissolve waits on `fromMeshData` from mesh-13,
which waits on mesh-12's layers). The earlier chain's tail, ui-09 → ui-26
(3.5 weeks after doc-07), is shorter than doc-20 → rel-09 → rel-16 (6 weeks),
which also sit in phase-1 acceptance and also wait on doc-07.

```
qa-01 → qa-02 → mesh-01 → mesh-02 → mesh-10 → mesh-11 → mesh-12 → mesh-13
      → mesh-25 → doc-07 → doc-20 → rel-09 → rel-16
```

| link | size | weeks | what it unlocks |
|---|---|---|---|
| qa-01 green main | S | 1 | any merge |
| qa-02 package registration | S | 1 | the first code commit |
| mesh-01 the EditMesh spike | M | 2.5 | the API's shape and `toMeshData`'s cost |
| mesh-02 the persistence measurement | S | 1 | chunk or patch |
| mesh-10 persistent vectors | M | 2.5 | — |
| mesh-11 half-edge | L | 5 | doc-03 (the document), mesh-15/16/18/19 in parallel |
| mesh-12 attribute layers | M | 2.5 | mesh-13, 14, 16, 18, 23, 24 |
| mesh-13 fromMeshData | M | 2.5 | mesh-25, 27, 29, doc-11 |
| mesh-25 merge/dissolve | M | 2.5 | doc-07 (the last of mesh-22..26) |
| doc-07 mesh commands | M | 2.5 | ui-09 → ui-26 (3.5 wks, in parallel), doc-20 |
| doc-20 the MCP tool table | M | 2.5 | doc-21 (2.5 wks, in parallel), rel-09 |
| rel-09 the tutorial as a test | M | 2.5 | rel-16 |
| rel-16 the cohort | S | 1 | phase-1 acceptance (the cohort's calendar time exceeds one week) |
| **total** | 4 S, 8 M, 1 L | **≈ 29** | |

Three notes. The whole chain sits in the geometry core, up through doc-07;
everything before mesh-11 is phase 0 and the first weeks of phase 1, and
can't be sped up, only kept from stalling on decisions (§5.2). After mesh-11,
mesh-14/15/16/18 and mesh-22..24/26 run in parallel with mesh-12 → 13 → 25 by
dependency, but with one executor they sit in the same queue — that's exactly
the difference between the ≈29-week path and the §4.3 calendar. The ≈29
figure didn't change by accident: two Ms (mesh-14, mesh-19) left the path,
two Ms (doc-20, rel-09) joined it. The 2026-09-09 decisions didn't change the
path: doc-31d (history in the file) hangs off doc-08/10, away from the
chain; ui-21 and rel-19d are S with no followers on the path; and the
acceptance "opens on an iPad and a Galaxy A55" rests on ui-21, ready well
before rel-16.

### 4.2 Tracks for agents: what doesn't depend on `EditMesh`

The items below don't depend on `EditMesh` and can start the day `main`
turns green. With one executor (§4.3) they don't run "in parallel" on their
own — these are the tracks handed to agents under pre-written tests;
candidates are marked **(agent)**, the criterion being a mechanical check
(a round trip, a golden frame, the scanner, a key set) written before the
code.

- **Formats (agent):** fmt-01 → fmt-02/03/04/05 → fmt-06 (after doc-01,
  deadline 09.25) → fmt-07 → fmt-10/11/12/13/14, fmt-08, fmt-09, fmt-15,
  fmt-16. The working-through §8 names `GltfWriter` as the one item that can
  start "today, with nothing to agree on first"; after B1 [В1], "today"
  means "in the engine, moving into `formats` alongside doc-01." Tests —
  round trips on Khronos models and `compareModelDocuments`, ready before
  the writer.
- **Rendering (agent — overlays with a golden frame: view-05/06/11/13):**
  p0-01 → view-01 → view-05 → view-06, p0-10 → view-09 (after mesh-03) →
  mesh-20, view-14 (per p0-06), p0-06.
- **Platforms (agent):** ui-20, ui-21, qa-17, rel-11 — Android/iOS/macOS/web
  configuration and their CI builds; checked by the scanner and a green job.
- **Localization (agent):** ui-22 — checked by "the ru/en key sets are
  equal, no Cyrillic under `Locale('en')`."
- **Vocabulary:** doc-00 → doc-01 (with mesh-03) — mesh-13/14, doc-11/12,
  doc-19 sit on it; deadline 2026-09-25.
- **The shell:** ui-00 → ui-01 → ui-02 → ui-03 → ui-04 → ui-05/07/12/22/23,
  ui-14 (with the p0-08 spike), ui-15, ui-25; view-02 → view-03 →
  view-04/08/12 → view-11. All of this works on `Imported(MeshData)` and
  parametric objects while `EditMesh` doesn't exist yet.
- **The document:** doc-02 → doc-13/15/18 → doc-09 → doc-10 (over
  `Imported`, the `editMeshes` section empty until mesh-18) → doc-16/17;
  doc-05/06 — as soon as `ModelProject` exists (doc-03 now only waits on
  mesh-11's identity semantics, recorded in its `depends`); mat-01 →
  mat-04a-n after doc-03/05.
- **Measurements:** p0-02/03/07/08/10/11/13n, anim-31 (FK only), qa-13.
- **Animation with no app:** anim-01, anim-02, anim-14, anim-17, anim-21 —
  pure Dart and engine code, can run alongside phase 1 (the anim aspect
  proposes this directly).

### 4.3 Team

2026-09-09 owner decision: **one** executor, with agents. The design plan
called for a minimum team of three (geometry core, rendering, UI), and the
earlier "1 / 2 / 3 people" table is dropped: there are still several tracks,
but one person walks them, so phase 1's calendar is the sum of the sizes of
all its items, not the critical path's length.

**Counted from the §2 tables.** Phase-1 items with their own work (excluding
eleven whose content is entirely folded into another item, with "see" as
their acceptance: fmt-17/18, qa-07/08/09/10/12/14/15/18, rel-14), with the
2026-09-09 decision items (ui-21 moved, doc-31d, ui-33d, rel-19d added), and
excluding conditional ones (ui-34d, view-14 in phase 1 only per p0-06,
view-06 counted as S):

| size | items | weeks each | weeks |
|---|---|---|---|
| S | 80 | 1 | 80 |
| M | 53 | 2.5 | 132.5 |
| L | 5 (mesh-11, doc-10, view-12, mcp-01n, mcp-03n) | 5 | 25 |
| **total** | **138** | | **≈ 237** |

**Recomputed 2026-09-10.** It was 120 items and ≈198 weeks. Fifteen `mcp-`
aspect items (all phase 1) and three gap-analysis phase-1 items (mesh-81n,
doc-34n, view-26n) were added: 7 S, 9 M, 2 L — another ≈39.5 weeks. The rest
of the gap-analysis items sit in phases 2–4 and aren't in this count.

**The `gfx-` track is counted separately and isn't in the sum above**,
because it runs in parallel and is numbered with its own phases: G1 ≈4.5
weeks (a profiler and two measurements), G2 ≈11 (four pains seen with one's
own eyes), G3 ≈16 (a close-up hero and what the ROADMAP already promised) —
**≈31.5 weeks**. It doesn't lengthen the modeler's phase 1: these are
engine changes with their own golden frames and their own conformance.

Converting to weeks — S = 1, M = 2.5, L = 5, midpoints of the §6
working-through intervals. If the conditional items fire (ui-34d as M,
view-06 as M instead of S), add 4 weeks to the sum: ≈202.

**Estimate 1 — one person with no agents:** ≈237 weeks of pure work, about
4.6 years; the critical path ≈29 weeks inside that sum — the order to walk
it in. The `gfx-` track adds another ≈31.5 weeks to the calendar if the same
person walks it, and none at all if agents walk it under ready-made golden
frames — exactly the shape of §4.2's "overlays with a golden frame" track.

**Estimate 2 — one person with agents on the §4.2 tracks.** Handed to
agents under ready-made tests:

| track | phase-1 items | size | weeks |
|---|---|---|---|
| format writers with round-trip tests | fmt-01..05, 11, 12, 13, 15, 16 (S), fmt-06, 07, 08, 09, 10 (M) | 10 S + 5 M | 22.5 |
| overlays with a golden frame | view-05, view-13 (M), view-06, view-11 (S) | 2 S + 2 M | 7 |
| platform configuration | ui-20, ui-21, qa-17, rel-11 | 4 S | 4 |
| localization | ui-22 | 1 S | 1 |
| **handed to agents, total** | | | **34.5** |

An agent doesn't remove an item from the calendar entirely: a human writes
its tests, a human reads the result. Putting this at a quarter of the
item's size — an estimate, not a measurement — leaves the human 237 − 34.5 +
8.6 ≈ **211 weeks**, about 4.1 years. This second number is checked by the
very first track: fmt-01..05 (5 S) go to an agent under fmt-01's tests; if
acceptance takes more than a week and a quarter, the fraction is revised and
the estimate with it.

Consequence for timing: December 27 is not the target (C8 [В8]); the first
publish and release come once phase 1 is in the hands of its first users
(rel-16 → rel-06).

---

## 5. Milestones by phase

### 5.1 Phase 0 — measurements and spikes (by 2026-10-05)

**Includes:** qa-01, qa-02 (with mesh-00, ui-01, rel-02, rel-03, rel-07),
qa-03, qa-04, qa-05, qa-13, doc-00, doc-01 (with mesh-03), mesh-01, mesh-02,
mesh-04, p0-01..p0-12, p0-13n, view-01, view-02, ui-00, ui-14 (the p0-08
spike and the p0-13n sandbox spike), anim-31 (FK only), rel-01, rel-04,
rel-12, rel-17, syn-02.

**Done when:**
*`main` is green three runs in a row, and `dart run tool/structure.dart`
holds 31 rules with six new directories in the tree (33 packages: 28 today,
`geometry`, `formats`, mesh, core, mcp). The vocabulary is split into two
packages — `flutter3d_geometry` with the geometry and `TriangleBvh`,
`flutter3d_formats` with the document, decoders, and writers built on it —
`flutter3d` re-exports both, the publishing order geometry → formats →
flutter3d is accepted by `publish_check.sh`, and in a container with no
Flutter SDK, both `dart pub get` and
`dart run flutter3d_model_mcp:model_mcp --help` (rel-02's stub; `tools/list`
is doc-19's acceptance, in phase 1) pass. It's known which call the modeler
uses to write a file under the macOS sandbox (p0-13n). A half-edge cube with
an extruded face is drawn by the software rasterizer and matches the
reference; `toMeshData` at 200,000 triangles, a snapshot when moving 1% of
vertices under two distributions, `DeviceMesh.upload` versus overwrite, an
isolate versus chunks, a million triangles on macOS, in Chrome, and on a
Galaxy A55 — all of it is numbers with a date and a machine in
doc/model-editor.md §6, and not one line in §7 says "the measurement
decides." The web opened a GLB through the browser's own panel and
downloaded a `.f3d` in three browsers; wherever a p0-02/p0-08 threshold
wasn't met, §5.2 records the item that closes it (a JS build, chunks,
ui-34d) — the web's measurements became quality gates, not a choice between
"equal" and "view-only" (2026-09-09 decision). The ROADMAP at the September
28 review contains a model-editor track with an Acceptance line and a
reworded node-graph item (F1 [Ж1]).*

**Decisions before starting:** none. Package names and where the code lives
were settled 2026-09-09 (C5 [В5]: this monorepo, mesh / model_core /
model_mcp / geometry / formats / modeler), rel-01 records them with the
check's date. B1 [В1] is closed with two packages and sits in phase 0 as a
decision with a 09.25 deadline, not a question; phase 0 produces everything
else.

### 5.2 Phase 1 — the first version

**Includes:**
- mesh: 10–33 (with anim-09 excluded);
- core: doc-02..22, doc-29, doc-31d (history in the project file), mat-01
  (with `SetTexture`/`AddImage`), mat-03, syn-01;
- formats: fmt-01..16 (fmt-17/18 merged; fmt-01..09/12/15 — in `formats`);
- engine/rendering: view-03..06, view-08..13, view-22, view-09; view-14 —
  only if p0-06 doesn't pass;
- shell: ui-02..13, ui-15..26 (ui-21 — Android and iOS, moved from phase
  2), ui-30n..33d, ui-34d conditional on p0-07/p0-08, mat-04a-n (the
  phase-1 material panel);
- MCP: doc-19..22 (with rel-14);
- quality: qa-06..10, qa-12, qa-14..18, qa-19n;
- publishing and purchases: rel-05, rel-06 (only after rel-16 — C8 [В8]),
  rel-08..11, rel-15, rel-16, rel-18, rel-19d (an iPad and an Apple
  Developer account by mid-phase).

**Done when:**
*A Khronos model is imported with a warnings screen (units and up axis
chosen right there), one face is extruded with the mouse, the offset value
is corrected as a number in the card with no new history step; the
extruded cube's base color is changed and a texture assigned in the
"Material" panel, and both show up in the GLB; the result goes into a GLB
the shooter's own loader reads with no warnings, that the glTF Validator
accepts with no errors, and that headless Godot opens in CI with the same
mesh count. The original's frame and the re-read export's frame match on
the software rasterizer. The same scenario
is replayed by an agent through `flutter3d_model_mcp` over stdio and
compared in CI against a reference project file and command journal.
`EditMesh` holds `validate()` across 500 random operations over three
seeds, a history snapshot after moving 1% of the vertices of 200,000 costs
less than 10% of a full copy, and the bench prints that number. A project
is saved with history, reopened, and its last three steps undone —
untouched chunks are `identical` to the original. The app builds for
macOS, the browser, Android, and iOS: it opens on an iPad and a Galaxy
A55, in Chrome — editing, not just viewing; the three layouts show one
tool set, the interface switches between Russian and English with no
Cyrillic under `Locale('en')`, the hotkeys are Blender-like and listed in
help, export with a red `Issue` warns and, after confirmation, writes the
file, the status line is green or orange per `ExportReadiness`, the app's
tests run through `flutter3d_cpu` with golden frames. The `mesh-overlay`
scene is recorded across all four sets. Five people went through the
tutorial, and the time on its page is measured, not promised.*

**Decisions before starting (remaining from §8's questions):** stable ids
with tombstones (B2 [Б2]); enum versus sealed (B7 [Б7]); `materialSlot` in
phase 1 (B6 [Б6]); the project file's magic number and autosave location
(D1 [Г1]); exporting skins in phase 1 (E4 [Д4]); `overwrite` in phase 1 or 2
(per p0-06). Closed 2026-09-09 by owner decision: chunk or patch — persistent
values, the split measured by p0-05 (B3 [Б3]); non-manifold splits on
import (B1 [Б1]); icons — the SDK's `Icons` (F12n [Е12n]); the web is equal
footing, measurements are gates (F1 [Е1]); B1 [В1] — two packages. D4 [Г4]
(the language of `says` — English, hints — `ParamHint`) closed by critique
and confirmed by the owner.

### 5.3 Phase 2 — materials, modifiers, the scene, formats

Caveat: phase-2 items were written before phase 0's numbers and before
`EditMesh`'s shape settled; sizes are an order of magnitude, dependencies
within mesh-4x are solid, between mat-/doc-/mesh — the best knowledge
available.

**Includes:** mesh-40..49; doc-23, doc-24 (with pro-job-01), doc-28,
doc-11a-n (unconditional — placing assets, 2026-09-09 decision); mat-02,
mat-04..16, mat-09n, mat-18..20, mat-22..25 (mat-24 with placement and scene
export), mat-28..32; fmt-19..22; FBX as a separate track after rel-16 —
fmt-29d, fmt-24, fmt-25 (fmt-26 dropped); view-07, view-14 (if not in phase
1), view-16 (⇢ mat-15); ui-27; rel-13. ui-21 moved into phase 1.

**Done when:** *the "mirror → array → smooth → boolean" stack on an object
is computed from a version cache, "Apply" leaves one history step, a
boolean on coplanar faces warns and doesn't crash; a material is edited
with sliders built from hints and a texture compositor with a fixed node
set that bakes into five slots with no shader change — the engine's golden
frames haven't shifted; "Scene" mode holds light, environment, and shadows,
a ninth source shows in the status as dropped, two assets are imported into
one project via `ImportInto`, placed with a gizmo, and exported as one GLB
with two nodes; frames `bevel`, `subdivision`, `boolean`, `material-studio`,
`scene-lit` are green on ubuntu; FBX from Blender — binary and ASCII — is
read by its own `flutter3d_fbx` reader down to floats against a glTF of the
same scene, skins and clips within 1e-4, and the package resolves with no
Flutter SDK; textures shrink to fit the profile, and `.ktx2` from the
engine's own encoder loads under conformance across four backends.*

**Decisions before starting:** PNG deflate and a PNG/JPEG decoder — from
scratch or `package:archive`/`package:image` (D6 [Г6], mat-09n); one
modifier flag or two (G3 [Ж3]); texture-budget numbers (G5 [Ж5]). Closed
2026-09-09: "node graph" → "texture compositor," recorded in the ROADMAP at
the September 28 review (G1 [Ж1]); "Scene" mode = light/environment/
shadows/post plus placing assets (G4 [Ж4], §7 #36); FBX — its own reader in
Dart (E7 [Д7]).

### 5.4 Phase 3 — the character pipeline

Same caveat, plus: `Pose`, IK, and retargeting weren't checked against a
single real mocap clip — only Khronos samples.

**Includes:** anim-01..08, anim-10, anim-12..18, anim-19..23, anim-25,
anim-27..30, anim-31a-n, anim-32 (anim-09 — in mesh, anim-11/24/26 merged);
mesh-60..62; view-15, view-17, view-18; ui-28; fmt-23 (fmt-25 moved into
phase 2 with the FBX reader); pro-eng-02; syn-03.

**Done when:** *a clip edited in the timeline plays identically through
three paths — `Pose.sampleClip`, `AnimationPlayer.seek`, `BakedPoses` — and
after a GLB round trip the tracks match byte-exact; a weight brush paints
on a bent pose and leaves ≤ n influences from the profile, summing to 1;
retargeting a clip onto a skeleton twice as tall keeps the foot within a
centimeter of the floor; auto-rigging RobotExpressive from eight markers
gives a skeleton ≤ 64 bones with primary weights in seconds inside an
isolate; screen 19 shows triangles, bones, and textures against the
profile with the same renderer the game uses; an agent runs "auto-rig →
weights → keys → GLB" in CI.*

**Decisions before starting:** the `flutter3d_rig` package (C2 [В2]); four
influences as a hard limit (H1 [З1]); IK always bakes silently (H3 [З3]);
seconds as the time base (H5 [З5]); the v1 scope for retargeting (H6 [З6]).

### 5.5 Phase 4 — professional modes

Caveat: the least precise phase. Sculpting at 1.2M, XPBD cloth, LSCM, and
ray-based baking are numeric algorithms whose L sizes could double; the
order inside the phase is set by pro-sc-01 and pro-rn-01, not by this list.

**Includes:** pro-eng-03..07, pro-uv-01..07, pro-sc-01..09, pro-lod-01..04,
pro-rt-01..07, pro-sim-01..06, pro-rn-01..04, pro-pt-01..05, pro-doc-01,
pro-test-01, pro-after-01; view-19..21 (⇢ pro), ui-29; mat-17; fmt-27,
fmt-28; mesh-70..73 (⇢ pro).

**Done when:** *a cube is subdivided to 1.2M triangles and a pen stroke
only touches its own chunks within the frame budget on desktop (on the web
— within the profile's limit); retopology gives ≥70% quads on the source
surface, and a baked normal map shows the stroke as relief on the low-mesh
in a GLB; a cube is LSCM-unwrapped into non-overlapping islands with
stretch in the list; a 20×20 cloth hangs from two corners and exports as
eight morph targets; a 4K snapshot is assembled in tiles with progress,
and editing bloom only recomputes post; painting across a seam lands on
both islands and flattens into `baseColorTexture`; a phase-1 project opens
after eight new sections; eight frames and an end-to-end MCP scenario are
green in CI.*

**Decisions before starting:** simulation export (H2 [И2]); a second UV set
(E10 [Д10]); the timing of the `renderPost`/`overwriteTexture` contract
changes (H3 [И3]). Closed 2026-09-09: cloth — a separate `flutter3d_cloth`
solver in phase 4 (C3/H1 [В3/И1]); sculpting — `SculptMesh` with
multiresolution, screen 08 gets a "Subdivide" button instead of "density"
(B8/B9 [Б8/Б9]); screen 12's "Render" — a snapshot from the same renderer
with supersampling and frame-graph passes, a path tracer is out of scope,
"samples" leaves the mockup (pro-rn-02).

---

### 5.6 After phase 4

Closes `pro-after-01`. This section decides nothing new — it collects, in
one place, what the plan already called deferred past phase 4, and the
reason for each item where it was decided. **Agreed by the owner
2026-09-13** as `pro-after-01`'s closing text, unedited.

**From phase 4's "honest boundary"** (§5.5: "ABF++, dyntopo, quadriflow,
GPU baking, cloth self-intersection, body rotation, a path tracer — after"):

- **A path tracer** for screen 12's "Render." 2026-09-09 owner decision:
  screen 12 stays a snapshot from the same rasterizing renderer, with
  supersampling and frame-graph passes (`pro-rn-02`); a ray-tracing path
  isn't built, and "samples" leaves the original screen mockup's text
  (§5.5 "Decisions before starting"; §7 #32).
- **ABF++.** `pro-uv-03` unwraps an island with a planar or box projection
  "instead of ABF++" — the more accurate angle-based parameterization
  method isn't implemented.
- **Dyntopo.** B9 [Б9] closed by owner decision 2026-09-09 in favor of
  `Multires` — multiresolution with fixed subdivision levels (`pro-sc-07`);
  dynamic topology rebuilding during sculpting — later.
- **Quadriflow.** `pro-rt-01` builds retopology through its own chain
  (simplify → greedy quadrification → BVH-based shrink-wrap); quadriflow
  as a separate algorithm — later.
- **GPU map baking.** `pro-rt-04` rasterizes and ray-traces for baking on
  the CPU; a GPU path for the same maps — later.
- **Cloth self-intersection.** `flutter3d_cloth` (`pro-sim-01`) only checks
  collisions against an external `CollisionShape` from physics — cloth
  never checks against itself.
- **Rigid-body rotation.** `pro-sim-02` gives a "Rigid body" with no
  rotation, labeled as such in the panel (H4 [И4]); full rotation with
  joints is "a solver port after phase 4" (§7 #6, an owner decision on the
  ROADMAP's "Not doing: rigid bodies with rotation and joints").

**Sculpting beyond the measured budget.** `pro-sc-01` is a measurement, not
an implementation, and since this line was written the measurement has
landed in §6: on macOS (an M3 Pro), opening a 1.2-million-triangle sculpt
cube along with building its BVH costs 3.3–5.7 s (the 3 s threshold — not
met), and the stroke itself (selection + edit + normals + overwrite +
raycast) costs 294–1005 ms (the 8/16 ms thresholds — missed by 20–60×, the
bottleneck being a full mesh-wide normal recompute). *Amended 2026-09-13,
after this section was agreed: Chrome was also measured the same day*
(opening+BVH 24.2–24.4 s, a stroke 7.58–7.71 s, both thresholds equally
unmet) *— nothing below changes because of this, only the count of measured
platforms.* The Galaxy A55 remains unmeasured — `pro-sc-01` is flagged in
`doc/plan-status.json` as `"partial"` for exactly this reason, not as
finished. The `pro-sc-09` decision (the web-profile triangle limit) is
still open — what's already measured says chunking (`pro-sc-02`) is needed
before a stroke becomes interactive at 1.2M, but the actual number for the
web waits on the remaining platform's measurement. This is the same
mechanism as the rest of this list: `pro-sc-02..09` are already part of
phase 4 at the scope the plan named, and any expansion of sculpting beyond
what a full (all three platforms) `pro-sc-01` measurement confirms is not
part of phase 4 and not part of this plan at all, until the owner opens a
dedicated line for it based on the actual numbers.

**Collaborative editing.** Not part of the flutter3d plan at all — not in
phase 4, not after it. It's listed as a "missing aspect" found by the
2026-09-09 critique while checking against the design handoff archive (§10,
"critique edits": twelve missing aspects, one of them "collaborative work
(`pro-after-01`)"); in the original archive it belongs to phase 4 of the
development plan and to the handoff README (`doc/model-editor.md`) as
something this phase lays groundwork for. This very line (`pro-after-01`)
closes the aspect — not by implementing it, but by explicitly naming it out
of scope and pointing at the one piece of groundwork that already exists
for it, independent of any decision about collaborative editing:

- the `doc-16` command journal — the `CommandJournal` class
  (`packages/flutter3d_model_core/lib/src/command_journal.dart`): a
  line-by-line JSON Lines journal of successfully run commands with an
  author and transaction markers, restoring a project through `replay`
  byte-exact; `mcp-12n` already writes every command of an agent session
  into it;
- commands as values — the `sealed class ModelCommand`
  (`packages/flutter3d_model_core/lib/src/command.dart`, doc comment "One
  change, as a value."): every document edit is a serializable value with
  its own `arguments`, not an imperative call, which is the only reason the
  journal can replay anything at all.

Neither one solves collaborative editing — there's no network, no
conflict resolution between authors, no OT/CRDT over `ModelDocument`. This
is only what such work could be built on, if the owner decides to start it
as a separate track after phase 4.

---

## 6. Engine changes

Every item with `engineChange = true` after merging duplicates — 46. Each
one is also needed by games; each passes conformance, a golden frame, or a
round trip, like any engine change. The "contract" mark means a
`GraphicsDevice` change — all four backends, `testing_fake_backend.dart`,
and a minor shelf bump (§7, item 13).
| # | id | what | package | phase | check |
|---|---|---|---|---|---|
| 1 | doc-01 (+ mesh-03) | two pure vocabulary packages (2026-09-09 decision): `geometry` — geometry/*, `Ray`, `TriangleBvh`; `formats` — the document, `lighting_model`, `model_loader`'s synchronous half, f3d/gltf/obj/fmat, animation; `flutter3d` re-exports both | engine → geometry + formats | 0 | 4322 tests with no import edits; scanner; `bench_geometry.dart` builds AOT as a separate main |
| 2 | fmt-01 | `compareModelDocuments` in lib | formats | 1 | a per-category test via breakage |
| 3 | fmt-02 | `PlainModelDocument`, `sniffImageMimeType` | formats | 1 | tests ported |
| 4 | fmt-03 | `authoredAttributes` + section 17 | formats | 1 | old `.f3d` files read as "all" |
| 5 | fmt-04 | `meshName`, `asset`, `sourceUri` + sections 18–20 | formats | 1 | round trip; old files with null |
| 6 | fmt-05 | `TextureSampling.mipLinear` | formats | 1 | golden unchanged |
| 7 | fmt-06 | `GltfWriter` (GLB, `.gltf`+`.bin`) — in `formats`, so MCP can export with no Flutter | formats | 1 | round trip on 8 models; fmt-10/11; `dart test` with no SDK |
| 8 | fmt-07 (+ anim-26) | skins, animations, morphs in `GltfWriter` | formats | 1 | 7 rigged round trips; a pose at t=0.5 |
| 9 | fmt-08 | `ObjWriter` + `.mtl` | formats | 1 | a round trip by triangle set |
| 10 | fmt-09 | `StlLoader`, `ModelFormat.stl` | formats | 1 | five fixtures; sniff; sendable |
| 11 | fmt-11 (+ qa-09) | the glTF Validator in tests/CI | engine + tool | 1 | a broken min/max → an error |
| 12 | fmt-12 | writer `warnings`, `ExportReport` | formats | 1 | OBJ loses a skin → a warning |
| 13 | fmt-13 | `encodeModelInIsolate` (a `kIsWeb` wrapper) | engine | 1 | isolate bytes = synchronous |
| 14 | fmt-14 | `convert_asset -f` | engine | 1 | a GLB from `.f3d` passes the validator |
| 15 | fmt-15 | Draco/meshopt — a loud skip | formats | 1 | 0 surfaces + a warning |
| 16 | fmt-16 | documents and `boundaryEnumExempt` | engine + docs | 1 | scanner |
| 17 | view-03 | ortho zoom, `frameBounds` for ortho, `animateTo` in `OrbitController` | engine | 1 | an ortho-zoom test |
| 18 | view-05 (+ qa-10) | `MeshOverlay`, the `mesh-overlay` scene, 43 → 44 | engine | 1 | four sets, 0 pixels |
| 19 | view-06 | an `OverlayVertex` stage (conditional per view-01) | shaders + 4 backends | 1 | `mesh-overlay` within tolerance; `manifest_test` |
| 20 | view-09 (+ mesh-20, p0-10) | `TriangleBvh` in `geometry`; `Raycaster` over the tree | geometry + engine | 1 | 10k rays = brute force |
| 21 | view-14 (+ pro-eng-01, qa-11, p0-06) | **contract** `overwriteGeometry`; `DeviceMesh.overwrite`; conformance 33 → 34 | hw + 4 backends + engine + conformance | 2 (1 per p0-06) | conformance across four; a manual Impeller run with a date |
| 22 | ui-18 | `BinaryStorage`/IndexedDB in `flutter3d_screens` | screens | 1 | an in-memory Storage test |
| 23 | ui-20 | `WebGlDevice` resize or device recreation | webgl / backend | 1 | a resize conformance check, if changed |
| 24 | ui-27 | a new `flutter3d_editor_widgets` package | new package | 2 | the level editor's tests after the move |
| 25 | view-07 | `MeshData.edgeIndices`, a `MeshWireVertex` stage, wireframe on every backend | engine + shaders + backends | 2 | scene `wireframe-edges`; `wireframeDeclined` is never true |
| 26 | view-15 | `SceneSurface.views:` | session | 3 | a CPU test with two views |
| 27 | view-17 (+ anim-24) | `FrameResult.triangles`/`instances` | engine | 3 | a cube + instances = the formula |
| 28 | fmt-19 | `extras`, `KHR_texture_transform` passed through end to end, section 21 | engine | 2 | byte-exact JSON fragments |
| 29 | fmt-20 | `StlWriter` | engine | 2 | `84 + 50·count` |
| 30 | fmt-21 | KTX2 through `GltfWriter` (`KHR_texture_basisu`) | engine | 2 | the loader reads it |
| 31 | fmt-22 (+ mat-30) | `Ktx2Writer` + BC1/BC3/ETC2 (a ROADMAP item) | engine | 2 | PSNR ≥ 30 dB; conformance |
| 32 | fmt-23 | Basis ETC1S: a decision and a spike | engine | 3 | transcode via the existing reader |
| 33 | anim-01 | `Pose` and FK with no scene | engine | 3 | = `Skeleton.matrices` (1e-5) |
| 34 | anim-02 | `SkinBlend` | engine | 3 | = `MeshSkinnedVertexShader` (1e-4) |
| 35 | anim-14 | `TwoBoneIk`, `FabrikIk` | engine | 3 | a target within 1e-4; the pole |
| 36 | anim-16 | `AnimationPlayer.rootMotionDelta` | engine | 3 | a per-cycle sum |
| 37 | anim-27 | a shape name in `F3dRecord.morphTarget` | engine | 3 | a name round trip |
| 38 | pro-eng-02 | **contract** `overwriteTexture` | hw + 4 backends | 3 | a region readback |
| 39 | pro-eng-03 | `Renderer.renderPost` with an external HDR | engine | 4 | a `post-only` scene |
| 40 | pro-eng-04 | `TiledProjection` | engine | 4 | 2×2 tiles = the frame |
| 41 | pro-eng-05 | `FrameResult.passes` | engine | 4 | bloom absent when disabled |
| 42 | pro-eng-06 | LOD in `ModelDocument`, `.f3d`, `ModelAsset`, `MSFT_lod` | engine | 4 | scene `lod-asset` |
| 43 | pro-eng-07 | fixed-width ribbons in the overlay | engine | 4 | scene `overlay-ribbon` |
| 44 | mat-17 | `.hdr` and a float environment | engine + conformance | 4 | float-cube conformance; `ibl-hdr` |
| 45 | fmt-27 | `UsdzWriter` (on demand) | engine | 4 | Quick Look on a device |
| 46 | fmt-28 | light and cameras in the vocabulary, `KHR_lights_punctual` | engine | 4 | a round trip |

After the 2026-09-09 decision the "package" column reads as: `geometry` and
`formats` — two pure vocabulary packages, `engine` — what stays in
`flutter3d` (the isolate wrapper, `convert_asset`, rendering, overlays,
`Pose`), `hw` — the `GraphicsDevice` contract and the four backends. Format
writers (fmt-01..09/12/15) all live in `formats`; only fmt-13 and fmt-14
stay in the engine from formats.

Beyond these: doc-25 (a public `SurfaceMaterial ↔ Map` codec in fmat.dart,
S) folds into doc-10; rel-13 (`make_templates.py` via `dart run
flutter3d_model_core:export`) is a tooling change, not an engine one; ui-29
is consumer #21. The FBX reader (fmt-24/25, the `flutter3d_fbx` package
over `formats`, fmt-29d) is not an engine change and isn't in the table:
`flutter3d` doesn't re-export it, the decoder is registered by the editor.

---

## 7. Conflicts with the ROADMAP and ARCHITECTURE

One list, each with a proposed resolution. ROADMAP text edits happen at the
revision date (September 28), as it itself requires; 2026-09-09 owner
decisions closed #34 and #36 and shifted the wording of #3, 5, 11, 12, 24,
28, 31, 37.

| # | Against | Who touches it | Resolution |
|---|---|---|---|
| 1 | ROADMAP, the level editor's acceptance: "zero changes inside the engine's own sources made for the editor's sake" | mesh-03, doc-01, view-05/07/09/14/17, mat-03/17, ui-18/20, pro-eng-*, qa, rel-12 | rel-12 opens a separate model-editor track with its own Acceptance; the level-editor wording doesn't extend to it; each of §6's 46 changes is named as an engine capability with a caller outside the editor (games: per-triangle collisions, deformable meshes, an HDR sky, asset export) |
| 2 | ROADMAP: "every edit is a command object with apply and revert" | doc-05, doc-08, ui-11, qa-18 | doc-29: the ROADMAP is rewritten to what the code does (a level's own snapshots, a model's own prior value, no inverse commands anywhere); ARCHITECTURE §8.7 explains the three undo models |
| 3 | ROADMAP "Not doing: Node-graph materials" | mat-10..13, pro-rn-03, ui-27, pro-eng-03 | add to "Not doing": "a fixed set of nodes that bakes into texture slots is not that"; in the design, "node graph" → "texture compositor," "compositing graph" → "a graph over fixed passes"; proof — the engine's golden frames don't change, `LightingModel.builtIn` doesn't grow. 2026-09-09 owner decision (G1 [Ж1] closed): a texture compositor with a fixed node set; the ROADMAP's node-graph wording changes at the September 28 review |
| 4 | ROADMAP §Rendering: "eight lights is a ceiling on the scene today" | mat-23 | `LightBuffer.gatherNear` / `gatherNearFrom` already selects eight per object (light_lists_test) — the text fell behind the code; fix at the revision, the plan counts "8 per object" |
| 5 | ROADMAP: soft bodies, "the solver and its collisions are the committed part," but nothing's in Committed | pro-sim-01 | the owner decides whether `flutter3d_cloth` goes into the ROADMAP as that same solver (then moves into `flutter3d_physics` later) or stays editor-only; 2026-09-09 decision (C3/H1 [В3/И1]): cloth is a separate flat `flutter3d_cloth` solver in phase 4 with an API only against `CollisionShape`; it doesn't claim the ROADMAP's Committed line about soft bodies, moving into `flutter3d_physics` is a separate decision after phase 4 |
| 6 | ROADMAP "Not doing: rigid bodies with rotation and joints" | pro-sim-02 | a "Rigid body" chip with no rotation, labeled in the panel; rotation only as a solver port after phase 4 |
| 7 | ROADMAP puts animation export in phase 3 | fmt-07 | do it in phase 1: a writer with no skins silently loses imported data; anim-26 merges in |
| 8 | ROADMAP: Draco/meshopt readers at the end of the quarter | fmt-15 | not a conflict: an honest refusal comes first, readers replace the skip later |
| 9 | ROADMAP: `KHR_lights_punctual` on the rendering track | fmt-28, mat-23 | the vocabulary (`ModelLight`/`ModelCamera`) is added by fmt-28, the rendering track consumes it; coordinate so it isn't built twice |
| 10 | ROADMAP "Two tiers, and only two," eight committed tracks (green main, editor, strategy, rendering, terrain, backends, measurement, games) | rel-12 | a ninth track joins, moving something down at the same revision date; candidates — the rendering track's tail (decals) or measurement; the owner decides |
| 11 | ROADMAP "A level editor in the browser — after this quarter" versus a phase-1 web model editor | rel-10, ui-14 | record in the ROADMAP: the web model editor arrives earlier because it's where file writing gets solved for the first time; 2026-09-09 decision (F1 [Е1]): the web is a phase-1 equal-footing platform, p0-02/p0-08 are quality gates, not a choice |
| 12 | ROADMAP "exporter from a modelling tool" after the quarter; FBX not listed | fmt-24/25, fmt-29d | the glTF writer appears here, a Blender exporter stays separate; FBX — its own reader in Dart in `flutter3d_fbx` over `formats` (E7 [Д7] closed 2026-09-09), fmt-26 dropped; the ROADMAP still doesn't list FBX — it's an editor package, not an engine one |
| 13 | ARCHITECTURE §7.1: "changing any of these breaks a backend, and that is the bar"; §16: `^0.6.0` doesn't cover 0.7 | view-14, pro-eng-02, qa-11 | one contract change per phase; a PR touching all four backends + the fake + conformance; "visible from the next pass" semantics recorded in the contract; shelf versions bump in one commit, "shelf 0.7.0"; an Impeller `conformance.sh` run with a date in the HANDOFF |
| 14 | ARCHITECTURE §3.2/§13/§16 and README: package, test, publishing-order, scene, and check counts | mesh-00, doc-02, qa-02/10/11/16, rel-03/07, view-05/22, fmt-16 | in the same commit as the directory/test/scene; the numeral lists in rules.dart are extended ahead of time |
| 15 | ARCHITECTURE §4 and `render_settings.dart`: `RenderSettings.wireframe` / `wireframeDeclined` semantics | view-07 | the document is amended in the same PR; the "wireframe drawn as edges or refused" conformance check is untouched |
| 16 | ARCHITECTURE §6.3, environment_map.dart: an 8-bit environment by decision | mat-16, mat-17 | mat-16 stays within that decision (an LDR panorama, labeled); mat-17 is framed as an engine capability for games (an HDR sky), phase 4 |
| 17 | ARCHITECTURE §14: no FFI at runtime | fmt-23 | not decided for the offline converter; an explicit owner decision at fmt-23; on the web and in the editor there's no FFI regardless |
| 18 | ARCHITECTURE §1: "desktop only, not an oversight"; the web on `--wasm`; the engine example has no Android | ui-00, p0-08, p0-01 | the modeler picks a backend through `flutter3d_backend`; if `file_selector_web` doesn't build under wasm — a JS build as §1's recorded exception; the example's Android runner — a row in §1's platform table |
| 19 | ARCHITECTURE §8.1 promises a Flutter-free `ModelDocument`, but the package declares the Flutter SDK | doc-00/01, qa-03 | the promise becomes a checkable package (doc-01) and a scanner rule on transitive SDK dependency (qa-03) |
| 20 | ARCHITECTURE §15: no additive pose | anim-20 | not a conflict: additive morph weights are what §15 already allows |
| 21 | CONTRIBUTING "Generated files are generated" + libm's history | rel-13, doc-21, qa (risk) | writers quantize coordinates, canonical JSON, comparing geometry with a tolerance rather than by bytes; fixtures are recorded on two OSes |
| 22 | The scanner rule "an enum in a published package is machinery or is not an enum" | mesh-19, fmt-09, qa-06 | `ElementLevel`/`IssueSeverity` — enums with an exemption and a reason; `ModelFormat.stl` changes the exemption text and the "Three decoders" prose; content — sealed |
| 23 | The rule "a step reaches for no clock," "asks no machine" | mesh-00, qa-02 | three packages in `notARepeatableStep` with the reason "an editor, not a simulation step" |
| 24 | doc/model-editor.md §5.1: `flutter3d_model_core → flutter3d` | everything | replaced with `→ flutter3d_formats → flutter3d_geometry` (B1 [В1] closed 2026-09-09: two packages); the working-through §5.1 was rewritten 2026-09-09, ARCHITECTURE — alongside doc-29 |
| 25 | doc §5.2: parametric objects "through the existing Shape"; "1024-element chunks" | mesh-28, p0-05 | `ParametricShape` builds the quad topology, `Shape` is the parity reference; the chunk was a hypothesis before p0-05 |
| 26 | doc §5.5: "a Renderer inside Texture.asImage()" | ui-06 | as in the level editor — `SceneSurface → device.present` |
| 27 | doc §4.3: immutable values | p0-11 | under GC pauses >16 ms, a mutable working mode inside the transaction is allowed — a refinement, not a reversal |
| 28 | doc §5.1: three packages | anim-09/17/21, pro-sim-01, ui-27, doc-01, fmt-29d | up to nine: `geometry`, `formats`, `rig`, `cloth`, `fbx`, `editor_widgets`; `geometry`/`formats` (B1 [В1]), `cloth` (C3 [В3]), and `fbx` (E7 [Д7]) resolved 2026-09-09, `rig` and `editor_widgets` — §8 questions |
| 29 | The handoff README: `ColorScheme.fromSeed` and exact hex values at once | ui-02 | an explicit scheme, seed only for unnamed roles |
| 30 | The handoff README: `selection`/`history` inside `document` | doc-04 | in the `Modeling` session, so the project value is exactly what gets serialized |
| 31 | The handoff README: "heavy operations in an isolate" on every platform | doc-24, p0-07, pro-job-01 | on the web — chunked, yielding to the frame; the README's wording gets clarified per p0-07's outcome; 2026-09-09 decision (F11 [Е11]): a freeze with progress on an indivisible operation is acceptable, a web worker (ui-34d) is a conditional phase-1 item for a freeze longer than 1 s |
| 32 | Screen 12's design: "256 / 256 samples" | pro-rn-02 | "N / M tiles" and "supersampling"; a path tracer is out of scope |
| 33 | Design: an arbitrary influence limit from the profile | anim-32 | ≤4 (the vertex format) and ≤64 (the bundle); more is a new layout outside phase 3 |
| 34 | The design plan §7: the tablet as a second wave, but screens 03/04 in phase 1 | ui-05, ui-21 | **Closed 2026-09-09 (owner decision):** Android/iOS layouts and runners — phase 1 (ui-21 moved, §2.12 footnote ⁴); phase 1 ships on four platforms, the iPad and account — rel-19d; the design plan §7 is amended accordingly |
| 35 | The macOS sandbox is off in the level editor ("Under the sandbox that is `PathAccessException`" — from writing via rename) | ui-14, ui-20, p0-13n | the modeler has it on, but the p0-13n phase-0 spike chooses the write method (`saveFile` + a direct write, or a security-scoped directory); two entitlement files (Debug without, Release with) — question F4 [Е4] |
| 36 | The design plan §1: the product's third differentiator — "Scene and composition with no tool switch. Assets are assembled into the scene right here, not only in the engine"; the plan reduces "Scene" mode to light/environment/shadows/post (G4 [Ж4]), doc-11 rebuilds a project from a document each time, no merging or placing assets | G4 [Ж4], mat-24, doc-11 | **Closed 2026-09-09 (owner decision):** composition stays — doc-11a-n (`ImportInto`) is unconditional in phase 2, mat-24 is extended with placing assets via a gizmo and exporting the scene as one GLB; the design plan §1's third differentiator is preserved |
| 37 | The handoff README (hi-fi accuracy): the viewport — `radial-gradient(120% 100% at 50% 0%, #1A1E1F 0%, #0E1112 70%)`; G7 [Ж7] chooses a flat `#0E1112` | view-02, G7 [Ж7] | the gradient is buildable — `SkySettings` (view-02) or a full-screen unlit quad behind the scene on every backend; owner decision: flat in v1 with the divergence recorded, or the gradient via `SkySettings` with a golden frame. Still open (G7 [Ж7]); of the visual divergences from the handoff README, the neighboring icon question was closed 2026-09-09 (F12n [Е12n]: the SDK's `Icons` with a mapping table in ui-02); the gradient decision is unrelated |

---

## 8. Open questions

Duplicates from eleven aspects are merged, questions grouped; each carries a
recommendation where one follows from the working-through or the code. The
letter and number are what the §5 milestones reference. Of 87 rows, 24 are
closed: B1 [В1], F2 [Ж2], and D4 [Г4] — by the 2026-09-09 critique, 21 more
(A2, B1 [Б1], B3, B8, B9, C3 [В3], C5 [В5], C8 [В8], D2 [Г2], D9 [Г9], E7
[Д7], F1 [Е1], F2 [Е2], F5 [Е5], F8 [Е8], F11 [Е11], F12n [Е12n], G1 [Ж1],
G4 [Ж4], H1 [И1], K2) — by 2026-09-09 owner decisions, with B1 [В1]
rewritten along the way; a closed question's row starts with "Closed …" in
the answer column. 63 remain open.
### А. Timing and the rig

| # | Question | Recommendation |
|---|---|---|
| А1 | Phase-1 start date: critical-path answers (p0-04/05/09) by 2026-09-25, the rest by 2026-10-05 — confirm or shift; phase 0 competes with ROADMAP dates (September 28, October 26) | accept 2026-10-05 as the phase-1 start, if В1 is resolved by September 25 |
| А2 | The "tablet with a pen" device for p0-03: an iPad (none physically available) or an Android tablet | **Closed 2026-09-09 (owner decision):** a physical iPad with a Pencil and an Apple Developer account are purchased by mid-phase-1 (rel-19d, S, owner); before purchase, the iPad row in p0-03 (and the phase-0 table in doc §6) stays unmeasured and is recorded as such, p0-03 is re-measured after rel-19d |
| А3 | Is the p0-01 stress scene the same "stress scene on the software backend" from the ROADMAP's "Measurement"? | yes, one scene and one draw-call baseline (view-22) |
| А4 | The web-profile budget threshold: 16.6 ms at 1M, or 33 ms, since the viewport isn't the only thing Flutter draws | choose before measuring; ≤16.6 → a 1M budget, 16.6–33 → ≤300k (p0-02); the web's equal footing doesn't depend on the threshold (Е1) |

### Б. Core data structures

| # | Question | Recommendation |
|---|---|---|
| Б1 | Non-manifold input: split edges with ≥3 faces on import and show it as a problem, or a radial structure following BMesh | **Closed 2026-09-09 (owner decision):** split on import and flag as a problem (mesh-13, mesh-27); no radial structure |
| Б2 | Element id stability: tombstones + `compact()` with `IdRemap`, or dense ids with renumbering | tombstones — needed by the operation card, the journal, and `Selection` in MCP (doc-07) |
| Б3 | The 0.3 criterion "≤10% of a full copy": on an adjacent 1% or a random one; chunks or a log of prior values | **Closed 2026-09-09 (owner decision):** undo for meshes — persistent values with structural sharing (mesh-10/11, doc-08); chunking versus patches, and with it which distribution the ≤10% bar applies to, is measured by p0-05/mesh-02 — already a measurement, not a question |
| Б4 | Do parametric objects build their own quads, with `Shape` as the parity reference (diverges from §5.2)? | confirm (mesh-28/29) |
| Б5 | Which attributes go per corner, which per vertex | UV and color per corner, position/joints/weights/shape keys per vertex (mesh-12) |
| Б6 | `materialSlot` per face in phase 1? | yes: a GLB with several materials needs `MeshData` per slot (mesh-14, doc-12) |
| Б7 | Enum versus sealed for the selection level, severity, mode | `ElementLevel`/`IssueSeverity` — enums with an exemption; content (geometry, modifiers, commands) — sealed (qa-06, mesh-19) |
| Б8 | Sculpting: `SculptMesh` as a separate flat structure (pro-sc-02), or a patch layer over `EditMesh` (mesh-72) | **Closed 2026-09-09 (owner decision):** `SculptMesh` with multiresolution (pro-sc-02/07); a dirty chunk = a contiguous buffer range; pro-sc-01 measures, doesn't choose |
| Б9 | Multiresolution or dynamic topology | **Closed 2026-09-09 (owner decision):** multiresolution (pro-sc-07); screen 08 gets a "Subdivide" button instead of "brush density" (ui-29) |

### В. Packages and publishing

| # | Question | Recommendation |
|---|---|---|
| В1 | **Closed 2026-09-09 (by critique, rewritten by owner decision).** The vocabulary package: name and contents | **Closed 2026-09-09 (owner decision):** two packages instead of one, phase-0 deadline 2026-09-25. `flutter3d_geometry` — `MeshData`, `VertexLayout`, `Shape`/`LatheShape` and derivatives, tangents, `morph_target`, `CpuMesh`, `math/intersections`, `Ray`, `TriangleBvh`; `flutter3d_formats` — `ModelDocument`, `SurfaceMaterial`, `MaterialDocument`/`MaterialHint`, `lighting_model`, `model_loader`'s synchronous half, gltf/obj/f3d/ktx2/stl decoders, writers `F3dWriter`/`GltfWriter`/`ObjWriter` (fmt-01..09/12/15; only fmt-13/14 stay in the engine — otherwise `flutter3d_model_mcp` can't export a GLB (doc-21) and can't start with no Flutter (rel-04)). `formats → geometry`, `mesh → geometry`, `model_core → both`, `flutter3d` re-exports both; §16 publishing order: geometry → formats → flutter3d; 33 packages by the end of phase 0 |
| В2 | A fourth package `flutter3d_rig` (retargeting, auto-rig), or all of it in core, or in the engine | `rig` — algorithms over `Pose`/`ModelDocument`, not needed by games; weights — in `flutter3d_mesh/skin/`; `Pose` and IK — in the engine |
| В3 | `flutter3d_cloth` separate, or a `flutter3d_physics` subfolder | **Closed 2026-09-09 (owner decision):** a separate `flutter3d_cloth` solver in phase 4 — a flat package depending only on `CollisionShape` (pro-sim-01); И1 closed by the same answer |
| В4 | The `.fmat`-write gate (mat-03): in `flutter3d_editor_core`, with the modeler depending on it for one library, or duplicate it | in `editor_core` (one gate for two editors), but only after doc-01: the library takes a `MaterialDocument`/`MaterialHint`, and `editor_core` is a flat package that can't pull in the Flutter SDK; `editor_core` picks up a dependency on `flutter3d_formats`, the §16 tier shifts (rel-03); an alternative — the library in model_core, the level editor imports from there. In phase 2 — alongside `FieldRow` in `flutter3d_editor_widgets` (ui-27) |
| В5 | Names: mesh / model_core / model_mcp / modeler, or one shared root; reserve on pub.dev?; where does the code live | **Closed 2026-09-09 (owner decision):** the code lives in this monorepo — the packages join the workspace, the structure scanner, CI, and the §16 publishing order (qa-02/03/04, rel-02/03); names — mesh / model_core / model_mcp / geometry / formats and `flutter3d_modeler`; don't reserve with a placeholder, recheck before rel-06 (rel-01) |
| В6 | `bin/` utilities: `flutter3d_mesh:check`, `flutter3d_model_core:export` | `core:export` — yes (needed by rel-13); `mesh:check` — no, unnecessary public surface |
| В7 | New-package versions: 0.1.0 or the shelf number (0.7.0 after the HAL change) | the shelf number (§16: one number, one tree) |
| В8 | First publish: the December 27 set, or the first 2027 set | **Closed 2026-09-09 (owner decision):** the first publish and release come only once phase 1 is in the hands of its first users (rel-16 → rel-06); December 27 is not the target, before that it's "in order, not out," like strategy |

### Г. The document, history, the format, MCP

| # | Question | Recommendation |
|---|---|---|
| Г1 | The project file's magic number and autosave location (next to the file, or in the app directory); the `.f3dproj` extension is closed by the 2026-09-09 decision (Г2) | magic `F3DP`; autosave in the app directory via `Storage` (ui-18) |
| Г2 | Should history live in the project file (the handoff README)? | **Closed 2026-09-09 (owner decision):** yes — its own `.f3dproj` with history: a `history` section in the container (doc-09, doc-31d), a step = `says` + the command + a reference to the prior value through chunks already sitting in the file as blobs; the Г5 limit applies to the file; "save without history" — an option (ui-33d); the doc-16 journal stays. Acceptance round trip: save → open → undo three steps |
| Г3 | `Selection` in mesh command arguments and `select` as a verb — isn't that two paths for the UI? | both, as proposed (doc-04/07): object commands carry ids, mesh commands carry a `Selection` |
| Г4 | The language of `says` and tool descriptions; the parameter-hint type — **closed 2026-09-09**: a dedicated sealed `ParamHint` in core | **Closed 2026-09-09 (by critique, the language confirmed by owner decision):** English in the core, MCP, and `says`, localization in the app (ui-22, Russian and English from the first version — Е2); hints — a dedicated `ParamHint` (Int / Double / Bool / Enum / Vector3, `step`, `unit`, a range), because `MaterialHint` only has `RangeHint(double, step)`, `ColorHint`, `TextureHint`, `EnumHint` — no integers, no flags, no units — and `material_hint.dart` pulls in `LightingModel`; `MaterialHint` stays the material panel's (syn-01) |
| Г5 | History depth: 64 steps or a byte limit | both (doc-08); the byte number comes from p0-05 |
| Г6 | PNG with deflate: a from-scratch encoder, `package:archive` in core, or raw RGBA in the project with PNG only in the app; and decoding (the graph's Image node, mat-09n) — the repository has not one pure PNG/JPEG decoder (golden reads via `dart:ui`, `cpu_png.dart` only writes) | raw RGBA in the project always; for MCP export with no Flutter — `package:archive` in core (mat-12); the decoder — `package:image` in core or a from-scratch inflate + baseline JPEG (mat-09n); if neither — a pixel-free graph in core and baking via `dart:ui` in the app, in which case `bakeTextureGraph` from mat-32 becomes impossible and that's recorded |
| Г7 | `json_write_through.dart` from `flutter3d_sim`: a copy in core, or a shared package | a copy (~100 lines), a reverse dependency on sim is unacceptable |
| Г8 | MCP creates a new project at a non-existent path; the default profile | yes (doc-19); the `desktop` profile |
| Г9 | Export with an error-level `Issue`: refuse or warn | **Closed 2026-09-09 (owner decision):** warn and export after explicit confirmation; refuse only on empty geometry (doc-14, ui-17; §5.2 acceptance) |
| Г10 | Should the original imported file be stored verbatim in the project? | no in v1 (doubles the size); an option later (fmt-18) |

### Д. Formats

| # | Question | Recommendation |
|---|---|---|
| Д1 | STL as a built-in `ModelFormat.stl` (an exemption edit), or an external decoder | built-in (fmt-09) |
| Д2 | `authoredAttributes` on `ModelSurface` or on `MeshData` | `ModelSurface` (fmt-03) |
| Д3 | `extras` and `asset` in the vocabulary and in `.f3d`, or only on the glTF writer | in the vocabulary ("open, and without a registry"), by `.f3d` section per field (fmt-04/19) |
| Д4 | Skins/animations/morphs in `GltfWriter` in phase 1 or 3 | phase 1 (fmt-07) |
| Д5 | Does the `gltf` package (the Khronos validator) resolve under SDK ^3.12? | a half-day spike; otherwise `npx` in CI or a homemade checker (fmt-11) |
| Д6 | Compression families by profile (ETC2/ASTC/BC/ETC1S), and is FFI to libbasisu acceptable in the offline converter | fmt-22 in Dart for `.f3d`; Basis — fmt-23's decision before phase 3; no FFI on the web or in the editor |
| Д7 | FBX: a dedicated reader (fmt-24/25, two Ls) or a server only (fmt-26); where is it hosted | **Closed 2026-09-09 (owner decision):** a dedicated reader in Dart — fmt-24/25 (two Ls) in phase 2, a separate track, after phase 1 is in hand (rel-16); the `flutter3d_fbx` package, flat, depends on `formats` (fmt-29d); server-side conversion, fmt-26, is dropped — not doing it |
| Д8 | USDZ: is there demand; does Quick Look accept usda | a device spike before any estimate (fmt-27) |
| Д9 | Light and cameras in `ModelDocument`: who adds them — the rendering track or fmt-28 | fmt-28, the rendering track consumes it |
| Д10 | A second UV set (`texcoord1`) for AO/lightmaps | not in phase 4; AO on the main UV |
| Д11 | Replace `tool/make_models.py` with the Dart `GltfWriter`? | yes, after rel-13, one regeneration |

### Е. Shell, platforms, the web

| # | Question | Recommendation |
|---|---|---|
| Е1 | The web at launch — equal footing or view-only; is a JS build acceptable if `file_selector_web` doesn't build under wasm | **Closed 2026-09-09 (owner decision):** the web is an equal-footing platform from the first version, not "measurements decide"; p0-02/p0-08 stay quality gates: an unmet threshold becomes a phase-1 item (a JS build as ARCHITECTURE §1's recorded exception, chunks instead of an isolate, a worker ui-34d if needed) |
| Е2 | English from the first version | **Closed 2026-09-09 (owner decision):** Russian and English from the first version — a ru template + en (ui-22); the core, MCP, and `says` — English (Г4) |
| Е3 | Phase 2–4 modes in the switcher: disabled or hidden | disabled — the README requires five segments to always be present |
| Е4 | macOS sandbox: two entitlement files (Debug without, Release with) or one; and how to write a file under `user-selected.read-write` if `writeFileAtomically` renames into a directory with no access (the reason the level editor turned the sandbox off) | two; relative `--dart-define` paths only live in Debug; the write method — from p0-13n in phase 0 (`saveFile` + a direct write, or a security-scoped directory), after which ui-14 rewrites the native branch |
| Е5 | The hotkey set | **Closed 2026-09-09 (owner decision):** Blender-like (G/R/S/E/I, 1/2/3, Tab) wherever it doesn't conflict with the platform; listed in help (ui-32n) |
| Е6 | Autosave on the web: localStorage via `Storage`, or an IndexedDB extension | `BinaryStorage` in `flutter3d_screens` (ui-18), a repository-package change — needs agreement |
| Е7 | Opening files from the system (Finder, an intent, DocumentBrowser) | phase 2 |
| Е8 | macOS signing and notarization for phase 1 | **Closed 2026-09-09 (owner decision):** "right-click → Open" in phase 1; an Apple Developer account and an iPad are needed by mid-phase-1 (rel-19d), because iOS is a phase-1 platform |
| Е9 | The feedback channel: Issues with a label only, or also Discussions | Issues + an in-app button (rel-15); Discussions on demand |
| Е10 | The tutorial asset: a Khronos model or a "purchased asset" | Khronos from `flutter3d_samples` (the license already exists) |
| Е11 | Is a UI freeze on the web during an indivisible operation acceptable before phase 2 | **Closed 2026-09-09 (owner decision):** yes, with progress in the button's place; a web worker is a conditional phase-1 item (ui-34d) if p0-07/p0-08 show a freeze longer than 1 s |
| Е12n *(added by critique)* | The icon set: the handoff README requires Material Symbols Outlined (weight 400), which in Flutter means the external `material_symbols_icons` package (Apache 2.0, several MB of font in the bundle); the SDK's `Icons` — no dependency, but some glyphs differ | **Closed 2026-09-09 (owner decision):** the SDK's `Icons` with a mapping table in ui-02; not taking `material_symbols_icons` |

### Ж. Rendering, materials, modifiers

| # | Question | Recommendation |
|---|---|---|
| Ж1 | "Node graph" → "texture compositor," mat-10's node set; the ROADMAP entry | **Closed 2026-09-09 (owner decision):** a texture compositor with a fixed node set (mat-10); the ROADMAP's node-graph wording changes at the September 28 review (§7 #3) |
| Ж2 | Parameter hints for nodes and modifiers: `MaterialHint` as-is, or a shared `ControlHint` in the engine — **closed 2026-09-09** | `ParamHint` from core (Г4) for nodes, modifiers, and commands; `MaterialHint` stays the material panel's only; the engine isn't touched |
| Ж3 | A modifier: one `enabled` flag, or `enabled` + `showInViewport` | one, in v1 |
| Ж4 | "Scene" mode v1: light/environment/shadows/post only, or also placing assets and reflection probes; the design plan §1 names asset composition the product's third differentiator (§7 #36) | **Closed 2026-09-09 (owner decision):** light/environment/shadows/post plus placing several assets — doc-11a-n (`ImportInto`) unconditionally in phase 2, mat-24 extended with placement and exporting the scene as one GLB; §7 #36 closed; reflection probes are out |
| Ж5 | Texture-budget numbers per preset, and the default bake resolution | desktop 2048/256 MB, mobile 1024/64 MB, web 2048/128 MB; a 1024 default bake resolution — to be agreed |
| Ж6 | HDRI: an LDR panorama in phase 2, or `.hdr` with a float environment | LDR (mat-16) in phase 2, labeled; mat-17 in phase 4 |
| Ж7 | The viewport background: flat `#0E1112`, a `SkySettings` sky, or the radial gradient from the handoff README (hi-fi) | flat in v1; the gradient is buildable on every backend — `SkySettings` (as view-02 already proposes) or a full-screen unlit quad, not "impossible"; the divergence from the README — §7 #37 |
| Ж8 | Point vertices: quads everywhere, or `PrimitiveType.point` where available | quads everywhere — one picture, one golden path |
| Ж9 | Overlay depth offset: CPU or an `OverlayVertex` stage | per view-01(c), a 2 ms threshold |
| Ж10 | `overwriteGeometry` and frames in flight on Impeller: double-buffer `DeviceMesh`, or a backend obligation | the backend buffers; the contract — "visible from the next pass" (view-14) |
| Ж11 | Wireframe on skinned meshes in a pose: a second stage, or the bind pose only | the bind pose, in phase 2 |
| Ж12 | Hover over faces on every mouse move, on a phone | sub-element hover on desktop only; on touch — by tap |
| Ж13 | The default material-preview mesh; a floor with a shadow | a sphere; a floor — yes |
| Ж14 | Wait for the ROADMAP's encoder, or show a computed estimate | a computed estimate (mat-28) right away; mat-30 after fmt-22 |

### З. Animation

| # | Question | Recommendation |
|---|---|---|
| З1 | Four influences as a hard limit, or an 8-influence layout in phase 4 | a hard 4 (anim-32); remove the design's hint at an arbitrary number |
| З2 | 64 bones: "split the mesh by skeleton" as an operation, or just an error | just an error in v1 |
| З3 | IK on export: bake silently or ask; is runtime IK needed in the player | bake silently, recorded in the `ExportReport`; runtime IK — outside this iteration |
| З4 | The root-motion key in extras and `rootMotionDelta` — align with the "animation that adds" track | align at the ROADMAP revision, one API |
| З5 | The time base: seconds (glTF, `AnimationTrack`) or frames | seconds; profile fps only for display and binding (syn-03) |
| З6 | Retargeting v1: humanoid only, or quadruped too | humanoid |
| З7 | The mocap source for screen 14: glTF/GLB only | yes (BVH and FBX are outside the plan until fmt-25) |
| З8 | Facial sets: a standard nomenclature (ARKit's 52) as a template, or custom groups only | custom in v1 |
| З9 | Shape drivers: baked in the project only, or an `.f3d` section for runtime | baking in v1 (anim-20) |
| З10 | The additive pose layer from the ROADMAP: before phase 3 or after | after; the reference pose is the clip's frame 0 |

### И. Phase 4

| # | Question | Recommendation |
|---|---|---|
| И1 | Whose cloth solver: the ROADMAP's own (later into physics) or the editor's forever | **Closed 2026-09-09 (owner decision):** a separate `flutter3d_cloth` solver in phase 4 (В3); it doesn't claim the ROADMAP's Committed line about soft bodies, moving into `flutter3d_physics` is a separate decision after phase 4 (§7 #5) |
| И2 | Simulation export: ≤8 morph targets, a `.f3d` vertex-animation section + a node, or preview only | morph targets in phase 4, the section on demand |
| И3 | Three contract changes (`overwriteGeometry`, `overwriteTexture`, `renderPost`): in phases 2–3, or all at phase-4 start | one per phase: 2 / 3 / 4 |
| И4 | Is a "Rigid body" with no rotation acceptable for phase 4 | yes, labeled (pro-sim-02) |

### К. Quality and publishing

| # | Question | Recommendation |
|---|---|---|
| К1 | Who records the Impeller/WebGL/WebGPU sets for new scenes and runs Impeller conformance | needs the ROADMAP's own nightly macOS machine; until then scenes live in `_provisional`, which view-05's acceptance forbids merging |
| К2 | External export checking beyond the validator: headless Godot in CI, or a manual checklist | **Closed 2026-09-09 (owner decision):** headless Godot in CI — qa-19n (S), as the design plan requires ("opens in Godot and Unity" via an autotest); Unity and Blender — a manual HANDOFF checklist before the phase-1 release |
| К3 | A `tool/structure.dart --recount` that rewrites the numbers in documents | no: the scanner prints the number, a human edits |
| К4 | Where do phase-0 GPU numbers live: the HANDOFF (outside git) or doc §6 | doc §6 (the one copy in git), the HANDOFF duplicates it |
| К5 | What moves down in the ROADMAP to make room for the ninth track | the owner; candidates — decals, measurement |
---

## 9. Risks

Merged from eleven lists; the mitigating action is kept with its id.

| # | Risk | Mitigation |
|---|---|---|
| 1 | A red `main` and three packages under thirty rules: test and package counts, the publishing order, enums, "a public member with no caller," `dashed`/`reload`/`spike` in lib, `DateTime.now()` and `math.sin` under the step rules | qa-01 first; qa-02/03/04/05/06 before the first line of code; `dart run tool/structure.dart` before every commit; numbers land in the same commit as the test (qa-16) |
| 2 | A pure core doesn't resolve with no Flutter SDK (the scanner can't see a transitive dependency) — surfaces at the first MCP host | doc-00 → doc-01 in phase 0; rule qa-03; the rel-04 container check |
| 3 | A persistent mesh's snapshot under scattered edits touches nearly every chunk — §4.3 fails; GC pauses from fresh values every frame | p0-05 (chunks versus a log, two distributions) and p0-11 (the end-to-end pipeline) before mesh-10; `toMeshData(into:)`, a per-transaction snapshot, and on failure a working mode inside the transaction |
| 4 | Half-edge breaks silently: the picture looks right, the next operation crashes ten steps later; loop cut/ring/Catmull-Clark go quiet on a triangulated import | `validate()` after every operation in tests (mesh-11), seeded fuzzing (mesh-32), traversals stop on non-quads with a `report`, `dissolveEdge` restores quads (mesh-25), quads on parametric shapes (mesh-28), a parity test (mesh-29) |
| 5 | Export matches its own loader but not Godot/Unity/Blender; generated attributes make a round trip unreachable | fmt-03 before the writer; fmt-10 (frame against frame), fmt-11 (the validator), headless Godot in CI (qa-19n), a manual Unity/Blender checklist before release (К2 closed 2026-09-09); `compareModelDocuments` with categories and mutations |
| 6 | Byte-level non-determinism (libm, key order, double formatting) breaks fixture diffs across two OSes | coordinate quantization, canonical JSON, Float32 in blobs, comparing geometry with a tolerance; fixtures recorded on two OSes (doc-21, rel-13) |
| 7 | A `GraphicsDevice` contract change breaks all four backends and the fake; an async submit on Impeller reads an already-overwritten buffer | one contract change per phase; a PR covering every backend with a conformance check; "visible from the next pass" semantics and backend-side buffering (Ж10); an Impeller run via `conformance.sh` with a date (view-14) |
| 8 | Recreating `DeviceMesh` on every edit, and an overlay over 200,000 edges every frame, don't fit a frame on a phone or in WebGL | p0-06 and view-01(b,c) before implementation; `MeshLayoutPlan`/`fillVertices` (mesh-14); lines in a version-based persistent buffer, ribbons for the selection only; point thinning (view-13) |
| 9 | A new shader needs `glslangValidator`, `naga`, `impellerc`, and a Dart stage; a forgotten stage fails on one backend | no more than two vertex stages, no fragment ones; `ci.sh` regenerates the tables; `manifest_test` pins `kRequiredShaders` (view-06/07) |
| 10 | Golden scenes are only recorded on macOS with a GPU and in Chrome; between recording sessions a scene in `_provisional` doesn't catch a regression | the CPU set as the first, agreed-upon reference; one scene per PR; `_provisional` empty by merge time (view-05); the К1 machine |
| 11 | BSP booleans blow up in polygon count and time on coplanar meshes, overflow the stack, or hang the UI | an explicit stack, eps from bounds, a polygon budget with a refusal, a coplanarity detector, `Isolate.run` (mesh-47, mesh-30); version-based caching and a live-recompute threshold in the stack (mat-18/20) |
| 12 | There are no isolates on the web: a 100 MB import, booleans, baking, auto-rigging freeze the tab; "in an isolate" from the README is literally unreachable | one runner (doc-24/ui-25) with chunks yielding to the frame; p0-07 decides the shape of operations; the web is equal footing (Е1, 2026-09-09 decision): a freeze longer than 1 s on a reference operation → ui-34d in phase 1; an import limit in the web dialog |
| 13 | The web file stack (`file_selector_web`, `package:web`, wasm, COOP/COEP) works in Chrome and not in Safari/Firefox; a fixed viewport size (`kFixedResolution`) is soap on a 5K display | p0-08 with a browser × action table; rel-10 is checked with the same compiler the site itself ships; ui-20 — device recreation or a `WebGlDevice` resize |
| 14 | Weights and morphs get corrupted by the first topological operation; CPU skinning diverges from the shader; the editor paints "in the wrong place" | layers with inheritance rules in one place (mesh-12/60), full position layers instead of deltas (mesh-61), a `SkinBlend`/`Pose` parity check against the shader's own transcription and `Skeleton.update` (anim-01/02/28) |
| 15 | The 4-influence / 64-bone limits look like a profile setting in the design and like bundle constants in the engine | anim-32: the profile can't accept more, the refusal text names the reason; `RigReadiness` shows the excess before export |
| 16 | Auto-rig's primary weights (envelopes) and retargeting (foot sliding) disappoint | a visibility test and smoothing (anim-22), an honest "primary weights" label, foot planting via IK with a "≤1 cm at 2× height" test (anim-17); heat diffusion — a phase-4 candidate |
| 17 | The compositor graph reads as "node-graph materials" from "Not doing," and mat-10..13 get rejected outright; baking 2048² on the CPU takes seconds to tens of seconds | rename it and record it in the ROADMAP before starting (Ж1); proof — the engine's goldens don't change; a 256² branch-cached preview, full resolution behind a button in an isolate (mat-11) |
| 18 | The project format changes alongside `EditMesh` at every phase-1 step and breaks early users' autosaves; uncompressed PNG makes an 80 MB project | migrations from day one, fixtures for every version kept forever, unknown sections and keys survive a round trip (doc-28, pro-doc-01); raw RGBA with separated blobs, PNG on export (mat-12) |
| 19 | The three layouts drift apart in tool composition; `documents.dart` pulls `dart:io` into the web build; compact density fails contrast and textScaler | a tool table tested against an id set (ui-07); a conditional export from the first commit and a CI web build from phase 0 (ui-14); guideline tests (ui-23) |
| 20 | Localization arrives late: a Russian interface and English core `says` on the same status line | ui-22 before the first panels; the language of `says` decided before model_core (Г4) |
| 21 | Eight sources per object and six shadowed — "Scene" mode will allow more, and light will silently get dropped | the status reads `lightsDropped`/`shadowsDenied` every frame (mat-24); `ExportReadiness` duplicates it as an Issue |
| 22 | Sculpting at 1.2M doesn't fit a frame in Dart; the software rasterizer takes minutes at 4K | pro-sc-01 and pro-rn-01 before the structure and UI; fixed topology + chunks + local normals + overwrite; a web density limit (pro-sc-09); tiles with progress (pro-eng-04), SSAA ×1 by default |
| 23 | Cloth depends on `flutter3d_physics` for collision shapes, while the engine's soft bodies will arrive with a different API | a dependency only on `CollisionShape`; determinism and a fixed step following sim's own rules, so the move is a copy (pro-sim-01, И1) |
| 24 | The `check` CI job's time grows with three `dart test` runs, a browser run, a bench, a wasm build, and app tests, against a 60-minute timeout | every step's time is recorded in `ci.yml` (qa-17); the browser run is mesh-only; the bench is an artifact, not an assertion; over 30 minutes — a separate `modeler` job |
| 25 | Spikes under `tool/` grow into a third geometry engine nobody moves into a package | mesh-01/02 go straight into `packages/flutter3d_mesh`; the p0-08 web spike is a one-time question, README "The answer," "superseded by" after the move (p0-12) |
| 26 | Engine changes for the editor get stuck in review (vocabulary split, HAL) and block the critical path | mesh-01/02 don't depend on the decision; a `TriangleBuffers` fallback is described in mesh-03 (~50 lines of adapter); the В1 deadline — 2026-09-25; the ROADMAP track (rel-12) |
| 27 | There are no first users, or feedback doesn't arrive; "fifteen minutes on any device" stays a promise | rel-09 makes the tutorial a CI test with a measured time; rel-15 an in-app button; rel-16 a personally recruited cohort, the outcome in ROADMAP numbers |
| 28 | `MorphTexture` packs one column per vertex — the texture width caps the vertex count of a morphing mesh (checked: `geometry/morph_texture.dart` — "width the mesh's vertex count, height three rows per target") | the `ExportReadiness` rule is already in phase 1 (doc-14: "vertices with morphs > the profile's `maxTextureSize`"), because morph-target import arrives in phase 1; `rigIssues` (anim-13) and simulation export (pro-sim-05) read the same limit |


---

## 10. Revision history

### 2026-09-14 — the UI pass, the animation screens, the tutorial

Owner decisions after a read of the tree against the handoff, recorded here
because none of them follows from the code alone. The plan that carries them
is `~/.claude/plans/buzzing-herding-starlight.md`; the branch is `modeler-ui`.

**What the read found.** The status file says the `ui-`/`mat-`/`anim-`
aspects are nearly closed, and the tree disagrees in three ways that no row
named. `main.dart` is 3514 lines and nothing pumps it. The mode switcher
enables two modes of eight (`isReady => phase <= 1`) while the material
panel, the animation panel and all four Scene panels exist, are tested, and
are wired to nothing — `mat-24` closed on its tests. And the viewport never
skins: `SceneSync` uploads `VertexLayout.standard` and never sets
`MeshNode.skeleton`, so `skeleton-overlay` is a golden of a `Skeleton` the
test built by hand. Theme tokens drift from the handoff's table in nine
places, and the two editors hold three to four copies of every field control.

**Decisions.** The pass covers both halves — splitting and finishing what
exists, and closing the open rows — on macOS and the web only (`ui-21` stays
deferred). Pro rows stay untouched. Four choices went the more expensive way
on purpose: `RigTemplate` grows the composition options screen 16 draws
(`anim-33d`) rather than the screen losing them; the weight brush becomes a
real `PaintWeights` command so a stroke is one ⌘Z (`anim-10`'s own wording,
which the recipe in `beyondTheCommands` had quietly walked away from);
`ShapeDriver` is persisted (`anim-34d`); Scene mode is wired (`mat-34d`).
The order is the split first, then the shared widget package (`ui-27`), then
the screens; the core rows run alongside.

**The tutorial** becomes its own aspect (§2.15, `tut-`) and moves to
models.pleion.dev; `rel-08`/`rel-09` point there rather than repeating it.
Its screenshots are driven through `mcp-16d`'s UI tools, and each case is a
journal replayed in CI. The design handoff itself now lives in the tree at
`doc/design/modeler-handoff/` — this document has cited it since day one and
the file was never here.

§2's count: 378 → 391 (`doc-36d`, `view-27d`, `ui-37d`…`ui-41d`, `mat-33d`,
`mat-34d`, `anim-33d`, `anim-34d`, `mcp-16d`, `tut-00`).

### 2026-09-13 — after phase 4

`pro-after-01`: §5.6 "After phase 4" was added — a list of what the plan
already called deferred past phase 4 (the path tracer, ABF++, dyntopo,
quadriflow, GPU baking, cloth self-intersection, body rotation; each with
its own reason where it was decided, in §5.5/§7/§8, nothing new decided),
plus a separate item on sculpting beyond the budget that the still-unfinished
`pro-sc-01` measures, and a separate line on collaborative work: not part of
the plan, groundwork — the `CommandJournal` (doc-16) and `ModelCommand` as a
value. Needs separate owner sign-off (`pro-after-01`'s acceptance) — this
edit doesn't provide that.

### 2026-09-11 — checking readiness against the tree

An item's status is a claim, and until now nothing checked it. Now
`tool/verify_plan.dart` does: it reads `doc/plan-status.json`, takes
everything named in backticks from every finished row, and requires it to
be in the tree. The invariant is narrow, and honest for it: it doesn't read
the Russian-language acceptance text, but it does read names, and names are
exactly what rots.

The first run found seventeen rows. Not one was a nitpick:

- **mesh-10 described a structure the measurement rejected.** p0-05 measured
  copy-on-write chunks against a log of prior values: under a scattered
  selection, chunks cost 92–100% of a full copy. The code holds a log
  (`JournalledFloats`, `JournalStep`), while the row had promised
  `PersistentInt32Vector` for a month and a half. The row was rewritten to
  match reality.
- **Eight names had drifted from the code:** `fromMeshData` →
  `importMeshData`, `SelectionLevel` → `ElementLevel`,
  `selectByMaterialSlot` → `Selection.byMaterialSlot`, `nonManifoldEdges` →
  `MeshChecks.all()`, `loadModelInIsolate` → `decodeModelInIsolate`,
  `Modeling` → `ModelHistory`, `MoveElements` → `TransformElements` (one
  command, not three), `saveFile` → `getSaveLocation`, `editor_core` →
  `flutter3d_editor_core`.
- **p0-01 named a rig that doesn't exist:** a `StressSource` in the engine
  example with environment variables. The rig is built in the modeler
  (`staging.dart`, `--dart-define`), and measuring that path — the one a
  document actually opens through — is the right thing to measure.
- **Three statuses were false.** doc-06 and doc-07 are marked "done," yet
  the object commands are missing `AddLathe`, `SetParametric`,
  `AssignMaterial`, `SetOrigin`, `ApplyTransform`, and the mesh commands are
  missing `Separate`. Both became "partial."
- **p0-08 found a gap.** The web spike promised opening a `.gltf` together
  with a neighboring `.bin` via `openFiles`; in the code, `openModel` takes
  one file. On the web, where there's no neighboring directory, a `.gltf`
  has nothing to open with. `ui-36n` was opened.

Three names are absent on purpose, and this is recorded with a reason in
`doc/plan-status.json`: `dashedAxis` exists so the scanner rejects it;
`overwriteGeometry` and `bufferSubData` are a prototype in a separate
branch, as p0-06's own row says; `SkinBlend` and `bindWeights` are what
anim-31's own row assigns to phase 3. The check also flags a stale
exemption: once a name appears, the reason is no longer a reason.

§2's count: 377 → 378 (`ui-36n`).

### 2026-09-10 — an agent that can see; graphics; gap analysis

Three passes in one day, all three additions, none a reversal.

**The `mcp-` aspect (15 items).** `doc-19`…`doc-22` set up a server, a
session of ten verbs, and a tool table — and not one verb is visual: the
agent edits the model blind, knowing numbers and never seeing the
silhouette. Investigation found why the picture can't be handed over today
and why it's cheaper than it looks. The `flutter3d_model_mcp` package is
required to be Flutter-free (a `tool/structure.dart` and
`flat_dart_check.sh` rule), and `GraphicsDevice.present` returns a Flutter
widget — which is why the level editor's own `screenshot` exists and
refuses. But in `packages/flutter3d/lib/`, Flutter is named in **four
files**, all about loading assets: `rootBundle` twice, `kIsWeb` twice,
`dart:ui` for decoding. `Renderer`, `Scene`, `DeviceMesh`, and the pass
graph aren't named. So the obstacle is three points, not something woven
throughout, and `mcp-01n`…`mcp-05n` close them.

This round's decisions: the consumer is an agent alongside a human; the
server in both homes (headless by default, GUI behind a flag); stdio and
local HTTP; every command plus composite recipes; numeric-id addressing;
shared history, the agent only undoes its own; a journal underneath.

**The `gfx-` aspect (17 items, its own phases G1—G3).** Engine changes,
tracked here because the editor is what makes these gaps visible. Priority
is set by observation: a 60-frame budget on a 1440p MacBook, a typical scene
one close-up hero, one or two characters. Four things are named as seen
with one's own eyes: light popping, jagged edges, no distant shadows,
aliasing on the floor.

The order inside G2 is set by two findings. First: filling the surface
buffer turns off MSAA for the whole scene, so SSAO costs the game its
anti-aliasing — a mutual exclusion between two existing capabilities, and
FXAA removes both complaints at once. Second, found by checking rather than
guessing: anisotropic filtering **already exists** in the engine
(`maxAnisotropy` in the HAL, scene `anisotropic-floor`), but
`RenderSettings.anisotropy` defaults to 1 and no demo raises it — the level
editor's bridge gives bricks `min(8, maxAnisotropy)`, an imported model gets
1. Hence G1 is a profiler and two measurements, not immediate fixes: with no
numbers, any order would be an impression.

Ruled out of the track: what "one close-up hero on desktop" doesn't hit —
a sort key, occlusion culling, streaming, geometry compression (the web
matters to the modeler, not games), vertex-shader skinning (the CPU keeps
up with one or two characters), decals, water, terrain, scattering.
Everything under the ROADMAP's "Not doing" isn't proposed again.

**Gap analysis against open-source editors (11 items).** A comparison
against Blender, Godot, Blockbench, Wings3D, Dust3D, ArmorPaint, Material
Maker, meshoptimizer, and xatlas, stage by stage of the game-asset pipeline.
Every "no" was checked by searching this file, not by memory. Four gaps
break the "the asset makes it into the game" promise: collision shapes
(mesh-80n) — not one line existed; snapping to geometry (view-26n) — today
only a grid and an angle; sockets (doc-34n) and repair instead of diagnosis
(mesh-81n) — `MeshChecks` finds everything and fixes nothing. The rest:
texel density as a profile field (doc-35n), vertex-color painting
(pro-pt-06n), an atlas across objects (pro-uv-08n), output-side glTF
compression (fmt-30n), manual retopology (pro-rt-08n), impostors
(pro-lod-05n).

Inverse kinematics went, by owner decision, into the modeler rather than
the engine (`anim-31n`): needed for posing during auto-rigging, while in a
game the pose comes from a clip.

**The count, and an incidental fix.** §2 had 334 items, now 377. A
dependency-graph artifact showed 287 — a extraction bug, not a planning one:
its parser didn't pick up double-hyphenated identifiers, and all 52
`pro-uv-*`, `pro-sc-*`, `pro-rt-*`, `pro-sim-*`, `pro-rn-*`, `pro-lod-*`,
`pro-pt-*`, `pro-eng-*` items dropped out of the graph entirely. The
modeler's phase 1: 120 items and ≈198 weeks → 138 and ≈237. The `gfx-` track
is tracked separately: ≈31.5 weeks, not part of phase 1's sum.

### 2026-09-09 — critique edits

Twenty-five findings and twelve "missing aspects"; each checked against the
tree at `239ccf8e` and against the design handoff archive before being
entered. One line per finding.

- В1 closed: writers fmt-01..09/12/15 moved into a pure vocabulary package
  (then one, under a working name; with the owner decision below —
  `formats`), fmt-13/14 stayed in the engine; fmt-06/08/09 depend on
  doc-01; §3.1, §4.2, §5.1, §5.2, §6, and "In short" reconciled (the
  pubspec's `flutter: sdk`, `flatDartPackages`).
- Phase 1 got the mat-04a-n material panel; `SetTexture`/`AddImage` moved
  from doc-25 into mat-01; §5.2's acceptance requires color and texture in
  the GLB (the design plan: "Basic materials" in phase 1).
- rel-04 no longer depends on doc-19: the `bin/model_mcp.dart --help` stub
  is set up in rel-02, `tools/list` in the container is doc-19's
  acceptance.
- anim-31 narrowed to FK `Skeleton.update` (the code exists); the stroke/
  `SkinBlend`/`bindWeights` measurement — anim-31a-n at phase-3 start.
- Dependencies added: doc-03 ← mesh-11, doc-07 ← mesh-22..26, ui-09 ←
  doc-07/syn-01, ui-26 ← doc-07, mat-01 ← doc-03/05; §4.1 recomputed
  strictly against them (see below).
- `TriangleBvh` got an owner: view-09 (in the vocabulary package — after
  the owner's `geometry` decision, depends on doc-01 and p0-10), mesh-20 —
  `MeshBvh` on top, depends on view-09.
- Г4/Ж2 closed in favor of a dedicated `ParamHint` in core; `MaterialHint`
  stays the material panel's only (`RangeHint` has a step but no integers,
  flags, or units; the file pulls in `LightingModel`).
- Package count: qa-02 extends the numerals to forty; §5.1, qa-16, rel-06 —
  32 packages; doc-01, ui-27, anim-17, pro-sim-01, fmt-24 each carry an
  acceptance-count shift.
- doc-01 moves `render/lighting_model.dart` and `model_loader.dart`'s
  synchronous half (`ModelFormat`, `ModelDecoder`, `sniffModelFormat`,
  `decodeModel`), `kIsWeb` → `bool.fromEnvironment`; the `ModelFormat`
  exemption path is updated.
- mat-03 depends on doc-01; `editor_core` picks up a dependency on the
  vocabulary package (now `formats`), the §16 tier — rel-03; В4 rewritten.
- The p0-13n sandbox spike moved into phase 0; ui-14's native branch and
  ui-20 depend on it; Е4 and §7 #35 expanded (`Release.entitlements`,
  `atomic_write.dart`).
- §7 #36: the design plan §1's asset composition against Ж4; a conditional
  doc-11a-n `ImportInto` in phase 2; Ж4 flagged as a divergence.
- mat-09n: a pure PNG/JPEG decoder for the Image node (the tree only has
  `dart:ui` and the `cpu_png.dart` writer); mat-11 depends on it; Г6
  expanded.
- mesh-28 builds UV per corner like `Shape.build()`, mesh-29 compares
  texcoord (1e-6), mesh-23 tests side-quad UV; mesh-12 got a `uv0`-fill
  rule.
- §7 #4: `LightBuffer.packFor` → `gatherNear`/`gatherNearFrom`.
- §7 #10 and К5: eight committed tracks, a ninth joins.
- doc-29 → ARCHITECTURE §8.7, fmt-16 — §8.6 Writers; §7 #2 agreed.
- ui-15: `defaultStorage('flutter3d_modeler')` instead of
  `Storage(appName:)`.
- The bench path — `packages/flutter3d/tool/bench`; mesh-03's acceptance
  and §6 #1 — `bench_geometry.dart` builds AOT as a separate main.
- ui-13: Bézier curve segments flattened into a polyline for `LatheShape`,
  `AddLathe` stores the curve, "Point / Curve / Axis" chips.
- Ж7 with no "impossible": the gradient — `SkySettings` or an unlit quad;
  the divergence from the README — §7 #37.
- Risk 28: the "unchecked" flag removed (`morph_texture.dart`), the rule
  moved into doc-14 (phase 1).
- qa-08: provenance — the samples package's own `assets/ATTRIBUTION.md`
  (the critique named the README; the README references it,
  `LICENSES.md` only lives under apps).
- view-06: size S flagged conditional, estimated M under risk 9 if the item
  fires.
- pro-eng-06: section `LODS` = kind 24.
- Missing aspects: units and up axis on import (doc-11's `ImportOptions`,
  ui-16); icons (ui-02, Е12n); uncaught exceptions (ui-30n); a pivot and
  `ApplyTransform` (doc-06, ui-17); drag-and-drop (ui-31n); input limits
  (ui-16); collaborative work (pro-after-01); help and hotkeys (ui-32n);
  headless Godot in CI (qa-19n, К2).

The critical path after recomputation: `qa-01 → qa-02 → mesh-01 → mesh-02 →
mesh-10 → mesh-11 → mesh-12 → mesh-13 → mesh-25 → doc-07 → doc-20 → rel-09 →
rel-16`, 4 S + 8 M + 1 L ≈ 29 weeks — the same number, different content
(see §4.1). Counters: 317 + 3 + 9 items, 37 divergences, 84 open questions,
32 packages by the end of phase 0 (numbers as of this revision; different
after the owner decisions below).

### 2026-09-09 — owner decisions

Twenty answers from Dmitrii to §8's questions; each entered as fact, marked
"2026-09-09 decision." One line per decision and what it changed in the
plan.

- The code lives in this monorepo (В5 closed): the packages join the
  workspace, the scanner, CI, and the §16 publishing order; §5.1 "Decisions
  before starting: none."
- The web is an equal-footing platform from the first version (Е1 closed):
  p0-02/p0-08 rewritten as quality gates, an unmet threshold becomes a
  phase-1 item; §1 item 3, §5.1, §7 #11 aligned. A freeze with progress is
  acceptable (Е11 closed), a web worker is a conditional phase-1 item
  ui-34d (footnote ⁸), §7 #31 expanded.
- Phase 1 ships on macOS, the web, Android, and iOS: ui-21 moved from
  phase 2 into 1 (footnote ⁴), §7 #34 closed; an iPad and an Apple
  Developer account — rel-19d by mid-phase-1 (А2, Е8 closed); macOS
  signing — "right-click → Open."
- Russian and English from the first version (Е2 closed), the core/MCP/
  `says` — English (Г4 confirmed); ui-22 and §5.2's acceptance expanded.
- Undo for meshes — persistent values with structural sharing (Б3 closed);
  the split is measured by p0-05.
- Non-manifold input splits on import and is flagged as a problem (Б1
  closed; mesh-13/27).
- Sculpting — `SculptMesh` with multiresolution (Б8/Б9 closed); screen 08
  gets "Subdivide" instead of "density" (§3.1, §5.5).
- The project format — `.f3dproj` with history (Г2 amended): doc-31d (a
  `history` section, a step = `says` + the command + a reference to blob
  chunks, the Г5 limit applied to the file), ui-33d ("save without
  history"); the doc-16 journal stays; §5.2's acceptance — save → open →
  undo three steps.
- The node graph — a texture compositor with a fixed node set (Ж1 closed);
  the ROADMAP is reworded at the September 28 review (§7 #3, §5.1).
- Phase-2 "Scene" mode = light/environment/shadows/post plus placing
  assets (Ж4 and §7 #36 closed): doc-11a-n unconditional (footnote ⁶),
  mat-24 extended with placement and exporting the scene as one GLB;
  §5.3's acceptance expanded.
- Screen 12's "Render" — a snapshot from the same renderer with
  supersampling and frame-graph passes (pro-rn-02); a path tracer is out
  of scope; §5.5.
- Icons — the SDK's `Icons` with a mapping table (Е12n closed); §7 #37
  flagged, the Ж7 gradient stays open.
- The vocabulary — two packages instead of one: `flutter3d_geometry` and
  `flutter3d_formats` (В1 rewritten): §1 item 1, notation, §3.1, §5.1, §6
  #1/2–10/12/15/20 and the "package" columns, §7 #24/28, В4; 33 packages by
  the end of phase 0, publishing order geometry → formats → flutter3d; no
  trace of the earlier working name is left in the file.
- The first publish — once phase 1 is in the hands of its first users (В8
  closed); December 27 is not the target; rel-06 after rel-16, §4.3.
- Team — one person with agents (§4.3 rewritten): phase 1's calendar =
  the sum of sizes (S = 1, M = 2.5, L = 5 weeks) — 73 S + 44 M + 3 L ≈ 198
  weeks; with agents on the format, overlay, platform, and localization
  tracks ≈172 (an estimate, checked by the first track); the "1 / 2 / 3
  people" table is dropped; §1 item 2.
- Export on a check failure — warn and export with confirmation, refuse
  only on empty geometry (Г9 closed); §5.2's acceptance.
- Hotkeys — Blender-like (Е5 closed); §5.2's acceptance, ui-32n.
- FBX — its own reader in Dart (Д7 amended): fmt-24/25 in phase 2, a
  separate track after rel-16 (fmt-25 moved from phase 3 — footnote ⁵),
  fmt-26 dropped (footnote ⁷), the package `flutter3d_fbx` — fmt-29d; §6
  says this isn't an engine change; §7 #12/28.
- Cloth — a separate `flutter3d_cloth` solver in phase 4 (В3/И1 closed);
  §7 #5.
- Checking export in an external engine — headless Godot in CI (qa-19n)
  plus a manual Unity/Blender checklist before release (К2 closed).

The first pass at entering these decisions hit a limit after 57 edits
(§1–§5 and the §2 tables were done); §6, §7, §8, §10, the remaining traces
of the earlier package name, and the doc/model-editor.md working-through
were finished in a second pass the same day.

Counters after the decisions: 317 + 3 + 9 + 5 items (`-d`: doc-31d,
ui-33d, ui-34d, rel-19d, fmt-29d), 37 divergences (#34 and #36 closed), 63
open questions out of 87, 33 packages by the end of phase 0, phase 1 —
≈198 weeks for one person, or ≈172 with agents.

A check after the second pass (same day): fifteen loose ends where the
text still held earlier forks; each checked against the file before the
edit. One line per finding.

- Phase 1's count recomputed from the §2 tables under the same §4.3 rules:
  73 S, not 72 — 120 items total, ≈198 weeks (≈202 with conditionals),
  ≈172 with agents; §1 item 2, §4.3, and the counters here corrected.
- Who closed Г4: §1 item 8 brought in line with §8 (В1, Ж2, and Г4 — by
  critique, 21 more — by owner decisions); in §5.2, Г4 moved from "by owner
  decision" to "by critique, confirmed by the owner"; the critique
  revision's counter — 84 open, not 85.
- Risk 12 no longer says "the design plan allows the web as view-only":
  the web is equal footing (Е1), a freeze longer than 1 s → ui-34d in
  phase 1.
- Risk 5: headless Godot in CI (qa-19n) separated from the manual
  Unity/Blender checklist, as recorded in К2.
- rel-05: a train slot is counted up to the set rel-06 ships in (after
  rel-16), not up to December 27 (В8); five packages, including
  geometry/formats.
- Г1 no longer keeps the project-file extension open: `.f3dproj` is
  closed by Г2, Г1 keeps only the magic number and the autosave location;
  doc-09 and §5.2's "Decisions before starting" reconciled.
- А4 reworded: the threshold picks the web-profile budget (1M or ≤300k,
  p0-02), not the platform's status — the web's equal footing doesn't
  depend on the threshold (Е1).
- §2.11: the pub.dev free-name list swaps the dropped
  `flutter3d_model`/`flutter3d_asset_core` for the accepted
  `flutter3d_formats`, `flutter3d_fbx`, `flutter3d_cloth` (all five answer
  404 at `pub.dev/api/packages`, checked 2026-09-09).
- А2 referenced "a working-through §7 line for the iPad" that doesn't
  exist: the iPad measurement lives in p0-03 and the phase-0 table in doc
  §6.
- rel-11: signing and notarization aren't in phase 1, the release opens
  via "right-click → Open" (Е8); the acceptance says the same.
- The doc §6 working-through, phase 0: row 0.5 and the paragraph after the
  table give the web no "view-only" exit — an unmet threshold becomes a
  phase-1 item (§7).
- The doc §6 working-through, end of phase 1: "work for a second person"
  replaced by agent tracks under one executor (decision 15, plan
  §4.2–4.3).
- The doc §6 working-through: 1.9 (writers and `StlLoader`) sits in
  `formats` and depends on doc-01, 0.4 names the five new packages, §5.4's
  heading — "What to add to the engine and vocabulary."
- The doc §2 working-through, screen 08: "dynamic density" replaced by
  multiresolution with a "Subdivide" button (Б9).
- The doc §1 and §4 working-through: §4.1 and §4.2 gained "Decision made
  2026-09-09" paragraphs following §4.3's pattern, §1 says "all three
  resolved," not "with a recommendation."

### 2026-09-09 — what phase 0 decided

The measurements are taken; the numbers and how they were obtained are in
the `doc/model-editor.md` working-through §6. Below is only what they
changed in this plan; the §2 table rows are brought in line with this at
the next revision.

- **p0-05 cancels chunks.** Copy-on-write chunking only handles a clustered
  edit (1–2% of a copy) and fails a scattered one (92–100%); a log of prior
  values costs 2% in both. `mesh-10` is flat `Float32List`s plus a
  `(indices, prior values)` log, not `PersistentFloat32Vector`; `mesh-02`
  is closed by this measurement. `doc-31d`'s acceptance about "`identical`
  untouched chunks" is rewritten for the log: it has no versioned values,
  the old state exists through rollback.
- **p0-06 moves `view-14` from phase 1 to phase 4.** `DeviceMesh.upload` of
  a whole mesh per frame costs 1.24 ms at 200,000 triangles and 5.39 ms at
  a million — the threshold was 16.6. A partial buffer overwrite
  (`overwriteGeometry`, four backends, the `qa-11` conformance check)
  isn't needed for phase-1 interactivity.
- **p0-10 keeps picking on the CPU.** A ray through `TriangleBvh` is
  2.2–3.8 μs against 1.2–23 ms by brute force; a 200,000-triangle build is
  61 ms. Neither a face id pass nor a half-edge neighborhood search will
  be needed in phase 2. The implementation already sits in
  `flutter3d_geometry` (`view-09` got it from p0-10, as planned), with a
  test against brute force.
- **p0-11 confirms an API over values up to 200,000 triangles** (the whole
  edit → rebuild → upload path is 1.8 ms, zero slow frames) and brings in
  `toMeshData(into:)` from `mesh-14` for a million (12% of frames run
  late).
- **p0-07 allows both strategies**: an isolate on native costs nothing
  measurable, slicing into 32 chunks gives a worst chunk of 2.1 ms.
  Operations are written step-based from day one; `ui-34d` stays
  conditional.
- **p0-02 puts phase-1 web on dart2js.** The app doesn't start under
  `--wasm`, the same code works in JS — ARCHITECTURE §1's own recorded
  exception, anticipated by the threshold. The wasm failure's cause becomes
  its own phase-1 item; browser frame numbers are taken by `profile_web.py`
  and are still absent from this plan.
- **p0-13n: the macOS container works fully** — both a direct write and
  "temp file + rename." Autosave (`ui-18`) writes there. Writing to a file
  chosen in the panel stays a one-minute manual check.
- **anim-31: FK is 17.5 μs per pose across 64 bones**, taken by a test, not
  an AOT bench: `Skeleton` pulls in `Scene` → `flutter3d_hardware` → the
  Flutter SDK. This becomes comparable to `ARCHITECTURE.md` §14's own table
  only after `anim-02`.
- **Not measured, and staying outside phase 0**: p0-03 (a Galaxy A55 and an
  iPad are needed), browser frame numbers, a manual write through the
  macOS panel, and `syn-02` (two screen mockups — design work).
