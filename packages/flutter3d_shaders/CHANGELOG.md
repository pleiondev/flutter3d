## 0.4.2

* **`Luminance`**: the lit scene's log luminance at low resolution, sixteen
  taps per texel, encoded in eight bits over sixteen stops from minus ten —
  what an exposure meter reads back. `LuminanceInfo.params` carries the
  footprint and the two ends of the encoding.
* **`ObjectId`**: every mesh drawn again through its own vertex stage with a
  fragment stage that writes the id in `IdInfo.id` as three bytes, into a
  single attachment, so one pixel read back says which node is under the
  cursor. `kRequiredShaders` names both.

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
