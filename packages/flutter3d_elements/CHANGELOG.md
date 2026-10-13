## 1.0.0-rc.1

- **`radiantFluxOn` stands a flame by `FireExposure.standingMiddleOf`**,
  the core package's one rule for a flame under a ceiling, which the
  platformer's runner now burns by too.
- **Breaking: each `ElementsListener` callback takes its event.** `caught`,
  `out`, `burntOut`, `wetted` and `burnerOut` take the `ElementCaught` (and
  so on) the bus carries, with its `body` and `made`; `exploded` an
  `ElementExploded`, `budget` an `ElementsOverBudget`, `seen` an
  `ElementFireSeen` and `lost` an `ElementFireLost`. One object per
  callback can gain a field in a minor, where a list of parameters cannot.
- **Breaking: `ElementsSimulationPlugin` and `ElementPlugin` are the
  engine's by name.** `ElementsSimulationPlugin` is `flutter3d_elements` by
  default and an
  `ElementPlugin` `flutter3d_elements.<hook id>`, where they were
  `elements` and `element.<hook id>`: `elements` is an area of the
  engine's events, which no plugin id may take. `ElementEventKinds` and
  `ElementSwitches` refuse a plugin's kind or switch outside its
  namespace.
- **An element's followed pose is `flutter3d_foundation`'s `RigidPose`**,
  where it was a record of its own.
- **The heat on a body, from the field.** `ElementFields.radiantFluxOn` and
  `FieldQuantity.radiantFlux` (W/m²): each fire's radiant heat, Modak's
  point source at the middle of its flame, on the point of the body a ray
  from there meets first, and nothing from a fire something else stands
  in front of. A flame longer than the room is high is measured from the
  middle of the column under the ceiling, not from above the roof. What a
  game's character is burnt by, read rather than worked out beside the
  world.
- **A burner fed what was spilt.** `Fires.setBurner(body, burner, fuel:)`
  feeds a burner that many kilograms and no more: it goes out by itself
  when they are burnt, told as `burnerOut`, and `Fires.fuelLeft` and the
  snapshot keep what is left.
- **A body weighed from the catalogue.** `Solid.of(shape, material)` makes
  a solid of a catalogue material, as heat sees it and as dense as the
  catalogue says, at its reference state or a `MatterState`; `wall:`
  makes it hollow, displacing all of its shape and weighing its shell.
  `Solid.at(kelvin)` puts a solid in the world at a temperature of its
  own — a bomb from its melt — which `addBody` sets.
- **A throw aimed by the core's own flight.** `Ballistics.aim(world, solid,
  from:, to:, elevation:)` finds the velocity whose flight through the
  world's gravity, air and wind, flown by the core at the game's step,
  comes down on the mark: no vacuum formula and no number to make up for
  the drag.
- **Brands a fire lofts.** `Firebrands` lofts a share of the fuel each
  fire burns as brands of a game's solid, deterministically, from the top
  of the flame up its plume at McCaffrey's centreline speed and with the
  wind, as hot as the flame; the core burns them and lets them light what
  they come down on. A budget (`most`) and what it held back (`skipped`),
  and a save.
- **`ElementFields` has a body for every member**: what a backend does not
  override is refused with an `UnsupportedCapabilityException` naming the member,
  so a member added in a minor breaks no backend.
- **Fields by quantity.** `ElementFields.quantityOf(body, FieldQuantity)`
  reads a field as a foundation `Quantity` in its unit, and `addQuantity`
  adds one in any unit of the same dimension (a `UnitMismatchException`
  otherwise). `FieldQuantity` is an open set — `temperature`,
  `surfaceTemperature`, `heat` and `water` to begin with — so humidity,
  pressure or a concentration arrive as a backend's own quantity, not as a
  new member.
- **`ElementExploded` mixes `PlacedEvent` in** (`with`), which foundation
  made a `base mixin class`.

- **The first release: the elements' simulation, out of
  `flutter3d_effects`.** `ElementsSimulation`, `Fires`, `Igniter`,
  `WaterBody`, `Follower`, `TrackedBody`, `Solid`, `Bed`,
  `ElementHeightfield`, `ElementPose`, `ElementsListener`,
  `ElementsSimulationPlugin`, the plugin element's hook (`ElementHook`,
  `ElementStep`, `ElementFrame`, `ElementFields`, `NativeElementFields`,
  `ElementBody`, `installElement`, `ElementPlugin`), the registries
  (`ElementSwitches`, `ElementEventKinds`), the switches (`ElementsSteps`,
  `FireSteps`, `LiquidSteps`) and the events (`ElementEvent` and the
  listener's eight, `declareElementEvents`) were declared there in 0.9 and
  are declared here now. `flutter3d_effects` does not re-export them:
  import this package. New in 1.0, so no 0.8 code names them.
- **A body and a water hold nothing that draws them.** `TrackedBody.look`
  and `WaterBody.view` and `WaterBody.look` are gone;
  `ElementsSimulation.track` takes no look. The view keeps them:
  `Elements.lookOf`, `Elements.viewOf` and `Elements.waterLookOf` in
  `flutter3d_effects`.
- **`ElementsSimulation.addWater` pours a water with no view**, and
  `waters`, `waterAt` and `remove` hold it, so a server steps the waters a
  game draws. `Elements.addWater` pours through it.
- **`SmokePlume`**: the plume's virtual origin, width, centreline speed and
  optical depth, which `seenThroughSmoke` reads and `FireView.plumeDepth`
  draws with. The numbers are the ones `FireView` had.
