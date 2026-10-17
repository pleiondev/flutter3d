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
WebGPU. Both laboratories here are one `Flutter3dView` each, which opens the
device and owns the frame clock.

## A pendulum on the accurate profile

The second laboratory is a pendulum you step by hand:

```bash
flutter run -d macos -t lib/pendulum_main.dart
```

A rod of one metre, let go at 0.1 rad, in standard gravity. The panel shows
the angle and the period measured from the crossings of the vertical, beside
the period the series gives (2π√(L/g)·(1 + θ²/16 + …)). Over a hundred swings
the two agree to 1e-4, which `test/pendulum_lab_test.dart` holds.

Two things make it a laboratory rather than a game:

- **It runs on `SimulationProfile.accurate`.** The view's own loop runs the
  deterministic profile a game is played on, so the laboratory builds its own
  loop in `pendulumSimulation` and the view places it with
  `SimulationPlacement.isolate` (in the page on the web). On the accurate
  profile the pendulum is integrated with its rod held exactly; on the fixed
  step a game uses it would miss the period by 4.6e-4 and lose most of its
  swing over the same hundred periods. A laboratory a server checks by
  replaying the student's run stays on the deterministic profile; the
  accurate one is for showing.
- **Its clock is moved by hand.** The view's time source is a `ManualTime`:
  "Step" hands it one fixed step and "Run" a step's worth every frame. What
  the panel reads is what the laboratory's probes published, so it reads the
  same with the simulation in an isolate as it would beside the view.

## Glass from profiles

Almost everything on a bench is round, so none of it is modelled. Each piece
is half of its outline, a profile in the (radius, height) plane ordered bottom
to top, swept round the Y axis by `LatheShape`. A test tube is a quarter
circle, a straight wall and a slight flare; a flask is a handful of points.
`glassWall` turns an outline into glass with a wall: the inside walked back
down half a millimetre in, joined to the outside by a rounded rim. The scene's
environment is a sky (`labSky`), since glass shows mostly what is round it.

The liquid is a second lathe a little inside the glass, cut at the fill level
and topped with a meniscus that climbs the wall. Its material lets light
through with water's index of refraction and tints it, so a thicker layer is
deeper in colour. Pouring is a new profile with a different level
(`Bench.pour`).

The shadows and caustics are geometric optics (`optics.dart`): each
horizontal cut of a vessel is a set of circles, sunbeams are followed through
them by Snell, Fresnel and Beer–Lambert and counted where they land, and the
result is painted on a shadow-only card on the bench. The
reflections in the tabletop are the liquids and labels mirrored under a top
that lets a little of them through. Refraction is the engine's own: glass
and liquid read a copy of the opaque scene, offset by their index.

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
- **Ask for a frame.** The bench's view runs its clock only while a liquid
  moves, and otherwise draws when it is built, so a label put on or the
  camera turned is not seen until something rebuilds it. `BenchScreen` does
  both inside `setState`.

## Tests

`flutter test` checks the profiles, that the label strip's UVs run edge to
edge, the half turn, that filling stops at the glass's limit, that sharing
pours half and loses nothing, that mixed dyes take the colour light through
both would, and a picture of the bench drawn by the software backend with no
GPU. The liquid itself is `flutter3d_physics`'s and is tested there, and
the bench's tests run on the run's physics: the core by default, the Dart
reference with `--dart-define=FLUTTER3D_PHYSICS=dart`. The golden leaves the labels
off, since text is rasterised by the platform and differs between machines;
the label test checks the card's own pixels instead.

For the pendulum, `test/pendulum_lab_test.dart` checks the profile, that
nothing moves until the clock is moved, and the period against the series
over a hundred swings; `test/pendulum_screen_test.dart` steps the screen by
hand with the simulation in an isolate.
