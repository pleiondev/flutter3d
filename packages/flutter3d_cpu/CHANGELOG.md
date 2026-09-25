## 0.8.0

**Bindings follow the contract.** `bindPipeline` forgets every binding, as
the other backends do, and `clearBindings` forgets the vertex slots and the
index buffer as well as the blocks and textures. This backend used to keep
them, so a draw that missed a bind read the previous draw's and drew a
plausible picture while Metal failed. `bindTexture` returns false for a
sampler the compiled stage does not keep and true otherwise.

**Uniform blocks and samplers are held to the compiled bundle.** Every stage
carries `ShaderHandle.kept` and `ShaderHandle.layouts` from
`flutter3d_shaders`, and a block or sampler the stage dropped, or a misspelt
or overlong member, is refused by name before anything is drawn. A misspelt
member used to read as zero here and throw on the GPU backends.
`flutter3d_shaders` is now a runtime dependency for these tables.

**`GeometryBuffer`'s offset and length are honoured**; a slice was read from
byte zero with a stride worked out from the whole buffer.

**A triangle is clipped to the viewport and the scissor together.** It was
clipped to the scissor where there was one and to the viewport only where
there was not, so a triangle reaching past the clip volume drew outside a
viewport that had a scissor beside it. Lines follow the same rule. The new
fuzzer found this: it draws random programs of draws against exact rewrites of
themselves here, and against WebGL2 and WebGPU in the browser suites.

**Blending reads its destination as the hardware would have stored it.** A
float stays in an eight-bit target so `readHdrPixels` can show it, but what
blending reads back is clamped and, on a linear target, rounded to 1/255. A
reverse subtraction used to leave a negative value that the next additive
draw added to.

**Three colour attachments by default.** `CpuDevice.maxColorAttachments` is 3
where it was 2, for the albedo buffer the scene pass writes beside the
surface buffer; a stage writes it through `FragmentContext.albedo`.
`FragmentContext.fragDepth`, when a stage sets it, is stored in place of the
interpolated depth, which the static shadow copy needs.

**Compute runs here.** `supportsCompute` is true. `CpuStage.compute` hands its
mirror a whole workgroup and runs the phases between barriers across all its
invocations, storage buffers are their bytes, and a dispatch finishes before
it returns. `PrefixSum` is the first stage.

**The capabilities answer.** `supportsFloat32Filtering` is true,
`supportsIndependentBlend` is true unless the constructor says otherwise, and
`hdrOutputFormats` is empty unless the constructor is handed formats, so a
test can take the extended-range output branch. `supportsGpuTimestamps` is
false.

**Every new stage has its Dart transcription**, operation for operation with
the GLSL: `PbrLayered` with its layers, per-map texture transforms, sheen,
anisotropy, transmission reading the scene copy, dispersion and thin film;
the EON diffuse lobe and energy compensation in `PbrShader`; the rectangle
light's LTC integral; the per-pixel irradiance read and `IrradianceConvolve`;
the clustered light lookup; GTAO and SSIL; the metric soft-shadow search and
filter, `EvsmFilter` and `ShadowCopy`; `CameraVelocity`, the three velocity
vertex stages and `Velocity`; `TemporalResolve` with its k-DOP clip, and
`TemporalAccumulate`; `Reactive` and `ReactiveSprite`; `VelocityTileMax`,
`VelocityNeighborMax` and `MotionBlur`; `VolumetricFog` and its upsample;
`LocalExposure` and its blur; `Easu`; `WboitResolve`; `SceneColourCopy`;
`DepthPyramid`; `ImpostorVertex` and `Impostor`; `ParticleSixWay`;
`SplatHashed`; `FieldDecay`. `flutter3d_core`'s CHANGELOG says what each one
is for.

**The sRGB curve and AgX's `pow(2.2)` give the same bits everywhere.** They go
through `portable_root.dart`, Newton's method on IEEE arithmetic, where
libm's `pow` differed in the last bit on Linux. The image-based lighting path
takes the clamped n.v the GLSL takes. The one- and two-byte formats
(`r8UNormInt`, `r8g8UNormInt`, `a8UNormInt`) upload.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.4

