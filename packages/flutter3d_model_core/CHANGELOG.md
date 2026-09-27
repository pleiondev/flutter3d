## 0.8.0

**A project keeps a material's layers beyond metal-rough.** A
`SurfaceMaterial`'s `extensions`, the `MaterialExtensions` holding
`KHR_materials_ior`, `KHR_materials_specular` and `KHR_materials_clearcoat`,
is written to the project's material entry under `"extensions"` when a layer
is set and read back from it. The material commands carry it, `importInto`
remaps its textures, and the scene built from a project draws such a material
with the layered lighting model when a layer changes its shading. A material
with no layer is written as before. `M1`

**`AssetAudit.of(project)` measures an asset that arrived before it is
used.** Its `findings` are `AuditFinding`s, one sentence each with the
numbers in it, under five `AuditCheck`s: `units`, an overall size outside
`assetMinSize` (1 cm) to `assetMaxSize` (100 m), naming the unit the file was
most likely written in; `pivot`, the distance from the origin to the middle of
the base (`baseCentre`, `pivotDistance`); `materials`, materials identical
but for their names; `mesh`, what rebuilding each imported mesh's topology
would drop, split or turn round (`MeshAudit`); and `readiness`, every
`ExportReadiness` issue including the triangle and texture budgets. `says`
puts it in words. It measures and changes nothing; `flutter3d_model_mcp`'s
`audit` does the repairs.

**`materialKey(surface, named:)` is public.** It is the comparison key
`importInto` deduplicates materials by, and `named: false` leaves the name out,
which is how the audit finds duplicates.

**`renderSheet` takes `views`.** They are laid out in two rows. The default
four draw the same sheet as before, and all seven of
`RenderProjectView.values` make a 4x2 sheet with one tile empty.

**Animation pointer tracks pass through the rig pipeline.** Retargeting
carries an `AnimationPath.pointer` track, which moves a material or light
value, and the keyframe commands refuse the path as they refuse `weights`.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**A project's sun keeps its shadow.** The renderer reads `castsShadow` on a
directional light since 0.7.1, and every saved project wrote `false` for its
sun as a default nobody chose. `LightingSync` hands a directional light
`castsShadow: true` whatever the project says, which is what it always drew;
the flag still decides for point and spot lights.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**The first publication.** The 0.6.0 below was a number carried inside the
workspace and never reached pub.dev, and it describes a registered skeleton.
0.7.0 is the number the whole shelf goes out on, so that one number names one
tree and `^0.7.0` on any `flutter3d_*` package resolves against every other;
`doc/boundary-0.7.0.md` lists the thirteen packages that begin here. What
follows is what the skeleton was filled in with. Nothing in it imports Flutter
or `dart:ui`, and `dart:io` appears only under `bin/` and `tool/`.

**A project is a value, and an edit is a command.** `ModelProject` is
immutable and its object ids are never reused. `ModelCommand` is sealed; each
has a `name`, a `says` that reads as a sentence, `arguments`, `hints` for a
panel to draw from, and a `toJson` that `modelCommandFromJson` reads back,
answering null and never throwing. `modelCommandNames` lists 125 of them.
`ReplaceDocument` is deliberately outside that table. A refusal is an
`Outcome` with a sentence: every mesh command says why it will not touch a
parametric shape, an imported mesh or a socket.

**`ModelHistory` keeps documents and rolls mesh journals with them.** `run`,
`amend`, `undo`, `redo`, `transaction` and `markSaved`, 64 steps deep and
trimmed by bytes as well, under `kHistoryBudgetBytes` of 512 MiB, because the
size of a sculpt step cannot be predicted; the newest step is never dropped.
A `HistoryStep` carries a `StepAuthor` of `person` or `agent` and a `client`.
`undo(onlyIfAuthoredBy:)` lets an agent's undo refuse a person's step,
`undoAllBy` stops at the first step somebody else made, and a person who
amends an agent's step takes it over.

**`CommandJournal` and recovery.** A journal is JSON Lines with the author on
every record. A transaction's begin marker is written lazily, so an empty one
writes nothing, and `rollbackTransaction` marks a batch that must replay as
all or nothing. `CommandJournal.replay`, `recoveryPathFor`, `decideRecovery`
and `AutosavePolicy` are what an application builds crash recovery from.
Selection is a command too, from `SelectAll` to `SelectFacing`, `SelectNear`
and `SelectElements`, so a journal that selects and then edits replays.

