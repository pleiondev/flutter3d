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

## Shadows that know what the material lets through

A shadow map holds one depth per texel: whether something stands between a point and the light, and nothing about how much light that something lets through. So every caster darkened the bench as much as a brick would, and an empty tube threw a shadow as dark as a full one.

For a while the glass was simply marked `castsShadow = false`. I didn't like that, and in the end it went into the engine as `ShadowSettings.translucentCasters`. The atlas is a four-channel texture of which only red held depth, so the other three now hold what see-through casters let through, per colour. A glass or a liquid is drawn into it after the opaque casters, tested against their depth and blended so that layers combine, and the lit pass multiplies the sun by it.

What one surface lets through comes from its material: the share that is not there at all (one minus its opacity), what its transmission passes of the rest, tinted by its colour, and what is not reflected away at its surface, from the Fresnel term of its index of refraction. That last part is why clear glass casts a faint shadow with darker edges: light meets the walls of a tube at a grazing angle near its sides and is mostly reflected there. A coloured solution casts a shadow of its own colour, and light through the walls and the liquid gets all three.

```dart
final settings = RenderSettings(
  shadows: ShadowSettings(translucentCasters: true),
);
```

The first coloured shadows on this bench were hard to see, and the engine was not the reason. Only the sun's share of the light is tinted, and the room was lit by a sky as bright as the sun, so a shadow lost a third of its light and kept most of its grey. The tabletop was dark grey too, and colour does not read on dark grey. The bench now has a light, warm top, a stronger sun and a dimmer sky, and the solutions let more light through, as real ones do: their transmission is 0.85, so a tube's shadow is mostly the colour of what is in it.

That model looks at one surface at a time, so it knows how much light a tube takes and not where the rest goes, and where it goes is most of what a tube's shadow is: a bright line down the middle where the liquid focuses the sun, dark edges, and a little light thrown out past the sides. So the bench works the shadows out with geometric optics instead. Every vessel is a surface of revolution, so cut across at any height it is a set of circles round one centre: the outside of the glass, its inside four millimetres in, and the liquid's edge. A sunbeam crossing the cut is bent at each circle by Snell's law, partly reflected by Fresnel's, totally reflected where it meets a thinner medium too steeply, and dimmed in the liquid by Beer and Lambert over the length it actually travels there. The sun comes down at an angle to the tube, so in the cut each medium bends the ray as if it had Bravais's index, while the reflection is worked out at the angle the ray really meets the glass. Sixteen hundred beams per cut and sixty-four cuts per vessel, followed to the bench and counted where they land, give a picture of the light under it, recomputed in a few milliseconds whenever you pour.

The picture goes back into the engine through the same atlas. It is painted on a card lying on the bench along the vessel's shadow, which casts into the shadow map and nothing else, and the engine lets a see-through caster's colour map scale what it lets through, past one where light was gathered. The glass and the liquid cast nothing of their own any more, and the card does not shade them or the labels, which stand over that light, not under it.

The same idea went into the engine as well, for shapes that are not lathes: `ShadowSettings.caustics`. A caster with a volume is drawn from the sun into two small maps, its near faces and its far faces, and one photon per texel is bent in at one and out at the other, followed to whatever lies below, and splatted there. How big each splat is comes from where its neighbouring photons land, so a beam the caster spreads comes out wide and faint and one it focuses comes out small and bright, and light is neither made nor lost. It is general and it is an approximation: it sees two surfaces per caster, so a liquid in a thin glass is followed as the liquid, which is why the glass here is thin-walled, as glTF means it. The **Engine photons** switch in the demo shows the bench lit that way; with it off you see the cut-by-cut optics above, which are exact for these vessels.

It has limits. The atlas keeps the colour, not where along the light it was picked up, so something standing between the sun and a glass would be shaded as if it stood behind it; a bench has nothing like that. It does nothing with the moments filter, which uses those channels for itself. And a see-through surface that casts is not shaded by it, so a glass does not darken itself; the tabletop, which lets a little of the reflections under it through, casts nothing and is shaded like any floor.

## Refraction, caustics and reflections

**Refraction comes from the engine.** When a frame holds a material with transmission, the renderer draws the opaque scene first, copies it, and the glass and the liquids read that copy offset along the ray their index bends. Look at the bench through a tube and its edge kinks. Two limits come with it. It is screen-space, so it can only bend what is already on the screen. And the liquid is not in the copy, since it is drawn after it, so the glass in front of a liquid bends the bench behind it but not the liquid. The glass has a centimetre of thickness for this; with none it is a sheet that bends nothing.

**The caustics come from the optics** described above: the bright line the liquid focuses is where the traced beams pile up on the bench. An earlier version put a small coloured spot light in each shadow instead, which looked right from a distance and was wrong in every detail, and cost a light per vessel out of the eight the engine gives an object.

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

- **Shadows of everything else.** The optics are worked out for surfaces of revolution under one sun. A vessel's light passing through another vessel is not followed, and a lamp casts ordinary shadows.
- **The glass in the mirror.** The reflections carry the liquids and the labels; the glass itself is left out, since a copy of something nearly invisible is nearly invisible.
- **Movement.** When you pour, the surface should rock and settle. A meniscus that sways for a second after the level changes would do it.

## Tested without a GPU

The package's tests check the profiles, that the label strip's UVs run edge to edge, the half turn, that pouring stays inside the glass, and a picture of the whole bench drawn by the software backend. That picture leaves the labels off, because text is rasterised by the platform and differs between machines; a separate test reads the label card's own pixels.
