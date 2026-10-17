## 1.0.0-rc.1

- **Breaking: `LoopRegistry.addSystem` takes `reads:` and `writes:`.** A
  system names the state it touches, a component, a field or a genre's
  run, so the engine's loop can name two systems of one step phase that
  touch the same state with nothing ordering them: a replay is bit for
  bit only while they run in one order. Both default to empty, so every
  call compiles as it did; a class that extends `LoopRegistry` adds the
  two parameters to its `addSystem`.
- **New: `RenderProgram`.** What drives a render step frame by frame, the
  shape a Wasm render module is run in: it sets the step's parameters by
  index through a `RenderProgramFrame`, draws, and asks a light type's
  code; a data section reaches the one for its step with
  `DataSectionContext.renderProgram`.
- **Breaking: a render program sets a parameter with one object.**
  `RenderProgramFrame.setParameter` takes a `RenderParameterWrite` (new):
  the parameter, the first component and the values, made with
  `RenderParameterWrite.component(parameter, component, value)` for one
  component or `RenderParameterWrite(parameter, values)` for several.
  `setParameterFloats` is gone into it. A write can gain members in a
  minor; three scalars could not.
- **New: `EditorCommandValue`.** A command as its name and arguments, in
  `editor.dart`: what the editor's own commands and a plugin's are, and
  what a panel hands the editor typed.
- **New: `PluginPermission.replace`.** What a plugin from outside the
  engine declares to take over a step or a stage the engine draws — the
  renderer refuses a takeover without it — and the `tools` permission is
  now checked before the editor's MCP server offers a plugin's commands
  as tools, as well as by `McpTools.addTool`.
- **One plugin that throws no longer stops the others.**
  `PluginManager.installAll` checks the whole set first, as before, then
  installs each plugin in turn: one whose `install` throws is left off with
  what it registered withdrawn, `PluginStatus.reason` saying what it threw
  and `PluginStatus.error` holding it, and so is every plugin that depends
  on it, with a reason naming it. The rest install. A plugin switched on
  at a step boundary is held to the same.
- **New: `Flutter3dPlugin.ready`, the asynchronous half of installing.**
  A plugin loads what it needs after `install` — a shader library, a
  table — in `Future<void> ready(PluginHost host)`, called after each
  install and awaited by nobody on the frame's or the step's path;
  `PluginManager.whenReady` completes when every installed plugin's has.
  One that throws switches the plugin off at the next step boundary, with
  its dependents, and the error as its reason. What it registers after an
  `await` is the plugin's like the rest; a registration made once the
  plugin is off is withdrawn at once.
- **New: `NameTakenException`, the one refusal of a name already taken.**
  A `PluginException` naming the name, what it is and whose: a second
  plugin with one id, an MCP tool added twice (`McpTools.addTool`), a VM
  service extension or alias registered twice, a data section's name, and
  the renderer's steps, nodes, anchors and light types. Each was an
  `ArgumentError`, which reads as a bug, where the name is data two
  plugins can both have thought of.
- **`ComponentCodec.unreadIn`: the keys of a row its codec did not read**,
  handed the `ComponentRestoreContext` of the row and the component read
  back from it.
  A default member, so a codec written against rc.1 keeps compiling: the
  world keeps those keys beside the component and writes them back, so a
  save opened by an earlier minor keeps what a later one added.
- **Breaking: results that were records are final classes.** `OriginShifted`
  answered or held a record, which can never gain a field. Each answers a
  final class now, with the record's field names (a positional `$1` has a
  name of its own), `==` and `hashCode`. A field read compiles as before; a
  destructuring pattern names the class, and `flutter3d_build:migrate`
  rewrites the `$1` reads.
- **Breaking: the engine's anchors are named `f3d.<name>`.** `RenderAnchor`:
  `RenderAnchor.afterBloom.name` is `f3d.after_bloom` where it was `after
  bloom`, as every plugin's name carries its namespace and none has a space.
  `RenderAnchor.named` still finds an anchor by the old word, which files
  written before carry.
- **New: `tools.dart`, what a plugin hands an agent.** `McpTools`,
  `McpToolRegistry`, `ProjectTool`, `ProjectToolRun`, `ToolCall`,
  `SessionToolCall`, `ToolSpec`, `ToolHints`, `ToolResult` and its content
  types live here, over this package alone, and `flutter3d_mcp` re-exports
  them under the imports it had. A plugin that brings tools no longer puts
  the agent servers into the game that ships it.
