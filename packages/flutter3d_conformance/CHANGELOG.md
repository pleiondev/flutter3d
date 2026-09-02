## 0.4.2

* **`a pass renders into a cube face and a mip`.** Three clears into three
  subresources of one cube — a face's base, another face's base, and the
  first face's second level where the device says it can — read back through
  the probe prefilter stage with a single tap, so a backend that cleared the
  whole cube, the base level, or face zero ends with the wrong colour in the
  wrong place. The capability check reads `supportsRenderToMip`; the link
  checks pair `FullscreenVertex` with `ProbePrefilter`.

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
