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
  `LoopSettings.originShift` from it (1000 m unless set; `null` turns it
  off). Within
  that kilometre float32 places a point to about a tenth of a millimetre.
  The shift happens between steps, so a recording replays it only when
  the run makes the same move itself.
  **The precision a twin gets: ± 0.02 mm at 5 km from the site origin,
  physics in float32 relative to the shifted origin.** A crate dropped
  until it rests, beside a bob on a hinge in the C core or a crate sliding
  to a stop in the Dart one (which has no joints), stepped for ten seconds
  at 60 Hz 5 km out along each axis and along all three, stays within
  0.02 mm of the same scene stepped at the origin in both physics cores,
  the Dart one under both profiles (measured: 0.006 mm in the C core,
  0.0004 mm in the Dart one). `far_origin_test.dart` in
  `flutter3d_physics_native` and `far_origin_physics_test.dart` in
  `flutter3d_sim` hold that bound. It assumes the scene is placed relative
  to the shifted origin, through `toVector3Relative`. A body placed in
  float32 at 5 km before the origin moved keeps the rounding it was placed
  with, up to a quarter of a millimetre, and a hinge's swing drifts by it:
  within 4 mm after ten seconds. A scene a kilometre from the shifted
  origin, as when the camera watches it from that far, stays within 2 mm
  over five seconds.
  Without the shift the same scene at 5 km is out by up to 41 mm.

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
  `PassContributor.boundsFor`, `SceneEncodeRequest`'s
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
- **How many steps a frame brings is the loop's `TimeSource`'s answer**:
  real time, real time scaled by a factor, a log's timestamps, or a manual
  clock moved by hand. It changes how often the world steps, never `dt`.
- **State from outside enters as input, on a live step.**
  `InputState.feedExternal` puts an `ExternalStateInput` (a sensor's
  reading, a log's line, a headset's pose) on the next step's input and its
  tape. While the input is muted, which it is while a timeline replays,
  scrubs or bisects a tape, a reading fed is dropped, not held: one that
  landed then would be written into the past. A source whose readings
  arrive on their own clock queues them and drains the queue into
  `feedExternal` from `EngineLoop.onStepInput`, which runs at the start of
  every live step and never during a replay, so each reading reaches the
  first live step after it arrived.

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
- **A colour in a signature is a `LinearColor`, not a vector.** A level's
  fog and light colours, an effect's colours, a gradient's keys, a black
  body's colour, a sky preset's colours, a ring's outline and the blend
  constant all take or answer one. A colour shown to a person is an
  `SrgbColor` (`LinearColor.toSrgb`), with value equality and `toLinear`.
  A live particle still writes its `Vector4` in place, and the software
  backend's and the modeller core's colours are still vectors until they
  move.

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
sun-disc number times `LightNode.defaultIntensity` (about 5 790.6), and a pre-1.0
emissive strength times `RenderMaterial.defaultEmissiveStrength` (1 843.2), is the same light
now, so a picture does not change when a project moves. A level of format 5
writes its lights in candela, and its sun in lux; the lift from format 4
multiplies by that unit, and a light that never named its strength keeps
meaning the same one. `Light3D`'s defaults are photometric too: the
directional default and `Light3D.sun()` are 15 000 lux, and a point light
and `Light3D.lamp()` an 800-lumen bulb, about 63.7 cd.

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

### Reserved names

Two contracts of 1.0 have a name in rc.1 and no implementation; the
release that implements them adds them, and nothing written against rc.1
changes:

- **`f3d.rule`** is the id of the rule document: a condition over probe
  readings in the expression language, with a severity, a message and an
  acknowledgement. No other format may take the id.
- **Wasm plugin ABI 3** (`wasmRenderAbi`) is the ABI of render nodes: a
  module written for it exports `f3d_render_node`
  (`wasmRenderNodeExport`), which records encoder commands against the
  resources its `.f3dplugin` declares. A host reads ABI 1 to 2 until then
  and refuses a module that says 3 with the range named; a module of ABI 1
  or 2 that exports a function of that name is not read for it.

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

## The shader ABI

What a backend's shaders, and a plugin's stages, agree on with the engine
(D21, D22, D26, D27 and amendment 5 of the field review). A backend
written outside this repository reads it beside
`package:flutter3d_shaders/backend.dart`, which holds the same contract as
code.

### Entry points

