## 0.4.3

* **`RenderSettings.anisotropy`.** Taps a model's texture samplers may take
  along a foreshortened axis, applied at bind time to every material sampler
  that is trilinear and carries no level of its own, clamped to
  `GraphicsDevice.maxAnisotropy` on the way. One by default, so every
  picture is the bytes it was. A setting rather than a property of the
  asset because glTF has no way to say it: a `sampler` in the file names
  filters and wrap modes and nothing about taps. A level's brushes do not
  come through here — the bridge sizes their sampler to the device at load,
  and the setting leaves a sampler that already asks for taps alone.
  `anisotropic-floor` joins the Impeller and software golden sets, with the
  WebGL reference recorded at merge: the demo's ground under the cube,
  stretched to the horizon, retextured with a checkerboard and its chain
  and seen from just above it. The setting is asserted to be one or more,
  as `SamplerOptions.anisotropy` already was.
* **`Renderer.relinkShaders`: the engine's half of a hot reload.** A
  `LoadedShaderLibrary.refresh` swaps the code behind a stage and keeps the
  handle; a pipeline is a pair of stages linked, and the linked object still
  holds the old code until it is built again. This drops every pipeline the
  renderer linked — materials, shadows, sky, post, debug lines — so the next
  frame links the refreshed stages, at the cost of the first frame.
* **`loaded-shader`**, a golden in the Impeller and software sets: the teapot
  wearing `ExampleStripes`, a look compiled into the example's own bundle
  (`example/shaders/`, built by `example/tool/build_shaders.sh`) and loaded
  from bytes through `GraphicsDevice.loadShaders` before the renderer is
  built. `GoldenScene.shaderBundle` names the asset; the software backend
  draws it from the example's own Dart transcription.
* **Auto exposure.** `RenderSettings.autoExposure` meters the frame: a
  luminance node writes the lit scene's log luminance into a 64×64 eight-bit
  target, `GraphicsDevice.readback` hands the bytes back a frame or two
  later, `ExposureMeter` averages the band between two percentiles of their
  histogram — the brightest fifth, so a dark corridor does not push a torchlit
  wall past white — and `ExposureAdapter` moves the exposure towards the
  answer in stops, at one rate climbing and another falling, between two
  limits. The composite exposes each frame with what the frame before was
  metered at; `FrameResult.exposure` and `Renderer.exposure` say what that
  was. Off by default, since every golden is recorded at the setting's own
  number; `auto-exposure` is the one scene that turns it on. Its Impeller and
  software references are recorded here; the web one is not, because
  `golden_web.sh` holds a fixed port for the whole of its run and so records
  when the branch lands.
* **Picking by pixel.** `Renderer.pickPixel(u, v)` asks the next frame which
  mesh is drawn at a point: that frame draws every visible mesh once more with
  the `ObjectId` stage into a frame-sized target, reads the one pixel back and
  answers with the node whose number came back — null for the clear colour,
  the batch for an instanced batch. Only on a frame somebody asked; otherwise
  the node is inactive and the graph culls it. A frame that fails after the
  question was asked answers it with the failure rather than never.
  `Raycaster` stays for a game, which wants an answer now and needs no frame.
* `FrameResourceIds.luminance` and `FrameResourceIds.objectIds`, both frame
  outputs while their node is active, since their consumer is a readback the
  graph cannot see.
* **A pick through a hole answers with what is seen through it.** A masked
  material — glTF's `MASK` — discards under its cutoff in the scene pass, and
  the id stage now discards the same fragments: it is handed the material's
  texture, cutoff and tint alpha in `IdInfo.mask`, so a click through a
  fence's hole answers with the thing behind the fence rather than the fence.
  Before, the id pass wrote every fragment and picked the plane the hole was
  cut in, which contradicted the one promise picking by pixel makes.
* **A frame that fails to build answers its questions too.** The catch that
  answers a pending `pickPixel` with the frame's failure covered the passes
  but not what came before them — an application node reading a name
  nothing writes fails in the graph's compile, and a question taken off the
  renderer there was on no list anybody would ever finish. Both catches now
  answer it, and the test is a node with a misspelled read.
* **The exposure meter asks once per answer.** A readback in flight is not
  joined by another: the luminance pass still runs every frame, the copy and
  the download behind it are skipped until the last one has landed. On
  flutter_gpu each answer is a `toByteData` off a staging texture, and a
  meter asking every frame kept two or three of those in the air and a
  staging pool to match; an exposure that adapts over seconds cannot tell a
  reading every frame from one every other frame.
* **A device that refuses on the spot costs the question, not the frame.**
  Both readbacks are asked through `Future.sync`, because a refusal is
  synchronous by contract — `readbackRegionOf` throws before a future exists —
  and the backends refuse that way on their own account too: WebGL2 gives no
  fence for a lost context, flutter_gpu throws rather than returning false
  when a copy is turned down. Asked bare, the first of those came out of the
  luminance or the id node and took the whole picture down over a click, and
  the exposure meter's in-flight flag stayed set for ever, so it never asked
  the device again and `debugMeterFailures` stayed at nought — the one number
  that would have said so.
