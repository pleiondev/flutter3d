/// Plugins loaded while a game runs, and the doors they are handed.
///
/// Two kinds, after decision 4 of `tasks/0.9-plugins.md`:
///
/// * **Data plugins.** A `.f3dplugin` document ([DataPluginDocument]) names
///   loop phases, the events its systems publish, step systems in Wasm and
///   in the expression language, and sections each subsystem reads for
///   itself through the plugin API's `DataSectionRegistry`: entity kinds
///   (`flutter3d_sim`), materials and render steps (`flutter3d_core`),
///   effects (`flutter3d_particles`), substances (`flutter3d_matter`).
///   [DataPluginLoader] reads it and everything it points at, checks the
///   permissions its manifest declares against what the application grants
///   ([PluginGrants]), and hands back a [DataPlugin] — a `Flutter3dPlugin`
///   like any other.
/// * **Wasm modules.** Sandboxed and deterministic, under an ABI versioned on
///   its own ([wasmPluginAbi]): 32-bit integers only, the world reached
///   through [WorldFields] in [Fixed16], events published by index. A pure
///   Dart interpreter steps them on every platform, metered by fuel; the
///   browser's own WebAssembly is there for the web.
///
/// **No subsystem of the engine below it.** This package depends on the
/// plugin API alone, so a server that replays a run with data plugins in it
/// resolves the interpreter without the render core, the simulation or the
/// physics.
library;

export 'src/data/data_plugin.dart';
export 'src/data/data_sections.dart';
export 'src/data/expressions.dart';
export 'src/data_event.dart';
export 'src/permissions.dart';
export 'src/wasm/wasm.dart';
export 'src/world_fields.dart';
