---
description: A virtual chemistry bench on flutter3d, running in this page: glassware turned from profiles, labels typeset in TeX and wrapped on without a decal, and liquid you can pour.
---

# Demo: a chemistry bench in a browser

Five labelled test tubes, a graduated cylinder, a beaker and an Erlenmeyer flask, each holding a solution of its own colour. Every piece of glass is a surface of revolution, every label is a Flutter widget wrapped round its tube, and the slider pours.

<div class="demo">
  <iframe class="demo-frame" src="/demo/chemlab/" title="The chemistry bench" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGPU where the browser has it, WebGL2 where it does not</span>
    <span><a href="/demo/chemlab/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>The labels arrive a moment after the bench: each one is typeset, read back as a picture and only then put on its tube.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>Drag</dt><dd>Turn round the bench</dd></div>
  <div><dt>Scroll</dt><dd>Come closer or step back</dd></div>
  <div><dt>Vessel chips</dt><dd>Pick what to pour into</dd></div>
  <div><dt>Pour slider</dt><dd>Fill or empty the vessel you picked</dd></div>
</dl>

## Glass from profiles

Almost everything on a bench is round, so none of it is modelled. Each piece is half of its outline, a profile in the (radius, height) plane ordered bottom to top, swept round the Y axis by `LatheShape`. A test tube is a quarter circle for the bottom, a straight wall and a slight flare at the mouth. A repeated point is a hard edge.

```dart
List<Vector2> tubeProfile({double radius = 0.08, double height = 0.9}) => [
  for (var i = 0; i <= 8; i++) // the round bottom
    Vector2(radius * sin(i / 16 * pi), radius - radius * cos(i / 16 * pi)),
  Vector2(radius, height), // the wall
  Vector2(radius * 1.06, height + 0.01), // the flare
];
```

That outline is only the outside. Swept as it is, it ends in a bare edge, and from above the mouth of a tube read as a flat paper ring. `glassWall` gives it a wall: the inside is the outline moved in along its normal by four millimetres and walked back down, so its normals face the cavity, and a half circle joins the two as the rim that catches the light. Glass also shows almost nothing of itself, only what is round it, so the scene has a sky for an environment: a bright ceiling, a pale horizon and a darker floor for the glass to reflect.

The liquid is a second lathe a little inside the glass, cut at the fill level. Its top is not flat: water wets glass and climbs the wall a few millimetres, so it ends in a meniscus that dips towards the middle. Its material lets light through with water's index of refraction, and its colour also tints what passes through it, so a thicker layer is a deeper colour. Pouring builds a new profile with a different level and swaps the mesh, letting the old one go after the frames still drawing it.

## Labels without a decal

A lathe's u runs with the angle and its v with the distance along the profile. A label is therefore another strip of the same surface, just outside the glass, and its texture lands on it edge to edge with no stretching. Like a real label it goes more than half way round, so the paper shows from the side; the writing keeps to the middle, which faces the front.

```dart
LatheShape labelBand({double radius = 0.08, double wrap = 3.4}) => LatheShape(
  profile: [Vector2(radius + 0.002, 0.52), Vector2(radius + 0.002, 0.66)],
  startAngle: pi / 2 - wrap / 2,
  sweepAngle: wrap,
);
```

The picture on it is an ordinary widget: a coloured band, the formula typeset by [flutter_math_fork](https://pub.dev/packages/flutter_math_fork), which renders TeX in pure Dart, and a concentration. The application paints the cards out of sight in its own widget tree, reads each back with `RepaintBoundary.toImage` and uploads the pixels as the label's texture.

Three things catch you out. The card must have the strip's own proportions, its arc over its height, or the text is squashed one way and stretched the other; the bench works the card's size out from the strip's. u runs counter-clockwise seen from above, so from the front the text comes out mirrored, and v counts up the strip while image rows count down; reversing the order of the pixels before upload fixes both. And `SceneSurface` draws in `build`, so anything that changes the picture without rebuilding it, a label put on or the camera turned, is not seen until something else asks for a frame: the bench does both inside `setState`.

## Tested without a GPU

The package's tests check the profiles, that the label strip's UVs run edge to edge, the half turn, that pouring stays inside the glass, and a picture of the whole bench drawn by the software backend. That picture leaves the labels off, because text is rasterised by the platform and differs between machines; a separate test reads the label card's own pixels.
