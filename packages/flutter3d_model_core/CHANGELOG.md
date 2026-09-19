## Unreleased

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
