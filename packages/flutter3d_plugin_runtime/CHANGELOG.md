## 1.0.0-rc.1+1

- **Breaking: Wasm render modules, ABI 3.** A `.f3dplugin`'s `wasmRender`
  section declares a module that drives one of its render steps frame by
  frame (`WasmRenderSpec`, run as a `WasmRenderNode`): decoded as a render
  module, so it may compute in `f32` and needs no `f3d_step`, run in an
  instance of its own outside every save and digest, its commands imports
  with scalar arguments (`param`, `param_floats`, `draw`, `time`,
  `view_size`, `light_code`) naming what the declaration lists by index,
  and metered per frame (`WasmLimits.fuelPerFrame`). A trap switches the
  node off with the plugin named, and the frame is drawn. The browser's own
  WebAssembly runs it as the interpreter does. `wasmPluginAbiMax` and
  `wasmRenderAbi` are 3, and `DataSections.runtimeKeys` gains
  `wasmRender`.
- **Breaking: a module from a URL is pinned by its hash.** `WasmSystemSpec`
  and `WasmRenderSpec` take a `sha256`, whose key `WasmSystemSpec.keys`
  gains; a module fetched from an `https:` URL without one, or whose bytes
  hash to another, is refused before anything is installed
  (`wasmIntegrityRefusal`). A module of the plugin's own directory is not
  checked.
- **A data section's name already taken is a `NameTakenException`.**
  `DataSections.register` refused a second section under one name with an
  `ArgumentError`; it is the `PluginException` every registry throws for a
  name already taken now, naming the name. A name the runtime reads itself
  is still an `ArgumentError`, since no plugin can ever have it.
- **A plugin's entries keep the keys a later minor gave them.**
  `DataPhase`, `DataEventDeclaration`, `ExpressionSystemSpec` and
  `WasmSystemSpec` hold what their `keys` do not name in `unknown` and write
  it back, so a tool of this build saving a later `.f3dplugin` keeps what
  that build said inside each phase, event and system.

## 1.0.0-rc.1

- **The Wasm plugin ABI's vocabulary is a file.** `api/wasm_abi.vocabulary`
  holds the newest ABI and the oldest a host runs (1, through 1.x), and
  every import and export with the ABI it arrived in; `dart run
  tool/wasm_vocabulary.dart` writes it, a test keeps it current, and a
  structure rule holds it to the base recorded at the tag, so an import
  added under an ABI a 1.0 host already runs is caught.
- **A Wasm system orders itself against another of its plugin's by the
  name the document gives it.** `wasm[].after` and `wasm[].before` naming a
  system of the same document are filed under `<id>.`, as its phases are;
  any other name is the loop's as written, so a document that already
  wrote `<id>.blow` reads as before.
- **Render nodes are a capability their export names, not an ABI number
  set aside.** `wasmRenderAbi` is the lowest ABI they can arrive in, one
  past `wasmPluginAbiMax`; the release that implements them names the ABI
  they arrived in, as an import's, so a minor that only adds a simulation
  import takes the next number without them.
- **Breaking: a Wasm module's save has one shape, whichever runtime wrote
  it.** `globals` holds each mutable global the module exports by its
  export name, where the interpreter wrote every global as a list and the
  browser its exported ones; the interpreter writes the rest as
  `internal`, which a digest leaves out and the browser ignores, and
  `WasmSystem.save` names the `runtime` (new: `WasmSystem.runtime`,
  `digestible`). A run the browser recorded is replayed by the
  interpreter to the same digests. A data plugin's snapshot part is at
  version 2. A simulating module is refused a runtime that counts no
  fuel under a bit-exact profile, naming both: one that runs out traps
  only on the interpreter a replay steps it on.
- **Breaking: a Wasm runtime and its instances take one context per
  call.** `WasmRuntime.instantiate` takes a `WasmInstantiation` (new) with
  the module, its imports and its limits, and `WasmInstance.step` a
  `WasmStep` (new) with the step and its length in Q16.16, which the
  system reuses from step to step so a step allocates nothing. A runtime
  written outside (wasmtime, a JIT) then keeps compiling when a minor
  hands it more. `WasmImports` keeps the ABI's own shapes.
