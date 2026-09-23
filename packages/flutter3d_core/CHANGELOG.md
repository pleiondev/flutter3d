## 0.7.3

- **A material's own vertex stage gets the morph state when it declares it.**
  0.7.2 fixed `Material.polyline` on Impeller by binding morphs to a
  material's own stage only when the node morphed. A stage written from
  `MeshVertex` declares the morph block and texture either way, so on a plain
  mesh it went without them: another draw's weights on the software backend,
  garbage on WebGL, a native failure on Metal. The bind now follows
  `LightingModel.vertexStageMorphs`, which is new, true by default, false for
  `LightingModel.polyline`, and round-trips through `.fmat` as `vertexMorphs`.
- **`MaterialBindings.lightingModel` builds the model a material in the
  language needs.** Every flag comes off the program, `usesLightList: false`
  included. A hand-built model that samples maps defaulted the light list on,
  and the emitted stage never declares it.

## 0.7.2

- **`Material.polyline` draws on Impeller.** The renderer bound the morph
  block and texture to whichever vertex stage drew, and `PolylineVertex`
  declares neither. The missing block was skipped, but flutter_gpu refuses a
  texture bound to a slot the stage does not have, so every polyline threw
  "Failed to bind texture" at its first draw on macOS and iOS, in 0.7.0 and
  0.7.1 alike. WebGL and the software backend let the extra bind pass. A
  material's own vertex stage now gets the morph state only when the node
  morphs; the engine's four mesh stages still get it on every draw. Found by
  drawing an unlit sphere, a polyline and a lit cube one at a time on Metal.

## 0.7.1

- **A surface with no normal map is flat again, whichever way its tangent
  runs.** The fallback normal texture stores 0.5 as byte 128, which decodes
  to 0.0039 rather than 0, so every map-less material was tilted by about a
  third of a degree along its tangent and its shading depended on the
  tangent's direction. The renderer now sends a normal scale of zero with the
  fallback, which leaves exactly (0, 0, 1) on every backend. Setting
  `normalScale: 0` by hand is no longer needed for that.
- **`Scene.defaultLightWhenUnlit`, a switch for the light nobody added.** A
  scene with no live light is still lit by one directional light by default.
  A light counts as live only when it is visible and above zero intensity, so
  turning off the only lamp used to switch a bright default light on. Set the
  flag to false and an unlit scene stays unlit, with no black light parked in
  it to keep the count above zero.
- **`Material.baseColor` is documented as what it is: sRGB in rgb, linear in
  alpha.** The doc said linear, and every shader converts it with `toLinear`,
  so a colour converted by hand went through the curve twice. Nothing about
  the rendering changed.
- **An unlit draw no longer crashes Metal on the first frame.** 0.7.0 bound
  the light list, the `LightListInfo` block and `light_list_texture`, to
  every draw. The Unlit stage (and the polyline, which uses it) gathers no
  lights and keeps neither in its compiled Metal function, so the bind went to
  a slot index the driver does not have and the process died inside
  `setFragmentBuffer:offset:atIndex:` on macOS and iOS alike. Vulkan accepted
  the same bind, which is why Android drew. The list is now bound only when
  `LightingModel.usesLightList` says the stage reads it. That is new, defaults
  to `usesMaterialMaps`, round-trips through `.fmat` as `lightList`, and is
  false for anything the material language emits.

- **The rest of a full read of the engine.** A failed frame no longer keeps its
  texture out of rotation or leaves the timeline block open; a new shadow
  resolution, a resize, `dispose` and `FrameResources.provide` release what
  they replace. A flickering torch past the first eight lights keeps flickering,
  a spot light taking over a point light's atlas row clears its tiles, and a
  replaced `Sky` draws. `lookAt` and the IK solvers work under a scaled parent,
  a skinned mesh is picked in its current pose and an instanced batch against
  every instance, and morphs and skinned bounds stop culling a visible mesh.
  `Scene.clear` is linear. `Material.copy` keeps the parameter block,
  parameters and extra textures.
