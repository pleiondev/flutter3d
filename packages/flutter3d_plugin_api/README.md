# flutter3d_plugin_api

What a flutter3d plugin is written against. A plugin depends on this package
and on nothing of the engine's, so the engine can change underneath it
without the plugin changing.

- `Flutter3dPlugin` is one plugin: a `PluginManifest` and an `install`.
- `PluginManifest` says what the plugin is: its id, the plugin API version
  it was written for, the plugins it depends on, the backends it runs on,
  whether it touches the simulation or only the view, and the permissions it
  asks for. Read from a document, it keeps the keys it does not know.
- `PluginHost` is what `install` is handed: the loop (`LoopRegistry`), the
  event bus (`EventRegistry`), and typed slots for render steps, decoders,
  entity kinds, editor pieces and MCP tools that the engine's packages fill.
- `PluginManager` is the host itself. The engine owns one; a plugin never
  sees it.
- `PublishedState` and `PublishedEvent` are what a step publishes for the
  view, and `SimulationVersion` names the simulation a run was played by.

The loop and the bus are implemented by `EngineLoop` in `flutter3d_sim`,
which also declares the handle a view holds of a simulation
(`SimulationHandle`) and the named questions a plugin answers
(`SimulationQueryRegistry`).

## What the contract is, and what it is not

This package is what a plugin is, what it is handed and what it publishes,
and nothing else. Every type it declares is reachable from
`Flutter3dPlugin`, `PluginHost` and `PluginManager`, and a structure rule
holds that, with a budget on how many types there are.

- **The foundation is underneath, re-exported.** `Flutter3dException` and
  its four families, `WorldPosition`, `LinearColor`, `Issue`, the file
  envelope (`FormatSpec`, `FormatDocument`) and `Registration` are declared
  in `flutter3d_foundation`, this package's one dependency, because the
  hardware layer, the shaders and the backends need them and not the
  contract. This package re-exports them under the same names, since the
  contract's signatures name them, so a plugin imports one library.
- **A registry slot is declared by the package that fills it.** The engine
  looks a registry up by its type, so the type lives where it is
  implemented: `DecoderRegistry` in `flutter3d_core`, `EntityKindRegistry`
  in `flutter3d_sim`, `EditorRegistry` in `flutter3d_editor_core`,
  `McpToolRegistry` in `flutter3d_mcp`. Until 1.0.0-rc.1 they were empty
  markers here.

## A plugin

```dart
final class WindPlugin extends Flutter3dPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'wind',
    apiVersion: PluginApiVersion(1, 0),
    dependsOn: <String>['heat'],
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem(
      'wind.push',
      LoopPhase.fields,
      (step) => _push(step.dt),
      after: const <String>['heat.spread'],
    );
    host.events.onStep<Gust>('wind.gusts', (gust) => _record(gust.event));
  }
}
```

Everything `install` registers is withdrawn when the plugin is switched off,
so most plugins never write `uninstall`.

## The loop

Step phases run inside every fixed step: `input`, `movers`, `physics`,
`fields` (heat, water, wind and fire; it was `elements` until 1.0.0-rc.1,
and a loop still finds it by that name), `rules`, `publish`. Frame phases run once a displayed frame
after the steps: `animate`, `audio`, `camera`, `render`, `ui`. A plugin adds
its own phases between them, and its systems inside them, ordered by named
`after` and `before` constraints. Where the constraints leave a choice,
registration order decides: the application's own first, then each plugin's
in install order. A cycle is a `ConstraintCycleException` that names every
member of it.

A plugin whose manifest says `touches: PluginTouches.view` may not add to a
step phase or subscribe to the step channel. That is what lets the engine
leave its switches out of what a replay has to reproduce.

## The bus

Events are `BusEvent` subclasses with a stable `name`, and they write their
identifying fields in `digestInto`. They travel on two channels:

- **The step channel.** Events are collected during a fixed step and handed
  to step subscribers at its end, on the same turn of the loop. They are
  digested per step, so a replay can say at which step its events parted
  from the recording's.
- **The frame channel.** It carries sound, particles and the interface. A
  step run again on a rollback is marked `resimulated`. The frame channel
  does not show its events a second time; it reconciles them with what it
  already showed, by step and sequence number.

## Render steps and anchors

Every pass the engine draws has an anchor before it and one after it:
`RenderAnchor.beforeShadows`, `afterShadows`, `beforeOpaque`,
`beforeTransparent`, `afterScene`, `beforeBloom`, `beforeTonemap`,
`afterTonemap` and so on to `beforePresent`. There are fifty, listed in frame
order in `RenderAnchor.values`. A plugin puts its pass at an anchor rather
than at a priority number. The nodes at one anchor are ordered by `after`
and `before` constraints, and otherwise by registration order: the
application's first, then each plugin's in install order. An anchor stays
where it is when the passes around it are switched off.