- **`PluginApiVersion.current` says when it moves.** Its minor moves in
  the release that adds anything a plugin can call, in this package,
  `flutter3d_fields`, `flutter3d_plugin_runtime` or a registry another
  package hands a plugin, and a structure rule holds it to that from the
  first 1.x release on. A plugin writes the number it was written against
  as a literal, never `current`.
- **Breaking: every engine plugin is named after the package that ships
  it, and `isEngine` is the namespace alone.**
  `PluginManifest.engineNamespaces` holds the packages this repository
  publishes and published at 0.8.5, and no longer the never-published
  `flutter3d_addon_*` names or `flutter3d_demo_content`. The plugins of the
  0.8 add-ons are `flutter3d_post.bloom` (and its 22 siblings),
  `flutter3d_camera`, `flutter3d_game_kit.reactions`,
  `flutter3d_game_kit.soundtrack` and `flutter3d_game_ui.spoken_events`,
  and `AudioPlugin` is `flutter3d_audio_core`, where it was
  `flutter3d_audio`. `PluginChange.fromJson`, `SimulationVersion.fromJson`
  and a manifest's `dependsOn` read the old ids as the new ones, so a run
  or a `.f3dplugin` written before still opens; a plugin from outside may
  not take an add-on's namespace (`idProblem`).
- **`reservedAreas` is frozen at what 1.0.0 ships.** A test holds it to
  the list; an area a 1.x minor brings goes under `f3d.`, or under a name
  with an upper-case letter, which no plugin id can have.
- **A plugin's simulation profile is named in its namespace.** Bare
  profile names are the engine's; a subsystem a plugin registers under a
  bare profile the engine does not define, or another namespace's, is
  refused (`SimulationProfile`).
- **`PluginManifest.engineNamespaces` names `flutter3d_pointer_lock`**, the
  name `pointer_lock` is published under from 0.4.3 on. The old name stays
  in the set, so a recorded run that names it still reads as the engine's.
- **Breaking: a codec, a snapshot part and a data section take one context
  each.** `ComponentCodec.decode`, `EventCodec.decode` and
  `SnapshotPart.restore` take a `ComponentDecodeContext`,
  `EventDecodeContext` and `SnapshotRestoreContext` (new) holding the data
  and the version it was written at; `InPlaceCodec.restoreInto` takes a
  `ComponentRestoreContext` (new) with the component too, and
  `InPlaceCodec.restoreAny` (new) types one for a registry that holds
  codecs as `InPlaceCodec<Object>`. `DataSection.read`, `load` and
  `install` take a `DataSectionRead`, `DataSectionLoad` and
  `DataSectionInstall` (new), each with the step's input and the
  `DataSectionContext`. The `.of` factories' callbacks take the same
  contexts. A parameter added to any of them later would have broken
  every codec and section written against 1.0; a member added to a
  context breaks none.
- **Breaking: a queued spawn's builder takes one `SimSpawned`.**
  `SimCommands.spawn` hands its builder a `SimSpawned` (new), the entity
  and its world, rather than the two as parameters.
- **`LightType`, `RigidPose` and `Severity` come with the contract.** The
  foundation types a plugin's signatures name now include an `Issue`'s
  severity, a light's type and a pose, so a plugin gets them from this
  one import like the rest.
- **The engine is a list of packages, not a prefix.** `isEngine` reads
  `PluginManifest.engineNamespaces` (new), the packages this repository
  publishes and the ones it published before 1.0.0 under other names, so a
  package somebody else calls `flutter3d_frost` registers in its namespace
  like any plugin from outside.
- **A plugin may not be named after an area of the engine.** `idProblem`
  refuses a plugin from outside whose namespace is one of
  `PluginManifest.reservedAreas` (new): the areas of the engine's MCP
  tools, VM extensions and events (`light`, `render`, `physics`, …) and
  the ones a minor is expected to bring, so a tool or an extension the
  engine adds to an area never shadows a plugin's.
- **A simulation keeps what a newer build wrote.** `SimulationVersion.extra`
  (new) holds the keys `fromJson` does not know and `toJson` writes them
  back; `==` and `refusalOn` compare them, so a run or a hello from a
  simulation with a part this build has no field for is refused with the
  key named rather than read as this build's.