A backend's bundle answers to every name in `requiredShaders`
(`package:flutter3d_shaders/flutter3d_shaders.dart`), generated from
`shaders/flutter3d.shaderbundle.json` and checked against it by a test:
19 vertex stages and 86 fragment stages at the time of writing. A backend
that computes answers to `computeShaders` too (`PrefixSum` and the three
`SplatSort*` stages, which it may leave out). The names are stable within a
major; a minor may add one, never rename or drop one.

- Vertex: `MeshVertex`, `MeshSkinnedVertex`, `MeshInstancedVertex`,
  `MeshLightmappedVertex`, `FullscreenVertex`, the three `Velocity*Vertex`,
  `PolylineVertex`, `ParticleVertex`, `ParticleMeshVertex`, `ImpostorVertex`,
  the three `Sky*Vertex`, `DebugLineVertex`, `CausticPhotonVertex`,
  `ShadowTileResetVertex` and `VertexTextureProbeVertex`.
- Fragment: the lighting models and their `*Opaque` variants (`Unlit`,
  `Lambert`, `BlinnPhong`, `Pbr`, `PbrLayered`, `Toon`), the engine's own
  surfaces (`Xray`, `PlanarReflection`, `Normals`, `Impostor`, `Splat`,
  `SplatHashed`, the six `Particle*`), the shadow stages (`ShadowDepth`,
  `ShadowDistance` and their `*Masked`, `ShadowTransmittance`, `ShadowCopy`,
  `EvsmFilter`, `ShadowTileReset`, `CausticSurface`, `CausticPhoton`), and
  the frame's full-screen stages (`Composite`, the bloom chain, `Decal`, the
  velocity, temporal, depth-of-field and motion-blur chains, `Reflections`,
  `Ssao`, `ContactShadow`, `VolumetricFog`, `LightShafts`, the anti-aliasing
  and upscale stages, `Luminance`, `DepthPyramid`, `ObjectId` and the rest);
  the manifest is the list.

`stageBindings` says which uniform blocks and samplers each compiled stage
keeps, and a draw binds by it; `uniformBlocks` gives every block's members,
offsets and sizes as std140 laid them out. Both are generated after every
shader change and both only grow in a minor.

**Checked, not only promised.** `packages/flutter3d_shaders/api/flutter3d_shaders.abi`
holds the whole ABI one fact a line: each entry point and its kind, each
stage's blocks and samplers, each member with its offset, byte length,
element count and type, and each engine vertex stage's inputs in order.
The package's test keeps it current (`dart run tool/abi_snapshot.dart`
writes it), and the structure rule *the shader ABI only grows* fails on any
line of the base recorded at 1.0.0-rc.1 (`tool/api/abi_base/`) that is
gone: a dropped stage, a removed or reordered member, a moved offset, a
renumbered vertex input. Adding lines is a minor; a base is recorded again
only at a major.

### The defines

The engine's GLSL is compiled with these, each set by the stage that
includes the shared headers, never by the backend:

| Define | What it does |
|---|---|
| `F3D_OPAQUE` | the opaque variant of a lighting model: no reachable `discard` |
| `F3D_LAYERED` | `pbr.glsl` with the glTF layers (`PbrLayered`) |
| `F3D_MEDIUMP` | colour arithmetic in `mediump` where a stage allows it |
| `F3D_LTC` | the area-light lookup of `ltc.glsl` |
| `F3D_TEXTURE_TRANSFORM` | a map's transform read at the sampler |
| `F3D_SOFT_PARTICLE` | a particle stage that fades into the scene's depth |
| `F3D_NO_LIGHT_LIST` | a stage that gathers no lights declares no light list |
| `F3D_NO_POINT_SHADOW` | a stage that samples no cube shadow declares none |
| `F3D_NO_METALLIC_ROUGHNESS_MAP` | a stage that reads no metal-rough map declares none |
| `F3D_NO_SURFACE_BUFFER` | a stage drawn into one attachment writes no surface buffer |
| `F3D_NO_FOG` | a stage that applies no fog declares no `FogInfo` |

A material written in the material language sets none of them: its stage
is emitted for the engine's headers as they are.

### A material's own blocks and textures

A plugin's lit model may bind more than the engine's five textures and its
blocks (D21). Its source declares them, `uniform(Hair) vec3 tint = …;` for
a member of a block of its own and `texture fur;` for a texture of its own,
and its `MaterialSlotTable` lists them in a fixed order: `MaterialParams`
first when the material has a uniform of its own, then its blocks in the
order they are first named, then its textures in declaration order. The
emitted GLSL declares each block as `uniform <Name> { … } f3d_block_<Name>;`
(`MaterialParams` as `material_params`) and each texture as `uniform
sampler2D material_<name>;`. A backend binds them:

