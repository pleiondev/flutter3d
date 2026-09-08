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