**The Dart transcriptions follow `flutter3d_shaders` 0.7.4 operation for
operation** — AgX linearised, the grade's pivot, lift and LUT, the dither
centred, reflections jittered and refined, shafts scattered with a phase,
bloom's Karis average and per-level tint, depth of field's reach and sky,
contact shadows jittered, the occlusion blur's relative weight, the sun's
normal offset scaled by texel and slope and clamped past the last cascade,
the back face's tangent turned with its normal. `shadowFactor` takes the
light's `nDotL` for the slope. See
`flutter3d_core`'s CHANGELOG for why each moved.

**`FragmentContext.frontFacing`**, new: `gl_FrontFacing`, set from the pass's
winding, so the back of a double-sided surface is lit from its own side here
as it is on the GPU. `bayerCell` is public, the one 4x4 table the jittered
passes share. It asks for `flutter3d_shaders` ^0.7.4.

## 0.7.1

**`compareFrames` and `differingPixels` can compare alpha.** Both take
`alpha: true` now, and `channel: 0` together with it is a byte-for-byte
comparison. The defaults are unchanged: a pixel differs when red, green or
blue is more than 8 steps off, and alpha is left out.

**The mip level a texel reads is the same on every platform.** It came from
`math.log`, which is the platform's libm, so the last bit of a footprint's
logarithm could pick a different level on Linux than on a Mac. `portableLog2`
takes the exponent from the bit pattern and the mantissa's logarithm from a
series of plain arithmetic, and answers the same everywhere.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**Breaking.** `CpuDevice.present` is gone with `GraphicsDevice.present`
itself (mcp-01n), and with it the dead `_presented` field it was the only
reader of. `CpuFrame`, the widget it used to return, moved to
`flutter3d_app` (mcp-02n) — this package resolves without the Flutter SDK
and cannot also build a Flutter `Widget`.

**`ensureCpuBackendRegistered`, new.** This backend registers its own
opener as the native fallback with `flutter3d_hardware`'s device registry.
Its presenter is registered by `flutter3d_app` instead, on its behalf, since
this package has nothing Flutter-shaped to register it with. Floors to
`flutter3d_hardware` `^0.7.0` and `flutter3d_conformance` `^0.7.0`.

**The pubspec names no Flutter.** `flutter: sdk` and `flutter_test` are out,
`test` is in, and the dev dependency on the engine moved to `flutter3d` with
the forty-one test files that built a scene through it. What is left runs
under `dart test` on a machine with no Flutter SDK, and that is why
`flutter3d_model_core`'s `renderProject` and `RenderSnapshotJob` are tested
here, against a real device.

**`overwriteGeometry` and `overwriteTexture`.** The two in-place writes
`flutter3d_hardware` 0.7.0 asks of a device. Geometry is copied into the bytes
the buffer already holds. A texture region is converted from RGBA8 into the
`Float32List` a `CpuTexture` is, texel by texel, and the future completes in
the same turn. Both refuse a write that does not fit with `ArgumentError`.

**`CpuDevice` takes `maxColorAttachments`, default 2.** On Impeller's OpenGL
ES path a second colour attachment aborts the process, so the path the engine
takes on a device that answers one cannot be run on the hardware that has it.
`CpuDevice(maxColorAttachments: 1)` is that device with pixels at the end of
it. A pass past the limit throws from `beginRenderPass`.

**`maxAnisotropy` is 16, and the taps are taken.** It answered 1.
`BoundTexture.sample` accepts the four screen-space derivatives `dudx`, `dvdx`,
`dudy` and `dvdy` and takes several taps along the long axis of the footprint,
each at the level the short axis asks for. A sampler whose `anisotropy` is 1
does not reach the new path and draws the same bytes as before.

**`CpuDevice.readHdrPixels`, new.** It returns a texture as the linear floats
it is stored in. `readPixels` clamps to eight bits on the way out, so a depth
of forty metres or a NaN a broken stage wrote was indistinguishable from an
ordinary 1.0.

**Ten new stages, transcribed from the GLSL.** `Fxaa`, `SsaoBlur`,
`ContactShadow`, `LightShafts`, `DepthOfField`, `ViewportShade`,
`ShadowDepthMasked`, `ShadowDistanceMasked`, `Splat` and `PolylineVertex`
answer to the names `flutter3d_shaders` 0.7.0 requires. The existing ones
follow their sources: `Composite` selects one of five tone curves, samples a
colour table, grades with lift, gamma and gain and adds its grain after the
sRGB encode; `BloomUpsample` tints its wide levels; the surface stages read up
to twenty-four lights past the first eight from a light texture, shade a
rectangular area light, keep a hashed fraction of a material's pixels and
widen a directional shadow's edge with the distance to its caster. The engine
leaves each of these off or at zero by default, and the default tone curve is
the one 0.6.0 had.

