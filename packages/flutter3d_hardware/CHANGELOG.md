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
