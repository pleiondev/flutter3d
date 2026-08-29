## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* First release. `renderFrame` draws a scene through the software backend, with
  no GPU, no driver and no display; `expectMatchesGolden` holds the result to a
  reference image, recording one when there is none.
* The tolerance defaults to zero, because a software rasteriser draws the same
  scene the same way twice and a test that allows drift has stopped watching
  it.
