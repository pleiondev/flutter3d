# The units contract

Every number the engine takes or gives has a unit, and in 1.0 it is the same
unit everywhere. This page is that promise. A public member whose unit is
not the one below says so in its name (`fovYDegrees` would, `fovY` does not
need to) and in its doc comment, and a format that stores numbers refers to
this page rather than restating it.

It was item 29 of `tasks/1.0-scope-additions.md`, and §D.4 and §E.4 of
`tasks/1.0-api-review.md` apply it; `migrate` carries user code along. Where
the 1.0 API still falls short of a rule below, the rule says so rather than
pretending otherwise.

## Space

- **Lengths are metres.** A unit cube is one metre on a side, gravity is
  9.81 m/s², and a character is about 1.8 tall.
- **Y is up.** Gravity points down negative Y.
- **The frame is right-handed.** With X to the right and Y up, positive Z
  points towards the viewer, and a camera with no rotation looks down
  negative Z. glTF uses the same frame, so an imported model needs no
  conversion.
- **Angles are radians.** A field of view is `fovY`, the vertical angle, in
  radians. A rotation is a quaternion or radians about an axis; there are no
  degrees in a signature. A widget that shows an angle to a person converts
  at the widget.
- **World positions are `WorldPosition`.** Three doubles, from
  `flutter3d_foundation`, because a position is the one quantity that grows
  with the level and float32 runs out of millimetres about ten kilometres
  from the origin. Local positions, directions, velocities, mesh vertices
  and anything in a GPU buffer stay `vector_math`'s float32 `Vector3`. The
  crossing is always relative to an origin someone names (the camera, a
  chunk): `WorldPosition.relativeTo` subtracts in doubles, and
  `toVector3Relative` beside it narrows the small difference.
  **Not every signature carries it yet.** A scene node's position and many
  physics and gameplay calls still take a float32 `Vector3`, read in the
  frame of the current floating origin; those count as the local positions
  above, and they stay exact only as far as the origin follows the camera.
  **It does by default:** `Flutter3dView` moves the loop's origin to the
  camera, rounded to whole metres, whenever the camera is more than
  `originShift` from it (1000 m unless set; `null` turns it off). Within
  that kilometre float32 keeps about a tenth of a millimetre. The shift
  happens between steps, so a recording replays it only when the run
  makes the same move itself.

### Three spaces

A position is in one of three spaces, and a signature that takes or gives
one says which, in its parameter's name or its doc.

- **World space** is the level's own frame, in `WorldPosition`'s doubles. It
  does not move when the camera does, and it is what a save, a level file, a
  network message and a gameplay rule hold a place in.
