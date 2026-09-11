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