- **The decoders refuse a bad file instead of hanging or reading past it.**
  meshopt, sparse glTF accessors, `.f3d` record counts, zstd and HDR sizes and
  KTX2 universal levels are checked, each with its own `FormatException`.
  meshopt filters are refused by name rather than decoded as noise, OBJ keeps
  corners with different UVs apart on the web, smooth OBJ normals follow
  positions across UV seams, USDZ flips winding under a mirror, JPEG decodes
  non-interleaved and multi-scan files, and `.fmat` keeps `mipLinear` and a
  custom vertex stage.
- **`LightNode.castsShadow` is read on the sun too.** The renderer cast the
  first directional light whatever its flag said, because only the cube
  shadows read it, so "this sun does not cast" could only be said by turning
  shadows off for the frame. It now picks the first directional light that
  asks. **The default follows the type**: left out of the constructor, it is
  true for a directional light and false for the others, which is what every
  scene already drew. A sun built with `castsShadow: false` stops casting.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3, `image` ^4.10.1.

## 0.7.0

- **The first publication: the engine with no Flutter SDK behind it.** The
  0.1.0 below was a number carried inside the workspace and never reached
  pub.dev. 0.7.0 is the number the whole shelf goes out on, so one number names
  one tree and `^0.7.0` on any `flutter3d_*` package resolves against every
  other; publishing first at 0.7.0 skips numbers nobody outside ever saw, and
  `doc/boundary-0.7.0.md` lists the thirteen packages that begin here. This is
  the renderer, the scene graph, animation and the asset layer that `flutter3d`
  0.6.0 held, moved out whole (`mcp-03n`), with everything written since. It
  depends on `flutter3d_hardware` and `vector_math` and on nothing else, and
  `flutter3d` re-exports it, so an application importing
  `package:flutter3d/flutter3d.dart` keeps every name. What follows is what
  changed against the engine inside `flutter3d` 0.6.0.

- **Accepted `flutter3d_geometry`, `flutter3d_formats` and `flutter3d_fbx`.**
  They are `package:flutter3d_core/geometry.dart` and
  `package:flutter3d_core/formats.dart` now, each importable on its own and
  both exported from `flutter3d_core.dart`; `FbxDecoder` is part of the formats
  library. All three were plain Dart with `vector_math` as their only
  third-party dependency and none was published, so the package boundary gave a
  caller that wanted a mesh or a `.glb` without the renderer nothing a library
  does not. Their tests, tools and skills moved with them; the skills are
  `flutter3d-core-geometry-meshes` and `flutter3d-core-formats-reading-models`.
  `FbxDecoder` recognises an FBX file by its magic or its extension and refuses
  every one with a `FormatException` that says to export glTF; the reader is
  not written. `flutter3d_core.dart` hides the formats library's `Ktx2Texture`,
  which carries a raw `vkFormat`, behind the engine's own, which carries a
  `TextureFormat`.

- **What a file written against `flutter3d` 0.6.0 has to change.**
  `uploadEncodedImage` requires `decodeImage`, an `ImageDecoder` answering an
  `Rgba8Image`, because this package cannot call `dart:ui`. `flutter3d` has
  `defaultImageDecoder`, and `decodeImagePure` here reads PNG and baseline JPEG
  with no SDK at all. Three enums gained a value, so an exhaustive `switch`
  over one stops compiling until it answers it: `LightType.area`,
  `MaterialAlphaMode.hashed` and `ModelFormat.stl`. `GraphicsDevice.present` is
  gone from `flutter3d_hardware`, which this package re-exports; a frame is
  shown through `presentFrame` in `flutter3d_app`. `SceneNode.visible` is a
  setter over a cached value where it was a field, so hiding a branch reaches
  everything under it. `AssetSource`, `FileAssetSource` and `fileUriResolver`
  are here, and `BundleAssetSource` and `assetUriResolver`, which name
  Flutter's asset bundle, stayed in `flutter3d`.