* **A blended surface is picked as though it were opaque**, written down
  rather than left to whichever way the pass fell. Glass, a translucent
  marker, an additive flash answer with themselves and not with what is seen
  through them: `MASK` says "there is nothing here" and is discarded in both
  passes, `BLEND` says "there is something here, faintly", and that is still a
  thing to click on. `Renderer.pickPixel` says so and a software-backend test
  holds it — a red pane at half alpha over a box, the click answering the pane
  while the picture shows the box through it.
* `FrameResult.exposure` defaults to `RenderSettings.defaultExposure` rather
  than to its own copy of the number.
* `example/lib/surface_probe.dart` measures flutter_gpu's `GpuImageSurface`
  against the `asImage()` path `present` uses, and
  `surface_probe_main.dart` runs it the way `conformance_main.dart` runs the
  conformance suite: an application, because Flutter GPU needs Impeller and
  a headless test does not have it. In the example rather than in the
  backend because it reaches flutter_gpu directly, and an instrument is not
  part of a backend's API. It runs the ring twice — as the renderer has it,
  and holding the presented frame back one frame more, which is the promise
  the surface makes and the only version whose texture count compares with
  it — and its allocation control runs over the resize as well, so a pool
  that has not shrunk means the surface kept something rather than that the
  collector had not run. Its report and arithmetic are held by a headless
  test in `example/test`.
* **The ring of finished frames says what its accounting tracks.** The
  callback that returns a frame texture to rotation fires when the
  renderer's own GPU work is done, which is before the compositor has
  sampled the texture; the note at `_ldrFrames` now says so, with what the
  probe measured, what the ring could do about it, and why it has not.
* **X-ray silhouettes.** `RenderSettings.xray` names a layer, and every
  visible node on it is drawn twice more at the end of the scene pass: once
  to mark the stencil where it is visible, with no colour and no depth
  write, and once as a flat unlit colour where it fails the depth test and
  the stencil says no marked node's visible part is there. The stencil is
  what keeps the lit half of a half-hidden monster lit and one monster from
  painting through another; every mark is written before any paint. Both
  draws go through the same node encoder as the lit one, so skinning and
  batches come for free. Nothing is emitted when the mask is zero, the
  device has no stencil, or nothing visible is on the layer — every other
  golden is the bytes it was. `stencil-xray` joins the set on all three
  backends. Neither extra draw writes the surface buffer: they use
  `LightingModel.xray`, which is unlit with its second output compiled away,
  so a silhouette describes no surface to ambient occlusion or reflections —
  and it cannot, since it is drawn precisely where its node is behind
  something else. A software test holds one scene's surface buffer
  byte-identical with silhouettes on and off.

## 0.4.2

* **Lightmaps.** `MeshNode.lightmapped` picks a vertex stage that reads the
  colour attribute as a place in `Material.lightmap`, and every lit model
  adds `albedo × lightmap` beside its ambient, with a one-texel black bound
  where a material has none so nothing branches and every picture without a
  map is the bytes it was. `lightmapped-room` is a golden in all three sets.
* **KTX2 is read.** A pure-Dart reader for the container, and a port of Basis
  Universal's ETC1S transcoder verified level by level against the encoder's
  own unpack of three real files: mip chains and alpha slices included, run
  on an isolate where there is one. `uploadEncodedImage` sniffs the format
  before `dart:ui` sees the bytes; a Basis file arrives as RGBA8, and a file
  carrying its own BC, ETC2 or ASTC blocks is uploaded as those blocks, chain
  and all, once `GraphicsDevice.supportsTextureFormat` has said the device
  samples them.
* `uploadEncodedImage` takes a `report` callback and says why an image was
  left out — a refused supercompression scheme, a family the device does not
  sample, a size that is not whole blocks. `ModelAsset` and the material
  loader route it into their `warnings`.
* glTF reads `KHR_texture_basisu`: a core `source` wins while it exists, and
  the extension's KTX2 is what a file that ships only that falls back to. The
  extension may be required without the file being refused.
* Still refused by name: UASTC, Zstandard and ZLIB supercompression, texture
  arrays, cube maps, 3D textures.

## 0.4.1

* **A minimal example.** `example/lib/minimal_main.dart` is one sphere and one
  point light in seventy lines, opened through `flutter3d_backend` the way a
  new application would — and `example.md` puts those lines on pub.dev's
  Example tab in place of the full model browser. A smoke test runs the file
  headless through the software fallback, so the claim in its comment is a
  thing CI checks rather than a thing the comment says.

## 0.4.0

