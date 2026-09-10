---
name: flutter3d-shaders-one-copy
description: Use when adding, editing or porting a flutter3d shader — the GLSL lives here once for all backends, the manifest is the contract, and three rules the sources are written under.
---

# One copy of the GLSL, three backends compiling it

`shaders/` holds every stage: the vertex stages that define the layouts, one
fragment shader per lighting model in `lighting/`, the post chain in `post/`,
the shared headers in `lib/`. `flutter3d_impeller` compiles them into a
`flutter_gpu` bundle, `flutter3d_webgl` translates them to GLSL ES 3.00, and
`flutter3d_cpu` implements the same stages in Dart against the same
declarations.

**A shader that exists in one backend and not the others is a picture that
differs by platform and nothing that can see it.** The sky was rewritten here
once and the browser's copy of the table was a year out of date. Edit the source
here; let each backend build from it.

## The manifest is the contract

`shaders/flutter3d.shaderbundle.json` lists every entry point, and
`kRequiredShaders` exposes the same list to Dart. That list is the one
requirement `GraphicsDevice` cannot express — no signature says which entry
points must exist, so a backend written from the interface alone compiles and
draws nothing. `flutter3d_conformance` reads it and tells a new backend which
entry point is missing rather than which frame came back empty.

`test/manifest_test.dart` fails when a shader is added to one and not the other.
Adding a shader means both files, then each backend.

## Rules the GLSL is written under

**Never declare a uniform block a stage does not read.** Two different failures
come of it, and the second was found the hard way.

The first: the compiler drops the block from the compiled function while
reflection still reports it at a non-zero size, and binding that phantom block
is a `SIGSEGV` inside the driver with no Dart stack trace.

The second: on Vulkan the descriptors of *both* stages are merged into one set
layout, and two bindings with the same number in it is not a layout the
specification allows. A fragment shader whose only block is an unused one lands
on the same binding as the vertex stage's first, and the pipeline is refused —
`Could not create graphics pipeline: ErrorUnknown`, with an empty label, and
nothing else. Some drivers accept the layout anyway, so this is a shader that
works on every machine but one. `shadow_depth.frag` did exactly that with
`FogInfo` for as long as it existed.

Hence the split: `lib/color.glsl` for stages with no material inputs,
`lib/surface.glsl` for the ones that have them. Include the narrower header —
**and check what that header still declares.** `lib/color.glsl` carries
`FogInfo` for the fog helpers, which a shadow pass reads no more than it reads
a texture; `F3D_NO_FOG` is what leaves it out, and it exists because including
the narrow header was not by itself enough.

**A sampler whose result never reaches the output disappears the same way**, and
the binding then fails by name at run time. `LightingModel` metadata has to
describe what the compiled shader actually has;
`flutter3d_impeller/tool/build_shaders.sh` prints the compiled binding table.

**Lighting is a uniform array, not a permutation per light count.** `vec4
lights[8]` with the count as a uniform survives into the compiled Metal struct,
and the whole array is written from its base offset because the std140 stride
for a `vec4` array is a flat 16 bytes. Switching a light on or off rebuilds no
pipeline. `shaders/spike_array.frag` is the probe that re-establishes this after
an SDK bump; keep it.

Shaders compile ahead of time, so a material graph assembled while the game runs
is impossible: every lighting model is a separate pre-built shader and a
separate pipeline. That is also why the pipeline is the high-order sort key.

## After a Flutter SDK change

The bundle format is tied to the Flutter version. Rebuild through
`flutter3d_impeller/tool/build_shaders.sh`, re-record goldens, and read the diff
rather than accepting it. A demo that opens and draws nothing usually means a
bundle the loader refused by version.