- **The frame says what it did.** `FrameResult.passes` is one `FramePass` per
  node the compiled graph ran, in order, with `micros`, `drawCalls`,
  `triangles` and `pipelineSwitches` (`gfx-01n`). `FrameResult.triangles` and
  `instances` count the scene's meshes, an instanced batch once per instance.
  `skipped` lists each pass that did not run with a `PassSkip` reason: off by
  its own setting, disabled by name, unconsumed, starved, or `unsupported` on
  this device. `PassSkip` is a final class with constants, so a sixth reason
  will not break a `switch`. `antiAliasing` reports what smoothed the edges and
  why multisampling was declined, which is one of two things: the device, or a
  pass in this frame that reads the surface buffer. Counting per pass found
  that `drawCalls` had never included the shadow map or the bloom chain; a
  directional fixture that read 4 reads 13.

- **Passes are addressed by name.** `RenderSettings.disabledPasses` takes node
  names, and the graph refuses a name no node carries, so `'fxaa'` for the node
  called `antialias` is an error and never a silently unchanged frame.
  `RenderSettings.passOrder` publishes the names in registration order,
  `undisablePasses` the three the graph will not drop (`scene`, `composite`,
  `object ids`), and `probePassName` the name of a probe's pass.
  `Renderer.planFrame` compiles the graph for a frame without drawing it and
  answers the `CompiledFrameGraph`, with its own light buffer and shadow slots
  so that a frame drawn after a plan is the frame drawn without one.
  `RenderSettings.forMeasurement()` is the complete set for reading values off
  a debug view: tone map off, exposure 1, bloom off. It replaces three
  hand-built copies that left bloom on, which moved the `animation-weights`
  golden.

- **A frame captured pass by pass, and one pass measured.**
  `Renderer.captureNextFrame()` is a one-shot that answers a `FrameCapture`:
  each `CapturedPass` with its reads, optional reads, writes and keeps by the
  graph's own names, and an image of everything it wrote. A resource with no
  image says why: tile memory, multisampled, a cube, or a name nothing provided.
  `FrameCapture.firstBlack` finds the first pass whose output came back black.
  It is exact on the software rasteriser; on the hardware backends a readback
  may resolve after the queue moved on. `contributionBetween` differences two
  frames into a `PassContribution` of four numbers: pixels changed, their mean
  change, the largest change and the bounds of the change.

- **A caller's own post effect, and post-processing on a buffer from
  outside.** `FullscreenEffect` wraps the read-modify-write of the right
  resource, the transient target and the shared vertex stage; it has a name and
  an `enabled`, so it appears in `passes` and `skipped` and answers to
  `disabledPasses` like a pass of the engine's. Two constructors pick the
  phase. `Renderer.renderPost(hdr, settings)` runs bloom and the composite over
  an HDR buffer handed in, registered through `FrameGraph.addExternal`, and
  answers a `PostFrameResult`; with `keepHdr` it also returns the bloomed
  buffer. Reflections and ambient occlusion are not in that call, since both
  read the surface buffer.

- **A second colour attachment is refused where opening it would abort.** On
  Impeller's OpenGL ES path a second attachment reaches an `FML_CHECK` and the
  process stops, in release too. The five nodes that read the surface buffer
  are culled on a device whose `maxColorAttachments` is 1 and reported as
  `PassSkip.unsupported`, and the scene pass attaches only what the device can
  open (`gfx-50n`).

- **Culling and the work a still scene no longer does.** The render list culls
  by the mesh's world box where it used the sphere around it, which for a wall
  or a fence reached up to sqrt(3) times further (`gfx-61n`). A scene that
  moved refits `SceneBvh` and no longer rebuilds it: 23 ms to 0.85 ms on
  50 000 meshes, and `RenderList.bvhThreshold` is a field, 256 by default
  (`gfx-62n`). `SceneNode.subtreeBounds` lets a branch outside the frustum cost
  one test, with `RenderList.considered` counting them (`gfx-66n`). Each shadow
  cascade and each cube face culls its casters against its own frustum
  (`gfx-63n`). `worldMatrix` and `visibleInHierarchy` return on one integer
  comparison against `SceneNode.changeEpoch`, and `Skeleton.update` returns at
  once for a pose it already computed: 16.4 us to 4.7 us on 64 joints
  (`gfx-64n`, `gfx-65n`). The directional shadow pass is cached on the cascade
  matrices, the change epoch and the casters' materials, so a still camera over
  a still scene draws no cascade (`gfx-68n`). None of the forty-four golden
  scenes moved.

