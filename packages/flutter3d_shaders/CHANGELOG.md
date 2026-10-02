## Unreleased

- **`FragInfo.debug_view` and `WriteDebugView`** in `surface.glsl` — `P6`:
  every lit model asks it before writing its light. NaN is found by
  comparison, because `impellerc`'s GLSL ES output has no bit casts.
  `CompositeInfo.lens` y and z say whether a debug view is on and where it
  starts.

- **`LensFlare`**, with the `LensFlareInfo` block, and a `lens` member
  appended to `CompositeInfo` for the distortion.
- **Three stages for SMAA 1x**: `SmaaEdges`, `SmaaWeights` and `SmaaBlend`,
  with the `SmaaInfo` block. A bundle must answer to them; the renderer falls
  back to FXAA when one does not.

**A decal stage.** `post/decal.frag` (`Decal`) paints up to sixteen
projected boxes, reading four pictures, over the point the surface buffer
names under each pixel. It writes a factor and a term for two blends, the
albedo swapped under the light the albedo buffer lets it read back, and the
colour an unlit surface and an emissive decal add.

**Two stages for `P4`.** `lighting/planar_reflection.frag` lays a mirrored
picture over a reflector's surface, read by the fragment's place in its view
and weighted by Schlick's Fresnel; it declares no surface buffer, as
`xray.frag` does not. `post/render_texture_encode.frag` turns a camera's
light into the sRGB bytes a material's map is read as, turning the rows over
where the backend draws its first row at the bottom. Both are in the bundle,
in `kRequiredShaders` and in `stageBindings`, `uniformBlocks` and
`typed_blocks.dart`.

**`SkyPhysical` and `SkyPhysicalVertex`**, the physical sky: single
scattering by molecules and haze marched per pixel, sixteen samples along the
view and eight towards the sun from each, the disc and the stars dimmed by the
air, and the ground below the horizon. The air travels on the vertices, as the
gradient's preset does.

**`ApplyFog` integrates a height fog.** `FogInfo.eye.w` carries the falloff
and `FogInfo.fog.w` the density at the eye; a falloff of nought takes the old
path unchanged.

**The WebGL2 and WebGPU translators live here now, behind
`translate.dart` and `compile.dart`.** `flutter3d_build`'s material step has
to translate a project's materials from a hook process that cannot resolve a
package declaring the Flutter SDK, and `flutter3d_webgl` and
`flutter3d_webgpu` both declare one. None of the moved files ever needed the
SDK. `translate.dart` holds the pure parts: `translateGlsl` and
`resolveIncludes`, `prepareStage`, and the writers for both sections.
`compile.dart` adds the parts that need a machine: `loadShaders` (which now
takes `from:`, and whose `ShaderSet` carries the `root` it read),
`compileStage` through glslang and naga, and `bundleVaryingLocations`, which
used to be private to `pack_wgsl_section.dart`. The barrel exports neither,
so an application carries no compiler.

## 0.8.2+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2`, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.2

**A PCSS tap allows for the receiver's own slope.** `ShadowFactor` in
`lib/shadow.glsl` compared every tap of the soft-shadow kernel with the one
bias the centre was given, and a lit slope's own depth, now in the sun's map
since `flutter3d_core` 0.8.2 records both faces, rose past it a few texels
up the slope: at a 75° slope under a sun of 0.2 rad, 9% of the slope came
out self-shadowed. Each tap now adds the depth the receiver's plane gains
over its distance from the centre, beyond the reach the normal offset
already covers, and the same slope is fully lit. The blocker search and the
filter both use it.

The comment on the direct-light energy compensation in `lib/pbr.glsl` names
its source, Turquin 2019.

## 0.8.1

