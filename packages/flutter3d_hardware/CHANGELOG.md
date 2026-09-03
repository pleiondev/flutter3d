## 0.4.2

* **`SamplerOptions.anisotropy` and `GraphicsDevice.maxAnisotropy`.** A
  floor seen along its length covers a footprint a few texels tall and many
  wide, and a trilinear sampler picks one level for the whole of it — the
  level that stops the long axis aliasing blurs the short one. The field is
  a count of taps along that long axis, one by default so every picture is
  the bytes it was, checked at construction to sit on a trilinear sampler
  because that is flutter_gpu's rule and the taps are taken across the
  chain, and clamped by every backend to what the device answers, so
  sixteen is a safe thing to ask for. The device getter is there to decide
  with rather than to guard: the bridge asks it once per level. `FakeBackend`
  answers sixteen and can be told otherwise. `withAnisotropy` copies a
  sampler with the one field a caller decides at run time.
* **`GraphicsDevice.loadShaders`: a shader bundle arrives as bytes.** The
  one way a shader reaches a device without being an asset, for an editor
  that rebuilds a bundle and wants to see it without restarting and for an
  application that ships a look the engine never heard of and wants it on
  every backend. `ShaderBundle` is the container — a header naming the
  bundle, the SDK it was compiled on and the stages it claims, then one
  section per backend — with `encode`/`decode` checked against each other.
  `LoadedShaderLibrary` is what comes back: a `ShaderLibrary` with `refresh`,
  which reparses new bytes in place and **keeps the identity of every handle
  already handed out**. `ShaderBundleRefused` is the one exception a device
  answers when it will not load a bundle, and it names the bundle: never an
  empty library, which would fail at the first draw naming a stage rather
  than the file to rebuild.
* `FakeBackend.loadShaders` and `FakeLoadedShaderLibrary`, which keep the
  same identity promise so a test of a reload path proves something;
  `FakeBackend.linkedPipelines` records every pair linked, in order, so a
  test can tell a frame that relinked from one that did not.
* **A loaded library lives as long as the device**, and `loadShaders` now
  says so: there is no release, because the handles it handed out are held
  by whatever resolved them, so an application whose shaders change loads
  one bundle and refreshes it in place. `LoadedShaderLibrary` also says what
  a pipeline linked before a refresh does until it is dropped — draws the
  code it had, on every backend — since one backend did not keep that.
* **A refresh that drops a stage in use is refused, naming the stage.** The
  other half of the identity promise, and `LoadedShaderLibrary.refresh` now
  says so: a handle is the renderer's for its lifetime, so a bundle that no
  longer names that stage would leave a live handle over nothing — a stale
  pipeline on one backend, a link error on another. Every backend and the
  fake refuse it the same way, before anything is swapped, and the
  conformance suite holds them to it.
* `ShaderBundle.decode` refuses a string field that is not UTF-8 as a
  `ShaderBundleRefused`, rather than letting the decoder's own
  `FormatException` out as the one exception that was not a refusal.
* `package:flutter3d_hardware/shader_bundle.dart` exports the container on
  its own, with no Flutter behind it: the barrel reaches `package:flutter`
  through `GraphicsDevice`, and the tool that packs a bundle is a `dart run`
  script.

## 0.4.1

* **`GraphicsDevice.supportsTextureFormat`.** The question a block-compressed
  format needs asked and none of the backends was asking: every value of
  `TextureFormat` has a name everywhere, and BC is a desktop family, ETC2 a
  mobile one, ASTC newer still. A loader asks before it uploads and a no is a
  texture left out with a reason, not an `ArgumentError` out of an allocation.
  A backend outside this repository has to add the member; the three inside
  answer from flutter_gpu's capability, the WebGL2 context's extensions, and a
  constant no for anything compressed.
* `TextureFormatCompression`: `isCompressed` and `blockLayout` for every
  block-compressed value, the one source every backend now reads.
* `FakeBackend` records the mip chain each upload came with and can be told
  which formats to refuse.

## 0.4.0

* **A loan that outlives a `trim` goes back to the allocator.** It used to be
  refiled under its retired pre-resize spec on release, where no acquire would
  ever match it — parked until the next trim. The pool now hands it straight
  back, keeps the throw-on-double-release contract, and has tests for the
  whole shape.

## 0.3.0

* `createCubeTextureFromPixels` takes mip levels, which is what image-based
  lighting needs and what a hand-built chain has to be uploaded through.
* `LayeredShaderLibrary` puts an application's own bundle in front of the
  engine's without replacing it.

## 0.2.0

* `PassEncoder` split from `CommandEncoder`, so a contributor drawing into
  somebody else's pass cannot end it.
* A render target pool that releases by identity and waits out the frames in
  flight, and capability questions a backend answers rather than guesses at.

## 0.1.0

* The vocabulary an engine writes a frame in: texture and buffer handles,
  formats, render targets, pipelines, a command encoder and a shader library.
* No implementation of its own. What it names is what a backend must answer to,
  and what the engine may assume.
