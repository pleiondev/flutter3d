## 0.4.1

* Three Basis Universal ETC1S files under `assets/ktx2/` — one level, then
  five levels with alpha, then seven levels of a 64×64 field — encoded by a
  from-source `basisu` and held level by level against its own unpack.
  `doc/ktx2_fixtures.md` says how they were made and what their bytes are.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* First release. The Khronos glTF sample assets, the Utah teapot and the `.f3d`
  conversions of them, moved out of `flutter3d` where they were declared as the
  engine's own assets — so every application built on it bundled 4.1 MB of test
  models, and the engine's archive was four fifths fixtures.
* `kSamplesAsset` and `kSamplesPath`: the bundle key and the on-disk directory,
  said once instead of in the seven places that each had their own copy of the
  string.
