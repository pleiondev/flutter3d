## 1.0.0-rc.1

- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kSamplesAsset` is `samplesAsset`,
  `kSamplesPath` is `samplesPath`. The values are the same; `dart fix`
  carries the renames.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Joins the stack's number.** Nothing in the assets changed; the package moves
from 0.4.3 to 0.7.1 so that every `flutter3d_*` package carries one version.

## 0.4.3

* `teapot.stl`: the same geometry as `teapot.obj`, converted by this
  repository's own `StlWriter` — `qa-08`'s own STL fixture, so `fmt-09`'s
  decoder gets a round trip against real curvature to sit beside the
  synthetic edge cases `flutter3d_formats/test/fixtures/stl/` already holds.

## 0.4.2

* `AnimatedMorphCube.glb`, the Khronos sample for morph targets: two shapes
  and a clip that drives their weights. CC0-1.0, recorded in `ATTRIBUTION.md`.
  It is what the engine's morph pipeline is tested end to end against, and
  what the `morph-cube` golden draws.

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
