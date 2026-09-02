## 0.4.2

* **A colour attachment names a face and a level.** `ColorTarget.face` picks
  a face of a cube in the order the uploads take them, `ColorTarget.mipLevel`
  a level below the base, and a pass's initial viewport covers the level.
  What a reflection probe is drawn into, and the first time anything in the
  engine renders into a face or a mip.
* **`GraphicsDevice.createCubeRenderTarget`** allocates a cube a pass may
  draw into, device-private and empty, with a chain of the length asked for
  and trimmed to what the device will hold; **`supportsRenderToMip`** says
  whether a level below the base can be attached at all, which is the one
  capability that splits flutter_gpu by platform. `FakeBackend` records both
  and answers the capability either way.

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
