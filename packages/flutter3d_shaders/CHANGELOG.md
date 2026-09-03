## 0.4.2

* **`Xray`**, a seventh lighting entry point: `unlit.frag` with
  `F3D_NO_SURFACE_BUFFER` defined, so it declares no second output at all.
  The x-ray stage draws its mark and its silhouette with it. Drawn unlit they
  wrote the surface buffer — the silhouette wherever its `greater` test
  passed, which is where the marked node is *behind* what the depth buffer
  holds — so a hidden node's normal, roughness and depth landed on top of the
  surface in front of it, and every screen-space effect reads that buffer as
  the nearest surface. `kRequiredShaders` names the new entry point.

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
