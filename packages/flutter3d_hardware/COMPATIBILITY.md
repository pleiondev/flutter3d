# What this package promises

`flutter3d_hardware` is the interface a backend implements and the engine draws
through. Three backends implement it today — `flutter3d_impeller`,
`flutter3d_webgl` and `flutter3d_cpu` — and the whole point of naming a promise
is that another can be written without reading the engine.

The third one tested that claim, and half-confirmed it. `flutter3d_cpu` is a
software rasteriser with no GPU, no driver and no shading language under it,
and everything in the list below held: `GraphicsDevice` was implementable
straight from this document, `Renderer` started against it unmodified, and the
`plain` parity fixture came out within a mean of 0.56 of Impeller's. Nothing in
the engine turned out to assume a GPU.

What could **not** be written from this document is the shaders — see the last
section, which said so in advance. Written from a plausible memory of what a
renderer's uniforms are called, they drew an unlit scene: `light_count` does
not exist, and `material` is metallic and roughness rather than the colour. So
the limit named below is real and now measured: a backend can be written
against the interface, and its bundle must be written against the GLSL.

Nothing here is published, so "breaking" means breaking a checkout rather than
somebody's build. The promise is still worth writing down: it is the difference
between an interface and a description of whatever the renderer happened to
need this week.

## Promised

Changing any of these breaks a backend, and that is the bar for changing them.

**The device.** `GraphicsDevice` — every member. It is the whole contract: what
formats it prefers, what it can do, how a pass is opened, how geometry and
textures arrive, and how a finished frame reaches the screen.

**Recording.** `CommandEncoder` and `PassEncoder`. The split is deliberate:
`PassEncoder` is the recording half without `submit`, and it is what a
contributor drawing into somebody else's pass is given, so handing one an
already-submitted pass is a type error rather than a comment warning about one.

**Describing a pass.** `RenderPassDescriptor`, `ColorTarget`, `DepthTarget`,
`ScreenRect`, `BlendState`.

**Handles.** `TextureHandle`, `GeometryBuffer`, `ShaderHandle`, `PipelineHandle`,
`ShaderLibrary`. A handle carries a description and an opaque backend object.
`TextureHandle` deliberately has no `==`: the pool lends by identity and the
frame releases by identity, and value equality would quietly break both.

**Vocabulary.** All sixteen enums in `formats.dart`, plus `SamplerOptions`,
`RenderTargetSpec`, `TextureAllocator` and `RenderTargetPool`.

`PassState` and the `setState` extension are promised too, with one thing worth
saying about them: **no backend implements anything for them.** `setState` is an
extension over `PassEncoder`, statically dispatched, built only from types
already listed here — so a backend gets it for free and cannot get it wrong.
They live in this package rather than in the engine for the backend nobody has
written yet: a Vulkan-shaped one has to accumulate rasteriser state and look a
pipeline up at `draw()`, and that needs something hashable to accumulate into.

Its fields are optional on purpose, and that is a semantic rather than a
convenience — see the next section on `setDepthWrite`. Unset means *emit
nothing*, because what an omitted call means differs per backend and the
omissions in a pass's sequence are load-bearing.

Value names inside the enums are load-bearing beyond their own package: the
Impeller backend's translation asserts that each maps to the flutter_gpu value
of the *same name*, which is what catches a mapping that swapped two entries.

## Semantics, which are part of the promise and cannot be seen in a signature

These have each cost a day, and a backend that gets one wrong compiles and draws
the wrong thing.

- **A clear covers the whole attachment**, whatever the viewport or scissor say.
  The point-light atlas clears once and then draws tile by tile, and relies on
  it. GL does not give it for free — `clearBufferfv` respects `SCISSOR_TEST`.
- **Rectangles are stated from the top left**, matching where row zero of a
  render target is. A backend whose framebuffer origin is at the bottom must
  flip them; the engine will not.
- **`readPixels` returns rows from the top**, for the same reason and
  independently: a caller cannot tell which way round it was handed pixels, and
  a golden compared against a mirrored frame fails as though rendering broke.
- **A sampler that a shader declares must be bound.** Leaving one unbound is a
  native crash with no Dart frame on at least one backend, so the engine binds a
  stand-in rather than nothing.
- **`bindUniformBlock` returns false for a block the shader does not have**,
  which is ordinary — a compiler drops a block nothing reads. A block that
  exists without a member the caller named is an error, because then the two
  ends disagree about its shape and zeros are a plausible-looking value for
  most of what goes through there.