**A contact shadow resolve stage.** `post/contact_shadow_resolve.frag`
averages a 4×4 window of the contact shadow buffer, offsets -2 to +1 on both
axes, so every phase of the march's 4×4 Bayer dither is counted exactly once.
Each tap weighs less the further its depth is from the centre's, so the
average stops at silhouettes, and sky taps are skipped. It is in the bundle
and in `stageBindings`, `uniformBlocks` and `typed_blocks.dart`.

**The sun's flat normal offset is held to a texel of its cascade.**
`ShadowFactor` in `lib/shadow.glsl` took `ShadowSettings.normalOffset` whole,
two centimetres by default, on top of what the 3×3 kernel needs. Under a low
sun a step along the normal is nearly all sideways across the map, and in a
sharp near cascade two centimetres is several texels: a sheet folded a
centimetre or two over itself was lit through its upper layer along the
crest. Shadow edges move by about a pixel.

## 0.8.0

The stages behind `flutter3d_core` 0.8.0; its CHANGELOG says what each effect
does and what it costs. Every stage that existed in 0.7.4 draws the same
picture under the settings it had, apart from the corrections listed first.
What a caller of these sources and tables sees:

* **The bundle describes itself.** `stageBindings`, in
  `package:flutter3d_shaders/stage_bindings.dart`: what every stage keeps
  once compiled, the blocks and samplers a draw must bind and may bind.
  `uniform_blocks.dart` gives each stage's block layouts (member offsets,
  lengths, element counts and types, per stage, since one block name can be
  wider in one stage than another), and `typed_blocks.dart` a class per block
  with one preallocated array per member, extending `UniformBlock`, for
  `PassEncoder.bindBlock`. All three are generated from the compiler's own
  reflection by `flutter3d_impeller/tool/stage_bindings.dart`, and a test
  holds them to a fresh compile. `FakeBackend` takes `stageBindings` so a
  renderer's binds are checked against the real bundle on the VM. For the
  block classes the package now depends on `flutter3d_hardware`.
* **Compute stages have a manifest of their own**,
  `shaders/flutter3d.compute.json`, which neither impellerc nor the WebGL2
  generator reads. `kComputeShaders` lists it; `PrefixSum` is the first
  stage.
* **Screen patterns count rows from the top.** `lib/frag_coord.glsl` and
  `lib/frag_coord_info.glsl` (the `FragCoordInfo` block) give full-screen
  passes the target's orientation, and lit stages read it from `FragInfo`.
  The dither, grain, march jitter and point-shadow rotation were upside down
  on WebGL2.
* **`pbr.frag` is `lib/pbr.glsl` with nothing defined**, and compiles to what
  it did. `pbr_layered.frag` is the same file with `F3D_LAYERED`: IOR,
  specular, clearcoat, sheen, anisotropy, transmission, volume, dispersion and
  iridescence, factors in a `LayerInfo` block that also carries a 2x3
  transform per map, read through `MapUv`. The coat map packs coat, coat
  roughness, transmission and thickness; the sheen map is its sixteenth
  sampler. Both metal-rough stages integrate a rectangle light by LTC
  (`lib/ltc.glsl`, `F3D_LTC`) and take the EON diffuse lobe when
  `FragInfo.ambient_sky.w` asks.
* **`lib/shadow.glsl`**: near cascades carry their own converted bias
  (`FragInfo.shadow_bias`, `ShaftInfo.bias`), PCF taps stay in their tile,
  the soft directional search and filter are sixteen Vogel taps sized in
  metres, and a negative softness in `ambient_ground.w` reads EVSM moments
  (`lib/evsm.glsl`) with one tap.
* **`lib/surface.glsl`** reads the irradiance atlas per fragment
  (`lib/irradiance.glsl`) and writes the albedo buffer at location two. The
  light list declarations move to `lib/light_list.glsl`, with the cluster
  lookup, so `lib/contributor_lights.glsl` can share them; the lit stages
  compile to the same code.
* **`lib/blue_noise.glsl`** holds the 4x4 pattern the jittered passes used to
  copy, and the blue-noise slice they read while a temporal resolve runs.