**The `.f3dproj` container.** `writeProject` and `readProject` with
`kProjectMagic` "F3DP", numbered sections for the manifest, edited meshes,
blobs, imported meshes, images, checksums, history and simulation caches, a
CRC-32 per section and a header sum over the table. A fuzz found 7342 of
10 488 single-byte flips opening silently before the checksums.
`kProjectVersion` is 1 and has not moved: every key added since is optional on
read, so a file written at any point of this package's history opens. The
reader refuses a newer version and a missing required field, and turns an
unknown enum name into a default with a warning in `ProjectOpened.warnings`.
The undo history is written only on request and trimmed to `maxHistoryBytes`,
4 MiB by default, since it measured about nine times the file. An object's
modifier stack and the project's `SceneLighting` are written when they are not
the default, and lighting is carried through a saved history the way the
material table is, so an undo after reopening puts back that step's lamps. For
most of this package's life neither was written: `ModifierSlot` had a `toJson`
the format never called, and a mirror or three lights lasted until the file
was closed. A slot or a light this build cannot read is dropped with a warning
and the file still opens.

**Objects.** `AddPrimitive`, `AddLathe`, `AddSocket`, `SetParametric`,
`BakeToMesh`, `BuildTopology`, `DuplicateObjects`, `DeleteObjects`, `Rename`,
`SetParent`, `SetObjectVisible`, `SetObjectLocked`, and `MoveBy`, `RotateBy`
and `ScaleBy` with a `TransformPivot` and a `TransformSpace`. `SetOrigin` and
`ApplyTransform` compensate the children and flip the winding under a mirror.
A duplicate copies its `EditMesh` through `toBytes`, since a shared instance
extruded both objects.

**Mesh commands.** `Extrude`, `LoopCut`, `BevelEdges`, `InsetFaces`,
`BridgeLoops`, `SlideEdges`, `DeleteElements`, `MergeByDistance`,
`DissolveEdges`, `Separate`, `FillHoles`, `Triangulate`,
`RecalculateNormals`, `TransformElements`, `SubdivideMesh`, `Retopologize`
and `DrawQuad`, over `flutter3d_mesh`. A command that adds vertices grows the
object's shape keys to cover them. `SubdivideMesh` and `Retopologize` refuse a
mesh with skin weights or shape keys.

**A modifier stack per object.** `ModelObject.modifiers` holds `ModifierSlot`s
with `enabled` and `inExport`; `AddModifier`, `SetModifierField`,
`ToggleModifier`, `ToggleModifierExport`, `ReorderModifier`, `RemoveModifier`
and `ApplyModifier` edit it. `ModifierEvaluationCache.evaluatedMesh(project,
object)` resolves a boolean's operand recursively behind a cycle guard.
`toModelDocument` folds the slots marked `inExport`, and `planExport` takes
`applyModifiers`. Long work leaves the step through `JobRequest` and comes
back through `ApplyJobResult`, which refuses a result whose `baseVersion` is
stale.

**Materials, texture graphs and budgets.** `ProjectMaterial` carries a
`surface`, a linked `fmat` and a `graph`. `AddMaterial`, `DuplicateMaterial`,
`RemoveMaterial`, `SetMaterialField`, `SetTexture`, `AddImage`,
`AssignMaterial`, `LinkMaterialFile` and `EmbedMaterial` edit it; images are
interned by their bytes. A `TextureGraph` is eleven sealed `TextureNode`
kinds edited by `AddNode`, `Link`, `Unlink`, `SetNodeField`, `MoveNode` and
`RemoveNode`, checked by `validate` and baked by `bakeTextureGraph`. Its noise
is an integer hash with no `Random`, so two bakes are the same bytes.
`TextureBudget` has `desktop`, `mobile` and `web`, and `FitTexturesToProfile`
resizes what is over and leaves its input alone.

**Painting, UVs, baked maps and sculpting.** `PaintStroke` is a sphere in 3D,
so a stroke crosses a UV seam; layers are a `PaintStack` of 64-pixel
`PaintTile`s under five `BlendMode`s. `UnwrapCommand`, `MarkSeam` and
`PackAtlas` are the UV commands, and an unwrap can be restricted to the
selected faces. `BakeMaps` writes `normal`, `ambientOcclusion`, `curvature`
and `thickness`; the occlusion samples a Halton sequence so a bake repeats.
`SculptStroke` is a whole polyline with pressures and one journal step, and
`ProjectProfile.sculptTriangleLimitWeb` defaults to 300 000.

