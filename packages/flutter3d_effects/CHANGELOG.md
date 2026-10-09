## 1.0.0-rc.1

- **Breaking: the elements' simulation moved to `flutter3d_elements`**,
  and this package keeps the views. `ElementsSimulation`, `Fires`,
  `WaterBody`, `TrackedBody`, `Follower`, `Igniter`, `Solid`, `Bed`,
  `ElementHeightfield`, `ElementsListener`, `ElementsSteps`, `FireSteps`,
  `LiquidSteps`, `ElementsSimulationPlugin`, the plugin element's hook,
  its registries and every element event are declared there and not
  re-exported here: import `flutter3d_elements` beside this. `Elements`,
  `ElementsViewPlugin`, `ElementsQuality`, `Liquid` and the views stay.
  New in 1.0, so no 0.8 code names them.
- **Breaking: what draws a body or a water is kept by `Elements`.**
  `TrackedBody.look` is `elements.lookOf(body)`; `WaterBody.view` and
  `WaterBody.look` are `elements.viewOf(water)` and
  `elements.waterLookOf(water)`. A water dug with `setGround` is drawn on
  its new bed from the next frame.
- **`liquidMeshes`, `LiquidLayerMesh`, `jetMesh` and `particleMesh`** come here
  from `flutter3d_core`: a liquid in a vessel and a jet, drawn, are views of
  the physics, and the core no longer depends on it.
- **`FireView.plumeDepth` is `SmokePlume.depth`** of `flutter3d_elements`,
  which the simulation's `seenThroughSmoke` reads too; the numbers are
  unchanged.

- **Systems run in `LoopPhase.fields`**, the elements phase's new name, and
  `Portable` and the `vector_math` crossings come from
  `flutter3d_foundation`.

- **The seabed's sunlight takes the refracted path.** The way down is
  d / cos θt, cos θt = √(1 − (1 − cos²θi)/n²), and the caustics start from
  the refracted ray's offset; it was d / cos θi, which at a sun 30° up made
  the path 2.0 d instead of 1.32 d and the red at three metres some 40 %
  too dark. The sun's blur is σ = w/4 of its width, a disc's Gaussian.
- **Firelight breathes as its flames do**, at 1.5/√D Hz over the fire's
  base, light-weighted over a cluster, where it was 1.5 Hz for any fire.
  The flames' ≈29× emissive gain is a named constant beside the light's
  ≈91×, and both are documented, with the 4.56 of the tongues' rise and
  the two flame-length correlations.