- **A plugin may touch only tooling.** `PluginTouches.tooling` (new) is a
  plugin for the editor and its tools: it leaves `SimulationVersion` alone
  as a view plugin does, and the hosts refuse it a step phase, a step
  system or subscription, a subsystem, a render step or node and shader
  stages, so a game need not install it.
- **One namespace for every name, the editor's and the agent's too.**
  `PluginManifest.qualify` (new) answers a name in the plugin's namespace,
  `<namespace>.<name>` for a bare one, and refuses one in another namespace
  with the `PluginException` `nameProblem` words; the editor's pieces and
  panels and a plugin's MCP tools are filed by it.
- **A plugin describes its fields to an editor without depending on one.**
  `package:flutter3d_plugin_api/editor.dart` (new) holds `FieldHint` (a
  field's control: a number with ends, a step and a unit, a toggle, a
  choice, a colour, a vector, text, an asset path, an entity), `FieldKind`
  (an open set), `ComponentHints`, `EntityKindHints` and `MaterialHints`,
  each read and written as JSON, and `EditorHintRegistry`, the slot an
  editor fills and a game's engine does not have:
  `host.maybeRegistry<EditorHintRegistry>()`.
- **A run recorded under an outside profile reads back.**
  `SimulationVersion.fromJson(profiles:)` reads a profile by its name among
  the ones given, this release's by default; a name none of them has is
  read under that name promising nothing (not bit-exact, no double
  precision, no adaptive steps) instead of refusing the file, and a version
  matches another by its profile's name, since the name is all a file says
  of it.
- **A simulation names the subsystems that run in it.**
  `SimulationVersion.subsystems` holds every running solver's id at its
  own number (`withSubsystems`), written only when there is one, so the
  default simulation's run files and hellos read as before; a run recorded
  with a subsystem running is refused where it is not, and the other way
  round, with the subsystem named.
- **Scene bindings, as data.** `SceneBindingSpec` says how a component of
  the simulation is shown: the kind of node (an open name), the material,
  which fields drive which material parameters, `BindingInterpolation` and
  `BindingLifetime`; it reads and writes a `.f3dplugin`'s `bindings:` entry
  and keeps the keys it does not know. `SceneBindingRegistry` is where a
  plugin registers one.
- **Every name a plugin registers is in its namespace.**
  `PluginManifest.namespace` is the id up to its first dot — the package
  that ships the plugin — and `nameProblem` says why a name outside
  `<namespace>.` may not be registered; `f3d` is the engine's own, and the
  engine's packages (`isEngine`) register the engine's names. The format
  registry holds a plugin to the same namespace (it held it to the whole id
  before, which every id it took is still in). Names compare
  case-sensitively everywhere.
- **A registry brings its companions.** `PluginRegistry.companions` lists
  the registries that come with one, and `PluginHost.registry` finds them
  as if each had been handed to the host: an engine that hands it
  `renderer.renderSteps` gives a plugin the renderer's `LightingModels` too.
- **`PluginGroup`: plugins taken whole and adjusted.** `set` puts a
  configured plugin in place of the member with its id, `add` appends one,
  `without<T>()` and `withoutId` take members out, each answering a new
  group. A package's own group is a class extending it (`StandardPlugins()`),
  and the project's generated `installedPlugins` is one. A member a later
  release drops is not an error to `set` or `without`.
  `PluginManager.installGroup` installs one in its order.
- **`SimulationProfile`, what a simulation promises about its numbers.**
  `deterministic` (bit-exact on every platform) and `accurate` (double
  precision, adaptive steps), with wire names of their own and an open set:
  code asks a capability (`isBitExact`, `usesDoublePrecision`,
  `allowsAdaptiveSteps`), never which profile it is. `parse` refuses a name
  it does not know. A plugin is told its engine's as `PluginHost.profile`
  (`deterministic` unless the host says otherwise), which a
  `PluginManager` takes as `profile:`.

- **`LoopPhase.elements` is gone**; use `LoopPhase.fields`. A loop still
  finds the phase by the name `elements` (`LoopPhase.formerNames`).

- **`DataSection`, `DataSectionContext` and `DataSectionRegistry`.** A
  subsystem registers a reader for a named section of a `.f3dplugin`
  document, and the runtime that reads the document hands it what was
  written there, so the runtime depends on no subsystem it installs into.
