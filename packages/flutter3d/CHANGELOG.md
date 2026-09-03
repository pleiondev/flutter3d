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
