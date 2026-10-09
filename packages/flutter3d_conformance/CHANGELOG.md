## 1.0.0-rc.1

- **Breaking: a sixth plugin check, `materials`.** `pluginCheckNames` names
  it: every physical material a plugin declares has a source for each group,
  plausible SI numbers and an id in the plugin's namespace, and goes when the
  plugin does.
- **Breaking: `ConformanceFailure` is `ConformanceFailureException` and
  `ConformanceDeclined` is `ConformanceDeclinedException`** (decision H),
  with the same members; `dart fix` renames them.

- **Breaking: the plugin harness checks the loop's own snapshots.**
  `PluginHarness` lost `capture`, `restore` and `digest`: the world a plugin
  acts on is the loop's, so `setUp` puts the application's state in
  `loop.world` or adds a `SnapshotPart` for it (`loop.snapshots.add`), and
  determinism runs each step twice through the default `DeterminismCheck`,
  compares two runs by `loop.digest()`, and starts every check's loop from
  the first one's capture. A check of a loop whose snapshots hold nothing is
  declined, as a harness with no world was. A rollback restores what the
  check checked, because they take the same path. `hasWorld` is gone with
  the functions it asked about.

- **The badge names its suite: `conformant@1.0`.** `conformanceSuiteVersion`
  is `'1.0'`, `conformanceSuites` lists each suite with its checks, and
  `badgeFor` answers the badge a run earns, written with the suite. A check
  added later joins a new suite version and never an old one, so a plugin
  that earned `conformant@1.0` keeps it when this package grows.
  `earnsBadge` takes an optional `suite:` and answers for 1.0 by default.

- **`conformanceReport` writes a run as a versioned document**:
  `{"format": "f3d.conformance", "version": 1, ...}` with the plugin, the
  suite, the badge and each outcome, for a catalogue or a CI job to read.

- **The `tools` permission is one the manifest check knows**, so a plugin
  that offers MCP tools and declares it passes.

- **Breaking:** `ConformanceDeclinedException`, `ConformanceFailureException` extend
  `CapabilityException` instead of implementing `Exception` directly. The
  names and members are unchanged and every `on` clause that caught them still
  does; every exception the engine throws now hangs from `Flutter3dException`
  in `flutter3d_plugin_api`, in one of four families: format, capability,
  plugin and resource. A caller who reports anything the engine refused
  catches the root; one who acts on a kind catches its family. The migration
  table marks them as nothing to do. `ConformanceDeclinedException` gains `message`,
  which is its `reason`.
- **The blend, wireframe and primitive checks accept `UnsupportedCapability`**
  as the refusal, now that it is no longer an `UnsupportedError`. A bare
  `UnsupportedError` still counts, for a backend written before the type
  existed.
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

- **`reversed-depth` is listed among the features no call exercises**: it
  describes the depth range and the depth format, and a device without it
  draws a reversed projection all the same.

- **A conformance suite for plugins, and a badge.**
  `package:flutter3d_conformance/plugins.dart` holds a plugin to what
  `flutter3d_plugin_api` cannot say in a signature, in five checks: its
  manifest reads, writes back and installs; switching it off at a step
  boundary leaves exactly the loop it found; every step run twice from one
  state agrees, and the system that does not is named with its plugin; it
  steps on every backend it declares and is switched off on one it does not;
  and it keeps the budget its manifest declares. `runPluginConformance`
  registers them as tests, `checkPluginConformance` returns them as a list,
  and `earnsBadge` says whether they earn "flutter3d conformant": every check
  passed on every declared backend, with a world and a budget given. The
  package now depends on `flutter3d_plugin_api` and `flutter3d_sim`, both
  plain Dart, and stays so.

**Every capability a device reports is held true, both ways.**
`capabilityChecks` walks each `DeviceFeature`: one the device lists has to
work through a minimal call — a buffer written comes back, a copy lands, a
query set resolves, a pass state is accepted — and one it does not list has
to refuse that call with `UnsupportedCapability` naming it. Reserved
features may never be listed, the compression and float families must agree
with `textureFormatSupport`, and a second check holds the pre-1.0 getters to
the set they now forward to. What cannot be probed without a purpose-built
stage is named in `unprobedFeatures` with the reason. Thirty-two shader
checks, forty-four in all.

- Links `HighContrast` through the full-screen stage and `OutlineMask`
  through the three velocity vertex stages.
- Links the caustic stages: `MeshVertex` with `CausticSurface`, and
  `CausticPhotonVertex` with `CausticPhoton`.
