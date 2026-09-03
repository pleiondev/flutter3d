## 0.4.2

* **`GraphicsDevice.readback`.** The pixels of a texture, or a region of it,
  as the passes submitted *before* the call left them, answered without
  stalling on the GPU — a copy queued in order and a future that resolves when
  the queue reports it done, a frame or two later. `readPixels` stays for the
  golden run and the probes, where the caller has stopped drawing and can
  afford to wait; this is for a caller still drawing that wants last frame's
  answer while this frame goes on: an exposure meter, an editor's pick. What
  cannot be read — tile memory, a multisampled target, a cube, a region past
  the edge — is refused with an `ArgumentError` by `readbackRegionOf`, once,
  so every backend refuses alike. A backend outside this repository has to add
  the member.
* **A readback is eight-bit RGBA or it is refused.** `readbackFormats` names
  the four layouts — `r8g8b8a8`, `b8g8r8a8`, and their sRGB twins — and
  `readbackRegionOf` refuses any other format by name. The contract promises
  the same bytes on every backend, and a half-float target broke it three
  ways: on WebGL2 `readPixels(RGBA, UNSIGNED_BYTE)` of a float attachment is
  an `INVALID_OPERATION` that leaves the pack buffer at zeros and the future
  completing successfully with a black picture; flutter_gpu converted through
  `toByteData`; the software rasteriser clamped its floats. A float texture is
  read through `readPixels`, or drawn into an eight-bit target first, which is
  what the exposure meter's luminance pass is for.
* `FakeBackend.readback` records what was asked — texture and region — and
  answers zeros unless `answerReadback` says otherwise, so a test can be the
  device that saw a dark frame or a particular id.

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