- **Identical draws batched, resolution as a setting, and memory given
  back.** `RenderSettings.batchIdenticalDraws` merges a run of four or more
  opaque nodes that share a mesh, a material, mirroring and a reflection probe
  into one instanced call, and `FrameResult.batchedDraws` counts them; it is
  off by default because it was compared byte for byte on the software
  rasteriser only. `InstancedMeshNode` gained `ensureCapacity` and `clear`.
  `RenderSettings.renderScale`, clamped to [0.1, 1], sizes every target of the
  frame, and `FrameResult.frame` is the smaller texture, which a presenter
  already stretches. `AdaptiveScale` is the policy over it, driven by
  `FrameResult.cpuMicros`: down above 1.1 times the target period, up only
  below 0.7 times it and after six clean windows.
  `Renderer.releaseTransientTargets` trims the render target pool, and
  `MemoryPressureRelease` in `flutter3d_app` calls it on a memory warning.

- **More than eight lights reach one draw.** Twenty-four more come from a
  texture holding every scene light, with a per-draw block of row numbers and
  fade scales; a draw with eight lights or fewer never reads it. The tail casts
  no shadow. `FrameResult.lightsDropped` now means light the frame could
  deliver nowhere (`gfx-74n`). `RenderSettings.lightFadeBand` turns the edge of
  a draw's light list into a smoothstep ramp, and 0, the default, is the old
  hard edge byte for byte; on the fixture built for it the change between
  neighbouring frames goes from 3.16% to 0.23%. `LightNode.channels` and
  `SceneNode.lightChannels` are bit masks compared where the lights of a draw
  are chosen, so a light off an object's channel does not take one of its slots.

- **`LightType.area`: a rectangle that lights like a rectangle.** The diffuse
  term is Lambert's polygon form factor, exact and with no table; the specular
  term is the representative point, and its known error is a lobe not widened
  by the panel's solid angle. It takes over the two per-light arrays a panel
  has no use for, so it adds no bytes to a draw. The brute-force quadrature it
  is tested against agrees to better than half a per cent across five
  arrangements (`gfx-77n`). `Photometric` converts between
  `LightNode.intensity` and lumens, candela and lux, anchored so that an
  800-lumen point lamp is intensity 1. Nothing applies it automatically.

- **Shadows.** A cut-out caster casts its cut-out: `ShadowDepthMasked` and
  `ShadowDistanceMasked` test `Material.alphaCutoff` against the map's alpha
  times the base colour's, on the directional and the point path (`gfx-60n`).
  `ShadowSettings.directionalLightRadius` above 0 searches for the blocker and
  widens the penumbra with its distance; 0 is the 3x3 kernel as before.
  `ContactShadowSettings` marches sixteen steps toward the sun against the
  depth the scene wrote, at the frame's own resolution, fades a hit with its
  distance along the march, and declines when nothing directional lights the
  scene (`gfx-76n`). The cascade atlas and the cube atlases own their depth
  buffers. They took one from the pool each frame, and Impeller's Vulkan
  backend caches a framebuffer keyed on the colour attachment alone, so the
  second pass drew into the first pass's depth or crashed; reported upstream as
  flutter/flutter#192538.

- **`IrradianceField`: one bounce of diffuse light from the room itself.** A
  grid of probes, each an octahedral tile of irradiance with a gutter and the
  two depth moments Chebyshev's inequality needs to stop light crossing a wall.
  A probe is gathered with rays through the engine's raycaster, `gather` and
  `gatherProbe`, and a probe inside geometry is found by counting rays that
  land on the inside of a surface. It reaches a draw through the ambient
  uniform that already existed, sampled facing up and facing down per object,
  so a large floor reads one point of the field. A scene with no
  `Scene.irradianceField` is byte for byte what it was (`gfx-81n`).

