## 0.9.0

- **Water that ends at its shore and does not tile.** `LiquidView` draws a
  dry cell at the shore level with the water beside it, not down at its
  ground, so the surface runs flat into the bank and ends where it meets
  the ground — over voxels in steps a metre high there are no more glassy
  wedges along every edge. A film on a step whose ground stands over the
  water below it is drawn as that water's bank, so no slanting sheet
  crosses the step's face, while a river running down a slope or from its
  shallow side to its deep middle is left whole. Where the water stands
  over a dry cell, at a drop or a flat shore, it thins out short of
  halfway when it is a film and at halfway when it is deep, further into a
  bay of wet cells than past a lone corner, so the edge is not a staircase
  of cells. `LiquidLook`'s ripples are nine waves, 3.1 m down to 23 cm, in
  no ratio of small whole numbers and mostly running with the wind, over a
  plane bent at two scales and roughened in drifting gusts, so the pattern
  never repeats; they are gentler than the six they replace and calm where
  the water thins. Water hides the bed as much as the refracted ray's
  length through it says, the sky turns gently from horizon to zenith in
  it so a ripple at a low angle does not flash between the two, the sun's
  glint is as strong as Fresnel lets it be, and the last six centimetres
  of depth fade out, so a film at the shore is all but unseen, not the
  pale rim it was. Froth drifts in flecks a hand's breadth across that the
  flow carries, also where water deep enough to break runs fast, and the
  thin front of water arriving over dry ground shows the ground through
  it, a wet sheen rather than a pale slab. `SeabedLook`'s caustics follow
  the same nine waves.

- **Falling water that falls.** `LiquidView`'s sheet off a lip is drawn
  with `LiquidLook` too: clear and glassy at the lip, mirroring the sky;
  torn into streaks down the fall, with lumps running down them as the
  flow pulses, the pattern riding with the water; whitening streak by
  streak as air is torn in; and in the last of the fall fraying apart into
  the drops the core breaks it into, each strand fading at its own foot
  rather than ending in a cut edge. A liquid that lets no light through
  falls in its own colour and glow. Where it lands, the drops throw up a
  soft plume of mist, and the froth bubbles bring up spreads round in a
  plume that fades into the pool, not a square of cells.

- **The physics heard.** `PhysicsHearing` reads off a world what a
  listener would hear: a source for each fire as loud as its watts, for
  falling water as loud as the power it gives up falling, and a splash
  where a watched body enters a liquid as loud as the energy it enters
  with, each on a logarithmic scale, as hearing is, and a little lower in
  pitch the bigger it is. No audio here: a game plays them. A fire, falling
  water and a splash, synthesised by `tool/make_sounds.py`, ship in
  `assets/`.

- **A sea floor lit through its surface, and a surface seen from below.**
  `SeabedLook` draws a floor with the caustics the surface's own ripples
  focus on it — geometric optics, 1/|det(I + a·H)| with a = d·(1 − 1/n),
  blurred by the sun's half degree — and the colour water takes out of the
  light, red first, on the way down and back up to the eye. Over the floor
  the light averages to what fell on the surface. `LiquidLook`'s surface,
  seen from under it, is Snell's window: the sky in a cone of 97°, a mirror
  of the water outside it. `SeabedLook.under` dresses anything else under
  the same sea — a rock, a hull, a diver — in its own colour with the
  floor's stages and parameters, so one update moves the caustics on all
  of it and the water reddens it away with distance as it does the floor.

- **The physics core's water and fire, drawn, in a package of their own.**
  `LiquidView` draws one water of `flutter3d_physics_native`: its surface
  with the `LiquidLook` material — ripples the flow carries, Fresnel's sky,
  the sun's glint, colour by depth, froth where there is air — and the
  sheet off a lip as one sheet, its drops and its bubbles. `FireView` draws
  every fire of a world: tongues risen at the speed of a flame's gas along
  the core's leaning axis, lit smoke at the plume's speed, embers,
  firelight, and the watched bodies charring as they burn. Plain Dart, with
  the material shipped compiled as `LiquidLook.asset`.