* **`ssao.frag`** gains GTAO and SSIL, chosen by `SsaoInfo.screen.z`, and
  writes four channels; `ssao_blur.frag` smooths all four, and
  `composite.frag` takes occlusion from alpha, adds the indirect light from
  rgb, reads a display transform table and applies local exposure.
  `fxaa.frag` gains the robust contrast-adaptive sharpen.
* **New stages**: `CameraVelocity`, `Velocity` with `VelocityVertex`,
  `VelocitySkinnedVertex` and `VelocityInstancedVertex`, `TemporalResolve`,
  `TemporalAccumulate`, `Reactive`, `ReactiveSprite`, `VelocityTileMax`,
  `VelocityNeighborMax`, `MotionBlur`, `Easu`, `LocalExposure`,
  `LocalExposureBlur`, `VolumetricFog`, `VolumetricFogUpsample`,
  `IrradianceConvolve`, `FieldDecay`, `ShadowCopy`, `EvsmFilter`,
  `DepthPyramid`, `WboitResolve`, `SceneColourCopy`, `PbrLayered`,
  `ImpostorVertex`, `Impostor`, `ParticleSixWay` and `SplatHashed`. Each is in
  `kRequiredShaders`, and every compiled stage stays within WebGL2's 16
  samplers and 12 uniform blocks, which a test holds.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.4

The stages behind `flutter3d_core` 0.7.4's corrections; its CHANGELOG has the
reasons. What a caller of these sources sees:

* `composite.frag`: AgX linearised and without the extra desaturation; the
  contrast pivot at 0.18; the classic lift; the LUT through sRGB; the dither
  centred. `SrgbToLinear` is new beside `LinearToSrgb`.
* `lib/surface.glsl` and `lib/color.glsl`: a back face reverses its normal
  (`gl_FrontFacing`), for the lit term and the surface buffer.
  `lib/material_maps.glsl` turns the tangent with it.
* `lib/shadow.glsl`: the normal offset adds one cascade texel scaled by the
  slope to the light, and past the last cascade's far plane a point is clamped
  to it, not called lit. `light_shafts.frag` clamps the same way.
* `reflections.frag`: jittered, refined, faded with distance, back faces
  rejected, Schlick's Fresnel, the roughness window 0.05 to 0.25.
* `light_shafts.frag`: single scattering with transmittance and a
  Henyey–Greenstein phase; `ShaftInfo` gains `sun`.
* `bloom_threshold.frag`: Karis's weighted average. `bloom_upsample.frag`:
  `BloomInfo` gains `tint`, the per-level ratio the caller computes, in place
  of the halation it read from `params.w`.
* `depth_of_field.frag`: the reach test that held for every sample, the sky at
  infinity, a spiral turned per pixel.
* `contact_shadow.frag`: jittered steps and a tolerance of two steps' depth.
* `ssao_blur.frag`: the depth weight relative to the centre's depth.

## 0.7.1

* **Stages that read no light list declare none.** `F3D_NO_LIGHT_LIST` leaves
  the block and its texture out of `lib/surface.glsl`, and `unlit.frag` and
  `xray.frag` set it. Their compiled Metal functions had dropped both while
  the reflection still listed them with no index, which is what the renderer
  bound on 0.7.0. `object_id.frag` and the two point-shadow distance stages
  set `F3D_NO_FOG` for the same reason: they declared a fog block they never
  read, which on Vulkan collides with the vertex stage's binding.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

## 0.7.0

* **Not a Flutter package any more.** The pubspec carried `flutter: sdk` and
  `flutter_test` since the split from `flutter3d_impeller`, and nothing needed
  either: `kRequiredShaders` is a plain `const` list and `manifest_test.dart`
  uses `test` and `expect`, which `package:test` gives. This was the one edge
  through which `flutter3d_conformance`, and every backend's
  `conformance_test.dart` with it, resolved the Flutter SDK.
