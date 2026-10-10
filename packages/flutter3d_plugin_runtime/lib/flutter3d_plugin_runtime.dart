/// Plugins loaded while a game runs, and the doors they are handed.
///
/// Three kinds, after decision 4 of `tasks/0.9-plugins.md`:
///
/// * **Data plugins.** A `.f3dplugin` document ([DataPluginDocument]) names
///   loop phases, entity kinds, materials in the material language, render
///   steps, Wasm systems and the events they publish. [DataPluginLoader]
///   reads it and everything it points at, checks the permissions its
///   manifest declares against what the application grants
///   ([PluginGrants]), and hands back a [DataPlugin] — a `Flutter3dPlugin`
///   like any other. Its materials are compiled where the backend compiles
///   at run time ([RuntimeShaders]: the software rasteriser, WebGL2, and
///   WebGPU by [spliceMaterialWgsl]); its effects are `.f3dfx` documents,
///   installed into `ParticleEffects`.
/// * **Wasm modules.** Sandboxed and deterministic, under an ABI versioned on
///   its own ([wasmPluginAbi]): 32-bit integers only, the world reached
///   through [WorldFields] in [Fixed16], events published by index. A pure
///   Dart interpreter steps them on every platform, metered by fuel; the
///   browser's own WebAssembly is there for the web.
/// * **Interpreted Dart.** [ScriptRuntime] is the interface a script runtime
///   implements; none ships, and `tasks/0.9-plugins.md` says why.
library;

export 'src/data/data_entity_kind.dart';
export 'src/data/data_plugin.dart';
export 'src/data/data_sections.dart';
export 'src/data/material_wgsl.dart';
export 'src/data/runtime_shaders.dart';
export 'src/data_event.dart';
export 'src/permissions.dart';
export 'src/scripting/script_runtime.dart';
export 'src/wasm/wasm.dart';
export 'src/world_fields.dart';