- **Breaking: `.f3dplugin` version 4 files a phase under the plugin.** A
  phase a document declares is added to the loop as `<id>.<name>`, as its
  events and Wasm systems already were, and so is every `after`, `before`,
  `wasm[].phase` and `expressions[].phase` that names one of the
  document's own phases; the engine's and other plugins' are named as
  written. A version-3 phase already written as `<id>.<name>` is lifted to
  `<name>`, so it is not filed twice. An entity type a document declares is
  in its namespace (`glow.vent`), as every name a plugin registers is.
- **Breaking: `DataPluginDocument.sections` holds `DataPluginSection`s**
  (new), a class with `reader` and `section`, where it held a record, so a
  later minor can say more of a section read.
- **Breaking: `WasmModule` no longer shows the interpreter's compiled
  code.** `functions`, `data`, `functionTypes` and `globals` were of types
  the package does not export; a runtime from outside compiles `bytes`.
- **A data section and a world field a plugin adds are in its
  namespace.** `DataSections` and `WorldFields.add` refuse a plugin's bare
  name with a `PluginException`, as every registry does.
- **`wasm.trapped` is declared once for the engine** and kept, rather than
  by the first module that needed it and withdrawn with it.
- **Render nodes have a reserved ABI.** `wasmRenderAbi` (3) and
  `wasmRenderNodeExport` (`f3d_render_node`) name the Wasm plugin ABI that
  brings render nodes. No host runs it yet: a module that says ABI 3 is
  refused with the range named, as before, and ABI 1 and 2 modules are
  unchanged.
- **The runtime depends on the plugin API alone.** `entityKinds`,
  `materials` and `renderSteps` are sections like `effects`, read by the
  package that owns what they install through the plugin API's
  `DataSectionRegistry`: `entityKindsSection` and `DataEntityKind` are in
  `package:flutter3d_sim/data_plugins.dart`; `materialsSection`,
  `renderStepsSection`, `renderDataSections`, `DataMaterial`,
  `DataRenderStep`, `RuntimeShaders`, `RuntimeRenderStep`,
  `RuntimeShadersException`, `RuntimeBackends`, `runtimeMaterialBundle`,
  `spliceMaterialWgsl`, `fullscreenMaterialWgsl` and `runtimeShaderSdk` are
  in `package:flutter3d_core/data_plugins.dart`. `DataPluginDocument` loses
  `entityKinds`, `materials` and `renderSteps` (they are in `sections` when
  read, in `extra` when not), and `flutter3d_core`, `flutter3d_sim`,
  `flutter3d_shaders`, `flutter3d_physics` and `flutter3d_hardware` leave the
  pubspec: a server replaying a run with a data plugin no longer resolves
  the render core.
- **`ScriptRuntime` is gone, and `scripts` is `expressions`.** No script
  runtime ever shipped; the expression language covers what a script was
  for. `ScriptRuntime`, `ScriptProgram`, `ScriptContext`, `ScriptSystem`,
  `ScriptSystemSpec`, `ScriptException`, `ScriptFormatException` and
  `installScriptSystem` go; `ExpressionSystemSpec` and
  `DataPluginDocument.expressions` take their place. The format is at
  version 3, whose migration reads a version-2 `scripts` entry as an
  expression system with its `source` kept, and the v3 fixture is minted.
  This build reads expression systems and refuses, by name, to install a
  plugin that brings one.

- **A Wasm module's state is checked before it is restored.** The
  interpreter and the browser runtime refuse with a `WasmFormatException`
  a negative or out-of-range page count, memory that is not base64 or does
  not fit its pages, and globals of the wrong count or not whole numbers,
  and leave the module's memory and globals as they were; they used to
  wipe the memory first.

- **Breaking: the subsystems read their own sections.** `effects`,
  `physicalMaterials` and `materialPairs` are read by the sections
  `flutter3d_particles` and `flutter3d_matter` register in a
  `DataSectionRegistry` (`DataSections` here), handed to
  `DataPluginLoader(sections:)` and to `DataPluginDocument.parse`. The
  document's `effects`, `effectSources`, `physicalMaterials`,
  `materialPairs`, `DataPluginDocument.requiresPhysicalMaterials` and
  `DataPlugin.placeDataEvent` are gone: a section read is in
  `DataPluginDocument.sections`, and `DataPlugin.numbersOfDataEvent` is
  what an event places an effect by. This package no longer depends on
  `flutter3d_particles` or `flutter3d_physics`. The file format is
  unchanged; a section no reader takes is kept as written, and the plugin's
  notes say so.