- **by name** where its bindings are named: Impeller, WebGL2, the software
  backend;
- **by number** on WebGPU: the material's own blocks and textures take the
  bindings after the engine's in the material's group, in the table's order.
  WebGPU numbers them when the build packs the stage; at run time a material
  with blocks or textures of its own is refused and built from
  `assets_src/` instead.

The renderer binds each block from `RenderMaterial.parameters`, the members
that belong to it, and each texture from `RenderMaterial.extraTextures`
under its binding name. **Every slot is bound on every draw**: a member the
material leaves unset is bound at the default its source declares
(`MaterialBlockMember.defaultValue`) — in the fragment stage, the material's
own vertex stage and its instanced and lightmapped variants alike — and a
texture it names none for at a white texel, so a material written before a
model grew a member draws the same on every backend. The render check
`render.lit model defaults` holds each backend to it.

**The budget.** One stage binds at most 16 textures, 16 samplers and 12
uniform blocks, the engine's bindings and the material's own together
(`MaterialStageBudget`): WebGPU's guaranteed minimums, where a texture is a
texture and a sampler, and the tightest of the four backends. A lit model's
stage carries the engine's lighting bindings (the shadow maps, the
irradiance, the light list, the material maps it reads), so its own
textures and blocks get what those leave. The WebGPU section writer every
build and `RuntimeShaders` call refuses a stage over the budget, naming the
stage and the count, so the material fails on its author's machine and not
at its first draw on a device. A WebGPU device is opened with the adapter's
own stage limits, which may be higher; a bundle counts only on the
minimums.

### How the material language grows

A new input, builtin or reserved name arrives with a new `f3dmat <N>`, and
a source of an older `N` keeps every name it had: each input carries the
version it arrived in (`MaterialInput.since`) and each builtin too
(`materialBuiltinVersions`), and a name is taken from a declaration or a
`let` only where the source's version has it. The block names a material
cannot use are frozen at 1.0.0 (`materialReservedBlockNames`) together with
a shape the engine keeps for later blocks, `F3d…` and `…Info`, which a
material's own block was never allowed; a block the engine adds in a minor
is named in that shape, so `uniform(Hair)` stays a material's to use.

### Light codes

The light row the lit stages read (four `vec4`s a light: position and type
code, colour and intensity, direction and range, cone or half-height) codes
its type in the first `vec4`'s `w`: directional 0, point 1, spot 2, area 3;
the engine's later types take codes below 16. A light type of a plugin's own
(`LightTypeHook`, registered with `LightTypes`) takes a code from 16 up,
handed out once per renderer in registration order, and its hook fills the
row. **The engine's lit stages skip a light whose code is 16 or more**; a
lighting model of the plugin's own reads the code and the row in its
`light` block (the inputs `lightKind` and `lightParams`, the row's last
`vec4`) and computes its own falloff. The skip and the two inputs are part
of the next shader change of the backends, which is where the engine's
stages are compiled.

### Vertex layouts

A material's own vertex stage reads the standard vertex
(`VertexLayout.standard`). Its skinned half, `<name>Skinned`, reads joints
and weights beside it; its instanced half, `<name>Instanced`, the
instance's rows, colour and four numbers in a second buffer stepped per
instance (`MeshVertexLayouts.instanced`); its lightmapped half,
`<name>Lightmapped`, the level's baked coordinate. A material lists the
halves it ships (`LightingModel.vertexVariants`); the others are drawn
through the engine's.

### Decal stages

A decal of a plugin's own (`DecalNode.lighting`) is painted through a
full-screen stage with `Decal`'s interface: the `DecalInfo` block (sixteen
decals a draw), `decal_texture_0` to `decal_texture_3`, `surface_texture`
and `albedo_texture`, and two terms by `DecalInfo.params.w`: nought for the
factor multiplied in, one for the light added. `DecalSettings.decalsPerDraw`
and `picturesPerDraw` cut the draws within those limits.

### Skinning hooks

A `SkinningHook` (D22b) skins the meshes it claims into a buffer the
scene draws. It is placed with `RendererSteps.placeSkinningHook` as a
`ComputeStep` is: at its `demand`, or on the device drawing the frame and
then the CPU, and never on the sidecar, whose vertices would reach the
drawing device only through the host. A demand nothing meets is refused
with a `ComputePlacementException` (`skinningRefusal`), and the hook runs
on the CPU instead.

