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

## Liquid that reads as liquid

The liquid is a second lathe a little inside the glass, cut at the fill level. Pouring builds a new profile with a different level and swaps the mesh, letting the old one go after the frames still drawing it.

The first version was a coloured solid with a flat lid, and that is exactly how it looked: painted plastic. Four small changes fixed that.

- **A meniscus.** Water wets glass and climbs the wall a few millimetres, so the top of the profile rises at the wall and dips towards the middle. The curve catches a thin bright line where it meets the glass, which a flat cap never does.
- **Light goes through it.** The material is the layered model with some transmission and water's index of refraction, 1.33, so you see through the colour.
- **Thickness changes the colour.** The solution's colour is also its attenuation colour, so light that crosses more of it comes out deeper. The round bottom of a tube and its edges read darker than the middle, as they do on a real bench.
- **A wet surface.** A clear coat with almost no roughness over the colour gives the sharp highlight a liquid has and a painted surface does not.

```dart
Material liquid(Vector3 colour) => Material(
  lighting: LightingModel.pbrLayered,
  baseColor: Vector4(colour.x, colour.y, colour.z, 0.8),
  roughness: 0.03,
  alphaMode: MaterialAlphaMode.blend,
  extensions: MaterialExtensions(
    ior: 1.33, transmission: 0.35, thickness: 0.06,
    attenuationColor: colour, attenuationDistance: 0.08,
    clearcoat: 1.0, clearcoatRoughness: 0.02,
  ),
);
```

## Shadows: the glass casts none

A shadow map knows only whether something is between a point and the light, not how much light that something lets through. Every caster darkens the bench as much as a brick would. Clear glass that does this looks wrong straight away: an empty tube threw a shadow as dark as a full one.

So the glass is marked `castsShadow = false`, and the liquid inside it is what casts. The empty top of a tube leaves the bench lit, and the shadow starts where the liquid does. It is not physically right either. Real glass dims the light a little, and a coloured solution throws a tinted shadow; neither is possible until the shadow pass can record partial coverage, which is work for the engine; I would rather leave the shadow honest than fake it in a demo.

## Refraction, caustics and reflections

**Refraction comes from the engine.** When a frame holds a material with transmission, the renderer draws the opaque scene first, copies it, and the glass and the liquids read that copy offset along the ray their index bends. Look at the bench through a tube and its edge kinks. Two limits come with it. It is screen-space, so it can only bend what is already on the screen. And the liquid is not in the copy, since it is drawn after it, so the glass in front of a liquid bends the bench behind it but not the liquid. The glass has a centimetre of thickness for this; with none it is a sheet that bends nothing.

**The caustics are lights.** A column of liquid is a lens, and sunlight through it lands as a bright, tinted patch inside its own shadow. The engine traces no photons, so each vessel carries a small spot light of its solution's colour, aimed along the sunlight at the middle of the liquid's shadow. Light channels keep it on the bench: the glass and the liquids are on channel 0, the bench on channel 1, and the spot reaches only channel 1. Pouring moves the patch with the height of the column and makes it stronger.

The engine lights each object with at most eight lights, which I found out by losing the sun's shadow. The bench has the sun and a fill, so eight caustics would make ten, and the sun was the one pushed out. Six fit; the measuring cylinder and the flask go without.

**The reflections in the tabletop are geometry.** Screen-space reflections were the first try, and they reflected only the labels: the pass reads what the opaque pass drew, and the glass and the liquids come after it. A flat mirror, though, has an exact answer. Each liquid and label is drawn again, scaled by -1 in height so it hangs under the tabletop, flat and a little darker, and the top lets a twelfth of what is under it through. The copies are opaque, so they are drawn before the top and never sorted against it. Blended surfaces write no depth, so the top first laid itself over the lower half of every liquid; the liquids now write theirs.

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

## Turning round the bench

The camera is the engine's `OrbitController`, with tighter limits than its defaults. Left alone it lets one drag carry the camera under the table, which on a bench is never what anyone wants. The bench keeps the pitch between just above the tabletop and nearly overhead, the distance within the room, and turns a little slower per pixel than the controller does out of the box.

## What it does not do yet

- **Real caustics.** The patches are placed, not traced: they do not sharpen into the bright line a real tube throws, and glass without liquid throws none.
- **The glass in the mirror.** The reflections carry the liquids and the labels; the glass itself is left out, since a copy of something nearly invisible is nearly invisible.
- **Movement.** When you pour, the surface should rock and settle. A meniscus that sways for a second after the level changes would do it.

## Tested without a GPU

The package's tests check the profiles, that the label strip's UVs run edge to edge, the half turn, that pouring stays inside the glass, and a picture of the whole bench drawn by the software backend. That picture leaves the labels off, because text is rasterised by the platform and differs between machines; a separate test reads the label card's own pixels.
