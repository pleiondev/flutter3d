# flutter3d_plugin_runtime

Plugins a flutter3d game loads while it runs. A Dart plugin is compiled into
the application; these are read at run time, from the game's assets, a mod
folder or a server, and installed through the same plugin host, with the same
manifest, the same switch at a step boundary and the same journal.

Three kinds, after decision 4 of
[`tasks/0.9-plugins.md`](https://github.com/pleiondev/flutter3d/blob/main/tasks/0.9-plugins.md):

- **Data plugins.** A `.f3dplugin` document declares loop phases, events,
  entity kinds, materials in the material language, render steps, Wasm
  systems and scripts. `DataPluginLoader` reads it and every file it names,
  and hands back a `DataPlugin`.
- **Wasm modules.** Step systems under Wasm plugin ABI 1: sandboxed, 32-bit
  integers only, the world reached through four imports. A plain Dart
  interpreter steps them on every platform, metered by fuel.
- **Interpreted Dart.** `ScriptRuntime` is the interface a script runtime
  implements. None ships in 1.0; the plan says why.

## A data plugin

```json
{
  "f3dplugin": 1,
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
final plugin = await const DataPluginLoader().load(text, mySource);
final loop = EngineLoop(
  input: input,
  registries: [WorldFields([ListWorldField('wind', wind)]), entityKinds],
  plugins: [plugin],
);
```

`test/fixtures/v1/glow.f3dplugin` holds every key version 1 has.

| Key | Becomes |
|---|---|
| `manifest` | the plugin's `PluginManifest`; keys it does not know are kept |
| `phases` | step or frame phases, ordered by `after`/`before` |
| `events` | events declared as `<id>.<name>`, published as `PluginDataEvent` |
| `entityKinds` | `DataEntityKind`s in `EntityKinds`: required properties, an optional box |
| `materials` | the material language, built at run time where the backend can |
| `renderSteps` | a full-screen stage per backend at a `RenderAnchor` |
| `wasm` | Wasm step systems, `WasmSystemSpec` |
| `scripts` | interpreted Dart step systems, `ScriptSystemSpec` |
| `effects` | kept and not loaded: the particle system has no document form in 1.0 |

The document is versioned like every other engine file: `f3dplugin` carries
the version, a 1.x engine reads every 1.x document through a migration list,
a document from a newer engine is refused with the version that reads it,
and top-level keys this build does not know are kept and written back.

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
file is read. A Wasm module has no import that reaches either door, and a
script is handed none, so the loader is all the reach a data plugin has.

## Materials and render steps compiled at run time

`RuntimeShaders` is a registry the application hands the engine with the
device's `loadShaders` and the renderer's `renderSteps.addMaterials`. A plugin brings
source, and the registry builds it where the backend compiles at run time:

| Backend | A material | A raw render step |
|---|---|---|
| CPU | the source, evaluated by the software device | off: a raw stage is Dart there |
| WebGL2 | GLSL ES 3.00, translated against the engine's headers | GLSL ES 3.00 |
| WebGPU | off: no WGSL path inside the engine yet | off |
| Impeller | off: shaders are compiled ahead of time by `impellerc` | off |

Off is not an error. The material or the step is switched off, the reason is
in `RuntimeShaders.statuses`, and the rest of the plugin installs. A step
that is off is reported in `FrameResult.skipped` like any switched-off step.
A render step written in the material language waits for its full-screen
stages (decision 15).

## Wasm plugin ABI 1

`lib/src/wasm/wasm.dart` is the specification. In short:

- **Exports:** `f3d_abi() -> i32`, returning `1`, and `f3d_step(i32 step,
  i32 dt)`, called once a fixed step with `dt` in Q16.16.
- **Imports,** all from `f3d`: `field_len`, `field_get`, `field_set` and
  `publish`. A field and an event are named by their index in the module's
  declaration. There is no I/O at all.
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

## Interpreted Dart

`ScriptRuntime`, `ScriptProgram` and `ScriptContext` are the seam a script
runtime fills. A script is a step system held to a Wasm module's rules: the
fields it declared, the events its plugin declared, no network and no files,
and `Portable` arithmetic. An engine without a runtime refuses a plugin that
brings a script, by name.

## State

`DataPlugin.save` and `restore` carry what its Wasm systems and scripts keep
outside the world, and installed, the plugin adds them to the loop's snapshots
as a part under its id. So a rewind, a rollback and the debug double-step check
(`DeterminismCheck` in `flutter3d_sim`) cover them with nothing more said.