**The archive carries a skill**, `skills/flutter3d-cpu-rendering-in-a-test/`,
about drawing a frame with no GPU through `CpuDevice`, `encodePng` and
`compareFrames`. `dart run skills@ get` installs it for a coding agent.

## 0.6.0

* **Two reference pictures, and no code.** `cube-shadow-crowded` and
  `cube-shadow-many` are recorded again in this backend's own set. The scenes
  did not change; the demo that draws them stopped handing out point-shadow
  atlas rows on frames drawn before its model landed, and the software set held
  the same latched rows the other three did. The cross-backend gate is what
  caught it — 5037 and 1346 differing pixels against a budget of 0.02% — and all
  four sets now agree on the rows the ranking chose.
* The rasteriser, the encoder and every capability answer are byte for byte
  0.5.2's. A caller upgrading gets the same pixels out of the same calls; what
  moved is this package's test data.

## 0.5.2

* **A vertex stage can be told which vertex it is drawing.**
  `CpuVertexShaderByIndex` adds `runAt(vertexIndex, ...)` beside
  `CpuVertexShader.run`, which is handed attributes and no index. A second
  interface rather than a member on the published one, so every stage that
  exists still compiles: the encoder calls `runAt` when a stage implements it
  and `run` otherwise. Morph targets are what needed it — a vertex has to look
  its own deltas up in a texture.
* **`lib/morph.glsl`, transcribed.** Deltas read out of a texture by vertex
  index and added to the position, normal and tangent, against the GLSL rather
  than against `MorphBlend`: the same arithmetic on the host is a second
  source, and a transcription of a transcription drifts. Four tests hold it to
  a picture — weighting a target moves it, it lands where `MorphBlend` puts it,
  half a weight lands between, and a weight of nought costs nothing.
* `runAt` takes the instance index as well as the vertex index, and
  `lib/morph_instanced.glsl` is transcribed beside the one it extends: a batch
  whose copies wear different expressions draws them here too. The interface
  gained a parameter rather than a sibling because it had not been published
  yet — after this, adding one would break every implementer.
* **A float texture could not be uploaded at all, and said nothing.**
  `createTextureFromPixels` measured every format at four bytes a texel, so an
  `r32g32b32a32Float` — sixteen — was refused as the wrong size and the caller
  saw a null. Texel size now comes from the format, and the float formats are
  decoded as floats rather than as eight-bit unorm.

## 0.5.1

* **This backend was the one that was right, and its budget said otherwise.**
  Its transcription of the occlusion pass disagreed with Impeller over 7.647%
  of the corner scene, written down as a defect budget for whoever fixed it.
  What was wrong was the surface buffer's depth format on the two GPU backends;
  this rasteriser keeps every channel as a `double` whatever the format says,
  so it had the precision to draw the effect correctly and was being held to a
  picture that was not. The budget is 0.159% now, and reflections 0.633% to
  0.025%. See `flutter3d_shaders` 0.5.1.
* **`surface_depth_test.dart`**, holding the contract that channel now carries:
  a point round-tripped through it under a perspective camera and an
  orthographic one, and the two half-float numbers the change rests on.

## 0.5.0

* **`CpuShaderLibrary.stages` is unmodifiable.** It is built once and read
  afterwards, and a writer now breaks loudly rather than silently.
* Follows the engine's widened callbacks and the physics package's contact
  filter.

## 0.4.2

* **`maxAnisotropy` is one, and means it.** This rasteriser picks one level
  per triangle and takes one tap, so a sampler asking for eight is honoured
  on the hardware backends and ignored here — and the device says so rather
  than promising taps it does not take. `anisotropic-floor` is recorded in
  this backend's own set without them, and the cross-backend budget for the
  scene is the measured size of that difference, which is the one place the
  two sets are allowed to disagree on purpose.
* **A bundle loaded from bytes answers with the Dart this backend has.**
  `CpuDevice.loadShaders` compiles nothing — there is nothing here to compile
  — so `CpuLoadedShaderLibrary` answers each name the bundle claims with the
  device's own stage under that name, and refuses a bundle naming a stage it
  has no Dart for, naming the stages. An application's own look reaches this
  backend the way it always has, as a Dart stage handed to `CpuDevice.shaders`;
  the bundle that names it on the hardware backends then loads here too.
  `CpuShaderLibrary` caches its handles so their identity survives a refresh.