- **The composite: tone curves, a colour table and a three-way grade.**
  `RenderSettings.tonemapCurve` is a `TonemapCurve` of `neutral`, `aces`, `agx`,
  `reinhard` or `agxFull`, the last with its gamut rotation, and `neutral` is
  the old curve value for value. `LookSettings.lut` takes a strip of N slices
  of N by N with `lutStrength`, and `buildIdentityLut` makes the neutral one;
  an identity table was measured to change no byte of an eight-bit frame.
  `lift`, `gamma` and `gain` are colours, `whiteBalance` and `tint` sit beside
  the older `temperature`, and `dither` is a 4x4 ordered cell added after the
  sRGB encode: a 512-pixel dark ramp went from 39 flat runs to 255. Every
  default is an exact identity.

- **Anti-aliasing, occlusion, bloom, a lens, shafts and per-view exposure.**
  `AntiAliasSettings` is an FXAA pass after the composite, for the frame in
  which anything reads the surface buffer and multisampling is therefore off;
  `sharpen` rides in it and leaves a flat area untouched by construction.
  `AmbientOcclusionSettings.blurTaps` and `blurDepthFalloff` add a blur
  weighted by depth, so occlusion does not spread across a silhouette.
  `BloomSettings.referenceHeight` keeps a glow the same share of the picture at
  any resolution through `bloomLevelsFor`, and `halation` warms the wide levels
  of the chain and leaves the core. `DepthOfFieldSettings` is a thin lens:
  `focusDistance`, `focalLength`, `aperture` as an f-number and `sensorWidth`;
  it is a gather, so a foreground blur does not spread over a sharp background.
  `LightShaftSettings` marches the view ray against the directional shadow map
  sixteen steps a pixel and draws nothing when there is no caster.
  `AutoExposureSettings.perView` meters and exposes each view of a split
  screen from the one luminance readback. All of them are off by default.

- **Viewport shading read out of the surface buffer.**
  `RenderSettings.viewportShading` takes a `ViewportShadingSettings` whose mode
  is `normals`, `clay`, `outline` or `curvature`. It is drawn in the present
  phase from the normal and depth the scene pass already writes, so no node's
  material is swapped to show it (`gfx-43n` to `gfx-45n`).

- **Materials: a lighting model per surface, a vertex stage, hashed alpha and
  a source language.** `SurfaceMaterial.lightingModel` picks one of the six
  models by shader name; `.fmat` reads and writes it, glTF and OBJ have nowhere
  to carry it, and `.f3d`'s fixed material record has no room for it yet
  (`mat-04`). `LightingModel.vertexShaderName` names a vertex stage an
  application supplies through `Renderer.create(materials:)`: the name is the
  unskinned entry point and `<name>Skinned` the skinned one, and the pipeline
  cache key includes it. Instanced and lightmapped draws keep the engine's
  stages (`gfx-75n`). `MaterialAlphaMode.hashed` keeps a fraction of pixels
  equal to the opacity, hashed on world position, in the opaque half with
  depth written and nothing sorted; picking treats it as a mask at one half.
  `parseMaterial` reads a material written as typed parameters and a fragment
  body, `emitMaterialFragment` writes GLSL from the tree, `evaluateMaterial`
  runs the same tree on the CPU, and `describeMaterial` reads the bindings off
  it. The language has no uniform block, no loop, no `#define` and no vertex
  body (`gfx-84n`).

- **A route as one line.** `buildPolyline` writes each point twice with its
  neighbours, a signed half width and a colour, and `Material.polyline` pairs
  the `PolylineVertex` stage with Unlit, so a line is widened in the vertex
  stage and a camera move rebuilds nothing. Joins are mitres held at four half
  widths. `Material.parameters` now reaches a vertex stage the material
  brought as well as a fragment stage. The same commit fixed `FrameInfo` being
  bound through the engine's `MeshVertex` handle when the pipeline's vertex
  stage was the material's own (`gfx-86n`).