- **Data plugins declare physical materials.** A `.f3dplugin`'s
  `physicalMaterials` (and `materialPairs`) are read with the catalogue's
  codec, checked for plausible SI numbers and a source per group, and
  registered under the plugin's id; a document with them requires
  `f3d.physicalMaterials`.
- **Breaking: every thrown type is named `*Exception`** (decision H):
  `PermissionRefused` is `PermissionException`, `ScriptRefused`
  `ScriptException`, `WasmRefused` `WasmException`, `WasmTrap`
  `WasmTrapException` and `RuntimeShadersRefused` `RuntimeShadersException`,
  each with the same members.

- **A data plugin's outside-world state is in the loop's snapshots.**
  Installed, a plugin with Wasm systems or scripts adds what they keep
  (`DataPlugin.save`) as a part under its id, so a rewind, a rollback and the
  double-step check cover it.

- **Breaking: `RuntimeShaders` takes `addMaterials` as a function returning
  a `Registration`**, `renderer.renderSteps.addMaterials`, and no
  `removeMaterials`: cancelling the registration takes a library out. The
  renderer's own `addMaterials` and `removeMaterials` are gone.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `WasmInterpreter.metered` is `isMetered`; `WasmRuntime.metered` is
  `isMetered`. `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `normalise` is `normalize`. Only the Dart names changed: a file
  keeps the keys it was written with, and `dart fix` carries the renames.
- **Breaking: a render step can stand at another plugin's anchor.**
  `DataRenderStep.anchor` is the anchor's name (a `String`, where it was a
  `RenderAnchor`), and the engine resolves it through the renderer
  (`RendererSteps.anchorNamed`) when the plugin is installed, so an anchor
  a plugin added with `RendererSteps.addAnchor` is one a data plugin can
  name. An engine anchor is still checked when the document is read; a
  plugin's is checked at install, against the side of tone mapping its
  engine anchor is on, and a name the renderer does not have is refused
  there with the list of anchors it does.

- **Breaking: `.f3dplugin` is version 2, in the format envelope.** A
  document starts `{"format": "f3d.plugin", "version": 2, ...}`
  (`DataPluginDocument.format`) instead of `{"f3dplugin": 1}`. No section
  changed; a build from before refuses a version-2 document as having no
  version rather than misreading it. Version 1 documents still read.
- **A Wasm host runs a range of ABIs.** `wasmPluginAbiMin` (1) to
  `wasmPluginAbiMax` (2); `wasmPluginAbi` is the newest. A module outside the
  range is refused with the range named, so a module built for ABI 1 keeps
  loading.
- **Imports are feature-detected.** Each host function names the ABI it
  arrived in (`wasmImportSince`); a module that imports one newer than the
  ABI it declares is refused naming it (`wasmAbiRefusal`), and one that
  leaves an optional import out is fine. `WasmModule.importNames` lists what a
  module asks for, and `WasmInstance.abi` what it said.
- **A field says its unit and its scale.** `WasmFieldSpec.unit` (`"m"`,
  `"K"`) and `fractionBits` (`"fraction"` in a document, 16 by default): Q16.16
  holds ±32 768, which is not a world position, and 8 bits hold ±8 388 608 m
  at 4 mm. ABI 2's `f3d.field_frac` tells a module what it was given, and a
  field declared with anything but 16 is refused to an ABI-1 module at
  install. `FixedPoint` converts at any number of fraction bits; `Fixed16` is
  its 16-bit case.
- **Breaking:** declarations throw typed exceptions instead of `dart:core`'s
  `FormatException`: `WasmFormatException` for a Wasm system, its fields, its
  limits and a module's saved state; `ScriptFormatException` for a script;
  `DataPluginFormatException` for an entity kind. `WasmImports` gains
  `fieldFractionBits` and `WasmInstance` gains `abi`, both with defaults.
- **The run-time plugins' refusals are `PluginException`s.**
  `PermissionException`, `ScriptException`, `WasmException` and `WasmTrapException` extend it
  and inherit its `message`. `DataPluginFormatException` extends
  `Flutter3dFormatException`, and `RuntimeShadersException` extends
  `CapabilityException`, because a platform that cannot compile shaders at run
  time lacks a capability. All of them sit under `Flutter3dException` from
  `flutter3d_plugin_api`.
- **A render step written in the material language.** In a `.f3dplugin`,
  `"shaders": {"material": "fog.f3dmat"}` is a `fullscreen` source built for
  whichever backend the engine draws with, `RuntimeRenderStep.materialStage`.
  On WebGPU it is written as WGSL whole (`fullscreenMaterialWgsl`) at the
  location `RuntimeShaders(webGpuFullscreenUvLocation:)` gives. On the
  software backend and WebGL2, a material's `vertex` block becomes its vertex
  stages at run time. On WebGPU at run time, the vertex block, the scene
  depth and the hooks are refused with the reason, and the build compiles
  them. A premultiplied blend and `viewDepth` are spliced in. A compute kernel
  is refused at run time on every backend.
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

- **Plugins loaded while the game runs.** A `.f3dplugin` document is a
  plugin written as data: loop phases, events, entity kinds, materials,
  render steps, Wasm systems and scripts. `DataPluginLoader` reads it and
  every file it names, and the `DataPlugin` it returns installs through the
  same host as a compiled plugin, switched at a step boundary and journalled
  like one. The format is versioned (`f3dplugin` 1, with a fixture), reads
  older documents through a migration list, refuses a newer one with the
  version that reads it, and keeps the keys it does not know.

- **Permissions are enforced where access is handed out.** A permission a
  run-time plugin uses must be declared in its manifest and granted by the
  application (`PluginGrants`). The plugin's own files need nothing; a URL
  needs `network` and the application's `fetch`; a path outside the
  plugin's directory needs `files` and the application's `readFile`. A
  permission declared and not granted refuses the plugin before any file is
  read.

- **Wasm modules as step systems, under an ABI of their own.** Wasm plugin
  ABI 1 is 32-bit integers only, so a module gives one answer on the VM, in
  a browser and on a replaying server; it reaches the world through four
  imports (`field_len`, `field_get`, `field_set`, `publish`) and has no I/O
  at all. A plain Dart interpreter decodes, validates and steps a module on
  every platform, metered by fuel, so running out lands on the same
  instruction in every replay. The browser's own WebAssembly is there on the
  web, unmetered. A trap latches the system off and publishes
  `WasmTrapped`; its state, latch included, saves and restores.

- **Materials and render steps compiled at run time, where they can be.**
  `RuntimeShaders` builds a material in the material language for the
  software backend, WebGL2 and WebGPU, and a raw GLSL ES render step for
  WebGL2. On WebGPU no compiler runs: `spliceMaterialWgsl` writes the
  material's body as WGSL into the engine's own compiled `Unlit` stage,
  which `flutter3d_webgpu`'s `webGpuMaterialHost()` hands over as
  `webGpuHost`, and its uniforms become a `MaterialParams` block at the next
  free binding. A material with a `light` block, one reading `instance`, or
  one sampling a map other than the base colour is refused there with the
  reason and built from `assets_src/` instead. Impeller compiles shaders
  ahead of time, so on it the material or step is switched off with the
  reason, and the rest of the plugin installs.

- **A plugin's effects load.** `.f3dplugin`'s `effects` names `.f3dfx`
  documents by `source` or carries them in place; the loader reads them
  with the rest of the plugin's files and installs them into the engine's
  `ParticleEffects`, as `<plugin id>.<name>`, with their triggers on the
  bus. A trigger naming one of the plugin's own events listens for it under
  the plugin's prefix, and a `PluginDataEvent` whose first values are a
  position in Q16.16 places the effect (`DataPlugin.placeDataEvent`). An
  entry that is neither a source nor a document is kept as written, as
  version 1 kept the whole section, and the plugin's notes say so.

- **The world's fields, by name.** `WorldFields` is the registry an
  application fills with the fields a run-time plugin may reach, and
  `Fixed16` converts their doubles to Q16.16 exactly on every platform.

- **Interpreted Dart is an interface.** `ScriptRuntime` is what a script
  runtime implements, held to a Wasm module's rules. None ships: `dart_eval`
  was evaluated and not adopted, for the reasons in `tasks/0.9-plugins.md`.
