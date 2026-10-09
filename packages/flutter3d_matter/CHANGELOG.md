## 1.0.0-rc.1

- **`physicalMaterialsSection` and `materialPairsSection` read a data
  plugin's substances**, registered in the engine's `DataSectionRegistry`,
  and install them into the `MaterialCatalog`; a document that has them
  requires `physicalMaterialsRequirement`, as before. The plugin runtime no
  longer depends on the physics to read them.
- **The first release: what a world is made of, in a package of its own.**
  `WorldProperties`, `WorldPropertiesFormatException`, `PhysicalMaterial`
  and its property groups, `MaterialPhase`, `MaterialPair`,
  `MaterialCatalog`, `Materials`, `UnknownMaterialException`,
  `MaterialFormatException`, the standard world (`standardGravity`,
  `standardAtmosphere`, `airDensityAt`, `speedOfSoundAt` and the rest) and
  the constants of nature came from `flutter3d_physics`, which does not
  re-export them: a file that names them imports this package. The audio, the particles and the native core's header generator
  read them and step no body, so they depend on this instead of the
  physics.
- **`WorldProperties` has no step rate.** `stepRate`, `stepSeconds` and the
  `stepRate` parameters are gone: nothing read them, and how often a world
  is stepped is the loop's (`WorldTiming`, `EngineLoop.stepSeconds` in
  `flutter3d_sim`). `standardStepRate` moved to `flutter3d_sim` with it. A
  document that still carries a `stepRate` key reads, the key passed over.