- **The contract only: the foundation and the simulation host moved out.**
  `Flutter3dException` and its four families, `DocumentFormatException`,
  `WorldPosition`, `LinearColor`, `Issue`, `IssueSink`, `FormatSpec`,
  `FormatDocument`, `FormatMigration`, `FormatRefusal` and `Registration`
  are declared in `flutter3d_foundation`, this package's one dependency, and
  re-exported here under the same names, so a plugin changes nothing.
  `SimulationHandle`, `SimulationAnswer`, `SimulationQueryRegistry` and
  `SimulationCapabilityException` are `flutter3d_sim`'s, beside the loop
  that fills them; the registry slots are declared by the package that
  fills each (`DecoderRegistry` in `flutter3d_core`, `EntityKindRegistry` in
  `flutter3d_sim`, `EditorRegistry` in `flutter3d_editor_core`,
  `McpToolRegistry` in `flutter3d_mcp`). What stays is what a plugin is,
  what it is handed and what a step publishes (`PublishedState`,
  `PublishedEvent`, `SimulationVersion`, `WorldPositionCodec`).
- **`LoopPhase.fields`, the phase heat, water, wind and fire spread in**,
  named for what runs in it rather than for the package that filled it.
  `LoopPhase.elements` is deprecated and is `fields`; a loop finds the phase
  by its old name too (`LoopPhase.formerNames`, `currentName`, `current`),
  so a data plugin's file that says `"phase": "elements"` still installs.

- **`PublishedState.toWire` and `PublishedState.fromWire`**: a published
  state as plain values and back, for a handle that crosses an isolate or a
  socket. A value that is not one is refused with a
  `PluginFormatException`.
- **Breaking: every thrown type is named `*Exception`** (decision H).
  `FormatRefused` is `DocumentFormatException`. `ConstraintCycleError` is
  `ConstraintCycleException`, a `PluginException` rather than an `Error`,
  because a cycle comes from plugins' and a project's own constraints. A
  `FormatRegistry` clash, a plugin's format id or alias outside its
  namespace and a plugin's format with no fixture throw
  `FormatRegistrationException`, a `PluginException`, where they threw a
  `StateError`.
- **Breaking: `FormatSpec.binary` is `enveloped`**, true by default: whether
  a document starts with the JSON envelope. `.f3dmat` is text without one,
  which `binary` misnamed.
- **Breaking: `PluginPermission.simulation` is gone.** Nothing enforced it;
  a manifest that names it still reads, as an open permission.
- **A plugin's format aliases are held to its namespace** as its ids are.
- **`PluginTouches.named` keeps a kind it does not know**, under its own
  name and held to the simulation's rules, so a manifest read and written
  again says what it said. `PluginTouches.isKnown` tells the two apart.
- **VM extensions can be renamed without breaking callers, and say what they
  answer.** `registerFlutter3dExtension` and `VmExtensions.register` take
  `aliases:`, old names that keep answering until the next major and are
  listed under `aliases` in `ext.flutter3d.version`, and `answers:`, the keys
  of the JSON object the handler answers with, which `api/<package>.vm`
  snapshots.

- **The snapshot registry is the one path for state, and says so in its
  shape.** `SnapshotRegistry` gains `capture`, `restore` and `digest`, so a
  tool that rewinds, replays or checks a run is handed the registry rather
  than functions of its own; `restore` throws a `StateError` for a state
  that holds none of its parts. `SnapshotPart.restoresFirst` puts a frame
  the others are relative to — a physics world's floating origin — back
  before them.
- **The view reads the simulation through published state only**
  (decision A of `tasks/1.0-arch-review.md`). `LoopContext.published` is
  what a frame phase reads; `LoopContext.world` is the step phases', and the
  engine's loop throws for it in a frame phase. `PublishedState.events` are
  `PublishedEvent`s, encoded by each event's declared codec and read back
  with `decode`, so a published state crosses an isolate as plain values.
  `SimulationHandle.ask` asks a question by name, answered where the world
  is from a `SimulationQueryRegistry`; `query`, which takes a closure, is
  documented as the same isolate group's shortcut. A step-channel event is
  declared with its codec: the engine's bus asserts it.
  `OriginShifted.codec` and `eventName` are new, and the engine declares it.
- **`SimulationVersion` names every genre a run was played by**:
  `otherGenres` beside `genre`, written as `otherGenres` in a run file and
  compared like the rest; `genres` lists them all.