**Skeletons and skin.** `AddSkeleton`, `BindSkin`, `AddJoint`, `RemoveJoint`,
which moves the joint's weights to its parent, `RenameJoint`,
`ReparentJoint`, `SetRestPose`, `MirrorJoints`, `BendJoint`, `SetRig` and
`PaintWeights`. `buildSkeleton` fits a `RigTemplate`, a `humanoid` of 17
joints or a `quadruped` of 15, to markers, and `previewRig` shows it first.
`rigIssues` runs nine checks against the profile's limits, which
`SetProfileLimits` holds to 64 joints and 4 influences. `retargetClip` with
`lockFeet`, `autoMap`, `looseAutoMap` and `solveTwoBoneIk` came with
`flutter3d_rig`, with three fixes since: a sign error in the two-bone solver
for a chain bent at rest, a `RangeError` in `lockFeet` for tracks of mixed
kinds, and inverse bind matrices for a mesh whose transform is not identity.

**Animation and shape keys.** `ProjectClip` with `ProjectTrack`s and a
`KeyTable`; `AddClip`, `SetKey`, `MoveKeys`, `DeleteKeys`,
`SetInterpolation`, `SetTangent` and `PoseJoint`; `curveSamples` and
`tangentHandles` for a curve editor; `ProjectProfile.fps`, 30 by default, and
`frameSnap`. `IkConstraint` with `bakeIk`, and `LookAtConstraint` with
`bakeLookAt`, which is resolved and baked and not yet stored on a skeleton.
`ExtractRootMotion` and `BakeRootMotionIntoClip` keep the motion under
`kRootMotionExtra`. `ShapeSet`, `SetShapeWeight`, `AddShapeFromMesh`,
`RenameShape`, `DeleteShape` and `KeyShape` are the shape keys, and a
`ShapeDriver` moves one from a joint's rotation, live through
`evaluateShapeDriversLive` or baked through `bakeShapeDrivers`.

**Simulation.** `BakeClothJobRequest`, `BakeRigidBodyJobRequest` and
`BakeParticleSystemJobRequest` bake through `flutter3d_physics` and
`flutter3d_particles` into a `SimulationCache`. `ApplySimulationCache`
refuses a stale `baseVersion`, `BakeSimulationToShapes` reduces a cache to
shape keys, 8 at most by default, and a cache is saved in its own project
section with its frames deduplicated by identity.

**Levels of detail and impostors.** `LodSpec` with a `ratio` and a
`maxScreenFraction`; `AddLod`, `SetLodRatio` and `RegenerateLods`;
`LodMeshCache.meshFor`. `bakeImpostor` renders an `ImpostorAtlas` of views
around an object through a device the caller supplies.

**Scene lighting.** `SceneLighting` holds `ProjectLight`s, a
`SceneEnvironmentPreset`, exposure and `ScenePostSettings`, edited by
`AddLight`, `RemoveLight`, `SetLightField`, `SetLightTransform`,
`SetEnvironment`, `SetSceneLightingField` and `SetPanorama`, which refuses an
image that is not 2:1 and names its size. `ProjectLightType` and
`SceneEnvironmentPreset` are final classes with static constants and not
enums, as are `RigTemplate`, `BlendMode`, `RenderShading` and
`RenderProjectView`, so a `switch` over one needs a default.

**A headless picture of a project.** `renderProject(request,
deviceFactory:)` draws one of seven `RenderProjectView`s in a `RenderShading`
of `material`, `normals`, `weights` or `wireframe`, up to 1024 pixels a side,
and answers a `RenderRefusal` in words when it will not. `renderSheet` puts
four views on one labelled sheet with a 5x7 font of its own. A wireframe is
drawn from the document's polygon edges, so a cube shows 12 and not the 18 of
its triangles. The package names no backend: the caller hands in the factory,
and `RenderSnapshotJob` takes `concurrency`, 1 by default, since the core
count cannot be asked without `dart:io`.

**Import, sources and credits.** `fromModelDocument` and `importInto` with
`ImportOptions` of `scale` and `upAxis`; an import deduplicates materials and
images by content, keeps the hierarchy and answers an `ImportReport`.
`LinkToSource`, `UnlinkSource` and `Reimport` tie an object to a `SourceLink`
of a path and a hash the caller supplies. `ModelCredit`, `creditsIn` and
`creditsFile` carry attribution to an export, and `creditsFile` is null when
nothing is owed.

