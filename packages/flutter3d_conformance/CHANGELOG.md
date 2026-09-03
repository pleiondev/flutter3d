## 0.4.2

* **`a readback returns the frame before`**, in the core tier: red is
  cleared, a readback is asked for and not awaited, blue is cleared over it,
  and the answer has to be red. The same check holds a two-by-three region to
  two-by-three pixels and refuses a `deviceTransient` texture, a region past
  the edge and a texture in the device's own `hdrColorFormat` with an
  `ArgumentError` rather than an answer — the last because a half-float
  readback was three different answers on three backends, one of them a
  picture of zeros with no error.
* **`a readback of a region reads that region`**, in the shader tier: the top
  half of a picture is painted, a region in the top-left quarter has to be
  painted and one in the bottom-left not, and a region straddling the edge
  has its painted rows first — the check that found a backend measuring a
  region's y from the wrong edge.
* The link checks pair `ObjectId` with the three vertex stages the picking
  pass draws through and `Luminance` with the full-screen one.

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
