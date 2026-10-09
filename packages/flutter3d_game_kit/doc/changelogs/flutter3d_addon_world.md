## 1.0.0-rc.1

- **Breaking: `Horizon.addTo` takes `RenderMaterial`s.** The engine's
  `Material` is `RenderMaterial` in 1.0, so it no longer collides with
  Flutter's; `dart fix` renames it.

- **The hour of the day, on the physical sky.** `Daylight` moves the sun
  round one great circle a day and hands the renderer a `SkySettings` with
  the sun where the hour puts it: the air scatters the morning pale, the
  evening red, and lets the stars out at night. The sun and the moon are lit
  by what the air leaves of them, and only the one in the sky casts the
  shadows. The length of an hour, the sun's strength, the moon's share and
  where noon stands are a game's to set.

- **The world going on to the horizon.** `Horizon` builds rings round the
  simulated square, close at the edge and kilometres apart further out: a
  far floor that starts where the game's ground leaves off and sinks to a far
  depth with a slow swell in it, and a level surface over it carrying the
  depth under it, as a water look reads it. The ground function stays the
  game's; this asks it for heights.

- **Two pieces in one package.** Both dress the world around the part a
  game simulates, and each is a single class; two packages of one class each
  would cost a reader more than they save. They came from the sandbox demo's
  day and night and the Reef demo's open sea.