**Export and readiness.** `planExport` takes an `ExportFormat` of `f3d`,
`obj`, `glb`, `stl`, `stlAscii` or `usdz`, a `TextureEncoding` of `png` or
`ktx2`, `bakeTransforms`, `only` and `force`, and answers `ExportWritten`,
`ExportRefused` or `ExportBlocked`. `dart run flutter3d_model_core:export
<in.f3dproj> <out.ext>` is the same from a command line, with `--anyway`.
`ExportReadiness` gained rules for a blend material with opaque alpha, a
texture coordinate set other than 0, a texture over budget, a linked `.fmat`,
texel density off by more than two times, and a morph target wider than the
profile's texture limit; `ReadinessCache` keeps the answer per version, and
`ProfileBudgetReport` totals a project against a `ProjectProfile`.

**An object's levels of detail are in the file it is exported to.**
`ModelObject.lods` was edited by three commands, turned into meshes by a cache
and shown on a screen, and the converter to a `ModelDocument` never read it, so
`.f3d`'s section for levels and `.glb`'s `MSFT_lod` were always written empty.
`ProjectModelDocument.of` and `toModelDocument` take `withLods`, and
`planExport` passes it for the formats whose `ExportFormat.carriesLods` is
true, `.f3d` and `.glb`. Each level is cut from the mesh the file carries, with
the export-bound modifiers folded in, and is cached per object version. OBJ,
STL and USDZ are given the one mesh, because their writers walk every surface
and would put every level in the same place. `withLods` defaults to false for
the same reason.

**Accepted `flutter3d_rig`, because this package and the server above it were
its only callers.** Bone-name mapping, rest-relative retargeting with a
two-bone-IK foot lock and automatic skin weights now live under `lib/src/rig/`
and are exported from this package's own library, unchanged. They still read a
rig as nodes and tracks and know nothing of a project; what went is a package
boundary nothing outside the modeller ever crossed. `flutter3d_rig` was never
published, so no pubspec outside this repository names it.

**Accepted `flutter3d_render_job` too, and with it the second scene builder
it carried.** `RenderSnapshotJob`, `RenderPreset` and `SnapshotCamera` — a
tiled snapshot with a 2×2 supersample — live in `render_snapshot.dart`, and
`sceneFromProject` is now the one walk over a project that both it and
`renderProject` draw through; the two copies had already drifted on whether a
material's own lighting model is read. The job now takes its `tileDevice`
rather than defaulting to `CpuDevice`, because this package names no backend;
the default was the only thing the old package needed Flutter for. Its tests
live in `flutter3d_cpu`, beside `renderProject`'s, where a real device is.

**What it depends on.** `flutter3d_mesh`, `flutter3d_core`,
`flutter3d_physics` and `flutter3d_particles` at `^0.7.0`, and `vector_math`.
The PNG and JPEG decoders, the PNG encoder and DEFLATE that lived here for a
while are `package:flutter3d_core/formats.dart`'s. `render_snapshot.dart` and
`texture_bake.dart` import `dart:isolate`. The archive carries
`skills/flutter3d-model-core-project-and-commands/` for a coding agent,
installed with `dart run skills@ get`.

## 0.6.0

**A registered skeleton, and it is honest about that.** The package exists so
that the structure scan, the publishing order and the check that a plain `dart
pub get` resolves it all cover the modeller's document layer from its first
commit. What goes in it — `ModelProject`, `ModelCommand`, `ModelHistory`,
`ExportReadiness` — is `doc/model-editor-plan.md` §2.2.

* **The `.f3dproj` manifest's own fields, as they have grown since**:
  `ProjectProfile` gained `target`, `maxTextureBytes`, `requireTriangles` and
  `requireManifold` (`doc-13`); `ProjectMaterial` gained `fmat`, naming a
  standalone `.fmat` file a material defers its look to, relative to the
  project (`doc-10`); and a texture binding's `mipLinear` — `flutter3d_formats`'
  `fmt-05` — is now carried through a save and a reopen, which it silently was
  not for one commit's length of this package's own history. Every one of
  these reads with a fallback rather than as a required key, so a file saved
  before any of them existed keeps opening exactly as it did — `doc-28`'s own
  rule for why none of this moved `kProjectVersion`.