- **Scene space** is float32, relative to `Scene.origin`: the space every
  node's `worldMatrix` is in, the camera's view is built in, and the GPU
  draws in. `Scene.toScene(position)` takes a world position there,
  subtracting in doubles first, and `Scene.toWorld` brings a point back;
  `Scene.shiftOrigin` moves the origin and everything in scene space with
  it. The renderer's extension API is in scene space throughout:
  `PassContributor.boundsFor`, `RenderServices.encodeScene`'s
  `cameraPosition` and `viewProjection`, `ContributorFrame.viewProjection`
  (whose `origin` names the scene's), `ContributorLights.bind`, `DebugDraw`'s
  lines, `MeshOverlay`, and the particles' bursts and emissions
  (`ParticleSystem.burst`, `ParticleEffects.burst`, `PlacedEvent.at`).
- **Local space** is a node's own frame, relative to its parent's
  transform: a node's position, a mesh's vertices, an `InstancedMeshNode`'s
  instance transforms. A node at the root with no transform of its own has
  local space equal to scene space.

**Where a person places something in the world, there is a world entry
point** beside the scene-space one, and it converts through
`Scene.toScene`, never by narrowing the doubles first:
`DebugDraw.addWorldLine` (measured from `DebugDraw.origin`, which the
renderer sets to the drawn scene's origin each frame),
`ParticleSystem.burstInWorld`, `emitInWorld` and `emitTimedInWorld`, and
`ParticleEffects.burstInWorld` and `emitInWorld`. The renderer's own
internals (its passes, its buffers, the frame graph) stay in scene space
and do not take a `WorldPosition`.

## Time

- **Seconds, as a `double`, in the simulation.** A step's `dt`, a cooldown,
  an animation's length and a replay's timestamps are seconds.
- **`Duration` only where a clock the platform owns comes in**: a widget
  parameter, an animation controller, a vsync timestamp, a frame-time budget
  the renderer measures against the wall clock. The engine converts once,
  where the value comes in, and nothing a step runs reads one.
- **A step is counted, not timed.** Code that has to be repeatable reads the
  step number and the fixed `dt`, never a clock.

## Mass and force

SI throughout: kilograms, newtons, newton-seconds for an impulse, pascals
for pressure, kilograms per cubic metre for density. A world's gravity, air
and sea are read from the world, not written as literals (the structure rule
`a world's gravity, air and sea are read from the world` holds that).

**Friction is one coefficient.** A body has a single μ, not a static and a
kinetic one: the solver limits a sliding contact's tangential impulse to μ
times its normal impulse, and a body at rest is held by the same μ. Two
bodies meeting take the geometric mean of their two μ and the larger of
their two restitutions, in the reference `Dynamics` and in the C core alike,
unless the material catalogue holds a measured pair for their materials
(`MaterialCatalog.contact`). A material's static and kinetic coefficients
are both kept in its entry, and the kinetic one is the μ (`MechanicalProperties.friction`).

### World properties

What a world is made of is one value, `WorldProperties` in
`flutter3d_matter`, held by the world (`CollisionWorld.properties`) and
read there by everything in it. The engine's defaults are written once, in
`standard_world.dart`; **a game sets its own world where it stages it** (the
platformer's gravity is 24 m/s², the racing game's 20), and a level's
`world` block overrides any of it on top, field by field.

| Property | Unit | Default | Who reads it | How a level overrides it |
| --- | --- | --- | --- | --- |
| `gravity` | m/s², a vector | 9.81 down y (`standardGravity`) | rigid dynamics (both backends), characters (`MovementSettings.gravity` when null), navigation's jump arcs, particles (`ParticleGravity()`), cloth, liquids, debris, ragdolls, a car's tyre grip (μ·g), a swimmer's buoyancy, weirs and depths | `"world": {"gravity": [x, y, z]}`; a single number is m/s² down y, as the scalar `"gravity"` of level format 3 was |
| `airTemperature` | K | 293.15 (`standardAirTemperature`) | the air's density, the speed of sound, heat (what a pool fills at, what cools a body) | `"airTemperature": 253.15` |
| `airPressure` | Pa | 101 325 (`standardAtmosphere`) | the air's density, a depth gauge, a lung | `"airPressure": 70000` |
| `airDensity` | kg/m³ | derived: ρ = p M / R T, 1.204 at the defaults (`airDensityAt`) | drag and lift on bodies, cloth, embers, a car's air drag | `"airDensity": 0.02`, only to override the derivation |
| `wind` | m/s, a vector | none | bodies' drag, cloth, particles, smoke and fire | `"wind": [3, 0, 0]` |
| `medium` | a material's id | `f3d.air` | what a body moving through the world is dragged and lifted by (`mediumDensity`) | `"medium": "f3d.seawater"`; a medium no installed plugin declares refuses the level, naming the plugin |
| speed of sound | m/s | derived: 343 at 293.15 K, as √T (`speedOfSoundAt`) | a listener's Doppler shift | through `airTemperature` |

A world's properties are part of the simulation: the dynamics' saved state
carries them, so a rewind puts back the world a snapshot was taken under,
and a change mid-run replays the same.

**How often a world is stepped is not one of its properties.** The step
rate is the loop's: `WorldTiming` (60 steps a second, `standardStepRate`,
unless a game says otherwise) in `flutter3d_sim`, journalled like any
change to the simulation. A world carried a `stepRate` until 1.0.0-rc.1
that nothing read; a document that still has the key reads, the key passed
over.

### Physical materials

A substance's properties are one entry, `PhysicalMaterial`, in the engine's
`MaterialCatalog` (`flutter3d_matter`), by an id namespaced as a format's
is: `f3d.<name>` for the engine's own (`Materials`), `<pluginId>.<name>` for
a plugin's, added through `host.registry<MaterialCatalog>()` or a data
plugin's `physicalMaterials` list (and `materialPairs`; its `materials`
is the material language's shaders). Everything that needs a substance — a liquid's
preset, the core's heat presets, a world's medium, a collider's material —
is a view of an entry, and the C core reads the built-ins from a header
generated from the catalogue. Numbers are quoted at 20 °C and one standard
atmosphere unless an entry's `temperature` and `pressure` say otherwise, and
each group names its `source`.

| Group | Property | Unit |
| --- | --- | --- |
| `mechanical` | `density` (bulk, for a granular material) | kg/m³ |
| | `youngsModulus`, `yieldStrength`, `tensileStrength`, `hardness` | Pa |
| | `poissonRatio` | none |
| | `staticFriction`, `kineticFriction` (against itself; the kinetic is the μ), `restitution`, `rollingResistance` | none |
| `fluid` | `viscosity` (dynamic) | Pa·s |
| | `surfaceTension` | N/m |
| | `bulkModulus` | Pa |
| `thermal` | `specificHeat` | J/(kg·K) |
| | `conductivity` | W/(m·K) |
| | `volumetricExpansion` | 1/K |
| | `meltingPoint`, `boilingPoint`, `ignitionTemperature`, `autoignitionTemperature` | K |
| | `latentHeatOfFusion`, `latentHeatOfVaporization`, `heatOfCombustion` | J/kg |
| | `emissivity`, `radiantFraction` | none, 0–1 |
| `acoustic` | `absorption`, per octave band 125–4000 Hz | none, 0–1 |
| | `speedOfSound` | m/s |
| | `impedance` | Pa·s/m (rayl) |
| `optical` | `refractiveIndex` (n_D), `abbeNumber` | none |
| | `absorption`, linear red, green, blue | 1/m |
| | `metalReflectance` (F0), linear red, green, blue; `roughnessMin`, `roughnessMax` | none, 0–1 |
| `electrical` | `resistivity` | Ω·m |

A pair of materials may be measured as a pair (`MaterialPair`: friction,
restitution, rolling resistance, and a liquid's contact angle on a solid in
radians), which wins over the rule above. A material is written to a file in
the envelope as `f3d.physicalMaterial`, version 1, its unknown keys kept, so
a level or a `.f3d` section can hold one; a data plugin's `physicalMaterials`
list holds the same body without the envelope.

## Colour

- **Linear unless the name says sRGB.** The engine's colour type is
  `LinearColor` from `flutter3d_foundation`: red, green, blue and alpha in
  linear light, unclamped above 1 for emissive and HDR values, with straight
  (not premultiplied) alpha.
- **sRGB is an encoding, applied at the edges.** A colour a person picked,
  a hex code or a texture marked sRGB is decoded with the exact sRGB transfer
  function (`LinearColor.fromSrgb`); the frame is encoded once, at the end.
  A parameter that takes sRGB values says `srgb` in its name.
- **Flutter's `Color` appears only in widgets.** `flutter3d` converts it with
  `color.toLinear()` and back with `linearColor.toColor()`.

## Light

Photometric units, so a scene lit from a datasheet or a physically based
renderer looks the same here.

- **A directional light is in lux** (lumens per square metre at the surface
  it falls on): about 100 000 for direct sun, 1 000 to 10 000 for an overcast
  day.
- **A point, spot or area light is in candela** (lumens per steradian): about
  100 for a 1 200 lm bulb. An area light's is its intensity along its normal.
- **Lumens are allowed as a constructor**, converted to candela once: a point
  light's candela is its lumens over 4π, a spot light's over the solid angle
  of its cone, and an area light's over π, because a flat Lambertian emitter
  of normal intensity I sends πI lumens into its hemisphere.
- **A literal below 50 passed to a light's `intensity` is flagged** (the
  structure rule `a light's intensity is lux or candela, not the pre-1.0
  unit`): it is almost always a pre-1.0 number. A light meant to be that dim
  says its unit in a comment on the line.
