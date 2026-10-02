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
  <div><dt>Tilt slider</dt><dd>Lean it towards you or away; move it quickly and the liquid sloshes</dd></div>
  <div><dt>Tap</dt><dd>Knock on the glass and watch the rings</dd></div>
  <div><dt>Share with clean tube</dt><dd>Pour the vessel you picked into the empty tube at the front until the two hold the same</dd></div>
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

The liquid fills the inside of the glass up to its surface. Pouring, tilting and every frame of a slosh build a new mesh and swap it in, letting the old one go after the frames still drawing it.

The first version was a coloured solid with a flat lid, and that is exactly how it looked: painted plastic. Several changes fixed that, and the one that mattered most was not in the liquid at all.

- **A meniscus.** Water wets glass and climbs the wall a few millimetres, so the top of the profile rises at the wall and dips towards the middle. The curve catches a thin bright line where it meets the glass, which a flat cap never does.
- **Light goes through all of it.** The material is the layered model with full transmission and water's index of refraction, 1.33. Its colour is the volume's, an attenuation colour over thirty centimetres, and the base colour is nearly white so the colour is not given twice.
- **It is a lens.** A column of liquid is a convex body, and `MaterialExtensions.convexVolume` tells the engine so: the thickness is the depth through the middle, and the path a ray takes inside is that depth times how squarely the bent ray meets the surface. Both the colour and how far behind the liquid the scene is read from follow that path.
- **A wet surface.** A clear coat with no roughness over the colour gives the sharp highlight a liquid has and a painted surface does not.

```dart
Material liquid(Vector3 colour, {required double depth}) => Material(
  lighting: LightingModel.pbrLayered,
  baseColor: Vector4(0.75 + 0.25 * colour.x, 0.75 + 0.25 * colour.y,
      0.75 + 0.25 * colour.z, 1.0),
  roughness: 0.02,
  alphaMode: MaterialAlphaMode.blend,
  depthWrite: true,
  extensions: MaterialExtensions(
    ior: 1.33, transmission: 1.0, thickness: depth, convexVolume: true,
    attenuationColor: colour, attenuationDistance: 0.3,
    clearcoat: 1.0, clearcoatRoughness: 0.0,
  ),
);
```

I expected the convex volume to make the edges of a column paler than its middle, and it hardly does. A ray entering a cylinder of water near its edge is bent towards the axis, so even there it crosses two thirds of the middle's depth. That is true of real tubes too, and it is not what tells liquid from plastic. What does is the world seen through it: the bench, the horizon and the shadows behind a tube, flipped and stretched. For a long time the liquids showed none of that, and the reason was the table. It was slightly transparent, for the reflections under it, so it was drawn after the liquids and was missing from the copy of the scene they read what is behind them from. Through a column of water they saw the sky behind the bench, and clear water came out as a white rod. Made opaque, the table is in the copy, and every tube became a lens.

The glass needed a fix in the engine too. A thin wall bends nothing, so what is behind it is exactly what the frame already holds where it is drawn. The engine used to read it from the copy instead, and the copy is taken before any transmissive draw, so a tube's wall showed the table where its liquid stood and washed the colour out. A blended material that transmits and has no thickness is now composited over the frame: it adds what it reflects and lets the rest through by its alpha, so the liquid shows through its glass.

## Liquid that moves

A liquid's surface keeps level while the glass tilts, and it lags. None of that needs a fluid solver, because a liquid in a round vessel has known modes of oscillation: shapes J_m(ξr/R)·cos mθ, where ξ is a zero of the derivative of J_m so the surface meets the wall square, each ringing at ω² = g·k·tanh(k·h) with k = ξ/R. For a tube this size the first one rocks about two and a half times a second.

- **Tilting.** The surface settles to the plane that is level in the world, and that plane is kept exactly. What the bench follows is how far the liquid is from it, along the first three modes with m = 1. When the glass turns faster than the liquid can follow, the plane moves and the liquid stays where it was, so each mode is left off its rest by its share of the change in slope. A plane expands over those modes with the share 2R / ((ξ² − 1)·J₁(ξ)): the first mode, the sloshing, takes most of it, and the other two are the finer waves that run across the surface as it rocks.
- **Tapping.** A knock starts the axisymmetric modes, at the zeros of J₁: rings that run out from the middle and fade. None of them moves liquid in or out of the middle, so the level stays where it was poured.
- **Damping.** Water in glass this size rocks four or five times before it is still, and a finer wave dies sooner, roughly with the root of its frequency.

Each mode is a damped oscillator stepped six hundred times a second, which costs nothing, and the mesh is rebuilt every frame while anything moves: up the wall at each angle to where the surface meets it, then across the surface to the middle, with the normals taken from the modes' gradients. When the last mode is under a tenth of a millimetre the ticker stops and the bench stops drawing.

