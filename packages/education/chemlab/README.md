# chemlab

A virtual chemistry bench on flutter3d: five labelled test tubes, a graduated
cylinder, a beaker and an Erlenmeyer flask, each holding a solution of its own
colour. Drag to turn round the bench, scroll to come closer, pick a vessel and
move the slider to fill or empty it.

```bash
flutter run -d chrome
flutter run -d macos
```

It runs in the browser on the site, under Education, through WebGL2 or
WebGPU.

## Glass from profiles

Almost everything on a bench is round, so none of it is modelled. Each piece
is half of its outline, a profile in the (radius, height) plane ordered bottom
to top, swept round the Y axis by `LatheShape`. A test tube is a quarter
circle, a straight wall and a slight flare; a flask is a handful of points.
`glassWall` turns an outline into glass with a wall: the inside walked back
down four millimetres in, joined to the outside by a rounded rim. The scene's
environment is a sky (`labSky`), since glass shows mostly what is round it.

The liquid is a second lathe a little inside the glass, cut at the fill level
and topped with a meniscus that climbs the wall. Its material lets light
through with water's index of refraction and tints it, so a thicker layer is
deeper in colour. Pouring is a new profile with a different level
(`Bench.pour`).

## Labels without a decal

A lathe's u runs with the angle and its v with the distance along the profile.
So a label is another strip of the same surface just outside the glass
(`labelBand`), and a texture lands on it edge to edge with no stretching.

The label itself is an ordinary Flutter widget, `LabelCard`: a coloured band,
the formula typeset by [flutter_math_fork](https://pub.dev/packages/flutter_math_fork),
which renders TeX in pure Dart (`\mathrm{K_2Cr_2O_7}`), and a note.
`LabelPrinter` paints the cards out of sight in the app's own tree, reads each
one back with `RepaintBoundary.toImage`, and `Bench.dress` wraps it on.

Three things to know when doing the same:

- **The picture has to be turned half round.** u runs counter-clockwise seen
  from above, so from the front the text comes out mirrored, and v counts up
  the strip while image rows count down. `forLathe` reverses the pixel order,
  which fixes both.
- **The card has the strip's proportions.** A wide card on a tall strip
  pulls the text upwards; `LabelCard.size` is worked out from `labelAspect`.
- **Ask for a frame.** `SceneSurface` draws in `build`, so a label put on or
  the camera turned is not seen until something rebuilds it. `BenchScreen`
  does both inside `setState`.

## Tests

`flutter test` checks the profiles, that the label strip's UVs run edge to
edge, the half turn, that pouring stays inside the glass, and a picture of the
bench drawn by the software backend with no GPU. The golden leaves the labels
off, since text is rasterised by the platform and differs between machines;
the label test checks the card's own pixels instead.
