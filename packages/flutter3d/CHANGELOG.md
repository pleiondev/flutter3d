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