- **`Issue` and `IssueSink` are re-exported here** (declared in
  `flutter3d_foundation`), the one type a library reports what it could
  not do in, so the audio packages, which name no
  application, report in the same type `flutter3d_app` does.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `LoopContext.resimulated` is `isResimulated`; `SimWorld.alive` is
  `isAlive`. `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `isCancelled` is `isCanceled`. Only the Dart names changed: a
  file keeps the keys it was written with, and `dart fix` carries the
  renames.
- **A plugin may add anchors of its own.** `RenderAnchor.after(anchor,
  '<pluginId>.<name>')` stands right after another anchor; a renderer's
  `RendererSteps.addAnchor` makes it placeable. `follows`, `isEngine` and
  `engineAnchor` say where one stands. An engine anchor's `name` is a wire
  name a `.f3dplugin` file stores, and never changes within a major.

- **The simulation's model is in the plugin API: entities, components and
  their codecs.** `Entity` moved here; `ComponentCodec<T>` (id, version,
  encode, decode) and `InPlaceCodec<T>` say how a component is written for a
  snapshot, the network, a prefab or the editor; `ComponentRegistry` files
  them, with a `published` flag that is the boundary to the view;
  `SimWorld` is the world a system reaches as `LoopContext.world`: spawn and
  despawn, get and set, a query builder (`having`, `without`, `changed`),
  resources and commands deferred to the end of the phase.
- **One path for state: `SnapshotPart` and `SnapshotRegistry`.** A plugin
  that keeps state outside the world registers a part (id, version, capture,
  restore, digest), and every rewind, rollback, replay check and scrub covers
  it.
- **The view reads `PublishedState` through a `SimulationHandle`.**
  Immutable, built after the `publish` phase: published components as their
  codecs wrote them, positions as `WorldPosition`, the step's events. The
  handle (`published`, `submit(input, seat)`, `query`, `rewindTo`) has one
  shape whether the world is in this isolate or another. `OriginShifted` is
  the bus event a floating origin moves with.
- **Plugins have versions, and dependencies have ranges.**
  `PluginManifest.version` (`PluginVersion`), `simulationVersion`, and
  `dependsOn` entries that may carry a range: `'heat ^1.2.0'`
  (`PluginDependency`, `VersionRange`). The manager refuses a dependency
  outside its range with both numbers named, and reports every simulation
  plugin's number (`PluginManager.simulationVersions`).
- **`SimulationVersion` lives here, with `plugins`.** Moved from
  `flutter3d_sim`, which no longer exports it, so a network hello and a manifest
  reach it; a run, a hello and a relay compare the engine's number, the
  genre's and every simulation plugin's.
- **Events can have codecs.** `EventRegistry.declare<T>(…, codec:)` with an
  `EventCodec<T>`; a declared codec is what an event's digest is taken of,
  and `codecFor` reads it back. `onRetracted` moved onto `EventRegistry`.
- **Breaking: what the plugin API reads from text throws
  `PluginFormatException`**, a `Flutter3dFormatException`, where it threw a
  bare `FormatException`: a manifest, a plugin change, a version, a range.
- **The engine's VM service extensions have one door and a version.**
  `registerFlutter3dExtension` registers an `ext.flutter3d.*` extension and,
  the first time, `ext.flutter3d.version`, which answers `vmSchemaVersion`
  and the name of every extension registered so. `VmExtensions` is the
  registry a plugin adds its own through: a plugin's extension is
  `ext.flutter3d.<pluginId>.<verb>`, and switching the plugin off switches
  it off (the VM service cannot forget a name, so it answers an error until
  the plugin is back).
- **`PluginPermission.tools`.** A plugin that offers tools to an agent says
  so in its manifest; `McpTools.addTool` refuses one that did not.
- **One envelope for every JSON format, and a registry that knows them.**
  `FormatSpec` declares a format once, beside its reader: its id
  (`f3d.<kind>`, or `<pluginId>.<kind>` for a plugin's), suffixes, the
  version it writes, the migrations that lift older documents, and the
  fixture minted at each version. `open` refuses another format's document,
  a version from the future and a `requires` it does not understand, each
  with a sentence through the format's own exception, and lifts the rest;
  `envelope` writes `{"format", "version", "requires", "generator"}`. The
  shapes from before the envelope (`{"version": N}`, a format's own key such
  as `{"f3dfx": 1}`, an old id listed in `aliases`) read as version 1.
  `FormatDocument` is the base every document type extends to keep the
  top-level keys it did not read and write them back. `FormatRegistry`
  finds a format by id, suffix or first bytes, and is a `PluginRegistry`: a
  plugin's formats are held to its namespace and must name a fixture.

- **`PluginPermission.tools`**: a plugin that offers tools to an agent
  asks for it, and `McpTools.addTool` refuses one that did not.

- **One root for every exception: `Flutter3dException`.** It has a `message`
  and an optional `cause`, and four families under it, each an `abstract base
  class` a package can add its own leaf to: `Flutter3dFormatException` (bytes
  or text that are not what they claim, named with the prefix so it never
  shadows `dart:core`'s `FormatException`), `CapabilityException` (a device or
  platform without a feature), `PluginException` and `ResourceException` (a
  file, tool, device or service the engine needed and did not get).
  `PluginException` is the family and still a class you can throw, as it was;
  it moved here from the manager's file and is now `base` rather than `final`,
  so the run-time plugins' refusals extend it.
- **`WorldPosition`: a place in the world in double precision.** Three doubles
  in metres, Y up, right-handed, immutable, with `translated`, `relativeTo`
  (the offset from an origin, still in doubles), `distanceTo`, `lerp` and
  value equality. Float32 `vector_math` stays in local spaces, the view and
  GPU buffers; `flutter3d_foundation` has the conversions, each relative to
  an origin you name. Nothing takes it yet: the simulation and the scene graph
  move onto it next.
- **`LinearColor`: the engine's one colour type.** Red, green, blue and alpha
  in linear light, unclamped above 1, with `fromSrgb` and `toSrgb` through the
  exact sRGB curve, `withAlpha`, `scaled`, `lerp` and the `black`, `white` and
  `transparent` constants. A Flutter `Color` converts in `flutter3d`. Nothing
  takes it yet either.
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

- **The first plugin API, and its own version line.** A plugin depends on
  this package alone: `Flutter3dPlugin`, its `PluginManifest`, and the
  `PluginHost` it is installed through. The API version a plugin names is
  checked before `install` runs. A different major, or a newer minor than
  the engine provides, is refused with a sentence saying which to update.

- **One host, keyed by ids.** `PluginManager` checks ids and versions,
  installs plugins in dependency order and keeps the given order wherever
  dependencies leave a choice. A cycle is a `ConstraintCycleException` that
  names the plugins in it, and a missing dependency names both sides. It
  switches plugins on and off, and reorders them, only at a step boundary,
  and journals each change with its step so a replay makes it at the same
  one.

- **The loop's phases and the bus's types.** `LoopPhase` names the engine's
  step and frame phases, and `LoopRegistry` adds a plugin's own phases and
  systems with `after`/`before` constraints. `BusEvent`, `Delivered` and
  `EventRegistry` are the typed bus with its step and frame channels.

- **Slots for what later releases open.** `RenderStepRegistry`,
  `DecoderRegistry`, `EntityKindRegistry`, `EditorRegistry` and
  `McpToolRegistry` are declared now and filled by the engine's packages as
  each is opened, so a plugin's API version already knows their types.

- **Render anchors, and the first slot filled.** `RenderAnchor` names the
  places in the frame a plugin's pass may go: before and after every pass
  the engine draws, from `beforeShadows` to `beforePresent`, fifty in all,
  in frame order in `RenderAnchor.values`. It is an open value class, and
  the names hold for the whole major. `RenderStepRegistry.anchors` lists
  them. The renderer in `flutter3d_core` fills the slot with
  `RendererSteps`, which adds render steps and places nodes at anchors.

- **Every other slot filled, and this package unchanged for it.** Each slot
  is filled the way the render one is, by a type in the package that knows
  what it registers: `ModelDecoders` (`flutter3d_core`) and `Decoders`
  (`flutter3d`) for `DecoderRegistry`, `EntityKinds` (`flutter3d_sim`) for
  `EntityKindRegistry`, `EditorPieces` (`flutter3d_editor_core`) for
  `EditorRegistry`, and `McpTools` (`flutter3d_mcp_kit`) for
  `McpToolRegistry`, whose tools are published as `<plugin id>.<tool>`. A
  registry with no slot here is still found by type: behaviour-tree kinds
  are `BehaviorKindsRegistry` in `flutter3d_sim`. The slots' own
  declarations only gained documentation naming who fills them.

- **Built to grow without breaking.** Registries, the host and the loop
  context are `base` classes, so a new member arrives with a default. The
  kinds a later minor may extend are open value classes rather than enums.
  A manifest read from a document keeps the keys it does not know.

