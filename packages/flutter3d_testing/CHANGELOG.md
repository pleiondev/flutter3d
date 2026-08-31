## 0.3.0

* First release. `renderFrame` draws a scene through the software backend, with
  no GPU, no driver and no display; `expectMatchesGolden` holds the result to a
  reference image, recording one when there is none.
* The tolerance defaults to zero, because a software rasteriser draws the same
  scene the same way twice and a test that allows drift has stopped watching
  it.