- **A captured cloud of Gaussians loads, sorts and draws.** `parseSplatPly`
  reads the binary PLY a capture ships as, including the three conventions its
  header does not state: `opacity` is a logit, `scale_*` are logarithms and
  `f_dc_*` are the zeroth spherical-harmonic band. `SplatCloud` holds the
  splats as flat arrays and `SplatContributor` draws them as quads blended
  back to front with no depth write. Two approximations are stated in the
  code: the projection drops the perspective Jacobian, and the higher
  harmonic bands are skipped, so a splat does not change colour with the
  viewing angle. The CPU rebuild measured 359 ns a splat per camera move
  (`gfx-80n`).

- **Cameras and projections.** `OffAxisProjection` takes four tangents, which
  is what a headset hands over per eye, and `Projection.verticalFieldOfView`
  answers null where the question does not apply; `LodGroup` and the shadow
  cascades ask it and no longer fall back to 45 degrees or 200 metres.
  `RenderSettings.forStereo()` takes out what a pair drawn side by side cannot
  have: ambient occlusion, reflections and bloom. `TiledProjection` answers
  for one tile of a frame larger than any render target, checked by a 2x2
  stitch against one whole render byte for byte. `OrbitController` has an
  `orthoHeight` kept in step with its distance, `animateTo(yaw:, pitch:)` with
  `advance(seconds)`, and a `frameBounds` that lowers `minDistance` to a tenth
  of the radius it frames, so a millimetre-scale model can be framed.
  `FreeLook` turns the head and walks over the same yaw, pitch and target.

- **An overlay that sits on the surface, and a skeleton on screen.**
  `MeshOverlay` draws edges, vertex handles and a face wash in three batches
  and three draws whatever is in them, with handles and the nudge toward the
  eye sized in pixels. Design colours are converted on the way in, because the
  overlay is encoded inside the scene pass and the composite encodes on the
  way out. `throughGeometry` writes into a second pass with no depth test at
  `throughOpacity`, for a gizmo whose pivot is inside the object.
  `DebugDrawOptions.skeletons` draws every skinned mesh's joints through
  `addSkeletonOverlay`: an octahedron per bone and a cross at each leaf.

- **Poses, skinning and IK without a scene.** `Pose` holds a hierarchy's local
  TRS in flat arrays, samples a clip, composes `worldMatrices` and
  `jointMatrices` by the formula `Skeleton.update` documents, and `writeTo`
  pushes it onto scene nodes. `SkinBlend` repeats the skinned vertex stage on
  the CPU. `TwoBoneIk` solves from the chain's current bend toward a target
  and a pole, and `FabrikIk` a chain of any length; a sign error in
  `TwoBoneIk.solve` for a chain bent at rest was fixed with a test on a chain
  bent 90 degrees. `AnimationPlayer.rootMotionDelta` reads the
  `flutter3dRootMotion` extra of a clip, across the wrap. A layer can be
  `AnimationBlend.additive` over a clip whose `AnimationClip.referenceTime`
  names its rest frame; a clip without one gets the override path.

- **Picking, screen space and vertices overwritten in place.** `Raycaster`
  tests a skinned mesh where its pose puts it, through `PosedMesh`, and
  `Raycaster.posed` turns that off; the early box rejection uses the posed box,
  and weights that do not sum to one are renormalised. `TriangleBvh` in the geometry library is new: a tree over one
  mesh's triangles, in typed arrays, with `raycast`, `refit`, and
  `forEachInAabb` and `forEachInFrustum`, which report by a triangle's box and
  so may report a few extra. `screenBoundsOfBox` projects a world box to
  a rectangle on the glass, and answers the whole viewport for a box the eye
  is inside. `DeviceMesh.overwriteVertices(device, firstVertex, vertexBytes)`
  writes into a live vertex buffer through `GraphicsDevice.overwriteGeometry`,
  grows `bounds` to cover the new positions and bumps `version`; the box only
  grows.

- **A panorama lights the scene.** `readHdr` decodes Radiance `.hdr` in both
  scanline encodings to floats and `hdrSizeOf` reads the header alone.
  `EnvironmentMap.equirectToCubeFaces` cuts six faces from a 2:1 panorama and
  `EnvironmentMap.fromPanorama` uploads and prefilters them. The cube is eight
  bits a channel, so a sun far brighter than its sky clamps to white.

