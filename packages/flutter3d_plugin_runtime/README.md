# flutter3d_plugin_runtime

Plugins a flutter3d game loads while it runs. A Dart plugin is compiled into
the application; these are read at run time, from the game's assets, a mod
folder or a server, and installed through the same plugin host, with the same
manifest, the same switch at a step boundary and the same journal.

Two kinds, after decision 4 of
[`tasks/0.9-plugins.md`](https://github.com/pleiondev/flutter3d/blob/main/tasks/0.9-plugins.md):

- **Data plugins.** A `.f3dplugin` document declares loop phases, events,
  step systems in Wasm and in the expression language, and sections each
  subsystem of the engine reads for itself: entity kinds, materials in the
  material language, render steps, particle effects, substances.
  `DataPluginLoader` reads it and every file it names, and hands back a
  `DataPlugin`.
- **Wasm modules.** Step systems under the Wasm plugin ABI: sandboxed, 32-bit
  integers only, the world reached through a handful of imports. A plain
  Dart interpreter steps them on every platform, metered by fuel.

**It depends on the plugin API alone.** A server that replays a run with a
data plugin in it steps the plugin's modules with this package, so it
resolves without the render core, the simulation or the physics.

## A data plugin

```json
{
  "format": "f3d.plugin", "version": 3,
  "manifest": {"id": "gusts", "apiVersion": "1.0", "touches": "simulation"},
  "phases": [{"name": "weather", "kind": "step",
              "after": ["physics"], "before": ["elements"]}],
  "events": [{"name": "gust"}],
  "entityKinds": [{"type": "vent", "requires": ["size"], "collider": "trigger"}],
  "wasm": [{"module": "gusts.wasm", "system": "blow", "phase": "weather",
            "fields": [{"name": "wind", "write": true}],
            "events": ["gust"]}]
}
```

```dart
final loader = DataPluginLoader(
  sections: DataSections([
    entityKindsSection,      // package:flutter3d_sim/data_plugins.dart
    ...renderDataSections,   // package:flutter3d_core/data_plugins.dart
    effectsSection,          // flutter3d_particles
  ]),
);
final plugin = await loader.load(text, mySource);
final loop = EngineLoop(
  input: input,
  registries: [WorldFields([ListWorldField('wind', wind)]), entityKinds],
  plugins: [plugin],
);
```

`test/fixtures/v<N>/glow.f3dplugin` holds every key version N has.

| Key | Read by | Becomes |
|---|---|---|
| `manifest` | the runtime | the plugin's `PluginManifest`; keys it does not know are kept |
| `phases` | the runtime | step or frame phases, ordered by `after`/`before` |
| `events` | the runtime | events declared as `<id>.<name>`, published as `PluginDataEvent` |
| `wasm` | the runtime | Wasm step systems, `WasmSystemSpec` |
| `expressions` | the runtime | step systems in the expression language, `ExpressionSystemSpec` |
| `entityKinds` | `flutter3d_sim`'s `entityKindsSection` | `DataEntityKind`s in `EntityKinds`: required properties, an optional box |
| `materials` | `flutter3d_core`'s `materialsSection` | the material language, built at run time where the backend can |
| `renderSteps` | `flutter3d_core`'s `renderStepsSection` | a full-screen stage per backend at a `RenderAnchor` |
| `effects` | `flutter3d_particles`' `effectsSection` | `.f3dfx` documents in `ParticleEffects` |
| `physicalMaterials`, `materialPairs` | `flutter3d_matter`'s sections | substances in the `MaterialCatalog` |

A section no registered reader takes is kept as written, written back, and
named in `DataPlugin.notes`.

The document is versioned like every other engine file: the envelope carries
the version, a 1.x engine reads every 1.x document through a migration list,
a document from a newer engine is refused with the version that reads it,
and top-level keys this build does not know are kept and written back.
Version 3 has `expressions` where version 2 had `scripts`: a version-2
script's declaration is read as an expression system, its `source` kept for
its author to rewrite. This build reads expression systems and refuses, by
name, to install a plugin that brings one: it evaluates no expression
language yet.

## Permissions

A run-time plugin gets nothing it is not handed. A permission it uses must be
declared in its manifest **and** granted by the application:

```dart
final loader = DataPluginLoader(
  grants: PluginGrants([PluginPermission.network]),
  fetch: (url) => myHttp.get(url),
);
```

- A path inside the plugin's own directory is read from its `PluginSource`,
  with no permission.
- An `http:` or `https:` URL needs `network` and goes through `fetch`.
- An absolute path, a `file:` URL, or a path climbing out with `..` needs
  `files` and goes through `readFile`.

A permission declared and not granted refuses the whole plugin before any
file is read. A Wasm module has no import that reaches either door, and an
expression has none to name, so the loader is all the reach a data plugin
has.

## Materials and render steps compiled at run time

`RuntimeShaders`, in `package:flutter3d_core/data_plugins.dart` beside the
two sections that use it, is a registry the application hands the engine
with the device's `loadShaders` and the renderer's `renderSteps.addMaterials`.
A plugin brings source, and the registry builds it where the backend compiles
at run time: the software device evaluates it, WebGL2 gets GLSL ES 3.00
translated against the engine's headers, and WebGPU gets the material
spliced into the engine's own compiled stage. Impeller runs what `impellerc`
compiled ahead of time and turns each one off with the reason. Off is not an
error: the reason is in `RuntimeShaders.statuses`, and the rest of the plugin
installs.

## Wasm plugin ABI

`lib/src/wasm/wasm.dart` is the specification. In short:

- **Exports:** `f3d_abi() -> i32`, returning the ABI, and `f3d_step(i32
  step, i32 dt)`, called once a fixed step with `dt` in Q16.16.
- **Imports,** all from `f3d`: `field_len`, `field_get`, `field_set`,
  `publish` and, since ABI 2, `field_frac`. A field and an event are named by
  their index in the module's declaration. There is no I/O at all.
- **Values:** `i32` only. A float's last bit and a 64-bit integer's exactness
  both differ between the VM, a browser and a server; a module using either
  is refused when it is read. The world's numbers cross as Q16.16
  (`Fixed16`).
- **Limits:** memory pages, fuel per step (instructions, so a trap lands on
  the same instruction in every replay) and call depth. A trap latches: the
  system stops, `WasmTrapped` is published, and a rollback before the trap
  takes the latch back.

`WasmRuntime.interpreter` is plain Dart and runs everywhere; it is the
default and the one replays are held to. `browserWasmRuntime()` is the
browser's own WebAssembly on the web: it refuses the same modules, holds the
memory limit through the maximum a module must declare, and cannot count fuel
or calls.

## State

`DataPlugin.save` and `restore` carry what its Wasm systems keep outside the
world, and installed, the plugin adds them to the loop's snapshots as a part
under its id. So a rewind, a rollback and the debug double-step check
(`DeterminismCheck` in `flutter3d_sim`) cover them with nothing more said.
