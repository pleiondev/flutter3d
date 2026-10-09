## 1.0.0-rc.1

- **Wrecks that burn and sink, on the elements.** `BurningWrecks` places
  what a hit leaves in a game's `Elements` and holds a blast's fireball to
  it: `oil` is a slick of crude afloat and alight, drawn black and glossy,
  carried off by the current while the hull goes down under it; `timbers`
  is a heap of wood burning where it fell. The physics core's heat burns
  them as long as their fuel lasts, and the elements draw the flames and
  the smoke.

- **Let go behind the player.** `step` is told how far the player has come
  along the way the game travels, `along`, and lets go of every wreck more
  than `behind` metres back. `clear` puts every fire out for a new run.

- **From the River demo**, whose tankers and depots leave these behind.

- **`BurningWrecks` takes `elements` and `device`** as plain positional
  parameters rather than `this._elements` and `this._device`, which put a
  private name in the API. Callers pass them as before.