A leaning vessel turns about where it stands and is lifted so its lowest point stays on the bench. The cut-by-cut shadows are worked out for upright glass, so while a vessel leans its card is put away and the glass and liquid cast for themselves.

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

The same idea went into the engine as well, for shapes that are not lathes: `ShadowSettings.caustics`. A caster with a volume is drawn from the sun into two small maps, its near faces and its far faces, and one photon per texel is bent in at one and out at the other, followed to whatever lies below, and splatted there. How big each splat is comes from where its neighbouring photons land, so a beam the caster spreads comes out wide and faint and one it focuses comes out small and bright, and light is neither made nor lost. It is general and it is an approximation: it sees two surfaces per caster, so a liquid in a thin glass is followed as the liquid, which is why the glass here is thin-walled, as glTF means it. The demo is lit that way. The cut-by-cut optics above are still in the bench, `Bench(photons: false)`, exact for these vessels and nothing else, and I keep them to check the photons against.

It has limits. The atlas keeps the colour, not where along the light it was picked up, so something standing between the sun and a glass would be shaded as if it stood behind it; a bench has nothing like that. It does nothing with the moments filter, which uses those channels for itself. And a see-through surface that casts is not shaded by it, so a glass does not darken itself; the tabletop, which lets a little of the reflections under it through, casts nothing and is shaded like any floor.

## Pouring one tube into another

There is an empty tube at the front of the bench. Pick a solution and press **Share with clean tube**: the tube rises over its neighbours, comes over the clean one, tips until it pours, and stops when both hold the same. Then it goes back to its place and rocks for a second after it is put down.

None of it is keyframed. Tipped that far, a surface is no longer a height over the floor, so the bench works from the volume instead. The surface is the plane level in the world, and in the glass's frame its height along the world's up is whatever leaves the liquid's volume under it. Cut across its axis a tube is a disc and the plane cuts it along a chord, so the volume under the plane is a sum of circular segments, slice by slice, each with a closed-form area. Liquid runs out when that plane would have to stand above the lowest point of the mouth.

That also says how far to tip. The pour has a schedule, how much should be left in the tube at each moment, and every frame the bench finds by halving the lean at which the tube holds exactly that much below its lip. So it tips quickly to where it starts to run and then slowly, further as it empties, which is what a hand does. What left the tube is added to the other one, whose level comes back from its volume.

The stream is a free fall from the lip. A steady stream carries the same flow at every height, so its section is the flow over its speed and its radius goes as one over the root of the speed: it starts as wide as the flow needs and narrows as it falls. Where it lands it keeps starting rings on the surface. Poured into a tube that already holds something, the two mix by Beer and Lambert: each takes light away per metre, so the mixture takes away the two absorptions weighed by volume, and blue into orange comes out as dark as the two together would be, not as a paint mix of their colours.

The tipped liquid is cut out of the inside of the glass by that plane: the inside swept as a lathe, each triangle the plane crosses cut to the part below it, and the outline of the cut closed with a fan for the surface. The volume came out as a staircase at first, slice by slice, and the first few drops into the empty tube vanished in its first step; the slice the surface crosses now counts for the part of it below.

## Refraction, caustics and reflections

**Refraction comes from the engine.** When a frame holds a material with transmission, the renderer draws the opaque scene first, copies it, and the liquids read that copy offset along the ray their index bends. It is screen-space, so it can only bend what is already on the screen, and one liquid does not see another through itself: both read the same copy. The glass is thin-walled and bends nothing, so it is composited over whatever is behind it, liquid included.

**The caustics come from the optics** described above: the bright line the liquid focuses is where the traced beams pile up on the bench. An earlier version put a small coloured spot light in each shadow instead, which looked right from a distance and was wrong in every detail, and cost a light per vessel out of the eight the engine gives an object.

**The reflections in the tabletop are geometry.** Screen-space reflections were the first try, and they reflected only the labels: the pass reads what the opaque pass drew, and the glass and the liquids come after it. A flat mirror, though, has an exact answer. Each liquid and label is drawn again, scaled by -1 in height so it hangs under the tabletop, flat and a little darker. The copies used to show through a top a twelfth transparent; now the top is opaque, for the refraction above, and the copies are laid over it at a twelfth of their strength with `CompareFunction.greater`, which draws them only where they are behind the top. That is where a mirror shows them, and nowhere else.

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
- **Waves that break.** The modes are linear, so a hard enough jerk makes a surface that would in reality splash simply rock harder. Lean a full tube far enough and the liquid would spill; here it stops at the rim.

## Tested without a GPU

The package's tests check the profiles, that the label strip's UVs run edge to edge, the half turn, that pouring stays inside the glass, and a picture of the whole bench drawn by the software backend. That picture leaves the labels off, because text is rasterised by the platform and differs between machines; a separate test reads the label card's own pixels.
