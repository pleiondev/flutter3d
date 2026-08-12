# What this package promises

`flutter3d_graphics` is the interface a backend implements and the engine draws
through. Two backends implement it today — `flutter3d_impeller` and
`flutter3d_webgl` — and the whole point of naming a promise is that a third can
be written without reading the engine.

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
- **`GeometryUsage` is not a hint.** WebGL binds a buffer to its target for
  life, and a buffer uploaded as vertices can never be bound as indices; the
  attempt is an `INVALID_OPERATION`, the draw is dropped, and the frame comes
  back the clear colour with nothing logged.
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
ship a bundle answering to them. `flutter3d_shaders` holds the GLSL both compile,
which makes that one list rather than two, but a backend cannot satisfy the
contract without it.

This is also the limit on extensions: an application that builds its own bundle
can add a lighting model today, because `LightingModel` is a value class rather
than an enum. An extension that does not control the bundle cannot.