- **Breaking: the elements' names no longer repeat the simulation's.**
  `Pose` is `ElementPose`, `Heightfield` is `ElementHeightfield`, and the
  body the elements made or track is `TrackedBody` (`ElementBody` is the
  hook's handle on a core body, which already had the name). A game that
  imports this and `flutter3d_sim` together no longer hides `Pose`, `Body`
  or `Heightfield`. New in 1.0, so no 0.8 code calls them.
- **The build hook depends on `flutter3d_build_hooks`**, the material
  compiler on its own, and no longer on `flutter3d_build`: a game that
  depends on the effects resolves no MCP server, `dart_mcp` or editor core
  through them.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `LiquidParams` is `LiquidParameters`, `MistOptions` is
  `MistSettings`, `SeabedParams` is `SeabedParameters`. Every settings
  class is `final` with a `const` constructor and a `copyWith` over every
  field; a nullable field is reset with `copyWith(clearX: true)`.
  `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `colour` is `color`, `sunColour` is `sunColor`. Only the Dart
  names changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **Breaking: the elements split into a simulation and a view.**
  `ElementsSimulation` steps the world, the flames and every element with no
  device or renderer; `Elements` draws it (`draw`) and still steps it in
  `update`. `ElementsSimulationPlugin` steps it in a loop's `elements` phase
  with its state a snapshot part, and `ElementsViewPlugin` draws it in the
  frame. `Elements.over` draws a simulation something else steps.
- **Breaking: `ElementFields` is backend-neutral.** An element's step reads
  and writes bodies as `ElementBody` and places as `WorldPosition`;
  `NativeElementFields` is the core's, with its fires and waters beside.
- **`SeabedParameters` and `LiquidParameters`**: typed accessors generated from the
  two materials, which `SeabedLook` and `LiquidLook` now set their uniforms
  through. Neither look's API changed.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **The liquid and seabed bundles are rebuilt** against the engine's
  headers, which now read the sun's shadow map in whichever way round it
  keeps its depth — `A2.8`.

- **A new element is a Dart hook over the world, and fire and water are
  two.** An `ElementHook` steps in its own phase (`elements.<id>`, after the
  engine's `elements` and before `rules`), reading and writing the world's
  heat, water, wind and forces through `ElementFields` with `Portable`
  arithmetic; draws once a frame through `view`; and keeps what the world's
  snapshot does not through `save` and `restore`. `installElement` puts one
  into an `EngineLoop` and `ElementPlugin` makes one a plugin.
  `Elements.addElement` adds one to the elements' own update, and
  `saveElements`/`restoreElements` carry every element's state, the flames
  still held among them. `Elements` runs its fire and water through the
  same hooks, in the order it always ran them, so nothing it draws or steps
  moves.

- **`ElementsSteps` switches plugin elements too.** `elements` holds a
  switch per element id, `isOn` asks one, `withElement` sets one, and
  `ElementsSteps.none` switches every unnamed element off. A switched-off
  element is not drawn or heard and still steps, as fire and water are.
  `ElementSwitches` is the engine's registry of the switches elements
  declare, and refuses one id twice.

- **The elements speak on the bus.** `Elements.publishTo` publishes the
  world's events as `ElementEvent`s by kind, with what plugin elements
  publish from their steps. `ElementEventKinds` holds the core's kinds and
  the ones plugins add with `NativeEventKind.plugin`, and refuses a code or
  a name claimed twice, naming both claimants. `ElementsListener.toBus`
  makes the listener that publishes each callback as its event
  (`ElementCaught`, `ElementOut`, `ElementBurntOut`, `ElementWetted`,
  `ElementBurnerOut`, `ElementExploded`, `ElementsOverBudget`,
  `ElementFireSeen`, `ElementFireLost`); `Elements.listener` stays the
  field it is set on. `ElementExploded` is a `PlacedEvent`, so an effect
  document triggered by `elements.exploded` goes off where the charge did.

- **The effects fall by their world's gravity.** Embers drop, falling
  water is heard and mist is thrown up by the `NativeWorld`'s
  `gravityMagnitude` rather than a 9.81 of their own, so a world set on the
  Moon has Moon embers, a quieter falls and more mist. `mistShare` and
  `MistSettings.shareAt` take the world's `g` and the liquid's `viscosity`
  (water's preset when none is given); `LiquidView` takes the liquid's
  `properties`, which `Elements.addWater` hands it, and weighs its mist by
  that density; `PhysicsHearing.listen` defaults to water's preset density.
  The air density in the mist law stays the 1.2 kg/m³ the handbook's
  correlation was fitted in, as part of that law. A world with the Earth's
  gravity draws and hears to the bit what it did.

- **An ember is dragged through its world's air.** `FireView` works the
  air's density out of the world's `airTemperature` and `airPressure` as an
  ideal gas, ρ = p M / (R T), each frame, in place of a fixed 1.18 for air
  at 300 K: a fire in a cold world drags its embers harder, one up a
  mountain less. In the standard world that is 1.204, so embers lag their
  gas a little more than they did, **which moves every frame with embers in
  it: the effects' fire goldens are re-recorded before the release.**

- **Water poured into a world is as warm as that world's air.**
  `Liquid.water()` without a temperature is `atAirTemperature`, and
  `Elements.addWater` pours it at the world's `airTemperature` —
  `Liquid.heatIn(world)`. One given a temperature, or a heat of its own
  through `copyWith`, keeps it.

- **Smoke as dark as its fuel makes it.** `FireView` draws each fire's
  smoke with the soot its fuel makes, the core's `NativeFire.sootYield`,
  in place of wood's for every fire: a tyre's plume is three times as dark
  as a crate's, glowing charcoal sends up none. `FireView.plumeDepth`
  takes a `sootYield`, wood's when it is not told; 8.7 m² a gram stays
  for every fuel (`doc/smoke_plume.md`).

- **Mist as much as the fall makes.** `MistSettings.share` is no longer
  needed: left out, the share of landing water that goes up as mist is the
  airborne fraction measured off falling water at the speed it lands,
  3·10⁻⁴ at 10 m/s and rising as the speed to the 3.3, at most 1.5 %, and
  its droplets 14.8 µm, that spill's Sauter mean (`doc/mist_share.md`,
  `mistShare`). The demos no longer set a hundredth by hand.

- **Igniters that were measured.** `Igniter.match`, `lighter`,
  `propaneTorch` and `pilot`, from NBS Monograph 173, Williamson's lighter
  flames and the FAA's fire-test burners, with `copyWith`
  (`doc/igniters.md`).

- **Every step of the elements can be switched off, in any combination,
  and they tell the game what happens.** `Elements.switches` takes an
  `ElementsSteps` — the fires' `FireSteps` (flames, smoke, embers,
  firelight, charring), the waters' `LiquidSteps` (surface, falling sheet,
  drops, mist, bubbles) and sound — each on its own; a step switched off
  costs nothing and leaves nothing of itself drawn or heard, and the world
  steps the same. `Elements.listener`, an `ElementsListener`, is called
  from `update` in the order the core said things: caught, out, burnt out,
  wetted, burner out, exploded; a step drawing less than it wanted
  (`budget`); a fire coming into or leaving the camera's picture (`seen`,
  `lost`). `heatFluxAt` gives the radiant heat on a point from every fire
  (Modak's point source, capped by the soot's σT⁴), `burnDoseRate` ISO
  13571's burn dose for it, `waterAt` the water standing at a point, and
  `seenThroughSmoke` how much light gets through the plumes between two
  points.

- **Water, fire and bodies in a few lines.** `Elements` owns an effects
  world, steps it, keeps each look on its body, draws and hears it:
  `addWater` lays a pond or a river over a `Heightfield` with a `Liquid`
  and a `Bed` whose roughness is Chow's Manning n, and `WaterBody` fills a
  basin, pours, adds springs, weirs and drains, and sets its edges and
  walls; `addBody` makes a `Solid` of a material by its density; `follow`
  pushes water and fire with a game's own object and is never moved back,
  so replays stay as they were; `fires` lights a body by holding an
  `Igniter` to it for its time, feeds burners, sets charges off and douses.
  `Elements.adopt` does the same over a world a game steps itself.

- **Fires sized and lit by their own heat.** `FireView` takes each fire's
  base, the share of its body alight and its reach from the core, so one
  view draws a candle and a burning hall alike, with no width to set.
  `FireLights` lights by the lumens a blackbody at the soot's temperature
  radiates (`Blackbody`, the CIE 1931 observer against Planck's law), in
  its colour, gathered per fire, per cluster or not at all, with nothing
  capped. A watched look goes black by the share of it the core's char
  covers and glows at the char's temperature, and stays charred once the
  fire is out. A tongue of flame is as bright as the soot in it, a
  blackbody at its temperature through the flame's emissivity, cooling as
  it rises by McCaffrey's centreline excess. The smoke is as dark as its
  plume carries soot, τ = 2K_mṁ_s/(πbu) across it, thickest over the
  flame and thinning as z^(−2/3) as it climbs (`doc/smoke_plume.md`).

- **Water's look from its optics.** `LiquidOptics` is one pair of
  absorption and backscatter coefficients, 1/m, shared by the surface and
  `SeabedLook`; ripples steepen with the wind as Cox and Munk measured and
  fade as they shrink below a pixel. `MistSettings` sets the mist where a
  fall lands by its droplets' size, not by hiding a node. `HearingScale`
  is the game's to set.

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
  streak as air is torn in. A strand that plunges into water goes in
  whole; one the core parts into drops in the air frays through over the
  last of the twelve e-folds its ripples grow to part it (Grant and
  Middleman), and goes on falling as a veil of those drops, so no strand
  stops short in mid-air. A liquid that lets no light through falls in
  its own colour and glow.

- **Drops, mist and bubbles drawn as the light they stop.** Millimetre
  drops a few metres off are far under a pixel, and a falls' spray is
  what they hide together: each piece of drops the core throws is drawn
  as a cloud spread over the cell and the step it came from, as deep as
  van de Hulst's extinction makes its drops — twice their cross-section
  for spray, next to nothing for drops far finer than light — thinning
  out normally to a rim it reaches nothing at, so the pieces add up to an
  even veil rather than a few beads. The mist where drops land and the
  bubbles a plunge drives down are drawn the same way, the bubbles kept
  under the surface; the mist is carried out over the pool the way the
  water was going, in billows, not heaped in one dome over the foot. The
  froth the bubbles bring up spreads round in a plume that fades into the
  pool, not a square of cells.

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