- **A model is written as well as read.** `GltfWriter` writes a self-contained
  GLB: geometry, materials and samplers, skins, animation channels in all
  three interpolations, morph targets with their names, lights through
  `KHR_lights_punctual`, cameras, `extras` on five kinds of object, and a Basis
  KTX2 image through `KHR_texture_basisu`. `compressGeometry: true` adds
  `KHR_mesh_quantization`, vertex cache reordering and
  `EXT_meshopt_compression`, which the reader decodes too; with the index
  codec's edge history the measured fixture is 3.60 times smaller, and the
  output was checked against meshoptimizer 1.2.0's own decoder. `StlWriter`
  writes binary or ASCII, `ObjWriter` bakes each surface's world matrix,
  and `UsdzWriter` writes geometry only, one `Mesh` prim per surface, in an
  archive macOS identifies as USDZ. Every writer has `warnings` naming what
  its format cannot carry. `exportToGlb`, `exportToObj`, `exportToStl` and
  `exportToF3d` answer an `ExportReport` with the files, the warnings and the
  differences `compareModelDocuments` found on reading the file back, morph
  targets included. `validateGltfExport` checks each accessor's declared
  bounds against its data. `ModelWriter`, `modelWriterNamed` and
  `encodeModelInIsolate` with a `ModelWriteRequest` are the same from above.

- **STL is read, and a document holds more of its file.** `StlLoader` reads
  both dialects and tells them apart by the file's size arithmetic, since a
  binary header often begins with `solid`; its document has a node for its
  surface, which it did not at first. `ModelFormat.stl`, `sniffModelFormat`
  and `recognizedModelFormat` know it. `ModelDocument` gained `lights`,
  `cameras`, an `asset` of type `DocumentAsset` and `extras`; `ModelSurface`
  gained `meshName` and `authoredAttributes`, the attributes read from real
  data; `EncodedImage` gained `sourceUri`; `TextureSampling` gained `mipLinear`
  with `toGltfFilters()`; and `ModelNode.lods` holds `ModelLod` levels, written
  to `.f3d` as section 21 and to glTF as `MSFT_lod`, the latter checked only
  against this package's own reader. Every new `.f3d` section is optional on
  read and `kF3dVersion` is still 1. `surfaceMaterialToJson` and
  `surfaceMaterialFromJson` are the one codec for a material's fields.

- **KTX2: supercompressed files open, and textures are encoded.**
  `Ktx2Texture.parse` unwraps Zstandard and ZLIB levels through a decompressor
  written here, `zstd.dart`, since every Dart zstd binds the C library and a
  web build cannot load one. Thirty structured and sixty fuzzed streams at
  levels 1 to 19 decode byte for byte, and the four bugs found on the way are
  in the commit for `gfx-78n`. `encodeBc1`, `encodeBc3`, `encodeEtc2Rgb8` and
  `encodeAstc4x4` encode, `buildMipChain` halves with a box filter, and
  `writeKtx2` writes the container. The ASTC encoder wrote a reserved block
  mode that ARM's astcenc decoded as magenta; it writes mode 0x53 now and is
  pinned to astcenc's output, with a worst channel error of 7 over a 64x64
  gradient (`gfx-88n`). `encodeUniversalBlocks` writes a 4x4 intermediate of
  twenty bytes a block, and `transcodeUniversal` turns it into BC1, BC3, ASTC
  4x4, ETC2 or RGBA8; `uploadEncodedImage` picks the `UniversalTarget` from
  what the device samples. Against encoding directly it costs ASTC nothing,
  BC1 0.6 dB and ETC2 0.9 dB, and ETC2 takes about a second per 1024x1024
  level because that leg decodes and re-encodes (`gfx-83n`).

- **Images without `dart:ui`.** A PNG decoder and encoder, a baseline JPEG
  decoder, DEFLATE and inflate are in the formats library, `decodeImagePure`
  wraps the two decoders in the `ImageDecoder` shape, and `sniffImageMimeType`
  names PNG, JPEG, KTX2 and WebP from their first bytes.