- **What it writes.** For each claimed mesh, `SkinningContext.output`: the
  mesh's vertex count in `VertexLayout.standard` (position, normal,
  texture coordinate, tangent, colour; the skinned layout without joints
  and weights). The step writes `FrameResourceIds.skinnedVertices` before
  the shadows, and the scene reads it, drawing each claimed mesh from its
  buffer through the unskinned vertex stage.
- **Where it lives.** Placed on the drawing device, the hook's kernels
  write the drawing device's buffer and the vertices never leave the GPU.
  Placed on the CPU, they write a buffer of the CPU executor, which is
  copied into the drawing device's buffer from host memory: an upload,
  never a readback of the drawing device.
- **The host shape.** A `HostSkinningHook` answers `skin` with the
  vertices in the mesh's own layout, as `SkinBlend.vertices` holds them,
  and its `record` uploads their standard part. `LinearBlendSkinning` is
  the engine's own CPU skinning in that shape.
- **What it does not change.** The shadow passes, the pick pass and
  instanced draws skin with the engine's stage; a device that makes no
  buffers draws every mesh as the engine skins it.

### A backend's material compiler

A backend compiles the material language into its section of a material's
`ShaderBundle` with a `MaterialCompiler` (D26): it names its backend and its
section, says whether it compiles while a game runs, and takes one
`MaterialCompileRequest` (the source, the stages the engine's emitter
wrote as GLSL, the engine's headers, and backend options by name) to a
`MaterialCompileResult`, or refuses with a `MaterialCompileException` saying
why. A `MaterialCompilerRegistry` finds it by backend id, exactly: the
compiler's `backend` is its device's `GraphicsDevice.backendId` (`cpu`,
`webgl`, `webgpu`, `impeller` for the engine's four; a backend from outside
gives its own, its name in lower case by default), and
`RuntimeBackends.normalize` maps only the engine's own names to theirs.
`RuntimeShaders` asks the compiler of the backend the game runs on, before
the engine's own three run-time paths. The project's shader build
(`runShaderBuild`, handed the registry) asks every compiler it holds for a
backend from outside the engine for its section of the engine's bundle,
handed the engine's stages as GLSL with the engine's headers and an empty
source, and of every plugin material's bundle; a project whose only GPU
backend is from outside gets its bundle with that section alone. The
engine's three GPU sections are written by the build's own tools. Two
backends never write one section.

`compileStage` (`package:flutter3d_shaders/compile.dart`, with glslang and
naga on the machine) hands a backend a stage's SPIR-V and its text in a
`ShaderTarget`: WGSL, MSL, HLSL or GLSL, or the SPIR-V alone.

### Stages agree before a device sees them

The bundle writer reads every pipeline's stages as `StageInterface`s
(`StageInterface.fromGlsl`, after includes are resolved, or a backend's
reflection) and holds them to each other with `checkStageAgreement`
(amendment 5): every varying the fragment stage reads is written by the
vertex stage with the same type, and the same location where both state
one; every attribute the vertex stage reads is in the vertex layout the
pipeline is drawn with, with the same type; and a uniform block both stages
declare has the same members in the same order. Each mismatch is a
`StageMismatch` naming both stages and what each declares, and the writer
refuses the bundle with them: a build error with names, not a crash on one
backend at the first draw.

## Names

The units above are half of what a name promises; the other half is how it
is spelled and what its verb means. Item 28 of
`tasks/1.0-scope-additions.md` settled these for 1.0, and seven structure
rules hold them over every published API snapshot (`tool/structure/naming.dart`).
`dart fix` carries each rename made for them, from the migration table.

- **American spelling in identifiers**, as Flutter and Dart spell theirs:
  `color`, `center`, `meter`, `behavior`, `gray`, `normalize`, `isCanceled`.
  The docs may stay British. A word written into a file keeps its spelling
  until the format's version moves it — a tool's `boundsCentre` — because a
  file is read by the reader's wire table, never by a Dart name. Level
  format 5 moved its keys (`behaviors`, `behavior`, `texelsPerMeter`), and
  its lift reads the British ones of format 4.
- **One teardown verb per type.** `dispose()` ends an object's life, and
  `close()` is for a connection or a stream. A handle a graphics device
  made has one owner, who disposes it once: a second `dispose` asserts in a
  debug build, a disposed handle used again is named by `debugCheckLive` in
  a debug build, and the device's own `dispose` ends every handle it made
  (the whole contract is on `GraphicsDevice`). A `stop()` beside `dispose()`
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