* **The shadow pass no longer declares a block it never reads.**
  `shadow_depth.frag` includes `lib/color.glsl` for its varyings and got
  `FogInfo` with them. On Vulkan the descriptors of both stages merge into one
  set layout, and a fragment stage whose only block is that one lands on the
  vertex stage's first binding. A Galaxy A55 refused the pipeline with
  `ErrorUnknown` and the process died inside the driver a few passes later.
  `#define F3D_NO_FOG` before the include leaves the block out and turns
  `EyeDistance`, `ViewDepth` and `ApplyFog` into stubs, so a caller reads the
  same either way.
* **Ten new entry points in `kRequiredShaders` and the manifest.** `Fxaa`,
  `SsaoBlur`, `ContactShadow`, `LightShafts`, `DepthOfField` and
  `ViewportShade` under `post/`; `ShadowDepthMasked`, `ShadowDistanceMasked`
  and `Splat` under `lighting/`; and one vertex stage, `PolylineVertex`. A
  bundle built against 0.6.0 is missing all ten, and the conformance suite's
  name check says which. The two masked shadow stages are separate stages and
  not a branch in the plain ones, so a caster that is not cut out keeps a
  pipeline with no sampler in it.
* **`post/composite.frag` has five tone curves, a colour table and a three-way
  grade.** `TonemapBy` selects among the neutral curve, `TonemapAces`,
  `TonemapAgx`, `TonemapReinhard` and `TonemapAgxFull`; the neutral one is
  numbered 1 so that a scene recorded against the old on/off flag reads the
  same. `SampleLut` reads `lut_texture`, a strip of N slices of N by N, after
  the grade and before the vignette, and a strength of zero branches past the
  sample. Lift, gamma and gain are a colour each. Grain moved to after the
  sRGB encode, beside the dither: before it, `max(color, 0.0)` clipped the
  negative half and 0.08 of grain on black encoded to 56 of 255. The stage
  also declares `contact_shadow_texture`.
* **`lib/surface.glsl` reads lights past the eighth.** `kMaxLights` is still 8
  and `kExtraLights` is 24. The extra ones come from `light_list_texture`, four
  texels a light, addressed through the new `LightListInfo` block, and carry no
  shadow: `LightHasShadow` is `index < kMaxLights`. The four light arrays in
  `FragInfo` did not widen, so no offset in that block moved. The same file
  gains `RectangleFormFactor` and `RectangleClosestPoint` for a rectangular
  area light, and the hashed alpha mode, which rides in `material2.x` below
  -1.5.
* **`lib/shadow.glsl` can widen an edge with the distance to the caster.** A
  radius above zero searches for the blocker on the five points of
  `kShadowDisc` and filters with five more at a radius taken from how far away
  it was. The number rides in `ambient_ground.w`. Zero is the 3x3 kernel 0.6.0
  had and is what the engine sends by default.
* `post/bloom_upsample.frag` tints its wide levels and leaves the core the
  colour of the highlight.
* The archive carries a skill for a coding agent,
  `skills/flutter3d-shaders-one-copy/`, about the manifest as the contract and
  the three rules the sources are written under. `dart run skills@ get`
  installs it.

## 0.6.0

* **Six samples taken under a branch ask for a mip level by name.** `texture`
  derives its level from the difference between neighbouring invocations, and
  that difference is only defined where all four invocations of a quad arrive
  together. Five files were taking a sample where they do not: the cascade
  search returns early, the light loop skips a light facing away, the reflection
  march breaks when a ray leaves the frame, the ambient-occlusion loop
  `continue`s past a sample outside it. A WGSL backend refuses exactly that,
  which is how they were found. Four of the five — `shadow.glsl`,
  `surface.glsl`, `reflections.frag`, `ssao.frag` — now call
  `textureLod(..., 0.0)` at six call sites.