This package names the anchors. The renderer in `flutter3d_core` fills the
`RenderStepRegistry` slot with `RendererSteps`, which knows the renderer's
types, so a plugin that draws depends on `flutter3d_core` too:

```dart
const softGlow = RenderStep('soft glow', needs: {RenderStep.bloom});

@override
void install(PluginHost host) {
  host.registry<RendererSteps>()
    ..addStep(softGlow)
    ..addNode(SoftGlowNode(), at: RenderAnchor.afterBloom, step: softGlow);
}
```

A step added this way is switched like the engine's own. `without` and
`only` switch it off. Switching off a step it needs (here the bloom) takes it
down too, and `FrameResult.skipped` names it and its passes as switched off.
The engine's post steps are scheduled through the same anchors.

The engine hands the renderer's registry to the plugin host:
`EngineLoop(registries: [renderer.renderSteps], plugins: ...)`.

## The other registries

Every slot is filled the way the render one is: by a type in the package that
knows what it registers, scoped to the plugin and withdrawn when the plugin is
switched off. The engine hands each to the host among its registries.

| Slot | Filled by | A plugin adds |
|---|---|---|
| `DecoderRegistry` (`flutter3d_core`) | `ModelDecoders` (`flutter3d_core`), `Decoders` (`flutter3d`) | model and material decoders, `scheme:` asset sources |
| `EntityKindRegistry` (`flutter3d_sim`) | `EntityKinds` (`flutter3d_sim`) | entity kinds a level may name |
| `SimulationQueryRegistry` (`flutter3d_sim`) | `SimQueries`, which `EngineLoop` owns | questions a view asks by name, answered where the world is |
| `EditorRegistry` (`flutter3d_editor_core`) | `EditorPieces` (`flutter3d_editor_core`) | commands (`PluginCommand`), inspector components, palette entries |
| `McpToolRegistry` (`flutter3d_mcp`) | `McpTools` (`flutter3d_mcp/kit.dart`) | MCP tools, published as `<plugin id>.<tool>` |
| `MaterialCatalog` (`flutter3d_matter`) | `EngineLoop` installs one with the built-ins (`f3d.*`) | physical materials, as `<plugin id>.<name>`, and the pairs measured between them |

A registry needs no slot here to be found: `host.registry<T>()` finds any
`PluginRegistry` the engine was given. Behaviour-tree leaves, considerations
and composites come through `BehaviorKindsRegistry` in `flutter3d_sim`.

```dart
@override
void install(PluginHost host) {
  host.registry<EditorPieces>().addComponent(
    const EditorComponent(
      kind: 'buoyancy',
      title: 'Buoyancy',
      defaults: <String, Object?>{'density': 600.0},
      types: <String>{'boat'},
    ),
  );
  host.registry<McpTools>().addTool(sinkTool, _sink); // listed as "boats.sink"
}
```

### Physical materials

A substance a game can name — a liquid a level fills a pool with, a world's
medium, what a collider is made of — is an entry of the engine's
`MaterialCatalog`, from `flutter3d_matter`. The loop installs one holding
the engine's own (`Materials.all`, ids `f3d.*`); a plugin adds its own under
its id, and they go away when it is switched off:

```dart
@override
void install(PluginHost host) {
  host.registry<MaterialCatalog>()
    ..add(const PhysicalMaterial(
      id: 'orchard.plumJam', // refused outside "orchard."
      name: 'plum jam',
      phase: MaterialPhase.liquid,
      mechanical: MechanicalProperties(density: 1300.0, source: 'lab notes'),
      fluid: FluidProperties(viscosity: 30.0, source: 'lab notes'),
    ))
    ..addPair(const MaterialPair('orchard.plumJam', 'f3d.glass',
        contactAngle: 0.6, source: 'lab notes'));
}
```

Every number is SI, every property group names its `source`, and an entry is
refused when `PhysicalMaterial.problems()` finds a number no real substance has
(a density in g/cm³, a temperature in °C) or an id another plugin took. A level
or a world that names a material nobody installed is refused with an
`UnknownMaterialException` that names the plugin it needs. The conformance
suite's `materials` check holds a plugin's entries to the same rules.

Two things are not registries, because they do not run inside an engine. A
build step (`BuildStep` in `flutter3d_build`) runs in the build hook, so a
plugin package exports its steps and the application's `hook/build.dart` names
them: `build(args, buildAssetsWith([WindBaker()]))`. A force field
(`NativeForceField` in `flutter3d_physics_native`) belongs to one physics
world and is added to its `forceFields`; that is where a new joint goes too,
since `NativeJointType` stays closed in the C core.

