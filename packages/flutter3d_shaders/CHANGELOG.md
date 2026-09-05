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
