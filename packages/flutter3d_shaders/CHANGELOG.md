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
