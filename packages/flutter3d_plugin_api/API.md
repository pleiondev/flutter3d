# The flutter3d plugin and extension API

This is everything a plugin can name, register and rely on in flutter3d
1.0.0-rc.1: the contract in `flutter3d_plugin_api`, the fields and
subsystems in `flutter3d_fields`, the run-time plugins in
`flutter3d_plugin_runtime`, and every registry another package hands a
plugin. For each extension point it says how to register, what the hook is
handed, what it can be refused, and what may grow in a 1.x minor.

The application side of the engine (the view, scenes, assets, the loop,
physics, input, errors, versioning) is
[`flutter3d/API.md`](../flutter3d/API.md). The rules this document
summarizes are in [`docs/CONTRACTS.md`](../../docs/CONTRACTS.md), in
"Plugins" and "The shader ABI". Every name below is in a committed snapshot
under `packages/<package>/api/`.

Contents:

1. [The packages a plugin depends on](#the-packages-a-plugin-depends-on)
2. [A plugin and its manifest](#a-plugin-and-its-manifest)
3. [Namespaces](#namespaces)
4. [The plugin API version](#the-plugin-api-version)
5. [The host and its registries](#the-host-and-its-registries)
6. [Hooks and the objects they are handed](#hooks-and-the-objects-they-are-handed)
7. [The loop](#the-loop)
8. [The event bus](#the-event-bus)
9. [Components and the world](#components-and-the-world)
10. [Snapshots and saves](#snapshots-and-saves)
11. [Fields and subsystems](#fields-and-subsystems)
12. [Quantities, matter state and probes](#quantities-matter-state-and-probes)
13. [Contact events](#contact-events)
14. [Physical materials](#physical-materials)
15. [The simulation's other registries](#the-simulations-other-registries)
16. [Asset sources, decoders and formats](#asset-sources-decoders-and-formats)
17. [Render steps and post-processing](#render-steps-and-post-processing)
18. [Custom materials and lit models](#custom-materials-and-lit-models)
19. [Custom light types](#custom-light-types)
20. [The editor and MCP tools](#the-editor-and-mcp-tools)
21. [Plugins loaded at run time](#plugins-loaded-at-run-time)
22. [What an outside plugin may and may not do](#what-an-outside-plugin-may-and-may-not-do)
23. [The worked example: `examples/outside_plugin`](#the-worked-example-examplesoutside_plugin)
24. [Starting a plugin](#starting-a-plugin)
25. [What grows in 1.x](#what-grows-in-1x)

## The packages a plugin depends on

| Package | What it holds | Import it for |
|---|---|---|
| `flutter3d_plugin_api` | `Flutter3dPlugin`, `PluginManifest`, `PluginHost`, the loop, the bus, components, snapshots, profiles, `SimulationVersion`, `PublishedState`, render anchors, scene binding specs, data sections, the editor hints (`editor.dart`). Re-exports the foundation types its signatures name (`Flutter3dException` and its families, `Quantity`, `Unit`, `WorldPosition`, `LinearColor`, `LightType`, `FormatSpec`, `Registration`) | Every plugin |
| `flutter3d_fields` | `FieldDeclaration`, `FieldRegistry`, `HostField`, `Subsystem`, `SubsystemRegistry` | A plugin that keeps a grid of values or a solver |
| `flutter3d_plugin_runtime` | Data plugins (`.f3dplugin`), Wasm systems, permissions | Loading plugins while the game runs |
| The package that fills a registry | `flutter3d_core` (`RendererSteps`, `LightTypes`, `ModelDecoders`, `SceneBindings`, `RenderHooks`), `flutter3d_sim` (`EntityKinds`, `SimQueries`, `ContactEvent`, `ProbeSamplers`), `flutter3d_matter` (`MaterialCatalog`), `flutter3d_editor_core` (`EditorPieces`), `flutter3d_editor_widgets` (`EditorPanels`), `flutter3d_mcp` (`McpTools`) | What the plugin registers into |

`flutter3d_plugin_api` depends on `flutter3d_foundation` alone. A registry
type is declared by the package that implements it, so a plugin that only
simulates resolves no renderer, and a server replaying a run with a data
plugin resolves no render core. A plugin imports these libraries, never a
facade and never a `src/` library.

## A plugin and its manifest

A plugin is a `Flutter3dPlugin`: a `manifest` and an `install(PluginHost)`.
Everything `install` registers is withdrawn when the plugin is switched
off, so most plugins never override `uninstall(PluginHost)`.

```dart
final class Gust extends BusEvent {
  const Gust(this.strength);

  final double strength;

  @override
  String get name => 'wind.gust';

  @override
  void digestInto(EventDigestSink sink) => sink.add(strength);
}

final class WindPlugin extends Flutter3dPlugin {
  double _blown = 0.0;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'wind',
    apiVersion: PluginApiVersion(1, 0),
    simulationVersion: 1,
  );

  @override
  void install(PluginHost host) {
    host.events.declare<Gust>(
      'wind.gust',
      codec: EventCodec<Gust>.of(
        encode: (Gust gust) => gust.strength,
        decode: (EventDecodeContext context) =>
            Gust((context.data! as num).toDouble()),
      ),
    );
    host.loop.addSystem('wind.blow', LoopPhase.fields, (LoopContext step) {
      _blown += step.dt;
      if (_blown > 2.0) {
        _blown = 0.0;
        step.publish(const Gust(3.0));
      }
    });
    host.registry<SnapshotRegistry>().add(
      SnapshotPart.of(
        id: 'wind.blown',
        capture: () => _blown,
        restore: (SnapshotRestoreContext context) =>
            _blown = (context.data! as num).toDouble(),
      ),
    );
  }
}
```

### `PluginManifest`

| Field | Type | Default | Meaning |
|---|---|---|---|
| `id` | `String` | required | The plugin's id; its namespace is the id up to the first dot (`namespace`). `idProblem` says why an id is not one |
| `apiVersion` | `PluginApiVersion` | required | The plugin API it was written against, as a literal |
| `version` | `PluginVersion` | `PluginVersion.none` | The plugin's own version, which a dependency's range checks |
| `simulationVersion` | `int` | 1 | Joins `SimulationVersion.plugins` when the plugin touches the simulation; move it when what the plugin computes changes |
| `dependsOn` | `List<String>` | empty | Plugin ids, each optionally with a range (`"heat >=1.2.0 <2.0.0"`), read as `dependencies` (`PluginDependency`, `VersionRange`) |
| `backends` | `Set<String>` | empty (every backend) | The backends it runs on; `runsOn(backend)` |
| `touches` | `PluginTouches` | `simulation` | What it changes (below) |
| `permissions` | `Set<PluginPermission>` | empty | `files`, `network`, `tools`, `replace`: checked for plugins loaded at run time; `tools` also by `McpTools.addTool` and before the editor's MCP server offers a plugin's commands, `replace` by the renderer before a plugin takes over a built-in step or stage |
| `description` | `String?` | | For a list of plugins |
| `extra` | `Map<String, Object?>` | empty | Keys the manifest does not know, kept; `extra['budget']` is what the conformance suite holds the plugin to |

`PluginManifest.fromJson` reads the same fields from a document and keeps
the keys it does not know. `qualify(name, what:)` puts a bare name in the
namespace, and `nameProblem(name, what:)` says why a name is not the
plugin's.

### `PluginTouches`

| Value | The plugin | Held to |
|---|---|---|
| `simulation` | Changes what the simulation computes | Its switch is journalled and replayed; its `simulationVersion` joins the run's version |
| `view` | Changes only what is shown or heard (bloom, a sound pack) | No step phase, no system in a step phase, no step-channel subscriber |
| `tooling` | Belongs to an editor or an agent; a game ships without it | Everything `view` is held to, and no subsystem, no render step, node or shader stage |

An open set: a kind this build does not know is read as `simulation`, the
safe reading. `simulates` and `isKnown` answer for any value. A refusal
names the plugin and the claim (`'"outside.editor" ... only tooling'`).

### Installing and switching

The engine owns a `PluginManager` (a plugin never sees it).
`installAll` checks every manifest (`idProblem`, a duplicate id — a
`NameTakenException` —, the API version, each dependency's range) and
throws a `PluginException` for the first that fails; then it installs in
dependency order. A plugin whose backend does not match, whose dependency
is off, or whose `install` throws is left off with a `PluginStatus.reason`
(and the throw in `PluginStatus.error`), what it registered withdrawn; the
rest install.

`install` is synchronous, and so is every registration: each returns its
`Registration` at once, and what has to load behind one (a compute step's
kernels) is pending in the frame until it has. What a plugin loads itself
goes in `Future<void> ready(PluginHost host)`, called after each install;
`PluginManager.whenReady` completes when every installed plugin's has, and
one that throws switches the plugin and its dependents off at the next
step boundary. A registration made after the plugin was switched off is
withdrawn at once. `enable(id)`, `disable(id)` and `reorder(order)` are
checked when called (disabling a plugin another enabled one depends on
throws, naming the dependent) and take effect at the next step boundary.
Each change is a `PluginChange` (`PluginEnabled`, `PluginDisabled`,
`PluginsReordered`, `PluginsSet`) with its `step` and `affectsSimulation`,
journalled in `journal`; a run file carries the journal and a replay makes
the same change at the same step.

`PluginGroup` holds plugins in install order, one per id: `set` (replace or
add), `add`, `without<T>()`, `withoutId`. The generated `installedPlugins`
is one.

## Namespaces

The rules of D23 ([namespaces](../../docs/CONTRACTS.md#namespaces-d23)):

- **Every name a plugin registers is `<namespace>.<name>`**, the namespace
  being its id up to the first dot: a component, an event, a phase, a
  snapshot part, a field, a subsystem, a quantity, a profile, an MCP tool,
  a render step, a light type, a material. Registries that take a bare name
  (`EditorPieces.addCommand`, `McpTools.addTool`) publish it as
  `<namespace>.<name>`. A name outside the namespace is refused with a
  `PluginException` from `PluginManifest.nameProblem`.
- **Bare names and `f3d.` names are the engine's.**
  `PluginManifest.reservedNamespace` is `f3d`, and no outside plugin's id
  may use it.
- **The engine's rights go by list, never by prefix.**
  `PluginManifest.engineNamespaces` is the packages this repository
  publishes or published at 0.8.5, and `isEngine` is true for a plugin in
  one of them alone; every engine plugin is named after its package. The
  ids of the 0.8 `flutter3d_addon_*` plugins are read as today's, and no
  outside plugin may take one of those namespaces. A plugin named
  `flutter3d_wind` from outside is an outside plugin.
- **The engine's areas are frozen at 1.0.0.** `PluginManifest.reservedAreas`
  cannot be a plugin's namespace, and the set does not grow in a 1.x
  minor: `animationGraph`, `asset`, `behavior`, `brush`, `capture`, `clip`,
  `command`, `cutscene`, `experiment`, `game`, `history`, `image`, `joint`,
  `key`, `kit`, `level`, `light`, `lod`, `material`, `mesh`, `modifier`,
  `object`, `paint`, `play`, `plugin`, `prefab`, `project`, `render`,
  `retopology`, `rig`, `run`, `scene`, `sculpt`, `selection`,
  `shapeDriver`, `shapeKey`, `simulation`, `skeleton`, `skin`, `state`,
  `texture`, `textureGraph`, `track`, `type`, `uv`, `view`, `assets`,
  `cvar`, `timeline`, `version`, `actor`, `animation`, `elements`,
  `origin`, `physics`, `platformer`, `racing`, `sequence`, `shooter`,
  `strategy`, `wasm`, `audio`, `camera`, `editor`, `effects`, `fields`,
  `hub`, `input`, `matter`, `net`, `particles`, `post`, `sim`, `voxel`,
  `xr`. An area a minor brings goes under `f3d.` (`f3d.<area>.<tool>`,
  `ext.flutter3d.f3d.<area>.…`) or takes a name with an upper-case letter,
  which no plugin id can have.
- **A simulation profile's name is its identity** on every tape and hello:
  a plugin's profile is `<namespace>.<name>`, and a subsystem registered
  under a bare profile the engine does not define, or another namespace's,
  is refused.
- **An asset scheme is the namespace with `-` for `_`**, or that and
  `-<name>` (`acme-frost` and `acme-frost-pak` for `acme_frost`), never one
  of `AssetSources.reservedSchemes` (`http`, `https`, `file`, `asset`,
  `data`, `blob`, `package`, `hub`, `f3d`), a set frozen at 1.0.0.
- **A VM extension is `ext.flutter3d.<namespace>.<verb>`**:
  `VmExtensions.register(verb, handler)` through the plugin's view puts the
  id in front (`nameOf(verb)`).

## The plugin API version

`PluginApiVersion(major, minor)` is the plugin contract's own number,
`PluginApiVersion.current` (1.0) in this build. The policy:

- a different major is a different contract and nothing installs across
  it;
- a plugin asking for a newer minor than the engine provides is refused
  (it may call a registry this engine does not have);
- an older minor installs.

`refusalOn(provided)` answers the sentence, or `null`; `PluginHost.apiVersion`
is what the engine provides. The minor moves in the release that adds
anything a plugin can call: a member of `flutter3d_plugin_api`,
`flutter3d_fields` or `flutter3d_plugin_runtime`, or of a registry another
package hands a plugin (`McpTools`, `RendererSteps`, `ModelDecoders`). A
structure rule compares those snapshots with the last 1.x release and fails
while the number has not moved
([the plugin API's number](../../docs/CONTRACTS.md#the-plugin-apis-number)).

**A plugin writes the number it was written against as a literal**,
`PluginApiVersion(1, 0)`, never `current`: `current` is whatever the engine
it is compiled with provides, so it always passes and says nothing.

## The host and its registries

`install` is handed a `PluginHost`:

| Member | What it is |
|---|---|
| `manifest` | The plugin's manifest |
| `apiVersion` | The plugin API the engine provides |
| `profile` | The run's `SimulationProfile`; ask `isBitExact`, `usesDoublePrecision`, `allowsAdaptiveSteps` |
| `backend` | The backend the engine draws with, or `null` with no renderer |
| `loop` | The `LoopRegistry`, scoped to the plugin |
| `events` | The `EventRegistry`, scoped to the plugin |
| `registry<R>()` | The registry of type `R`, scoped to the plugin; a `StateError` naming `R` and the plugin when the engine has none |
| `maybeRegistry<R>()` | The same, or `null` |

Every registry is a `PluginRegistry`. The host calls `forPlugin(scope)` and
hands the plugin a view that checks its names against its namespace, tracks
each `Registration` (`PluginScope.track`) and cancels them when the plugin
is switched off. `companions` lets one registry bring others (the
renderer's steps bring its light types; the decoders bring texture codecs).

| Registry | Package | Reached as | A plugin adds |
|---|---|---|---|
| `LoopRegistry` | `flutter3d_plugin_api` | `host.loop` | Phases, systems, assimilations |
| `EventRegistry` | `flutter3d_plugin_api` | `host.events` | Event declarations and subscribers |
| `ComponentRegistry` | `flutter3d_plugin_api` | `host.registry<ComponentRegistry>()` | Component codecs |
| `SnapshotRegistry` | `flutter3d_plugin_api` | `host.registry<SnapshotRegistry>()` | Snapshot parts |
| `FormatRegistry` | `flutter3d_plugin_api` | `host.registry<FormatRegistry>()` | File formats (`FormatSpec`) |
| `DataSectionRegistry` | `flutter3d_plugin_api` | given to a `DataPluginLoader` | Readers for `.f3dplugin` sections |
| `SceneBindingRegistry` | `flutter3d_plugin_api` (filled by `SceneBindings`, `flutter3d_core`) | `host.registry<SceneBindings>()` | Components drawn as scene nodes |
| `RenderStepRegistry` | `flutter3d_plugin_api` (filled by `RendererSteps`, `flutter3d_core`) | `host.registry<RendererSteps>()` | Steps, nodes, compute steps, contributors, settings |
| `EditorHintRegistry` | `flutter3d_plugin_api/editor.dart` (filled by `EditorHints`) | `host.registry<EditorHints>()` | Inspector hints for components, entity kinds, materials |
| `VmExtensions` | `flutter3d_plugin_api` | `host.registry<VmExtensions>()` | VM service extensions |
| `FieldRegistry`, `SubsystemRegistry` | `flutter3d_fields` | `host.registry<FieldRegistry>()`, `host.registry<SubsystemRegistry>()` | Fields, solvers |
| `WorldFields` | `flutter3d_plugin_runtime` | `host.registry<WorldFields>()` | Named arrays a Wasm system reads and writes |
| `LightTypes`, `LightingModels`, `RenderHooks`, `PipelineNodeKinds`, `RuntimeShaders` | `flutter3d_core` | `host.registry<…>()` | Light types, lit models, draw-list, skinning and LOD hooks, pipeline node kinds, materials compiled at run time |
| `ModelDecoders` (a `DecoderRegistry`), `TextureCodecs` | `flutter3d_core` | `host.registry<ModelDecoders>()`, `host.registry<TextureCodecs>()` | Model decoders, asset schemes, image codecs |
| `Decoders` | `flutter3d` | `host.registry<Decoders>()` | Material decoders, beside the model decoders |
| `EntityKinds` (an `EntityKindRegistry`), `SimQueries` (a `SimulationQueryRegistry`), `BehaviorKindsRegistry`, `ProbeSamplers`, `PublishedWorlds` | `flutter3d_sim` | `host.registry<…>()` | Entity kinds, named questions, behavior-tree leaves and composites, probe samplers, worlds the view reads |
| `MaterialCatalog` | `flutter3d_matter` | `host.registry<MaterialCatalog>()` | Physical materials and measured pairs |
| `EditorPieces` (an `EditorRegistry`) | `flutter3d_editor_core` | `host.registry<EditorPieces>()` | Commands, inspector components, gizmos, importers, palette and asset entries |
| `EditorPanels` | `flutter3d_editor_widgets` | `host.registry<EditorPanels>()` | Panels |
| `McpTools` (an `McpToolRegistry`) | `flutter3d_mcp` (`kit.dart`) | `host.registry<McpTools>()` | MCP tools and their schema version |

`EngineLoop` hands the host its own (`ComponentRegistry`, `SnapshotRegistry`,
`SimQueries`, `PublishedWorlds`, `ProbeSamplers`, `FieldRegistry`,
`SubsystemRegistry`, `MaterialCatalog`) and whatever it is given in
`registries:`, which is where an application passes `renderer.renderSteps`
and the rest (`Flutter3dView` does it for you through
`PluginSettings.registries`). `host.registry<T>()` finds any registry the
engine was given, so a package may define a registry of its own and a plugin
reaches it the same way.

Every registry and the host are `base` classes: a member added in a minor
arrives with a default body, so a test double written against 1.0 keeps
compiling.

## Hooks and the objects they are handed

A hook an outside author implements, and a callback one writes, takes one
context object that can gain members. That is the rule
([what a plugin may touch](../../docs/CONTRACTS.md#what-a-plugin-may-touch));
the structure rule holding it lists the exceptions in
`tool/structure/repository.dart`.

| Hook | Handed | Section |
|---|---|---|
| `Flutter3dPlugin.install`, `uninstall` | `PluginHost` | [manifest](#a-plugin-and-its-manifest) |
| `LoopSystem` | `LoopContext` | [the loop](#the-loop) |
| `Assimilation.assimilate` | `AssimilationContext` | [the loop](#the-loop) |
| `EventHandler<T>` | `Delivered<T>` | [the bus](#the-event-bus) |
| `EventCodec.decode` | `EventDecodeContext` (`data`, `version`) | [the bus](#the-event-bus) |
| `ComponentCodec.decode` | `ComponentDecodeContext` (`data`, `version`) | [components](#components-and-the-world) |
| `InPlaceCodec.restoreInto` | `ComponentRestoreContext<T>` (`value`, `data`, `version`) | [components](#components-and-the-world) |
| `SnapshotPart.restore` | `SnapshotRestoreContext` (`data`, `version`) | [snapshots](#snapshots-and-saves) |
| `Subsystem.step` | `SubsystemContext` | [fields](#fields-and-subsystems) |
| `ProbeSampler.sample` | `ProbeSample` (`probe`, `entity`, `world`, `step`, `seconds`) | [probes](#quantities-matter-state-and-probes) |
| `EntityKind.spawn`, `validate` | `EntitySpawn`, `EntityCheck` | [other registries](#the-simulations-other-registries) |
| `SimulationAnswer` | `SimulationQuestion` (`world`, `arguments`) | [other registries](#the-simulations-other-registries) |
| `GenrePlugin.stepSimulation`, `restoreSimulation`, `publishEvents` | `GenreStepContext<S>`, `GenreRestoreContext<S>`, `GenrePublishContext<S>` | [other registries](#the-simulations-other-registries) |
| `DataSection.read`, `load`, `install` | `DataSectionRead`, `DataSectionLoad`, `DataSectionInstall` | [run-time plugins](#plugins-loaded-at-run-time) |
| `ModelDecoder.decode`, `handles` | `ModelDecodeContext`, `ModelProbe` | [decoders](#asset-sources-decoders-and-formats) |
| `MaterialDecoder.decode`, `handles` | `MaterialDecodeContext`, `MaterialProbe` | [decoders](#asset-sources-decoders-and-formats) |
| `TextureCodec.decode` | `TextureDecodeContext` | [decoders](#asset-sources-decoders-and-formats) |
| `RenderNode.setup`, `execute` | `FrameGraphBuilder`, `RenderFrame` | [render steps](#render-steps-and-post-processing) |
| `ComputeStep.record` | `ComputeContext` | [render steps](#render-steps-and-post-processing) |
| `PassContributor.encode` | `ContributorFrame` | [render steps](#render-steps-and-post-processing) |
| `DrawListHook.keeps`, `sortKey` | `DrawListContext` | [render steps](#render-steps-and-post-processing) |
| `SkinningHook.claims`, `record` | `SkinningContext` | [render steps](#render-steps-and-post-processing) |
| `FramePlacer.place` | `FramePlacementContext` | [render steps](#render-steps-and-post-processing) |
| `LightTypeHook.pack` | `LightPackContext` | [light types](#custom-light-types) |
| `EditorGizmo.marksFor`, `appliesTo`, `dragged` | `GizmoContext`, `GizmoDrag` | [the editor](#the-editor-and-mcp-tools) |
| `EditorImporter.import` | `ImportRequest` | [the editor](#the-editor-and-mcp-tools) |
| `EditorPanel.builder` | `EditorPanelContext` | [the editor](#the-editor-and-mcp-tools) |
| `ProjectToolRun` | `ToolCall` (`name`, `arguments`) | [MCP tools](#the-editor-and-mcp-tools) |
| `WasmRuntime.instantiate`, `WasmInstance.step` | `WasmInstantiation`, `WasmStep` | [Wasm](#wasm-systems) |

### The hooks handed one value

`hookValueParameters` names the hooks and callbacks handed one value that
cannot gain members, each with why that is right. The decisions a plugin
author meets:

- **Codecs are handed the value or the document.**
  `ComponentCodec.encode(T)`, `EventCodec.encode(T)`, `FormatMigration`,
  `MaterialUpdate.apply(values)`, `DataSection.write(section)` and
  `CommandReader(arguments)` take the one input of a conversion. What a
  later minor hands one (a target version, an entity remap) arrives as a
  member with a default body that calls this one, or as a named parameter
  of the factory.
- **Saved state is handed back as it was captured.**
  `SnapshotPart.capture()` and `digest()` take nothing,
  `WasmInstance.restore(state)` takes its own saved state; a later shape is
  told apart by the version saved beside it, never by a second parameter.
- **I/O seams take their path.** `PluginSource.read(path)` and
  `AssetSourceFactory(path)` stay in the shape of the call they wrap. The
  source a factory makes reads through `AssetSource.read(AssetRead)`: one
  request (`onProgress`, `cancel`, `range`) that a minor can add to, which
  a source that cannot report, stop or read a range ignores.
- **What the engine implements is not a hook.** `AssimilationContext`,
  `SubsystemContext`, `FieldRegistry`, `SnapshotRegistry`, `SimQuery`,
  `DataSectionContext` and `EventDigestSink` are made by the engine and
  called by a plugin by name or value; nobody outside implements them.
- **Tools were given a context.** `ProjectToolRun` and `OfferedTool.run`
  take a `ToolCall` (`SessionToolCall<S>` with its session) since rc.1.

`hookParametersAllowed` lists the few hooks that keep several parameters
for a fixed shape no minor will grow (the HAL's encoder calls, the physics
queries per pair, `VmExtensionHandler`'s `(method, parameters)`, the Wasm
imports mirrored one to one). `hookParametersPending`, the list of debts,
is empty at 1.0.0-rc.1.

## The loop

`host.loop` is a `LoopRegistry`:

| Member | What it does | Refused |
|---|---|---|
| `addPhase(phase, {after, before})` | A phase of the plugin's own, `LoopPhase.step(name)` or `LoopPhase.frame(name)` | A name outside the namespace; a step phase from a `view` or `tooling` plugin |
| `addSystem(name, phase, system, {after, before})` | A `LoopSystem` in a phase, ordered by system names | A step-phase system from a `view` or `tooling` plugin |
| `addAssimilation(name, assimilation, {after, before})` | A stage that turns the step's external readings into world state, in the `input` phase | As a step system |

The engine's step phases run inside every fixed step, in
`LoopPhase.stepPhases` order: `input`, `movers`, `physics`, `fields`,
`rules`, `publish`. Its frame phases run once per displayed frame after the
steps (`LoopPhase.framePhases`): `animate`, `audio`, `camera`, `render`,
`ui`. `fields` was `elements` until 1.0.0-rc.1 and is still found by that
name (`LoopPhase.formerNames`, `currentName`). Within the constraints,
registration order decides: the application's first, then each plugin's in
install order. A cycle is a `ConstraintCycleException` (a `PluginException`)
naming every member of it.

`LoopContext`, handed to every system:

| Member | Type | Meaning |
|---|---|---|
| `step` | `int` | The step number (frame phases: the last step run) |
| `dt` | `double` | The fixed step in seconds |
| `realDt` | `double` | The displayed frame's real seconds (frame phases) |
| `alpha` | `double` | How far the frame is between two steps, for interpolation |
| `phase` | `LoopPhase` | The phase running |
| `isResimulated` | `bool` | The step is being run again (rollback, scrub): solve as usual, repeat no effect outside the world |
| `world` | `SimWorld` | The simulation's world |
| `published` | `PublishedState` | What the last step published |
| `publish(event)` | | Publishes a `BusEvent` on the current channel |

`AssimilationContext` adds `inputs` (the step's `ExternalStateInput`s),
`from(source)` and `profile`. `XrPoses` and `XrSceneColliders` in
`flutter3d_sim` are assimilations.

**What grows in 1.x.** Members of `LoopContext` and `AssimilationContext`,
phases between the engine's (a minor's are under `f3d.`). The engine's
phase names and their order are frozen.

## The event bus

`host.events` is an `EventRegistry`:

| Member | What it does |
|---|---|
| `declare<T>(name, {channel, description, codec})` | Declares an event (`EventDeclaration`); `channel` is `BusChannel.step` by default |
| `publish(event)` | Publishes a `BusEvent` |
| `onStep<T>(label, handler)` | Calls the handler at the end of each step with that step's `T`s, in order; refused to a `view` or `tooling` plugin |
| `onFrame<T>(label, handler)` | Calls it once a frame with every `T` since the last frame, steps first |
| `onRetracted<T>(label, handler)` | Calls it on the frame channel for a `T` shown for a step and not produced when that step ran again; stop the sound or the burst it started |
| `declared`, `codecFor(name)` | What is declared |

A `BusEvent` has a stable `name` and writes its identifying fields in
`digestInto(EventDigestSink)`. Events on the step channel are digested per
step, so a replay says at which step its events parted from the
recording's. `Delivered<T>` carries `event`, `channel`, `step`, `sequence`
and `resimulated`. The frame channel never shows an event twice: a
resimulated step's events are reconciled by step and sequence. An event
with a codec (`EventCodec`, `version` and `encode`/`decode`) can be written
to a run's `EventTrace` and published to the view as a `PublishedEvent`
(`PublishedState.eventsNamed(name)`, `decode(codec)`).

Engine events a plugin may hear: `OriginShifted` (`origin.shifted`),
`ContactEvent` (`physics.contact`, see [contact events](#contact-events)),
`TimeLost`, `WasmTrapped` (`wasm.trapped`), and the frame's `FrameDrawn`,
`FrameOverTime`, `FramePassSkipped`. `LoopContext.publish` puts an event on
the step channel from a step phase and on the frame channel from a frame
phase.

**What grows in 1.x.** New engine events (under the reserved areas or
`f3d.`), members of `Delivered`, new channels (`BusChannel` is open).

## Components and the world

`host.registry<ComponentRegistry>()`:

| Member | What it does |
|---|---|
| `register<T>(codec, {published})` | Registers a component type by its codec; `published: true` puts its values in `PublishedState.components`, which a view or another isolate reads |
| `exclude<T>(because)` | Says a type is deliberately not saved (a renderer handle, a cache), and why |
| `codecOf<T>()`, `codecNamed(id)`, `isPublished<T>()`, `registered` (`ComponentInfo`) | Lookups |

A `ComponentCodec<T>` has an `id` (namespaced), a `version`, `encode(T)`
and `decode(ComponentDecodeContext)`; `ComponentCodec.of(...)` makes one
from functions. An `InPlaceCodec<T>` restores into the existing value
(`restoreInto(ComponentRestoreContext<T>)`) for a component that holds
buffers. `WorldPositionCodec` (`flutter3d.position`) is the engine's.

```dart
final class Sail {
  const Sail(this.area);
  final double area;
}

void components(PluginHost host) => host.registry<ComponentRegistry>().register(
  ComponentCodec<Sail>.of(
    id: 'wind.sail',
    encode: (Sail sail) => sail.area,
    decode: (ComponentDecodeContext context) =>
        Sail((context.data! as num).toDouble()),
  ),
  published: true,
);
```

`SimWorld` (`LoopContext.world`) is the ECS the engine implements: `spawn`,
`despawn`, `isAlive`, `get<T>`, `set<T>`, `has<T>`, `remove<T>`,
`resource<R>`, `setResource`, `query()` (`SimQuery`: `having<T>`,
`without<T>`, `changed<T>({since})`, `entities`), `commands` (`SimCommands`,
applied at the end of the phase), `changeStep`. `Entity` is an extension
type over an index and a generation. A system that iterates entities in an
order that matters sorts them (by `index`), since a query's order is not a
promise.

## Snapshots and saves

`host.registry<SnapshotRegistry>().add(part)` adds a `SnapshotPart`: `id`
(namespaced), `version`, `capture()`, `restore(SnapshotRestoreContext)`,
optionally `digest()` (null lets the registry digest the capture) and
`restoresFirst` (for a frame the other parts' numbers are relative to).
`SnapshotPart.of(...)` makes one from functions. Every part is captured
into the loop's snapshots, so a rollback, a replay, the determinism check
and a save carry the plugin's state with the world. State a plugin keeps
outside the world and does not put in a part is state a rollback does not
restore.

**A save requires its plugins.** A `Snapshot` (`f3d.save`) lists in
`requires` the namespace of every plugin whose snapshot part or component it
holds. An engine restoring it refuses a snapshot that requires a plugin it
does not have, naming the plugin, with a `SnapshotFormatException`, instead
of dropping that plugin's state.

## Fields and subsystems

`flutter3d_fields` is how a plugin keeps a grid of values over the world
and a solver that steps it, with what each reads and writes declared.

### `FieldDeclaration`

| Field | Type | Meaning |
|---|---|---|
| `id` | `String` | `<namespace>.<name>` (`FieldDeclaration.namespacedId`) |
| `quantity`, `unit` | `String`, `Unit` | What the values are |
| `grid` | `FieldGrid(width, height, depth, {components})` | Cells and values per cell |
| `transform` | `FieldTransform({origin, cellSize})` | Where the grid sits in the world (`WorldPosition`, meters); `gridOf`, `worldOf` |
| `residence` | `FieldResidence` | `host` (default), `buffer`, `texture3D` |
| `writer` | `FieldAccess` | The one step that writes it: `FieldAccess.simulation(id)`, `.frame(node)`, `.audio(name)` |
| `readers` | `List<FieldAccess>` | Who reads it |

`host.registry<FieldRegistry>()`:

| Member | What it does | Refused |
|---|---|---|
| `declare(field)` | Declares a field; a host field's values start at zero and join the loop's snapshots | `ArgumentError` for a `FieldDeclaration.problem` or an id taken; `PluginException` outside the namespace |
| `hostField(id)` | The simulation's values. Through a plugin's view, writable only for a field the plugin declared while it touches the simulation; `HostField.readOnly` otherwise | |
| `published(id)` | The values at the end of the last step, which a frame node or a sound reads | |
| `declared`, `declarationOf(id)` | Lookups | |

`HostField` holds `values` (`Float32List`) with `valueAt`, `setValueAt`,
`sample(WorldPosition)`, `quantityAt(WorldPosition)`, `fill`, `copyFrom`,
`digest`, and `snapshotPart`. A field on a device is placed by the frame
(`FieldUpload`, see [render steps](#render-steps-and-post-processing)); a
residence the device cannot hold is a `FieldResidenceException` with a
`FieldRefusal` (`missingFeature`, `noPlacement`, `notPlaced`).

### `Subsystem`

A `Subsystem` has a `declaration` and `step(SubsystemContext)`;
`Subsystem.of(declaration, step)` makes one from a function.

| `SubsystemDeclaration` field | Meaning |
|---|---|
| `id`, `version` | Namespaced id, and the number that joins the simulation's version |
| `phase` | `LoopPhase.fields` by default |
| `after`, `before` | Ordering among systems |
| `readsQuantities`, `writesQuantities` | Quantity ids it reads and writes on bodies |
| `readsFields`, `writesFields` | Field ids it reads and writes |
| `switchedOnBy` | The profiles it runs under; `null` for every profile (`runsUnder(profile)`) |

`SubsystemContext` holds `declaration`, `step`, `dt`, `isResimulated`,
`profile`, `world`, `publish(event)`, and `field(id)`: writable for a field
it declared among its writes, read-only for one among its reads, a
`StateError` for any other.

`host.registry<SubsystemRegistry>().register(subsystem)` checks the
declaration against the fields declared so far (each field it writes names
it as the writer and is held in host memory) and adds its step to its phase
when it runs under the loop's profile; one that does not is kept in
`declared` only. It is refused (`ArgumentError`) for a declaration
`problem`, an id taken, an undeclared field, a field not in host memory or
written by another; a `PluginException` for a name outside the namespace or
for a `tooling` or `view` plugin.

```dart
const FieldDeclaration smoke = FieldDeclaration(
  id: 'haze.smoke',
  quantity: 'haze.density',
  unit: Unit.kilogramPerCubicMeter,
  grid: FieldGrid(16, 8, 16),
  transform: FieldTransform(cellSize: 0.25),
  writer: FieldAccess.simulation('haze.drift'),
  readers: <FieldAccess>[FieldAccess.frame('haze.smoke upload')],
);

final class Drift extends Subsystem {
  @override
  SubsystemDeclaration get declaration => const SubsystemDeclaration(
    id: 'haze.drift',
    version: 1,
    writesFields: <String>['haze.smoke'],
  );

  @override
  void step(SubsystemContext context) {
    final values = context.field('haze.smoke').values;
    for (var i = 0; i < values.length; i++) {
      values[i] *= 0.99;
    }
  }
}
```

### `SimulationVersion` composition

A run records the `SimulationVersion` it was played by, and another run is
refused by it when `refusalOn(running)` answers a sentence. It is composed
of:

| Part | From |
|---|---|
| `engine` | `SimulationVersion.engineVersion` (1) |
| `genre`, `genreVersion`, `otherGenres` | The genre plugins' constants (`platformerSimulationVersion` and its siblings) |
| `plugins` | Every enabled plugin that touches the simulation, by id at its `simulationVersion` (a `view` or `tooling` plugin is not counted) |
| `subsystems` | Every running subsystem by id at its `version` (`SubsystemRegistry.versions`) |
| `profile` | The `SimulationProfile` |
| `extra` | Keys a later minor adds, kept |

So a run recorded with a subsystem on is refused where it is off, and the
other way round. A plugin that installs a solver switched on only by a
profile of its own (`switchedOnBy`) leaves what the default simulation
computes alone, digest for digest; its `simulationVersion` still joins
`plugins` under every profile, so a run recorded with the plugin installed
is refused where it is not.

**What grows in 1.x.** Members of `FieldDeclaration`, `SubsystemDeclaration`
and `SubsystemContext` with defaults; new residences and refusal reasons
(open sets); new parts of `SimulationVersion` (kept in `extra` by an older
reader).

## Quantities, matter state and probes

**Quantities.** `Quantity(value, unit)` from `flutter3d_foundation`, with
arithmetic that checks dimensions (`UnitMismatchException`), `to(unit)`,
`valueIn(unit)`, `Quantity.parse('20 °C')`. `Unit` has the SI units and
the common ones (`Unit.kelvin`, `Unit.celsius`, `Unit.pascal`,
`Unit.kilogramPerCubicMeter`, `Unit.lux`, ...), and `Unit.parse` reads a
symbol. A quantity a plugin adds has a namespaced id.

**`MatterState`** (`flutter3d_matter`) is a body's state as quantities by
id: `temperature` (`f3d.temperature`), `pressure` (`f3d.pressure`),
`f3d.wetness`, and any a plugin adds, plus a `MaterialPhase`. It is a value:
`withQuantity(id, quantity)`, `without(id)`, `inPhase(phase)`,
`operator [](id)`. `MatterState.checkedQuantityId` holds an id to the
namespace rule. In the simulation it is the component
`MaterialStateComponent` (`flutter3d_sim`, `state`, `withState`), which a
save, a snapshot and the wire carry with the body, a plugin's quantities
included; `unread` keeps what this build cannot read.

**Probes.** `host.registry<ProbeSamplers>().add(quantity, sampler)` makes a
plugin's quantity readable by any `Probe` that names it: the loop asks the
`ProbeSampler` registered for the probe's quantity each step with a
`ProbeSample` and publishes a `ProbeReading`. `ProbeSampler.of(function)`
makes one.

```dart
import 'package:flutter3d_sim/flutter3d_sim.dart';

host.registry<ProbeSamplers>().add(
  'haze.density',
  ProbeSampler.of(
    (sample) => sample.world
        .get<MaterialStateComponent>(sample.entity)
        ?.state['haze.density'],
  ),
);
```

**External state** arrives as `ExternalStateInput` on a step's input; an
`Assimilation` turns it into world state (see [the loop](#the-loop)).

## Contact events

`ContactEvent` (`flutter3d_sim`, `physics.contact`, step channel) is what
both physics cores report for each contact a step made: `bodyA`, `bodyB`,
`feature`, `materialA`, `materialB` (physical material ids), `phase`
(`ContactPhase.begin`, `persist`, `end`, an open set), `point`, `normal`,
`impulse` (newton-seconds) and `relativeVelocity`. A plugin hears it with
`host.events.onStep<ContactEvent>(label, handler)`; a step's events are
delivered after its phases, so heat a contact leaves is laid down on the
next step, and what the plugin keeps between the two belongs in a snapshot
part. A `view` plugin hears it on the frame channel instead.

**What grows in 1.x.** Members of `ContactEvent` and new phases.

## Physical materials

`host.registry<MaterialCatalog>()` holds the engine's materials
(`Materials`, ids `f3d.*`) and every enabled plugin's:

| Member | What it does |
|---|---|
| `add(PhysicalMaterial)` | Adds a material under `<namespace>.<name>`; refused when `PhysicalMaterial.problems()` finds a number no real substance has (a density in g/cm³, a temperature in °C) or the id is taken |
| `addPair(MaterialPair)` | A measured pair: friction, restitution, rolling resistance, contact angle |
| `byId`, `require(id)`, `pairOf`, `contact(a, b)`, `watch` | Lookups; `require` throws `UnknownMaterialException` naming the plugin it needs |

A `PhysicalMaterial` has `id`, `name`, `phase`, and property groups
(`mechanical`, `fluid`, `thermal`, `acoustic`, `optical`, `electrical`),
each in SI with its `source`. A level or a world that names a material
nobody installed is refused with an `UnknownMaterialException`. The units
are in [physical materials](../../docs/CONTRACTS.md#physical-materials).
A data plugin brings materials in its `physicalMaterials` and
`materialPairs` sections.

## The simulation's other registries

| Registry | Add | Handed |
|---|---|---|
| `EntityKinds` | `add(EntityKind)`, `replace`, `addAll` | An `EntityKind(type)` validates (`EntityCheck`: `entity`, `scope`, `out`) and spawns (`EntitySpawn`: `entity`, `context`) the level entities of its type; `place(...)` and the `require…` checks are helpers it calls. A data plugin's kinds are `DataEntityKind` |
| `SimQueries` | `add(name, answer)` | A `SimulationAnswer` handed a `SimulationQuestion` (`world`, `arguments`); a view asks `SimulationHandle.ask(name)` |
| `BehaviorKindsRegistry` | `leaf(kind, build)`, `consideration(kind, build)`, `composite(kind, build)` | A `LeafBuilder`, `ConsiderationBuilder` or `CompositeBuilder` handed `BehaviorParameters`; a leaf ticks with a `BehaviorContext` |
| `PublishedWorlds` | `add(EcsWorld)` | A world of the plugin's own the view reads |
| `ProbeSamplers` | `add(quantity, sampler)` | See [probes](#quantities-matter-state-and-probes) |

`GenrePlugin<S>` (`flutter3d_sim`) is the base a genre extends: its
`kinds`, a `systemName` stepped in `stepPhase`, and
`stepSimulation(GenreStepContext<S>)`, `captureSimulation(S)`,
`restoreSimulation(GenreRestoreContext<S>)`,
`publishEvents(GenrePublishContext<S>)`.

## Asset sources, decoders and formats

| Registry | Member | What it adds |
|---|---|---|
| `ModelDecoders` | `addModelDecoder(ModelDecoder)` | A model format: `handles(ModelProbe)` and `decode(ModelDecodeContext)` to a `ModelDocument`; asked after a request's own decoders and before the built-in readers |
| `ModelDecoders` | `addSource(scheme, AssetSourceFactory)` | Paths starting `scheme:` read through the plugin's `AssetSource` |
| `TextureCodecs` | `add(TextureCodec)` | An image format: `name`, `sniff(head)`, `decode(TextureDecodeContext)`; offered before the engine's |
| `Decoders` (`flutter3d`) | `addMaterialDecoder(MaterialDecoder)` | A material file format: `handles(MaterialProbe)`, `decode(MaterialDecodeContext)` |
| `FormatRegistry` | `add(FormatSpec)` | A file format of the plugin's own, `<namespace>.<kind>`, with its version, migrations and fixtures; `FormatRegistrationException` for one refused |

A scheme is the plugin's namespace with `-` for `_`, or that and
`-<name>`; a reserved scheme or another namespace's is refused with a
`PluginException`, and a scheme already taken with an `ArgumentError`. The
application's own view takes any scheme that is not taken.

```dart
void scheme(PluginHost host) => host.registry<ModelDecoders>().addSource(
  'acme-frost',
  (String path) => FileAssetSource('/srv/frost/$path'),
);
```

**What grows in 1.x.** Members of the decode contexts and probes. The
reserved schemes are frozen.

## Render steps and post-processing

The renderer is extended through `RendererSteps` (`flutter3d_core`), the
registry that fills `RenderStepRegistry`. A plugin that draws depends on
`flutter3d_core`. A `tooling` plugin is refused render steps, nodes and
shader stages.

### Anchors

Every pass the engine draws has an anchor before it and one after it,
`RenderAnchor.beforeShadows` to `RenderAnchor.beforePresent`, listed in
frame order in `RenderAnchor.values` (50 of them). A plugin puts a node at
an anchor rather than at a priority number; nodes at one anchor are ordered
by `after` and `before`, then by registration order. An anchor stays where
it is when the passes around it are switched off.
`RendererSteps.addAnchor(RenderAnchor.after(follows, name))` adds a
plugin's own anchor.

### `RendererSteps`

| Member | What it does |
|---|---|
| `addStep(RenderStep)` | A step switched like the engine's: `RenderSettings.without` and `only` switch it, and switching off a step it `needs` takes it down too |
| `provide(RenderStep)` | Says the plugin is the switch of a step: its own freely; one of the engine's only as a `RenderStepAddon` that declares it in `replaces`, with `PluginPermission.replace` |
| `addNode(RenderNode, {at, step, after, before})` | A node at an anchor, owned by a step |
| `addComputeStep(ComputeStep, {at, owner, ...})` | A compute node, placed by the hardware layer behind the registration (`PassSkip.pending` until it is) |
| `addWorkload(ComputeWorkload, {at})` | A simulation's workload, placed by the workload rule and told where it landed |
| `addFieldUpload(FieldUpload, {at, owner, ...})` | Puts a host field on a device, placed behind the registration |
| `addContributor(PassContributor)`, `removeContributor` | Draws into the scene pass; only who added a contributor takes it out (`PluginException` otherwise), and a plugin that touches only tooling adds none |
| `placeSkinningHook(SkinningHook)` | Skinning on the drawing device or the CPU, named `<namespace>.skinning_<n>` |
| `whenPlaced()` | Completes once every placement started so far has settled — for a test or a loading screen, never a frame |
| `addSettings(SettingsSlot)` | A settings group in `RenderSettings.extensions` |
| `addMaterials(ShaderLibrary)` | A plugin's compiled stages: through a plugin's view the library answers the stages in its namespace (`<namespace>__…`) and the engine names its addon declared in `replacesStages`, nothing else |
| `fromDocument(PipelineDocument)` | Nodes from a pipeline document |
| `anchors`, `named(name)`, `anchorNamed(name)`, `nodesAt(anchor)`, `providerOf(step)` | Lookups |

Refused: a step name outside the namespace (`PluginException`), a name
already taken or a built-in step added again (`NameTakenException`, naming
the name and its owner), a `needs` nobody registered (`ArgumentError`).

Every registration returns at once. Cancelling one takes the node out and
calls its `dispose` once no frame in flight can still be using it.

`RenderStep(name, {passes, passPrefix, needs, switchOff, isOn})` is one
switch over the frame. `isOn` and `switchOff` take one `RenderStepContext`
(`settings`, and inside a frame its `views`, `device` and `quality`), which
can gain members in a minor; `switchOff` returns the settings with the step
off. `RenderStepAddon` (a `Flutter3dPlugin` base) is how
`flutter3d_post` ships each effect: `provides`, `adds`, `settings`.

**Taking over what the engine draws is declared, and nothing else is
taken.** A plugin from outside the engine provides one of the engine's
steps only as a `RenderStepAddon` that lists it in `replaces`, and hands
the renderer a stage under an engine name (`Pbr`, a shadow pass's) only
when it lists the name in `replacesStages`; either puts
`PluginPermission.replace` in the addon's manifest, and a manifest without
it is refused. Everything else such a plugin adds stays in its namespace:
its libraries answer `<namespace>__…` stages only, a resource a node it
placed declares at run time (`FrameResources.declare`) is held to the
namespace as `FrameGraphBuilder.create` is, and a contributor it did not
add it cannot take out. The engine's own plugins and the application are
not held to this.

```dart
const RenderStep softGlow = RenderStep(
  'glow.soft',
  needs: <RenderStep>{RenderStep.bloom},
);

void renderStep(PluginHost host, FullscreenEffect effect) =>
    host.registry<RendererSteps>()
      ..addStep(softGlow)
      ..addNode(effect, at: RenderAnchor.afterBloom, step: softGlow);
```

### Nodes

| Type | What it is |
|---|---|
| `RenderNode` (`abstract base`) | A frame graph node: `name`, `setup(FrameGraphBuilder)` (`read`, `readIfProduced`, `write`, `create`, `keep`, `place`), `execute(RenderFrame)`, `defaultAnchor`, `isActive`, `isSupported`, `isReady` (false while what it runs with loads: `PassSkip.pending`), `viewRuns` (`ViewRuns.perView`, the default, runs it once per view with `viewIndex` set; `ViewRuns.once`), `dispose()` (called when its registration goes) |
| `ComputePlacementRequest` | What a node that is not a compute step hands `FrameGraphBuilder.place` for compute of its own: the renderer's placer loads its kernels where the hardware layer says, the node is pending meanwhile, and `RenderFrame.placement` is then a `ComputeNodePlacement` (`site`, `stage(kernel)`) |
| `FullscreenEffect` | A full-screen stage: `.overlay(...)`, `.present(...)`, and `FullscreenEffect.material(materials, stage, {name, shader, parameters, ...})` for a stage written in the material language, bound at its source's defaults (`parameters`), reading the surface buffer when its source reads `sceneDepth` (`readsSurface`) |
| `ComputeStep` (`abstract base`) | `kernels` (`ComputeKernel`s in the kernel language, `kernelLanguageVersion` 2), `record(ComputeContext)`, `prepare(device)`, `site` (where the hardware layer put it, a `ComputeSite`); a step nothing can run is a `ComputePlacementException` (`refusal`) and is not run. A step asks for no placement |
| `FieldUpload` | A host field carried into the frame as a 3D texture or a storage buffer (`residence`); `refusal` is a `FieldResidenceException` |
| `PassContributor` (`abstract base`) | Draws into the scene pass: `encode(ContributorFrame)`, `boundsFor(view)`, `order`, `readsSceneDepth`, `isOverlay` |
| `DrawListHook`, `SkinningHook`, `LodPolicy`, `PacingPolicy`, `QualityPolicy`, `ShadowTechnique` | Through `RenderHooks`, each a registration withdrawn with its plugin: keep or sort draws (`DrawListContext`), skin claimed meshes (`SkinningContext`, writing `FrameResourceIds.skinnedVertices`), choose LOD levels, hold a frame (`addPacingPolicy`), choose a quality row (`addQualityPolicy`, asked by an `AdaptiveQuality` handed the hooks), draw a shadow filter named after the technique (`addShadowTechnique`, `techniqueFor`). Several of a kind chain in dependency order — the application's first, then each plugin's in install order — the first to answer deciding and `null` passing to the next |
| `SceneBindingSpec` | Through `SceneBindings.add`: a published component drawn as a node of a `SceneNodeKind`, with its fields mapped to material parameters, `interpolation` and `lifetime` |

**A node that throws is quarantined, and the frame goes on.** The rest of
the frame is drawn; from the next one the node is left out as
`PassSkip.failed`, with `SkippedPass.failure` (a `NodeFailure`) naming it,
the plugin that placed it and what it threw, and what only read its output
is culled. `FrameResult.nodeFailures` lists the failures of the frame they
happened in, which a debug build hands to `FlutterError.reportError`.
Switching the plugin off and on places the node again. The engine's own
passes still end the frame they throw in.

`ComputeContext` holds `device`, `site`, `frame`, `step`,
`stage(kernel)`, `beginPass()`, `isOnFrameDevice`. `ContributorFrame`
extends `FrameContext` with the pass `encoder`, `viewProjection`, `lights`
and `sceneDepth`. The renderer's extension API is in scene space
throughout ([three spaces](../../docs/CONTRACTS.md#three-spaces)).

### Frame resources and their encodings

A node or a full-screen stage reads the frame's resources by name
(`FrameResourceIds`). Their encodings are part of the contract and frozen
within 1.x: a minor may add a resource, never change what the channels of
one hold.

| Resource | What it holds |
|---|---|
| `hdr_color` | The scene's light, linear, unbounded and before exposure, in the renderer's light scale: one unit is `FrameContext.nitsPerHdrUnit` nits (1 843.2). Alpha is not read |
| `surface_buffer` | `rg` the world normal of the nearest opaque surface, octahedral-encoded; `b` its perceptual roughness; `a` its depth along the view axis in meters. All zero where nothing was drawn. Read it nearest |
| `velocity` | `rg` the on-screen motion since the last frame, now minus then, in UV units; zero where nothing was drawn |
| `frame` | The finished picture, display-referred sRGB after tone mapping |

The other ids (`shadow_map`, `ao`, `bloom`, `depth_pyramid`, `object_ids`,
`skinned_vertices` and the rest) name resources a node may order itself
against. The full table is in
[frame resources a stage reads](../../docs/CONTRACTS.md#frame-resources-a-stage-reads).

**What grows in 1.x.** New anchors (an anchor keeps its place in the
order), resources, node kinds, hooks and members of the contexts. The
shader ABI only grows: a stage, a block member or an offset recorded at
1.0.0-rc.1 is never removed or moved
([the shader ABI](../../docs/CONTRACTS.md#the-shader-abi)).

## Custom materials and lit models

A material of a plugin's own is written in the material language
(`.f3dmat`); the language itself is described in
[the material language](https://flutter3d.pleion.dev/reference/material-language/).
What a plugin relies on:

**Versions.** The first line may be `f3dmat <N>`; none is version 1. A
build reads every version up to `materialLanguageVersion` (3) and refuses
a newer one with the version that reads it. Version 2
(`materialLanguageStagesVersion`) added the `state`, `vertex`, `ambient`
and `composite` blocks, the `fullscreen` and `compute` kinds, the scene
inputs and a material's own blocks and textures; version 3
(`materialLanguageUpdatesVersion`, `materialLanguageVariantsVersion`) added
a material's own version and `updates`, the instanced and lightmapped
halves of a `vertex` block, `lighttype`, and the light row in a `light`
block.

**`since`.** Each input carries the version it arrived in
(`MaterialInput.since`) and each builtin too (`materialBuiltinVersions`). A
name is taken from a declaration or a `let` only where the source's version
has it, so a source of an older version keeps every name it had.

**Reserved block names.** `materialReservedBlockNames` is every uniform
block the engine's shaders declared at 1.0.0, frozen; a block the engine
adds later is named `F3d…` or `…Info`, a shape a material's block was never
allowed. So `uniform(Hair) vec3 tint = …;` stays a material's to use.

**The slot table.** A lit model may bind blocks and textures of its own:
`uniform(Hair) …` for a member of a block, `texture fur;` for a texture.
Its `MaterialSlotTable` lists them in a fixed order: `MaterialParams` first
when it has a uniform of its own, then its blocks in the order first named,
then its textures in declaration order (`MaterialBlockSlot`,
`MaterialBlockMember` with `offset`, `size` and `defaultValue`,
`MaterialTextureSlotEntry`). Every slot is bound on every draw: a member
the material leaves unset is bound at the default its source declares, and
a texture nothing names at a white texel, on every backend. On WebGPU the
material's own bindings follow the engine's, numbered when the build packs
the stage; at run time a material with blocks or textures of its own is
refused there and built from `assets_src/` instead.

**`lightKind`, `lightParams`, `lighttype`.** From version 3 a `light` block
reads `lightKind` (the light's type code) and `lightParams` (the row's last
`vec4`). A material names a plugin's light type with
`lighttype tube = acme.tube;` and reads `tube` as that type's code; the
renderer fills it (`LightTypes.codeNamed`, `LightingModel.lightTypeMembers`),
minus one where no hook packs the type. Such a block gathers the plugin's
lights through the material's own loop with no falloff or shadow of the
engine's.

**Injecting into the standard model.** From version 3, `lighting
standard;` makes a material the engine's own metal-rough model
(`MaterialProgram.isStandard`) with three injection points of its own: a
`surface` block that rewrites the surface before any light
(`materialSurfaceOutputs`, written with `out`), a `light` block that reads
the model's answer to each light as `standard`
(`materialStandardLightInput`) and returns its own, and `lighttype`
declarations that let a plugin's light type into the model's light loop as
a point at its row, where the engine's stages skip it. It has no
`fragment`, `ambient` or `composite` block. The stage is `lighting/pbr.frag`
with `F3D_SURFACE_HOOK`, `F3D_LIGHT_HOOK` and `F3D_LIGHT_TYPE_HOOK`
switched on and `ShadeSurfaceHook`, `ShadeLightHook` and `F3dLightTypeHook`
defined by the material; it binds what `LightingModel.pbr` binds, and with
no injection it draws as the built-in PBR does. A plugin that only wants a
term added to PBR writes this, not a whole lit model.

**Budgets.** One stage binds at most 16 textures, 16 samplers and 12
uniform blocks, the engine's and the material's together
(`MaterialStageBudget`); a lit model's own share is 3 textures and 4
uniform blocks (`MaterialParams` included) in every 1.x
(`MaterialStageBudget.materialTextures`, `materialUniformBlocks`). Every
build and every `RuntimeShaders` call counts each stage from the GLSL it
emitted and refuses one over budget, naming the stage and the count
(`MaterialStageBudget.problemOfGlsl`).

**`materialVersion` and `updates`.** From version 3, `material Hatch
version 3 { … }` gives a material a version of its own (the program's
`version`, `firstMaterialVersion` by default), and an `updates` block says
how an older instance's values reach it: `rename a -> b`, `scale a
<factor>` or `remove a`, under the version each leads to.
`MaterialProgram.lift(values, from:)` applies them, as `MaterialUpdate`s.

```text
f3dmat 3
material Hatch version 3 {
  uniform vec3 inkColor = vec3(0.1);
  uniform float roughness = 0.5;
  updates {
    2: rename ink -> inkColor;
    3: scale roughness 0.5;
  }
  light { return albedo * step(0.5, nDotL); }
  fragment { return vec4(lit, alpha); }
}
```

**Registering.** A compiled lit model becomes one a material file may name
through `host.registry<LightingModels>().register(model)`;
`LightingModelAddon` is the plugin base for shipping models with their
stages (`ToonLightingAddon` is one). A data plugin's `materials` section is
compiled at run time by `RuntimeShaders` where the backend compiles at run
time, and its `statuses` and `refusals` say what was refused and why. A
backend from outside compiles the language through a `MaterialCompiler`
(`MaterialCompilerRegistry`, by backend id).

**What grows in 1.x.** New language versions with new inputs, builtins and
blocks (each with its `since`); new members of a slot table. The reserved
block names, the budget's material share, the slot order and the vertex
layouts a stage reads are frozen.

## Custom light types

A light type of a plugin's own is a `LightType.custom(name, base:)`, named
in the namespace and based on the built-in shape it is closest to, packed
by a `LightTypeHook` registered with `host.registry<LightTypes>()`:

| Member | What it is |
|---|---|
| `LightTypeHook.type` | The type it packs |
| `LightTypeHook.pack(LightPackContext)` | Fills the light's row; by default the row stays as the base packed it |
| `LightPackContext` | `light` (`LightNode`), `row` (16 floats: position and type code, color and intensity, direction and range, the base's cone or half-height with a free component), `code` |
| `LightTypes.register(hook)` | Gives the type a code from `LightTypes.firstPluginCode` (16) up, in registration order per renderer |
| `LightTypes.codeOf(type)`, `codeNamed(name)`, `hookOf(type)` | Lookups |

Refused: a built-in type, a type another hook packs (`ArgumentError`), a
name outside the namespace (`PluginException`). The engine's lit stages
skip a light whose code is 16 or more; a lighting model of the plugin's own
reads it through `lightKind` and `lightParams`. A custom type with no hook
registered is drawn as its base. Codes are handed out per renderer, so a
material names types, never codes.

```dart
const LightType tube = LightType.custom('lamps.tube', base: LightType.area);

final class TubeHook extends LightTypeHook {
  const TubeHook();

  @override
  LightType get type => tube;

  @override
  void pack(LightPackContext context) => context.row[15] = 0.02;
}
```

**What grows in 1.x.** Engine light types take codes below 16. The row's
layout and the codes 0 to 3 are frozen ([light
codes](../../docs/CONTRACTS.md#light-codes)).

## The editor and MCP tools

Tooling plugins usually declare `touches: PluginTouches.tooling`, so a game
ships without them and they cannot reach the simulation.

### Hints

`EditorHintRegistry` (`package:flutter3d_plugin_api/editor.dart`, filled by
`EditorHints` in `flutter3d_editor_core`) says how the inspector shows a
plugin's data without the editor depending on the plugin:
`addComponent(ComponentHints)`, `addEntityKind(EntityKindHints)`,
`addMaterial(MaterialHints)`. A `FieldHint(key, kind, ...)` describes one
field: `FieldKind` (`number`, `integer`, `toggle`, `choice`, `color`,
`vector3`, `text`, `asset`, `entity`, an open set), `min`, `max`, `step`,
`unit`, `choices`, `suffixes`, `defaultValue`, `readOnly`; `refusalOf(value)`
says why a value is not one, and `jsonSchema` is what an MCP tool's schema
uses.

### `EditorPieces`

| Member | Adds | Published as |
|---|---|---|
| `addComponent(EditorComponent)` | An inspector component: `kind`, `title`, `piece`, `keys`, `defaults`, `types`, `hints` | `<namespace>.<kind>` |
| `addCommand(name, CommandReader, {description, arguments, hints})` | A `PluginCommand` (a `DocumentCommand`) read back from its arguments; the editor's MCP server offers it as a tool with `arguments` as its input schema and `hints` as its `ToolHints` — only when the plugin declares `PluginPermission.tools`, and as `ToolHints.destroys` when it gave no hints | `<namespace>.<name>` |
| `addGizmo(name, EditorGizmo)` | Marks drawn over a level (`marksFor(GizmoContext)` to `GizmoMark.box`, `.cage`, `.ball`, `.line`) and the command a drag makes (`dragged(GizmoDrag)`) | `<namespace>.<name>` |
| `addImporter(name, EditorImporter)` | A file kind brought into a project: `label`, `suffixes`, `import(ImportRequest)` to an `ImportResult` (`files`, `commands`, `notes`) | `<namespace>.<name>` |
| `addPaletteEntry(PaletteEntry)`, `addAssetEntry(name, entry)` | A palette entry for an entity type; an asset browser entry | |

Refused (`ArgumentError`): an empty or dotted name, one of the editor's
own, one another owner registered, naming it. `EditorPanels.addPanel(EditorPanel)`
(`flutter3d_editor_widgets`) adds a panel whose `builder` is handed an
`EditorPanelContext`: `context`, `document`, `selection`, `path`,
`run(command)`, `say(sentence)`.

```dart
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

void editor(PluginHost host) => host.registry<EditorPieces>().addComponent(
  const EditorComponent(
    kind: 'buoyancy',
    title: 'Buoyancy',
    defaults: <String, Object?>{'density': 600.0},
    types: <String>{'boat'},
    hints: <FieldHint>[
      FieldHint.number(
        'density',
        min: 1.0,
        max: 20000.0,
        unit: Unit.kilogramPerCubicMeter,
      ),
    ],
  ),
);
```

### MCP tools

`host.registry<McpTools>()` (`package:flutter3d_plugin_api/tools.dart`, which
`flutter3d_mcp`'s `kit.dart` re-exports; a plugin that brings tools depends
on this package alone):

| Member | What it does |
|---|---|
| `addTool(ToolSpec, ProjectToolRun)` | A tool published as `<namespace>.<name>` (`McpTools.published`), name at most `maxNameLength` (128) |
| `declareSchemaVersion(version)` | The schema version the plugin's tools announce |
| `tools`, `named(name)`, `schemaVersions`, `listen` | What the project server lists |

`ToolSpec` has `name`, `description`, `inputSchema`, `outputSchema`,
`hints` (`ToolHints.reads`, `.writes`, `.destroys`; `readOnly`,
`destructive`, `idempotent`, `openWorld`) and `meta`. A `ProjectToolRun` is
handed a `ToolCall` (`name`, `arguments`) and answers a `ToolResult`
(`content`: `ToolImage`, `ToolResource`, `ToolResourceLink` and the rest;
`structuredContent`; `isError`). A tool that refuses answers a result with
`isError` set, which the agent reads. The application's own tools are
refused a reserved area as their namespace too.

```dart
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

void tools(PluginHost host) => host.registry<McpTools>().addTool(
  ToolSpec(
    name: 'sink',
    description: 'Sinks the boat by name.',
    inputSchema: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'boat': <String, Object?>{'type': 'string'},
      },
      'required': <String>['boat'],
    },
    hints: ToolHints.destroys,
  ),
  (ToolCall call) => ToolResult.text('sank ${call.arguments['boat']}'),
);
```

The engine's servers' tools follow the same semver as the Dart API: new
tools and optional arguments in a minor, a renamed tool kept as an alias
until the next major, each server's schema snapshotted in `api/*.mcp`.

**What grows in 1.x.** New editor registries and members, new field kinds,
new `ToolContent` kinds; `ToolCall` and the contexts gain members.

## Plugins loaded at run time

`flutter3d_plugin_runtime` reads plugins while the game runs, each a
`Flutter3dPlugin` with a manifest, installed through the same host and
switched at a step boundary like any other. It depends on
`flutter3d_plugin_api` alone.

### Permissions

A run-time plugin gets nothing it is not handed. A permission it uses
(`PluginPermission.files`, `network`, `tools`) must be declared in its
manifest and granted by the application:
`DataPluginLoader(grants: PluginGrants([...]))`. Declared and not granted
is a refusal when the plugin is loaded (`PluginGrants.refusalOf(manifest)`);
used and not declared is a `PermissionException` at the use.
`PluginGrants.none` reaches the plugin's own files and the world's fields
only.

### Data plugins and `.f3dplugin` version 4

A data plugin is a `.f3dplugin` JSON document (`f3d.plugin`,
`DataPluginDocument.formatVersion` 4), read by
`DataPluginLoader.load(text, source)` into a `DataPlugin`:

```json
{
  "format": "f3d.plugin", "version": 4, "requires": [], "generator": "flutter3d",
  "manifest": {"id": "gusts", "apiVersion": "1.0", "touches": "simulation"},
  "phases": [{"name": "weather", "kind": "step",
              "after": ["physics"], "before": ["fields"]}],
  "events": [{"name": "gust"}],
  "wasm": [{"module": "gusts.wasm", "system": "blow", "phase": "weather",
            "fields": [{"name": "wind", "write": true, "unit": "m/s"}],
            "events": ["gust"]}]
}
```

| Key | Read by | What it holds |
|---|---|---|
| `manifest` | the runtime | A `PluginManifest` |
| `phases` | the runtime | `DataPhase`s (`name`, `kind`, `after`, `before`), filed under the plugin: `weather` is the loop's `gusts.weather`, and so is `weather` wherever the document orders against it |
| `events` | the runtime | `DataEventDeclaration`s, declared as `<id>.<name>` and published as `PluginDataEvent` |
| `wasm` | the runtime | `WasmSystemSpec`s (below) |
| `wasmRender` | the runtime | `WasmRenderSpec`s: render modules of ABI 3, each driving one of the document's `renderSteps` (below) |
| `expressions` | the runtime | `ExpressionSystemSpec`s in the expression language; read and kept, and a plugin that brings one is refused at install, naming the systems, until this build evaluates the language |
| `entityKinds` | `flutter3d_sim`'s `entityKindsSection` | Entity kinds as `DataEntityKind` |
| `materials`, `renderSteps`, `bindings`, `pipeline` | `flutter3d_core`'s `renderDataSections` | Materials in the material language, render steps (`DataRenderStep`, `"shaders": {"material": "fog.f3dmat"}`), scene bindings, pipeline nodes |
| `lightTypes`, `vertexLayouts`, `lodTables` | `flutter3d_core`'s `renderDataSections` | Light types of the plugin's own (`DataLightType`: `name`, `base`, up to four `params` in the row's last `vec4`), vertex layouts held to the engine's attributes (`DataVertexLayout`), levels of detail by distance for the groups named `<id>.<table>` (`DataLodTable`) |
| `effects` | `flutter3d_particles`' `effectsSection` | Particle effects |
| `physicalMaterials`, `materialPairs` | `flutter3d_matter`'s sections | `PhysicalMaterial` bodies and pairs, held to SI and the namespace when read; the document `requires` `f3d.physicalMaterials` |

Version 2 put the envelope in place of `"f3dplugin": 1`; version 3 put
`expressions` in place of `scripts`; version 4 files a phase under the
plugin. A 1.x engine reads all of them, lifting older documents, and keeps
keys it does not know in `extra`. A section no registered reader takes is
kept and written back, and `DataPlugin.notes` says it was not read; a
document that `requires` a section nobody registered is refused rather
than installed without it.

**`DataSection`** is how a package reads a section of its own:

| Member | Handed | Does |
|---|---|---|
| `name` | | The document key |
| `requirement` | | The `requires` entry a document with the section names, or `null` |
| `read(DataSectionRead)` | `written`, `context` | Parses the section, when the document is read |
| `write(section)` | the parsed section | Writes it back |
| `resources(section)` | the parsed section | The files it names, which the loader fetches |
| `load(DataSectionLoad)` | `section`, `context` | Resolves it once its files are read |
| `install(DataSectionInstall)` | `section`, `host`, `context` | Registers it through the plugin's host |

`DataSectionContext` gives `plugin`, `textOf(path)`, `eventName(event)`,
`numbersOf(event)` and `note(sentence)`. `DataSections` is the registry;
`DataSections.runtimeKeys` are the keys only the runtime reads.

### Wasm systems

A Wasm system is a step system compiled by somebody else's toolchain,
stepped the same way on every platform.

**The ABI.** Numbered apart from the plugin API: a host runs
`wasmPluginAbiMin` (1, through 1.x) to `wasmPluginAbiMax` (3), and
`wasmPluginAbi` is what a module written today says. A step module
exports `f3d_abi()` returning its ABI and `f3d_step(i32 step, i32 dt)`,
and imports from `f3d`:

| Import | Since | What it does |
|---|---|---|
| `field_len(field)` | 1 | How many values field `field` holds |
| `field_get(field, index)` | 1 | A value, in the field's fixed point (Q16.16 by default) |
| `field_set(field, index, value)` | 1 | Writes one, for a field declared `write` |
| `publish(event, a, b)` | 1 | Publishes event `event` with two values |
| `field_frac(field)` | 2 | The fraction bits field `field` crosses with |

The indices are the order of the spec's `fields` and `events`.
`wasmImportSince` records the ABI each import arrived in, and
`wasmAbiRefusal(abi, imports)` refuses a module that claims an ABI outside
the range, or imports something newer than the ABI it claims. 32-bit
integers only; no I/O.

**Render modules (ABI 3).** A module the document declares under
`wasmRender` is a render module (`WasmModuleKind.render`), decoded as
one: it may compute in `f32`, exports `f3d_abi()` (3 or later) and
`f3d_render_node(i32 frame, i32 view)`, needs no `f3d_step`, and imports
the render commands only, each since 3:

| Import | What it does |
|---|---|
| `param(parameter, component, f32 value)` | Sets one component of a declared parameter, from this frame on |
| `param_floats(parameter, ptr, len)` | Sets a parameter from `len` bytes of floats at `ptr` in the module's memory, copied during the call |
| `draw()` | The step draws this frame |
| `time() -> f32` | The frame's time, in seconds |
| `view_size(axis) -> i32` | The view's width (0) or height (1), in pixels |
| `light_code(light) -> i32` | The code a declared light type is packed with, -1 for none |

`WasmRenderSpec`: `module`, `step` (one of the document's `renderSteps`,
written in the material language), `parameters` (the stage's uniforms, by
ABI index), `lights` (light types by ABI index; a bare name is the
plugin's own), `limits`, `sha256`. The module runs in an instance of its
own (`WasmRenderNode`, a `RenderProgram`), outside the run's save and
digest, and only on an engine that draws; its fuel is counted per frame
(`WasmLimits.fuelPerFrame`), and a trap switches its step's node off with
the plugin named. The renderer and the runtime meet in this package:
`RenderProgram` and `RenderProgramFrame`, which a render step section asks
for with `DataSectionContext.renderProgram`. A step module that exports a
function named `f3d_render_node` is not read for it. The sample is
`flutter3d_plugin_runtime`'s `example/plugin/acme_pulse.f3dplugin`, its
module built from `pulse.wat` by `wat2wasm`.

**The spec.** `WasmSystemSpec`: `module`, `system`, `phase`, `after`,
`before`, `fields` (`WasmFieldSpec`: `name`, `write`, `unit`, `fraction`
bits from 0 to 30, 16 by default; a field with other than 16 needs an ABI 2
module), `events`, `limits`, `sha256`.

**A module from a URL is pinned.** A `module` that is an `https:` URL
needs the `network` permission and a `sha256`, the SHA-256 of the bytes as
64 lowercase hexadecimal digits; the loader refuses a module without one,
and bytes that hash to anything else, with a `WasmException` naming both.
A module of the plugin's own directory is not checked.

**Metering.** `WasmLimits` (`memoryPages` 16, `fuelPerStep` 1 000 000,
`callDepth` 64, and for a render module `fuelPerFrame` 200 000) is counted
in instructions executed (fuel), never in time,
so a module runs out at the same instruction on every machine and in every
replay. A module that traps (`unreachable`, a division by zero, a read
past its memory, a budget spent) stops with a `WasmTrapException`, and the
bus carries `WasmTrapped` (`wasm.trapped`); a module that cannot load is a
`WasmException`.

**Runtimes and determinism.** `WasmRuntime.interpreter` is plain Dart,
metered, on every platform, and the runtime a replay is held to;
`browserWasmRuntime()` is the browser's own WebAssembly, not metered. A
runtime that counts no fuel is refused a simulating module under a
bit-exact profile. A module's saved state has one shape whichever runtime
wrote it: `pages`, `memory` (base64), `globals` (the exported mutable
globals by name), and `internal` for what only the interpreter reaches,
kept out of the digest. `WasmRuntime` and `WasmInstance` are `abstract
base`: a runtime from outside implements `instantiate(WasmInstantiation)`,
`step(WasmStep)`, `save`, `restore`, `fuelUsed`, `isMetered`.

`WorldFields` (`ListWorldField`, `WorldField`) are the named arrays a
module's fields resolve to; `Fixed16` and `FixedPoint` convert.
`installWasmSystem(host, spec, module)` installs one from Dart, and
`WasmPlugin` is a plugin of one module.

**What grows in 1.x.** New sections (a reader registered by the package
that owns it), new document versions, new Wasm imports and exports with
the ABI they arrived in, new render commands. A module written for ABI 1
runs on every 1.x engine: the minimum stays 1.

## What an outside plugin may and may not do

| May | May not |
|---|---|
| Register any name in its own namespace, in any registry the engine hands it | Register a bare name, an `f3d.` name, another plugin's namespace, a reserved area, or an engine namespace |
| Read the world, every field (read-only unless it declared it) and every published state | Write a field it did not declare, or any field while it claims `view` or `tooling` |
| Add step phases, systems, subsystems and step subscribers when it touches the simulation | Add any of those as a `view` or `tooling` plugin; add render steps, nodes or stages as `tooling` |
| Keep state in the world, in components and in snapshot parts | Keep simulation state where a snapshot does not reach it |
| Compute with float32 arithmetic and `Portable`'s functions, seeded randomness and the step's `dt` | Read a clock, an unseeded `Random`, a `dart:math` transcendental where `Portable` gives one answer, or iterate a hash order that differs between runs |
| Declare a budget in `extra['budget']` (`stepMicroseconds`, `eventsPerStep`) and keep it | Exceed the stage binding budget, the Wasm limits, or the budget it declared |
| Ask for permissions in its manifest when loaded at run time | Use one it did not declare or was not granted |
| Move its own `simulationVersion` when what it computes changes | Change what it computes under the same `simulationVersion` |

`flutter3d_lints` carries the step rules as an analyzer plugin.
`EngineLoop(determinismCheck: DeterminismCheck(...))` runs each step twice
in a debug build and names the plugin whose system made them differ.
`package:flutter3d_conformance/plugins.dart` runs the plugin suite
(`checkPluginConformance`, `pluginCheckNames`: `plugin.manifest`,
`plugin.switch`, `plugin.names`, `plugin.determinism`, `plugin.backends`,
`plugin.budget`, `plugin.materials`), and
`earnsBadge` says whether a plugin may show the conformance badge: every
check passed on every declared backend, with a world given to the
determinism check and a budget declared.

## The worked example: `examples/outside_plugin`

`examples/outside_plugin` is a plugin written as somebody outside the
repository writes one: it depends on `flutter3d_plugin_api`,
`flutter3d_fields`, `flutter3d_sim` and `flutter3d_core`, imports no `src/`
library (the structure rule `an outside example reaches only the published
API` reads every file), and registers every name under `outside`. Where two
bodies press on each other, the contact warms the air around it. It uses
each seam this document describes:

| Seam | In the example |
|---|---|
| A quantity on a body's matter state | `outside.warmth`, written into `MaterialStateComponent` with `MatterState.withQuantity` |
| Contact events | `host.events.onStep<ContactEvent>('outside.warming.contacts', ...)` |
| A field | `heatField`, `outside.heat`: kelvin in an 8 by 4 by 8 grid of half-meter cells, written by the simulation, read by a frame node and a sound |
| A subsystem | `Warming`, `outside.warming` version 1, writing the field and the quantity, `switchedOnBy` the plugin's own profile |
| A profile of its own | `warmingProfile`, `outside.warming`: bit-exact, like the default |
| A snapshot part | `outside.pending`, the heat heard and not yet laid down |
| A budget | `extra: {'budget': {'stepMicroseconds': 2000}}` |
| The frame | `OutsidePlugin.upload` makes a `FieldUpload` from the published field, placed with `RendererSteps.addFieldUpload` |

```dart fragment
// `OutsidePlugin.install`, with `Warming` and `heatField` its own.
@override
void install(PluginHost host) {
  host.registry<FieldRegistry>().declare(heatField);
  final subsystems = host.registry<SubsystemRegistry>()..register(warming);
  if (!subsystems.running.any((d) => d.id == Warming.id)) return;
  host.registry<SnapshotRegistry>().add(warming.pendingPart);
  host.events.onStep<ContactEvent>(
    '${Warming.id}.contacts',
    (Delivered<ContactEvent> delivered) => warming.heard(delivered.event),
  );
}
```

Under the default profile the solver is registered and runs nowhere, the
plugin hears nothing, and the default simulation's digests are the ones
recorded before fields and subsystems existed
(`test/default_simulation_test.dart`). `test/conformance_test.dart` holds
it to the plugin suite under both profiles, on no backend and on each of
the four by name. `test/tooling_plugin_test.dart` shows what a `tooling`
plugin is refused. The example's [README](../../examples/outside_plugin/README.md)
says how each backend's conformance suite holds the field's residence.

## Starting a plugin

```bash
dart run flutter3d_build:create plugin --kind <kind> --name <name>
```

or `flutter3d create plugin --kind <kind> --name <name> [--target <dir>]`;
`flutter3d create --list` prints the kinds:

| Kind | Writes | Touches |
|---|---|---|
| `render-step` | A full-screen pass at a render anchor, switched like a built-in step | view |
| `effect` | Something seen when an event arrives, aged once a displayed frame | view |
| `genre` | A step phase of its own between physics and fields, with a rule that scores and an event it publishes | simulation |
| `element` | A field of the world and a subsystem that steps it in the `fields` phase with `Portable` arithmetic, saved and restored with the run | simulation |
| `tool` | An MCP tool published under the plugin's id | tooling |
| `backend` | A graphics backend from `examples/flutter3d_backend_null`; not a `Flutter3dPlugin`, opened rather than installed | |

Each plugin template writes a package with the `flutter3d_plugins:` marker
in its pubspec, a plugin class with its manifest, a test that installs it
into an `EngineLoop`, and a test that runs the conformance suite.
`dart run flutter3d_build:plugin_mcp` serves the same as MCP tools for an
agent. A package marks its plugins for discovery:

```yaml
flutter3d_plugins:
  plugin: package:wind/wind.dart#WindPlugin
```

## What grows in 1.x

- **Added in a minor, with `PluginApiVersion`'s minor moving:** registries,
  members of a registry (with default bodies), members of the host and of
  every context object, new hooks (each handed one context object), new
  open-set values (`PluginTouches`, `PluginPermission`, `FieldKind`,
  `FieldResidence`, `ContactPhase`, `BusChannel`), new `.f3dplugin`
  versions and sections, new Wasm imports and ABIs, new material language
  versions, new anchors and frame resources.
- **Frozen within 1.x:** the namespace rules and the reserved areas,
  namespaces and schemes; the meaning of a manifest field; the shape of
  every hook (a context object, or the one value `hookValueParameters`
  allows); the frame resources' encodings; the shader ABI's recorded
  lines; the reserved block names and the material share of the binding
  budget; the light row and the plugin light codes; the Wasm imports of
  ABI 1 and 2 and the saved-state shape.
- **A plugin written against `PluginApiVersion(1, 0)` installs on every
  1.x engine.**
