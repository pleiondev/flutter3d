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
* **`a library loaded from bytes answers to the same names`.** The backend's
  own shaders, packed as a bundle by the harness — `OwnShaderSection` is the
  section id, the bytes and the SDK to stamp, or null from a backend that
  compiles nothing — are loaded through `loadShaders` and held to answering
  every name in `kRequiredShaders`, linking `MeshVertex + Pbr` through the
  loaded handles, keeping those handles' identity across a refresh, refusing
  bytes that are not a bundle with `ShaderBundleRefused`, and never answering
  a claimed stage no section holds with a handle. `runDeviceConformance`
  takes `ownShaders` and `conformanceChecksWith` builds the list for a
  harness that is not a test runner. The same check then refreshes with a
  bundle that no longer names `Pbr` while the `Pbr` handle is in use, and
  requires a `ShaderBundleRefused` naming the bundle and the stage with the
  library left as it was — the half of the identity promise the three
  backends had been keeping three different ways.
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
* **`a stencil test keeps what it should`.** A mark written where a mesh is,
  through `BlendState.keepDestination` so the picture is left alone, then
  `equal` landing only on the mark and `notEqual` only off it — three pixels
  read back, and each of the three ways to be wrong named in its failure. A
  backend whose `supportsStencil` is false is asked nothing, as with a
  compressed format it does not sample. The capability check reads
  `supportsStencil` with the rest.
* The link checks pair `Xray` with all three mesh vertex stages. It declares
  one output where every other lighting entry point declares two, which is the
  pairing least like the rest of the table.

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