- Links every mesh vertex stage with `ShadowTransmittance`.
**The linking check names `Decal`**, so a backend whose bundle lacks it
fails the check rather than the first frame with a decal in it.
**The linking check names `PlanarReflection` and `RenderTextureEncode`**:
the first through the three mesh vertex stages it is drawn over a
reflector's surfaces with, the second through the full-screen one, so a
backend whose bundle lacks either fails the check rather than the first
frame with a reflector or a render texture in it.
**The linking check pairs `SkyPhysicalVertex` with `SkyPhysical`**, whose
seven varyings are new on both sides.
**A window of the index buffer draws that window.** A new shader check draws
a window over the second of two triangles in one index buffer, then over the
first, then with no count, and asks that a window past the end of the binding
is refused with a `RangeError`. Thirty-two shader checks, forty-two in all.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.1

**The linking check names `ContactShadowResolve`**, the stage
`flutter3d_core` 0.8.1 draws, so a backend whose bundle lacks it fails the
check rather than the first frame with contact shadows and no temporal
resolve.

It asks for `flutter3d_shaders` `^0.8.1`.

## 0.8.0

**Four new checks, forty-one in all, and thirty-one of them need the shader
pipeline.** A backend written against 0.7 meets each as a failure or a
decline until it implements the members they ask about.

- `a texture bound to a slot the stage lacks is false`: a name no stage
  declares, and a fragment sampler bound through the vertex stage's handle, on
  every backend that reflects its stages.
- `a device that filters 32-bit floats filters and renders them` holds a
  device answering `supportsFloat32Filtering` with true to both halves of it:
  a bilinear tap between float texels, and a float target that renders and
  samples back. A device answering false declines.
- `a field steps in a float target and reads back through a vertex` steps a
  decay kernel three times from a start of two in each float format the device
  renders to, and reads the result through a vertex stage: 0.425 is right, and
  0.3 means the target clamped to one. The upload check never covered
  rendering into a float target.
- `a compute pass scans a buffer in place`, the one entry of the new
  `computeChecks`, which `conformanceChecks` now includes: a prefix sum over
  1024 integers, read back and held to i(i+1)/2. It declines where
  `supportsCompute` is false, which is Impeller and WebGL2.

**The link check covers the stages 0.8.0 added.** `PbrLayered` links against
every mesh vertex stage; the three velocity vertex stages against `Velocity`
and `Reactive`; the full-screen stage against `DepthPyramid`,
`CameraVelocity`, `TemporalResolve`, `TemporalAccumulate`, `VolumetricFog`,
`VolumetricFogUpsample`, `VelocityTileMax`, `VelocityNeighborMax`,
`MotionBlur`, `FieldDecay`, `IrradianceConvolve`, `EvsmFilter`,
`WboitResolve` and `SceneColourCopy`; and four pairs are new:
`ImpostorVertex` with `Impostor`, and `ParticleVertex` with `ParticleSixWay`,
`ReactiveSprite` and `SplatHashed`.

**Fuzzing, new.** `generateFuzzProgram` turns a seed into a program of draws
over the probe stages every bundle ships, with viewports, scissors, blending
and depth chosen at random, and `drawFuzzProgram` draws it on a fresh device
from any `DeviceFactory`. The oracle is the program against itself: each
`FuzzTransform` (`SplitDraw`, `SwapDisjointDraws`, `FoldPowerOfTwo`) rewrites
it into one that must draw the same bytes, exactly in IEEE 754. `fuzzSeed`
draws a seed's program and its rewrites and returns the ones that came out
different, and `shrinkFinding` cuts a finding down to the draws that still
show it. `fuzzDifference` compares a device against a reference device
instead, as the share of pixels more than a few steps apart. `FuzzRandom` is Park and Miller's
generator, so a seed is the same program on the VM and in a browser. Two
hundred seeds run on the software rasteriser, and fifty on each of WebGL2 and
WebGPU against it, held to 2% of pixels. The first run found two bugs in the
software rasteriser's scissor and blending, fixed in `flutter3d_cpu`. `H4`

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**Breaking.** `markTestSkipped` and `test`, this package's one Flutter
import, come from `package:test` instead of `flutter_test` — the same two
symbols, so no check changes. Nothing else here ever named Flutter directly;
the import outlived the reason for it, from before `flutter3d_hardware` had a
`dart:ui`-free `GraphicsDevice` of its own to test. `flutter3d_shaders` dropped
its own `flutter: sdk` dependency in the same release, so this package no
longer resolves the Flutter SDK through it either, and a backend's
`conformance_test.dart` runs under `dart test`. Floors to `flutter3d_hardware`
`^0.7.0` and `flutter3d_shaders` `^0.7.0`.