- **A UASTC KTX2 opens (`gfx-78n`).** What `toktx --uastc`,
  `gltf-transform uastc` and `basisu -uastc` write was refused by name — and
  by guess, since any undefined `vkFormat` outside Basis-LZ was taken to be
  one. `Ktx2Texture.parse` now
  reads the data format descriptor's colour model to learn *which* Basis
  Universal a file holds instead of inferring it from the supercompression
  scheme, and unpacks UASTC LDR 4×4 — all nineteen modes — to RGBA8 in
  `uastc_decoder.dart`, through the same Zstandard and ZLIB unwrapping the plain
  formats use, since a current encoder Zstandard-compresses UASTC unless told
  not to. Unpacked rather than repacked to BC7 or ASTC: every file opens on
  every device, at four bytes a texel. A glTF that ships only a
  `KHR_texture_basisu` UASTC texture keeps it. UASTC HDR and the newer
  intermediate colour models are refused by name. Tables transcribed from the
  Basis Universal reference transcoder, and checked against it the only way
  worth having: files its own encoder wrote, chosen until every mode appears
  in them, compared **byte for byte** with its own RGBA32 output.

- **A Draco-compressed glTF opens (`gfx-82n`).** `KHR_draco_mesh_compression`
  was detected, warned about and skipped, so a compressed file opened as a
  model with holes in it — and since every such file names the extension as
  required, most were refused outright before that. `decodeDraco` now reads
  edgebreaker connectivity, which is what every encoder writes unless told
  otherwise, in both its standard and valence traversals; both attribute walks;
  and every prediction scheme a bitstream 2.2 encoder can choose — difference,
  parallelogram, constrained multi-parallelogram, portable texture coordinates
  and geometric normals. `GltfLoader` decodes the payload and puts its values
  behind the primitive's own accessors through the new
  `GltfAccessorReader.supplyDecoded`, so morph targets, skinning and the writer
  read a compressed primitive as they read any other; joints stay the integers
  they were stored as. A payload that does not decode costs that primitive, and
  the warning carries the decoder's reason. Point clouds, bitstreams before
  2.2, the predictive traversal and the two retired prediction schemes are
  refused by name. Checked against `gltf-transform draco` at its default speed
  and at speed zero — which are nearly disjoint sets of code paths — on a
  thousand-face mesh with UV seams and on a skinned one, triangle for triangle
  against the uncompressed originals. **One bug in what was already there,
  found by that comparison**: the rANS end-of-stream check compared the state
  without first pulling in the bytes the encoder shifted out before its first
  symbol, so a valid stream whose first symbol was rare was refused.
- **`KHR_texture_transform` can be honoured, in the coordinates.**
  `sharedTextureTransform` names the one transform every texture of a material
  asks for, and `withTextureTransform` gives a mesh with that transform applied
  to its texture coordinates, tangents turned and mirrored with them. That is
  the case an atlas export writes, and it needs no matrix at the sampler. The
  decoder still applies nothing, so a document written out again is the file
  that was read. Its warning changes: it no longer fires for every texture that
  names the extension, only for a material whose textures name different
  transforms, which one set of coordinates cannot satisfy. A file that lists
  the extension under `extensionsRequired` is still refused.
- **A morph-target warning names its primitive.** The three warnings the glTF
  loader adds when it drops a morph target had their interpolations escaped,
  so each said, literally, `$label has ${targets.length} morph target(s)`.
  Nothing failed because nothing reads a warning but a person.
- **What it depends on, and what the archive carries.** `flutter3d_hardware` at
  `^0.7.0` and `vector_math`. `package:flutter3d_core/geometry.dart` and
  `formats.dart` import neither the renderer nor a device. The archive carries
  `skills/flutter3d-core-geometry-meshes/` and
  `skills/flutter3d-core-formats-reading-models/` for a coding agent, installed
  with `dart run skills@ get`.

## 0.1.0

- **The rendering core leaves `flutter3d` (`mcp-03n`).** Scene graph, render
  list, passes, materials and animation move here with no Flutter SDK
  behind them; `flutter3d` re-exports this package and keeps `rootBundle`,
  `dart:ui` and the widgets for its own thin shell.