* **Not a picture change on any backend, and that is the point.** Every texture
  involved is a render target with a single level — the cascade atlas, the two
  point-shadow atlases, the surface buffer, the scene colour — so level zero is
  the level the derivative was selecting anyway. Naming it costs nothing and
  removes the undefined behaviour rather than papering over it.
* **The normal map is the one that could not be pinned, so it was hoisted
  instead.** `ApplyNormalMap` samples before the degenerate-tangent test rather
  than under it. That map really is mipped — read at full resolution on a
  surface turned away from the camera it is the widest disagreement there has
  ever been between backends — so forcing level zero would have changed the
  picture. The sample now happens above the branch, reads the same texel the
  branch would have read, and pays for one unused fetch in the rare case.
* Nothing was added to or removed from the header set, and no entry point
  changed name, so a bundle built against 0.5.2 answers to the same list.

## 0.5.2

* **Every texture read under a branch names its level or moves above the
  branch.** WGSL will only derive a mip level where all four invocations of a
  quad agree to be, and six lit and screen-space stages sampled under a
  condition that does not promise it — a light the surface faces away from, a
  cascade that misses the fragment, a ray already off the frame, a tangent too
  degenerate to build a frame from. The cascade atlas, both point-shadow
  atlases, the surface buffer and the scene colour are single-level render
  targets, so `lib/shadow.glsl`, `lib/surface.glsl`, `post/reflections.frag`
  and `post/ssao.frag` read them with `textureLod` at level zero — the level
  the derivative was choosing anyway. `lib/material_maps.glsl` does the
  opposite, because a normal map's mip chain is real and pinning it would blur
  or sharpen the picture: the sample moves above the degenerate-tangent test
  instead. Nothing any backend draws changes.
* **`lib/morph.glsl`: a vertex moved towards the shapes its mesh carries.**
  Deltas in an `r32g32b32a32Float` texture — one column a vertex, three rows a
  target — read by `gl_VertexIndex` and blended by up to eight weights. A
  texture rather than vertex attributes because the layout here is structural:
  the `in` declarations of `mesh.vert` *are* the layout, and deltas as
  attributes would mean a second vertex shader for each lighting model.
* `lib/morph_instanced.glsl`, included by `mesh_instanced.vert` alone: the same
  blend with each instance's weights, read by `gl_InstanceIndex` from a texture
  of one row a slot. A file of its own because a sampler declared in
  `lib/morph.glsl` would be declared on all four mesh vertex stages and bound
  by every draw for ever; the deltas are worth that and a second sampler three
  stages can never use is not. `ApplyMorph`'s delta read is split out as
  `AddMorphTarget` so both paths reach a texel through the same three lines.
* Read with `texture()` at texel centres rather than `texelFetch`, and handed
  the texel size in the uniform rather than asking `textureSize`: impellerc
  aborts on `texelFetch` in a vertex stage.
* `mesh.vert`, `mesh_skinned.vert`, `mesh_instanced.vert` and
  `mesh_lightmapped.vert` all morph before their transform — the skinned one in
  the rest pose first, the instanced one before the instance matrix, since the
  deltas are in the mesh's own space and a batch shares its mesh.
* A probe pair, `probe/vertex_texture.vert` and `.frag`, which passes what the
  *vertex* stage sampled through to the fragment stage. It is how the
  conformance suite asks whether a backend can do this at all.

## 0.5.1

**The surface buffer's alpha changes meaning, and `FogInfo` gains a member.**
Breaking for anything that declares that block or reads that channel. It goes
out as a patch because nothing outside this repository has taken a dependency
on 0.5.0 yet; the entry says what it is rather than what the number implies.