- **A null `sampler` means `SamplerOptions.linearRepeat`**, not the
  `SamplerOptions` constructor's own defaults, which are nearest and clamp. The
  two hardware backends had each chosen `linearRepeat` and therefore agreed
  without anybody writing it down. The third read this document, took the
  constructor defaults, and drew hard seams everywhere the others drew soft
  ones — two percent of every textured golden, looking exactly like a filtering
  bug in the new backend rather than like a question the contract had never
  answered.
- **`GeometryUsage` is not a hint.** WebGL binds a buffer to its target for
  life, and a buffer uploaded as vertices can never be bound as indices; the
  attempt is an `INVALID_OPERATION`, the draw is dropped, and the frame comes
  back the clear colour with nothing logged.
- **`setDepthWrite(false)` means depth writes are off**, on all three backends,
  since SDK 3.47.

  It did not until then. `flutter_gpu`'s native setter ignored its argument and
  assigned `true` (`render_pass.cc:538`, SDK 3.44.6), so on Impeller depth
  writes could be switched on and never off — and additive particles, which ask
  for it precisely so they do not occlude each other, occluded each other. The
  software backend mirrored the bug on purpose, argument and default alike,
  because an honest implementation put the particle scenes five to ten percent
  away from the hardware one and a gap that size is loud enough to hide a real
  regression behind. 3.47 assigns the argument; the mirror is gone.

  **The lesson outlives the bug, which is why this paragraph is still here.**
  When a backend has to choose between being right and being comparable,
  comparable wins — and the choice earns a test that fails the day it stops
  being necessary. `flutter3d_cpu/test/depth_write_test.dart` was that test. It
  was not deleted when the SDK was fixed; one expectation was flipped, and it
  now proves the opposite of what it used to. Four particle goldens moved on
  the upgrade and twenty-four other scenes did not, which is what said the fix
  had landed and nothing else had.
- **Ask before requesting what a backend may not have.** `supportsWireframe`,
  `supportsOffscreenMsaa`, `depthRange`, `framebufferOrigin`, `hdrColorFormat`,
  `preferredSampleCount`. A backend refuses loudly rather than substituting
  something that looks similar.

## Outside the promise

Not because it is unstable, but because nothing outside this package should
depend on it.

- Everything in `flutter3d`'s `src/` beyond what `flutter3d.dart` exports.
- `FrameResources` internals. Its rules — versions, `keeps`, release by
  identity — are engine machinery, and a backend never sees them.
- `RenderServices.encodeScene`. Nine parameters and a caller that must remember
  to ask the frame for its shadows; the shape that survives is handing it the
  `NodeFrame`, and that is a change worth making rather than freezing.
- The compiled shader bundle's format and location. It is one backend's build
  output.

## The one thing this interface cannot abstract

**Shader names.** The engine asks for entry points — `MeshVertex`, `Pbr`,
`Composite` — and for uniform blocks and members by name. Every backend must
ship a bundle answering to them. `flutter3d_shaders` holds the GLSL the backends
compile and `kRequiredShaders` the names, pinned to the build manifest by a
test, which makes that one list rather than three — but a backend cannot satisfy
the contract without reading the shaders themselves.

The member names are the sharp edge, and they fail silently in both directions.
A shader that asks for a member nobody wrote gets zeros; a caller that names a
member the block does not have is an error, because then the two ends disagree
about its shape. `flutter3d_cpu` hit the first of those on its first run and
drew a scene with no light in it, with nothing anywhere reporting a problem.

This is also the limit on extensions: an application that builds its own bundle
can add a lighting model today, because `LightingModel` is a value class rather
than an enum. An extension that does not control the bundle cannot.

## Two rules a fragment stage keeps, learned the expensive way

Both were found in the sky, which is the only stage in this engine that was ever
written against a target it did not match, and both cost days rather than
minutes because the symptom was a picture rather than an error.

**A fragment stage declares exactly the outputs its target has.** The scene pass
carries one colour attachment when nothing reads the surface buffer and two when
something does; `lib/color.glsl` already guarded its second output behind
`F3D_NO_SURFACE_BUFFER` for the shadow pass, and `sky.frag` declared one anyway.
On `flutter3d_impeller` that kills the process — inside Metal, at
`setFragmentBuffer:offset:atIndex:`, with an address that is not a pointer — and
when it survives long enough to draw a frame, every uniform the stage reads is
rubbish. Nothing above the driver reports anything.

**A uniform block reaches every pipeline except one, and that one is measured
rather than assumed.** The sky's blocks — bound with the same call every mesh
and every post stage uses, in the same pass, in the same frame, with the
reflection reporting the right size and the right member offsets — never arrive
on Impeller. What does arrive is vertex attributes and the varyings built from
them, which is how the sky is fed now: see the note at the top of `sky.vert` for
the measurements, each read back off a recorded frame rather than eyed.