**Four new checks, thirty-seven in all, and twenty-eight of them need the
shader pipeline.** `a texture region overwrite lands only where it was aimed`
patches a 2x2 corner of a 4x4 texture through `overwriteTexture` and reads all
sixteen texels back. `a geometry overwrite draws what a fresh upload draws` and
`a geometry overwrite leaves its neighbours untouched` hold
`overwriteGeometry` to the picture and to the bytes either side of the write,
and expect a write past the end to be refused. `the colour attachment limit is
honoured in both directions` asks for a second attachment that receives its
own output and for a pass past `maxColorAttachments` that throws. A backend
that answers one declines the first half and is still held to the second. A
backend written against 0.6.0 meets all four as failures until it implements
the three new `GraphicsDevice` members.

**The link check covers the stages the engine added.** `ShadowDepthMasked` and
`ShadowDistanceMasked` link against each of the four mesh vertex stages,
`SsaoBlur`, `ContactShadow`, `LightShafts`, `DepthOfField` and `ViewportShade`
against the fullscreen one, and two pairs are new: `PolylineVertex` with
`Unlit`, and `ParticleVertex` with `Splat`. `Fxaa` is in `kRequiredShaders`
and is not in this list.

**A device factory may decline.** A `ConformanceDeclined` thrown while
`makeDevice` runs skips the check with the sentence it carries, the way a
declined check already did. Headless Chrome on a CI runner has `navigator.gpu`
and hands out no adapter, which is nothing a check could have been asked
about. Any other exception from the factory is still a failure.

**The archive carries a skill** for a coding agent,
`skills/flutter3d-conformance-running-the-suite/`, about the suite that says a
backend is finished and how declining differs from passing.
`dart run skills@ get` installs it.

## 0.6.0

* **A device factory may now answer with a `Future`.** `DeviceFactory` returns
  `FutureOr<GraphicsDevice>` instead of `GraphicsDevice`, and the runner
  `await`s it. The fourth backend cannot be built by a constructor —
  `requestAdapter()` and `requestDevice()` are both promises — while Impeller,
  WebGL2 and the software rasteriser are opened with a call. Nothing in
  `flutter3d_hardware` says how a device is *made*; the contract starts once one
  exists, which is why the widening costs the three backends that were here
  first exactly nothing and changed none of their call sites.
* **Breaking only for code that stores the typedef.** A factory that returns a
  device is still a valid `FutureOr` factory, so passing one is unchanged; a
  caller that held a `DeviceFactory` and used the result without awaiting is the
  one that has to add the `await`. That is the whole of the API change.
* The checks themselves are unchanged in number and in what they assert. What a
  backend declines it still declines by name.

## 0.5.1

* **A new check: a float texture uploads as floats.** Two of the three backends
  answered no and neither said so — one refused sixteen bytes a texel as the
  wrong size, the other filled float storage with bytes. Both looked finished.
  The check uploads a one-texel `r32g32b32a32Float` holding three quarters and
  samples it in a vertex stage, which is where morph deltas are actually read,
  and fails with a sentence naming the likely cause.
* Thirty-three checks in all, twenty-five of which link stages and draw.

## 0.5.0

* Follows the hardware layer's version. The checks are unchanged; the device
  suite now passes all thirty-one on Metal, including the blend constant, the
  multisample resolve and the object id, which had never been run on hardware.

## 0.4.2

* **A block missing a member the caller named is refused.** The one half of
  `bindUniformBlock` this suite named as deliberately outside it, and the half
  the two hardware backends had quietly disagreed about. It asks the backend
  which kind it is before holding it to the rule: a backend that answers false
  for a block no shader declares is one that can see inside a shader, and is
  then required to throw for a member the block does not have. One that accepts
  any block name has no reflection, and the check says so and stops rather than
  passing by construction.
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
* **`a pass renders into a cube face and a mip`.** Three clears into three
  subresources of one cube — a face's base, another face's base, and the
  first face's second level where the device says it can — read back through
  the probe prefilter stage with a single tap, so a backend that cleared the
  whole cube, the base level, or face zero ends with the wrong colour in the
  wrong place. The capability check reads `supportsRenderToMip`; the link
  checks pair `FullscreenVertex` with `ProbePrefilter`.
* **Three checks, and a way for a backend to decline one.** *A blend constant
  reaches the blend, or is refused* draws through `BlendFactor.blendColor`
  against a known constant and demands the two refusals from a backend that
  has none. *A multisample resolve resolves* is the first check to carry
  `RenderTargetSpec.sampleCount`, `ColorTarget.resolveTexture` and
  `StoreAction.multisampleResolve` at all. *An object id survives the draw and
  the readback* binds `IdInfo` with a known id, draws through the standard
  five-attribute layout — which nothing else here does — and decodes
  `r + g·256 + b·65536`.
* **`ConformanceDeclined` and `decline`.** A check the backend cannot be asked
  used to `return`, which every harness reported as a pass. It is now a skip
  that names the backend and what it answered, in the test runner and in the
  application harness's log and tally alike.

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