## Versions

The plugin API has a version of its own, now 1.0. A plugin names the version
it was written for, and the host refuses it with a sentence when the major
differs or the minor is newer than the engine's. The package moves rarely and
breaks only in a major. Every registry and the host are `base` classes, so
a member added later arrives with a default.

## Switching at run time

`enable`, `disable` and `reorder` are checked when asked. Disabling a plugin
another enabled plugin depends on throws, naming the dependent. The change
itself is made at the next step boundary and journalled with its step, and a
run file carries the journal. A replay schedules it and makes the same change
at the same step.

## Discovery

A package marks itself as a plugin in its pubspec:

```yaml
flutter3d_plugins:
  plugin: package:wind/wind.dart#WindPlugin
```

A package with several plugins gives a list of those, and a package of
several libraries can mark each library with the classes it declares, as
`flutter3d_post` marks its six families:

```yaml
flutter3d_plugins:
  plugin:
    light.dart: [BloomAddon, LensFlareAddon]
    shading.dart: AmbientOcclusionAddon
```

`flutter3d_build` writes the application's `lib/plugins.g.dart` from the
dependencies that carry the marker. Its build hook does this on every build,
and `dart run flutter3d_build:plugins` does it by hand. The file defines
`installedPlugins`, which builds a fresh list on each read, and the
application passes it to the engine. A list written in code takes its place.

Depending on a package installs every plugin it marks; `flutter3d_post`
marks twenty-three. An application that wants fewer says so in its own
pubspec, under the same key:

```yaml
flutter3d_plugins:
  exclude:
    - flutter3d_post/motion.dart                  # a whole library
    - flutter3d_post/style.dart#ToonLightingAddon # one class
```

`include:` is the other way round: only what it names is installed, and
`exclude:` is applied after it. Each entry is a package (`flutter3d_post`),
a library as the marker names it, relative to the package's `lib/`, or a
library and a class after `#`. An entry that matches nothing a dependency
declares is printed as a warning by the build and by
`dart run flutter3d_build:plugins`, because a misspelt exclusion would
otherwise leave the plugin installed and say nothing. `plugins --json`
lists what was left out under `excluded`.

## Plugins loaded at run time

A plugin does not have to be compiled in. `flutter3d_plugin_runtime` reads
three more kinds while the game runs, each one a `Flutter3dPlugin` with a
manifest, installed through the same host:

- **Data plugins**: a `.f3dplugin` document with loop phases, events, entity
  kinds, materials in the material language, render steps, Wasm systems,
  scripts, and physical materials: a `physicalMaterials` list of
  `PhysicalMaterial` bodies (the same fields its JSON has) and a
  `materialPairs` list, read and held to SI and to the plugin's namespace
  when the document is read, and installed into the `MaterialCatalog`. A
  document with either names `f3d.physicalMaterials` in its `requires`.
- **Wasm modules**: step systems under Wasm plugin ABI 1, which is versioned
  apart from this API. 32-bit integers only, four imports, no I/O, and a
  plain Dart interpreter that steps them the same way on every platform.
- **Interpreted Dart**: the `ScriptRuntime` interface. No runtime ships in
  1.0.

This is where `permissions` stop being only a declaration. A run-time plugin
gets a permission it declared only when the application grants it, and is
refused with the permission named otherwise.

## Writing one

- `dart run flutter3d_build:create plugin --kind
  render-step|effect|genre|element|tool --name <name>` writes a plugin
  package with its tests, its conformance suite and the pubspec marker.
- `flutter3d_lints` is an analysis server plugin carrying the rules a step
  is held to: no clock, no unseeded `Random`, no `dart:math` transcendental
  where `Portable` gives one answer everywhere.
- `EngineLoop(determinismCheck: …)` steps each step twice in a debug build
  and names the plugin whose system made the two runs differ.
- `package:flutter3d_conformance/plugins.dart` runs five checks: the
  manifest, the switch, determinism, every declared backend, and the budget
  the manifest declares under `extra['budget']`. A plugin that passes all of
  them on every backend it declares, with a world given to the determinism
  check, may show the conformance badge.
- `dart run flutter3d_build:plugin_mcp` is an MCP server through which an
  agent creates a plugin, runs its conformance and reads the report. Its
  skill ships in `flutter3d_build`.
- The site's [plugin catalogue](https://flutter3d.pleion.dev/reference/plugins/)
  lists packages on pub.dev with the `flutter3d-plugin` topic.