* **A pass's scene is lit by its own lights.** `encodeScene` used to encode
  whatever scene it was handed with the *frame's* light buffer, gathered from
  the world at the top of the frame — so a view-model studio's two lights were
  never uploaded, every held weapon drew near-black, and the studio's light
  indices read shadow-atlas rows assigned to the world's torches. A scene
  other than the frame's now gets its own lights gathered into a pass buffer
  and the no-shadow table; the frame's own scene reuses the frame's buffers
  unchanged.
* **Everything the engine creates, something now releases.** `ModelAsset`
  gained `release`, giving meshes and maps back with identity dedup — surfaces
  share meshes, materials share maps, and one image can sit in two slots of
  one material. `Renderer.dispose` releases the window-sized targets and
  drains both frames-in-flight rings instead of leaving them to a collector
  that, on WebGL2, deletes nothing. The texture upload path disposes its
  `ui.Codec`, which had leaked a decoder per decoded image.

## 0.3.0

* **A point light's normal offset is measured in texels, not metres**, which is
  what it was always compensating for: a texel of the shadow map covers a patch
  of surface, records it at one distance, and every fragment in that patch which
  is not the point measured compares against a distance from somewhere else. The
  patch is a solid angle and grows with range, so a flat 2 cm was right close to
  a lamp and a third of what was needed ten metres out. What it looked like: the
  floor under the golden teapot shadowing itself everywhere the lamp reached,
  ending in a straight line where the floor's own edge projects — a straight
  edge across a shadow in a scene with no straight edges in it.
  `pointNormalOffset` now defaults to 1.5 texels.
* **The static cube-shadow bake now redraws when the settings that decide it
  change.** It redrew when a light took another's atlas row and at no other
  time, so `casterFaces`, `depthPadding` and the cube tile size could be set and
  nothing happened — measured on the crypt as two frames identical to the pixel
  under opposite `casterFaces`. `StaticBakeKey` and `shouldBakeStatic` hold the
  rule, and exclude everything the lookup reads: a bias must not cost a re-bake.
* **Six point lights may cast at once, not four.** The crypt hangs six torches,
  so two of them lit their corner and cast nothing — and which two changed as
  the player walked, because the rows go to whatever matters most from where the
  camera is. Two torches side by side behaving differently is what a player
  reads as "the shadows are broken". Affordable only after the line below: at
  the old cube tile the extra rows would have cost 100 MB, and they cost 25.
* **`ShadowSettings.cubeResolution`**, defaulting to 512, so a cube face no
  longer inherits the cascade's tile size. It did, and the atlas is thirty-six
  tiles: a game asking for a 1024 sun was allocating 201 MB per atlas and there
  are two. The golden sets did not move when it changed.
* **The Khronos sample models are no longer this package's assets.** They moved
  to `flutter3d_samples`, a dev dependency here: declared in `flutter.assets`
  they were 4.1 MB in every application that depended on the engine — a third of
  the shooter's web asset payload, none of it ever loaded — and four fifths of
  this package's own archive. The decoder tests read them from disk as before.
* `.fmat`: a material as a file of its own, with `MaterialDecoder` as the
  boundary for formats the engine does not ship. Consulted before the built-in
  reader, so a project can replace it rather than only add to it.
* Image-based lighting: `EnvironmentMap.prefilter` builds a specular chain and
  a diffuse level from a cube map or from sky settings, over a fixed
  golden-angle spiral so two independently written backends agree exactly.
* `LookSettings` in the composite pass: colour grading, vignette, grain and
  chromatic aberration.
* Materials carry a parameter block, numeric parameters and extra texture
  slots, so an application's own shader has somewhere to read from.

## 0.2.0

* Cascaded directional shadows, cube shadows for point and spot lights into an
  atlas, screen-space reflections and ambient occlusion, a sky and two-colour
  ambient light.
* A frame graph that culls the passes a frame does not need, and a frame
  resource ring that returns a target when the GPU says so rather than a fixed
  number of frames later.
* Instancing and CPU-built mip chains, uploaded level by level because no
  backend can be trusted to generate the same ones.
* Written against `flutter3d_hardware` throughout, so the backend is a value a
  caller hands in rather than a compile-time choice.

## 0.1.0

* A CPU geometry layer with no GPU in it: vertex layouts, meshes, and shapes as
  values — surfaces of revolution generate the sphere, cylinder, cone, torus,
  capsule and disc.
* A scene graph whose transforms are held by version counters rather than dirty
  flags, so a stale world matrix is structurally impossible.
* glTF 2.0 / GLB and Wavefront OBJ behind one document abstraction, plus
  `.f3d`, the engine's own container: the teapot loads in 1.1 µs instead of
  4.54 ms, and the two render pixel for pixel.
* Six lighting models, each a pre-built shader; directional shadows, an HDR
  pipeline with tone mapping and bloom, skinning, animation, BVH culling, LOD
  and CPU picking.
