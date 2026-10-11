## 1.0.0-rc.1

- **Every property of a material is a law.** The fields of
  `MechanicalProperties`, `FluidProperties`, `ThermalProperties`,
  `AcousticProperties`, `OpticalProperties` and `ElectricalProperties` are
  `PropertyLaw?` where they were `double?`: `value` is the number at the
  material's reference state, as before, and `at(MaterialState)` the
  number for a body in another state. A law is a `ConstantLaw`, a
  `TableLaw` (one interpolation formula, written down) or a `FormulaLaw`
  of the expression language, whose unit is checked as it is read;
  `FormulaLaw.andrade`, `.arrhenius` and `.polynomial` write the handbook
  forms. Code that read a number reads `.value`; a constructor that took a
  number takes `ConstantLaw(number)`. `PhysicalMaterial.density` stays a
  number, the reference state's. The laws are read in Dart; the native
  core does not evaluate them yet and takes every property's value at the
  reference state, whatever a body's temperature.
- **`MaterialState`**: what one body of a material is like now, an open
  map of namespaced quantity ids (`f3d.temperature`, `f3d.pressure`,
  `f3d.wetness`, a plugin's own) to `Quantity`, and a phase. Unknown
  quantities survive its document, so a component can persist a plugin's.
- **`Confidence`** (`measured`, `handbook`, `estimate`, open for more) on
  every value, on a material as a whole and on a `MaterialPair`, and an
  optional `PropertyInterval` for the spread a source gives.
- **`externalIds` and `MaterialCatalog.byExternal(space, id)`**: the ids
  other systems know a material by, in the spaces `ExternalIdSpace` names
  (CAS, IFC, MaterialX, UNS, ISO 1043, EN).
- **`InelasticProperties`**: a loss factor and `ConstitutiveModel`s of
  large strains (Ogden), relaxation (Prony) and plastic flow (Johnson and
  Cook), each with its source.
- **`OpticalProperties.dielectricF0`**, and `f0` from the refractive index
  where it is not given.
- **The catalogue is generated from verified data**: 238 entries, every
  value with its source and confidence, about 550 of them with a law in
  temperature; the 33 entries it had keep their numbers, and their data
  says each value's confidence rather than leaving it to be read out of
  the source's wording. Every solid has a coefficient of friction, an
  estimate marked as one where no source measured it: the median of its
  family's measured ones, never of other estimates, or the engine's
  default where its family has none. A law scaled onto the value quoted at
  the reference state says by how much in its source; molten basalt has a
  thermal group. A coverage table on this
  README says which values change with temperature. Reference values for
  simulation, not for design or safety calculations.
- **`MaterialCatalog.contact` says how its friction was come by.**
  `ContactProperties` is a class rather than a record, and carries a
  `confidence` and a `source` beside the three coefficients: the measured
  pair's, or the less trusted of the two materials' own with how they were
  combined, so a friction made of an estimate does not read as a
  measurement.
- **The defaults a material that says none takes are on
  `MaterialCatalog`**, each with its source: `defaultEmissivity`,
  `defaultConductivity`, `defaultYoungsModulus`, `defaultPoissonRatio` and
  `defaultSpecificHeat`, beside `defaultFriction`. The native core's
  presets start from them.
- **`checkMaterialCatalog`** holds a catalogue to its shape: each law at
  its reference state gives its value exactly, a formula measures its
  property's unit (`propertyUnits`), every value says its confidence.
- **The material document is version 2**: a property may be a law, and
  `inelastic`, `externalIds` and `confidence` are new keys; a version 1
  document reads as it did. A surface tension down to 1e-5 N/m and an
  expansion up to 0.1 1/K are plausible, for the cryogenic liquids.

- **`WorldPropertiesPatch`** names the fields of a world something sets and
  nothing it does not: a level's `world`, laid over the game's own world
  with `over`. Its document is the world's JSON with keys left out, kept as
  written, unknown keys included; a value a world would refuse is a
  `WorldPropertiesFormatException` naming the key.

- **`WorldProperties.gravityMagnitude` recognizes standard gravity.** It
  compared the float32 `y` of the gravity vector with the double -9.81,
  which never matched, and answered 9.8100004…; standard gravity now gives
  `standardGravity` exactly.

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
