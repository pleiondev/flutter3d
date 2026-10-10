# flutter3d_elements

Water, fire and bodies in a world of the physics core's, stepped with
nothing that draws them.

```dart
final elements = ElementsSimulation.open();
final pond = elements.addWater(
  ground: ElementHeightfield.flat(
    origin: Vector3(-4.0, 0.0, -4.0), cell: 0.25, nx: 32, nz: 32,
  ),
  properties: NativeLiquidProperties.water,
  heat: NativeLiquidHeat.water(),
  bed: const Bed(roughness: Bed.naturalStream),
)..fillBasin(from: Vector3.zero(), level: 0.4);
final crate = elements.track(elements.addBody(
  Solid.box(Vector3.all(0.3), material: NativeMaterial.wood(), density: 500),
  at: Vector3(0.0, 1.0, 0.0),
));
elements.fires.ignite(crate, by: Igniter.lighter);

// every fixed step:
elements.step(1 / 60);
```

An **`ElementsSimulation`** owns a `NativeWorld` of
`flutter3d_physics_native`, or adopts one a game steps itself, and steps
everything the world does not step on its own:

- the flames an `Igniter` holds to a body until it catches or the flame
  is taken away (`Fires`), each preset a flame somebody measured
  (`doc/igniters.md`);
- the waters poured over a ground (`WaterBody`): springs, outlets, a basin
  filled to its rim, a bed dug or built up;
- the game's objects followed into the world (`Follower`), which push
  water and crates and are never pushed back, so a replay is the game's
  alone;
- every element's step, fire's and water's first, then each one a plugin
  adds (`ElementHook`), over the world's fields (`ElementFields`) with
  `Portable` arithmetic, so a step gives the same bits on every platform.

What the world says (a body caught fire, went into the water, burnt out)
is told to an `ElementsListener` and published on the engine's bus as
`ElementEvent` and its kin, each with a codec, so a recorded run carries
them. `ElementsSimulationPlugin` steps the simulation in an `EngineLoop`'s
`fields` phase and puts its own state, the flames still held and each
plugin element's, in the loop's snapshots. `seenThroughSmoke` and
`heatFluxAt` are what a game's watcher asks of the fires, worked out from
the smoke plume (`SmokePlume`, `doc/smoke_plume.md`) and the core's
radiant heat.

**Nothing here draws.** There is no `flutter3d_core`, hardware layer,
shader or particle under it: a server replaying a run, a headless test and
a game's fixed step hold this package and nothing else. A `TrackedBody`
and a `WaterBody` name no scene node; `flutter3d_effects` draws and
sounds the simulation (`Elements`, `ElementsViewPlugin`) and keeps the
looks, views and materials on its own side (`Elements.lookOf`,
`Elements.viewOf`).

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
3D engine for Flutter.