* **`frag_surface.a` holds the depth along the view axis in world metres**,
  where it held `gl_FragCoord.z`. The attachment is `r16g16b16a16Float` on
  every backend, and a window depth spends nearly the whole of `[0, 1]` on the
  first few metres — past twenty, one half-float step is wider than half a
  metre, so a wall at twenty and one at twenty and a half stored the same
  number. Both passes that read this buffer decide occlusion by subtracting two
  of them, and the rounding decided whole bands of the frame: vertical stripes
  along the lines of equal depth, on both GPU backends, in every scene with a
  wall in it. `WriteSurfaceGeometry` and the new `ViewDepth` beside
  `EyeDistance` carry the reasoning.
* **`FogInfo` gains `vec4 forward`**, the camera's world-space direction, which
  is what a fragment needs to compute that depth. A custom lit shader that
  declares this block must declare the member: the engine binds it, and a
  backend that checks its bindings refuses one the shader does not have. The
  three particle stages declare the block without it on purpose — a particle
  writes no surface buffer — and are bound without it.
* **`SsaoInfo` and `ReflectionInfo` gain `vec4 forward` beside `camera`.**
  Reconstructing a point from the stored depth is now a ray crossed with a
  plane, and both ends of the pixel's ray are unprojected rather than one end
  and the camera position: an orthographic camera's rays are parallel and meet
  nowhere, so the cheaper version is right on a perspective camera and wrong on
  every isometric scene. `reflections.frag` takes its view vector from that ray
  as well.

## 0.5.0

* No API change. Released with the set.

## 0.4.2

* **`Luminance`**: the lit scene's log luminance at low resolution, sixteen
  taps per texel, encoded in eight bits over sixteen stops from minus ten —
  what an exposure meter reads back. `LuminanceInfo.params` carries the
  footprint and the two ends of the encoding.
* **`ObjectId`**: every mesh drawn again through its own vertex stage with a
  fragment stage that writes the id in `IdInfo.id` as three bytes, into a
  single attachment, so one pixel read back says which node is under the
  cursor. `kRequiredShaders` names both. The stage samples
  `base_color_texture` and discards under the cutoff in `IdInfo.mask` — the
  material's alpha cutoff, negative when it is not masked, beside the tint's
  alpha — so what the scene pass throws away is thrown away here as well and
  a pick through a hole answers with what is behind it.
* **`Xray`**, a seventh lighting entry point: `unlit.frag` with
  `F3D_NO_SURFACE_BUFFER` defined, so it declares no second output at all.
  The x-ray stage draws its mark and its silhouette with it. Drawn unlit they
  wrote the surface buffer — the silhouette wherever its `greater` test
  passed, which is where the marked node is *behind* what the depth buffer
  holds — so a hidden node's normal, roughness and depth landed on top of the
  surface in front of it, and every screen-space effect reads that buffer as
  the nearest surface. `kRequiredShaders` names the new entry point.
* **`ProbePrefilter`**, a full-screen fragment stage that writes one face of
  one level of a reflection probe: the captured cube convolved by the
  roughness of the level, with the fixed spiral of taps and the cosine-power
  lobe `EnvironmentMap.prefilter` uses on the host, and a one-tap copy for
  the mirror level. `kRequiredShaders` names it.

## 0.4.1

* **`MeshLightmappedVertex`**, a fourth vertex stage: the standard layout
  with `color.xy` read as the vertex's place in a lightmap and the tint held
  at white. Every mesh stage now carries a `v_lightmap_uv` varying, and the
  lit models sample `lightmap_texture` (RGBM, `rgb × a × 8`) beside their
  ambient. `kRequiredShaders` names the new stage.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* The physical model samples a prefiltered environment, and the composite pass
  applies a look.

## 0.2.0

* Cascaded directional shadows, spot shadows, screen-space ambient occlusion, a
  procedural sky and two-colour ambient light.
* The shared header split so a stage declares only the uniform blocks it reads:
  a block a shader declares but never reads is reflected at a non-zero size and
  binding it is a native crash.

## 0.1.0

* The engine's shader sources in GLSL, shared by every backend so that no two
  of them can drift, with `kRequiredShaders` naming the entry points a bundle
  must answer to.