* **A refresh that drops a stage in use is refused, naming it.**
  `CpuLoadedShaderLibrary` remembers every name it answered with a handle,
  and a bundle that no longer names one of them is refused before it is
  taken — the contract `LoadedShaderLibrary.refresh` now states, kept the
  same way on every backend. Only a name that was handed out counts: a
  stage the bundle claimed and nobody asked for may come and go.
* **`readback`, at once.** Nothing here is in flight — the pass that wrote the
  floats ran to the end before `submit` returned — so the region is converted
  on the spot and the future is complete when it is handed back, which is the
  honest answer and what lets the engine's own tests of the callers run in a
  plain `flutter test`: a dark room climbing to the ceiling, two boxes picked
  apart.
* `Luminance` and `ObjectId` transcribed from the GLSL; `auto-exposure` joins
  the golden set at 0.581% from Impeller.
* **Alpha masking, transcribed.** `ReadSurface`'s discard under the cutoff
  had been left out on the grounds that no fixture exercised it; the picking
  stage needed the same hole, and an id pass that discards where the scene
  pass does not would pick what the eye cannot see. `readSurface` now answers
  null for a masked fragment under its cutoff and every lit model hands the
  null on, `ObjectId` samples the texture against `IdInfo.mask` the way the
  GLSL does, and the test is a red fence with a hole in front of a white box:
  the pick through the hole says box, and so does the pixel.
* **A stencil buffer, a byte per pixel beside the depth.** Every one of the
  eight operations, both masks, the reference and a state per face, tested
  before the depth test and applied after the fragment stage — so a discard
  writes nothing, as it does on hardware — with a fixture per rule in
  `stencil_test.dart`. Nothing is asked per fragment while the test is off,
  so the thirty-four scenes that never mention it draw as they did.
* **The blend equation, factor by factor.** Two states were recognised by
  testing two of their factors, and `BlendState.keepDestination` — zero and
  one — read as one and one. Every factor is a line now; the four that need
  a blend constant throw, because the interface has no way to set one.
* `XrayShader`, the transcription of `xray.frag`: the albedo and not one word
  about the surface, so `FragmentContext.surface` is left null and the encoder
  writes nothing to attachment one.
* `stencil-xray` joins the golden set.
* **A pass renders into a cube face and a mip level.** `CpuTexture.subresource`
  walks to the array a face and a level own — the same structure
  `BoundTexture.sampleCube` reads — and every write of a pass goes through
  it; `createCubeRenderTarget` builds that structure empty, a chain per face.
  `ProbePrefilterShader` transcribes `probe_prefilter.frag`; `probe-car`
  joins the golden set.
* **The blend constant, which this backend used to throw for.**
  `setBlendColor` is a field on the pass and four arms in the blend equation,
  so all fifteen `BlendFactor` values are drawn rather than eleven.
  `supportsBlendColor` answers true.

## 0.4.1

* The lightmapped vertex stage and the lightmap term in the four lit models,
  transcribed from the GLSL; the mesh varyings grow by the coordinate.
* **A compressed format is refused by name, and asked about first.**
  `createTextureFromPixels` used to read block bytes as RGBA8 and hand back
  a texture full of noise; it throws naming the format now, and
  `supportsTextureFormat` says no to every block-compressed value before a
  loader gets that far, because this backend samples raw texels and always
  will.

## 0.4.0

* **`CpuFrame` disposes its images.** It had no `dispose` at all — one leaked
  `ui.Image` per presented frame — and two in-flight decodes could finish out
  of order. The previous image is disposed when a new one lands, the fresh one
  when the widget is already gone, and a sequence number keeps a stale frame
  from overwriting a newer one.

## 0.3.0

* The composite pass mirrors the grading, vignette, grain and dispersion the
  hardware backends apply, so the two reference sets stay comparable.
* Cube texture uploads validate each mip level's size rather than accepting
  anything that fits.

## 0.2.0

* `flutter3d_hardware` rasterised in Dart with no GPU under it: what the golden
  images are drawn with, and what a test renders a whole frame through.
* Deliberately shares nothing with either hardware backend — no driver, no
  shading language, no command buffer — which is what makes agreeing with them
  mean something.
