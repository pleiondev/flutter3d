## 0.4.2

* **A sampler asking for more anisotropy than there is is accepted.** Bound on
  a trilinear sampler, drawn through the textured particle stage and read back
  at a texel centre — a check that the bind lands on a device that allows
  fewer taps, which is three different clamps behind one promise: flutter_gpu
  clamps inside its bind, WebGL2 has to be clamped before `texParameterf`,
  and the software rasteriser ignores the field. Asked twice: at sixteen, the
  number the engine's documentation names, and at `maxAnisotropy * 2`, which
  is above the ceiling on any device — sixteen is also what every desktop
  context answers, so it alone would never reach a clamp. The capability check
  asks `maxAnisotropy` and requires at least one.

## 0.4.1

* The link checks pair `MeshLightmappedVertex` with the lit models.
* **A compressed format the backend claims is drawn and read back.** One
  hand-built BC1 block and one ETC2 block, each uploaded where
  `supportsTextureFormat` says yes and sampled at the centre of a quad; a
  backend that answers no to both runs nothing, which is the honest outcome
  for the software rasteriser. The capability check asks
  `supportsTextureFormat` for every `TextureFormat` value.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* The behaviour `flutter3d_hardware` requires, as a suite a backend runs
  against itself: formats that must be renderable, pixels that must keep their
  row order, and every stage pair the engine actually links.
* Split into `coreChecks` and `shaderChecks`, because a suite that claimed to
  need no shaders met a new backend with five failures it could do nothing
  about.
