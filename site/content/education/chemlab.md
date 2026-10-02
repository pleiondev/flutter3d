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

Almost everything on a bench is round, so none of it is modelled. Each piece is half of its outline, a profile in the (radius, height) plane ordered bottom to top, swept round the Y axis by `LatheShape`. A test tube is a quarter circle for the bottom, a straight wall and a two-point lip. A repeated point is a hard edge, which is how the lip and the base get a crisp rim.

```dart
List<Vector2> tubeProfile({double radius = 0.08, double height = 0.9}) => [
  for (var i = 0; i <= 8; i++) // the round bottom
    Vector2(radius * sin(i / 16 * pi), radius - radius * cos(i / 16 * pi)),
  Vector2(radius, height), // the wall
  Vector2(radius * 1.12, height), Vector2(radius * 1.12, height + 0.012),
];
```

The liquid is a second lathe a little inside the glass, cut at the fill level and capped. Pouring builds a new profile with a different level and swaps the mesh, letting the old one go after the frames still drawing it.

## Labels without a decal

A lathe's u runs with the angle and its v with the distance along the profile. A label is therefore another strip of the same surface, just outside the glass and covering about a quarter of the turn, and its texture lands on it edge to edge with no stretching.

```dart
LatheShape labelBand({double radius = 0.08, double wrap = 1.6}) => LatheShape(
  profile: [Vector2(radius + 0.002, 0.5), Vector2(radius + 0.002, 0.72)],
  startAngle: pi / 2 - wrap / 2,
  sweepAngle: wrap,
);
```

The picture on it is an ordinary widget: a coloured band, the formula typeset by [flutter_math_fork](https://pub.dev/packages/flutter_math_fork), which renders TeX in pure Dart, and a concentration. The application paints the cards out of sight in its own widget tree, reads each back with `RepaintBoundary.toImage` and uploads the pixels as the label's texture.

Two things catch you out. u runs counter-clockwise seen from above, so from the front the text comes out mirrored, and v counts up the strip while image rows count down; reversing the order of the pixels before upload fixes both. And `SceneSurface` paints when its widget changes, so a label put on between frames stays unseen until something asks for a frame: the bench puts each one on inside `setState`.

## Tested without a GPU

The package's tests check the profiles, that the label strip's UVs run edge to edge, the half turn, that pouring stays inside the glass, and a picture of the whole bench drawn by the software backend. That picture leaves the labels off, because text is rasterised by the platform and differs between machines; a separate test reads the label card's own pixels.