- **Ambient light is in lux**, the illuminance it puts on a surface from every
  side: `Scene.ambientIntensity`, `Atmosphere.ambientIntensity`.
- **A sky's sun disc is in lux** (`SkySettings.sunIntensity`), as
  `Atmosphere.sunIntensity` and a directional light are: the disc shows the
  luminance a white surface in that light would, `E/π` nits.
- **A physical sky's sunlight is in lux** (`PhysicalSky.sunIlluminance`), and
  the sky it draws is luminance: lux times a scattering coefficient per metre
  times a phase function per steradian is nits. (Before 1.0-rc.1 it was
  drawn π too dark; `PhysicalSky.illuminanceLux`, its meter, read the same
  before and after.) The disc is the sun's angular radius, 0.2666°, the one
  the soft shadows use (`ShadowSettings.sunAngularRadius`).
- **Emissive is in nits** (cd/m²): `RenderMaterial.emissiveStrength` is the
  luminance an emissive of white shines at, and a colour at its share. A file's
  strength (glTF's `KHR_materials_emissive_strength`, a `.fmat`, a level) is a
  plain multiple and is converted where the material is made.
- **A reflection probe's `intensity` is a ratio**, the light it measured times
  it, and so has no unit.
- **Exposure is in EV100**, which turns those absolute values into an image.
  The renderer's own scale, in which shaders work, is hidden.

Before 1.0, light intensity was in an engine unit where 1.0 was
1843.2 cd/m² of luminance and π times that in lux. (The reference camera
draws 1843.2 cd/m² at 1.6, past white; its white is 1152 cd/m².) A pre-1.0 light, ambient or
sun-disc number times `Photometric.legacyUnit` (about 5 790.6), and a pre-1.0
emissive strength times `Photometric.legacyNits` (1 843.2), is the same light
now, so a picture does not change when a project moves.

## Files

A format that stores numbers stores them in these units and says so: an
imported asset carries a `units` header, and the format envelope (§D.1 of
the review) names the version of this contract it was written against. A
reader that meets another unit converts at the reader, never in the engine.

### The envelope

Every JSON document the engine writes as a file of its own, one a person, a
tool or a later build may open, starts with the same four keys:

```json
{"format": "f3d.level", "version": 3, "requires": [], "generator": "flutter3d"}
```

That covers the levels, saves, runs and tapes, materials, effects, plugins,
settings and action maps, the save-slot index, the cloud-save state and the
telemetry answer, a voxel world, a best run, `convert --report` and
`--json`, and the build's own caches. Three kinds of JSON are not files of
their own and do not carry it:

- **A document inside another**, which the outer one versions: a save's
  `run`, a level's entities, a project's manifest inside `.f3dproj`. A
  nested document that can also stand alone (a voxel world, an input tape)
  carries the envelope in both places.
- **Wire messages**: MCP tool answers, VM service extension answers and
  network messages are versioned by their server's schema version and
  snapshotted (below), not by an envelope.
- **A binary or non-JSON file**, whose envelope is its own magic and version
  word: `.f3d`, `.f3dproj`, `.f3dsplat`, `.f3dtrace`, the F3SB shader bundle,
  a lightmap, and the material language's optional `f3dmat <N>` line.
  `FormatSpec.enveloped` is false for these.

A build's cache (`f3d.assetCache`, `f3d.materialCache`) carries the envelope
too, but a cache from any other layout reads as empty and is rebuilt: for a
cache that is the safe answer, and the one place a version is matched
exactly.

`format` is what the document is (`f3d.<kind>` for the engine's formats,
`<pluginId>.<kind>` for a plugin's). `version` is that format's own number,
not the engine's. `requires` names what a reader has to understand to open
the document at all, a plugin's component namespace for example, so an older
reader refuses instead of dropping it. `generator` is who wrote it. YAML
configuration says the same with `format: 1`.

The rules a reader keeps:

- **A 1.x engine reads every 1.x file.** Older versions are lifted through a
  chain of migrations, one step per version, and each version has a fixture
  the structure check counts.
- **A newer file is refused with a sentence** naming both versions. It is
  never read halfway, and a reader never answers null for it.
- **Unknown keys are kept.** A document opened and saved by an earlier minor
  keeps what a later one added.
- **The shapes from before the envelope read as version 1:** `{"version": N}`,
  a format's own key (`{"f3dfx": 1}`, `{"f3dplugin": 1}`), an id the format
  lists as an alias, or no version at all.
- **Words written to a file come from explicit wire tables**, never from a
  Dart identifier's `.name`, so renaming a type in a major does not change a
  file.

`FormatSpec` (`flutter3d_foundation`) and `FormatRegistry`
(`flutter3d_plugin_api`) are the code side of this: each format declares
its id, suffixes, version, migrations and fixtures once, and a plugin's
formats go through the same registry. Ids are
`f3d.<kind>` in lowerCamelCase (`f3d.inputTape`, `f3d.frameCapture`,
`f3d.materialLanguage`); an id a file was written under before keeps
reading through `FormatSpec.aliases`. `Flutter3dView` builds the registry
from `coreFormats` and `simFormats` and the formats it is handed
(`gameFormats` from `flutter3d_game`), and a plugin asks the loop for it.

### Tools and the command line

MCP tools and VM service extensions are snapshotted (`api/*.mcp`,
`api/*.vm`) with their input and output schemas. A rename keeps the old name
as an alias until the next major, and each server announces its schema
version. The `flutter3d` command's subcommands, flags and exit codes (0 ok,
1 failed, 2 usage, 3 refused or out of date, 4 would overwrite) are
snapshotted in `packages/flutter3d_build/api/flutter3d_build.cli`, and its
`--json` output starts with the envelope, `"format": "f3d.cli"` and a
`version` of its own, with each subcommand's keys snapshotted beside the
help text.

## Names

The units above are half of what a name promises; the other half is how it
is spelled and what its verb means. Item 28 of
`tasks/1.0-scope-additions.md` settled these for 1.0, and seven structure
rules hold them over every published API snapshot (`tool/structure/naming.dart`).
`dart fix` carries each rename made for them, from the migration table.

- **American spelling in identifiers**, as Flutter and Dart spell theirs:
  `color`, `center`, `meter`, `behavior`, `gray`, `normalize`, `isCanceled`.
  The docs may stay British. A word written into a file keeps its spelling —
  a level's `centre`, a material's `texelsPerMetre`, a tool's `boundsCentre` —
  because a file is read by the reader's wire table, never by a Dart name.
- **One teardown verb per type.** `dispose()` ends an object's life, and
  `close()` is for a connection or a stream. A `stop()` beside `dispose()`
  is a state transition (`start()` may follow it) and its doc says so, as
  `PointerLock.release()` is the other half of `capture()`.
- **Creation verbs.** `create` is synchronous (the GPU's `create…Async` is the
  asynchronous variant of a synchronous one); a device or a session is
  opened (`open`, asynchronous); an asset is loaded, bytes are decoded, text
  is parsed. A read that empties what it reads is `drain`. `make`, `take`
  and `get` are not verbs here, except the ECS's own `get`/`set`.
- **Units are not in names** unless the unit is not the contract's: no
  `Degrees`, `Deg`, `Millis` or `Ms`. A field of view is `fovY`, in radians.
  A file that stores degrees or milliseconds keeps them, and its reader and
  writer convert.
- **A boolean reads as a question**: a getter starts with `is`, `has`,
  `can`, `uses`, `supports`, `did` or `was`, or is a third-person verb
  (`castsShadow`). A settings field stays bare (`enabled`). No `bool`
  parameter is positional: `setDepthWrite(enabled: false)` says what `false`
  means.
- **Constants are lowerCamelCase**, as Effective Dart asks: `f3dVersion`,
  not `kF3dVersion`.
- **Settings.** A settings type is `…Settings` (a HAL type is
  `…Descriptor`; a declaration made to a registry, such as `FormatSpec` or
  `ToolSpec`, is `…Spec`). It is `final`, its constructor is `const`, and
  its `copyWith` takes every field the constructor sets. **A nullable field
  is reset with a `clear…` flag**: `settings.copyWith(clearLabel: true)`,
  because `copyWith(label: null)` cannot tell "keep it" from "remove it".
  The flag beats a sentinel `Object?` parameter because the field keeps its
  type, and it beats a `T? Function()` wrapper because setting a field stays
  `copyWith(label: 'x')`.
- **Every public number says its unit in its doc**, or that it has none (a
  fraction, a ratio, a count). The rule counts the numbers that do not yet,
  per package, and the count only comes down.
