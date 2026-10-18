/// Wasm modules as step systems and as render nodes: Wasm plugin ABIs 1 to
/// 3, which this library is the specification of. What follows is a step
/// module's contract; a render module's (ABI 3) is at the end.
///
/// **Sandboxed and deterministic, written in any language** — decision 4 of
/// `tasks/0.9-plugins.md`. A module reaches the world through four imports
/// and nothing else, and computes in 32-bit integers, so it gives one answer
/// on the VM, in a browser and on the server that replays the run.
///
/// ## The contract
///
/// **Version.** Numbered apart from the plugin API. A module exports
/// `f3d_abi() -> i32` returning the ABI it was written for, and the host
/// runs every ABI from [wasmPluginAbiMin] to [wasmPluginAbiMax] (1 to 3);
/// a number outside that is refused at instantiation with the range named.
/// [wasmPluginAbi] is the newest, what a module written today says. The
/// minimum stays 1 through 1.x. An export named `f3d_` is the host's word
/// from the ABI it arrived in ([wasmExportSince]): a module of an earlier
/// ABI that exports a function of the name is not read for it.
///
/// **Exports.** `f3d_abi() -> i32` and `f3d_step(i32 step, i32 dt)`, called
/// once a fixed step with the step's number and its length in Q16.16. A
/// `memory` export is optional.
///
/// **Imports**, all from the module `f3d`, all functions:
///
/// | Import | Signature | What it does |
/// |---|---|---|
/// | `field_len` | `(i32 field) -> i32` | how many values a field holds |
/// | `field_get` | `(i32 field, i32 index) -> i32` | a value, in Q16.16 |
/// | `field_set` | `(i32 field, i32 index, i32 value)` | writes a value |
/// | `publish` | `(i32 event, i32 a, i32 b)` | publishes an event |
/// | `field_frac` | `(i32 field) -> i32` | ABI 2: the fraction bits a field crosses with |
///
/// **Imports are feature-detected.** Each arrived in an ABI
/// ([wasmImportSince]); a module imports only what it calls, and one that
/// imports a function newer than the ABI it says is refused naming it
/// ([wasmAbiRefusal]). Leaving an optional import out is never a refusal.
///
/// A field and an event are named by their index in the module's
/// declaration ([WasmSystemSpec.fields], [WasmSystemSpec.events]); the names
/// stay outside the module. Any other import is refused, by name. **There is
/// no I/O in ABI 1** — no file, no clock, no network, no randomness the
/// module did not compute — and that is how a module is held to its
/// permissions: what a manifest did not ask for and an application did not
/// grant is not reachable at all, because nothing reaches it.
///
/// **Values.** `i32` only: an i64, f32, f64 or v128 anywhere — a parameter,
/// a local, a global, a block, an instruction — is refused at decode. A
/// float's last bit differs between a CPU's instructions and a browser's,
/// and a 64-bit integer is not exact in a browser's `int`; neither is a
/// risk a replayed run can take. The world's numbers cross as Q16.16
/// (`Fixed16`) — or, under ABI 2, with the fraction bits the field's
/// declaration gives ([WasmFieldSpec.fractionBits]), so a world position far
/// from the origin fits — converted with a multiply by a power of two and a
/// `round`, which every platform does exactly. A field also names its unit
/// ([WasmFieldSpec.unit]).
///
/// **What a module may be made of.** Types, imports, functions, at most one
/// memory (plain: not shared, not 64-bit), `i32` globals initialised by one
/// `i32.const`, exports, a start function taking and returning nothing,
/// code, active data segments at an `i32.const` offset; custom sections are
/// skipped. Tables, element segments, `call_indirect`, passive data, and
/// imported memories, tables and globals are refused. A block yields
/// nothing or one `i32`. The instructions are the control instructions,
/// `call`, `drop`, `select`, the local and global instructions, the `i32`
/// loads and stores of 8, 16 and 32 bits, `memory.size`, `memory.grow`,
/// `i32.const`, every `i32` comparison and arithmetic instruction, and
/// `i32.extend8_s`/`i32.extend16_s`. Anything else is refused naming its
/// opcode.
///
/// **Limits** ([WasmLimits]). The memory's pages, at the start and after
/// every `memory.grow`, which answers -1 past the limit as Wasm says. Fuel:
/// instructions per step, counted, so running out traps at the same
/// instruction on every machine. Call depth. A module whose memory starts
/// above the limit is refused.
///
/// **A trap** stops the system: it is not called again, and
/// [WasmTrapped] is published on the step channel. The latch is part of the
/// system's saved state.
///
/// ## Runtimes
///
/// [WasmRuntime.interpreter] — plain Dart, on every platform, metered — is
/// the default and the one a replay is held to. [browserWasmRuntime] is the
/// browser's own WebAssembly on the web: it refuses the same modules (it
/// decodes them first) and holds the memory limit through the maximum a
/// module must declare, and it cannot count fuel or calls, so a module that
/// loops for ever hangs the page; its saves cover only what the module
/// exports.
///
/// ## Render modules (ABI 3)
///
/// **Told apart by the section that declares them**
/// ([WasmModuleKind.render]): a module under a `.f3dplugin`'s `wasmRender`
/// ([WasmRenderSpec]) is decoded as a render module, and the same bytes
/// under `wasm` are decoded as a step module and refused if they are not
/// one. A render module drives one render step of its plugin's document
/// ([WasmRenderNode], the plugin API's `RenderProgram`).
///
/// **Values.** `i32` and `f32`: the `f32` loads, stores, constants,
/// comparisons, arithmetic, `min`, `max`, `copysign`, the conversions to
/// and from `i32` (a truncation no `i32` holds traps) and the two
/// reinterpretations. No `i64`, `f64` or `v128`. A render module is outside
/// the simulation, so its floats need agree with nobody's.
///
/// **Exports.** `f3d_abi() -> i32`, 3 or later, and
/// `f3d_render_node(i32 frame, i32 view)`, called once a frame for the
/// view being drawn. `f3d_step` is not required.
///
/// **Imports**, from `f3d`, each since 3 ([wasmRenderImports]):
///
/// | Import | Signature | What it does |
/// |---|---|---|
/// | `param` | `(i32 parameter, i32 component, f32 value)` | sets one component of a declared parameter |
/// | `param_floats` | `(i32 parameter, i32 ptr, i32 len)` | sets a parameter from `len` bytes of floats at `ptr`, copied during the call |
/// | `draw` | `()` | the step draws this frame |
/// | `time` | `() -> f32` | the frame's time, in seconds |
/// | `view_size` | `(i32 axis) -> i32` | the view's width (0) or height (1) in pixels |
/// | `light_code` | `(i32 light) -> i32` | the code a declared light type is packed with, -1 for none |
///
/// A parameter and a light type are named by their index in the
/// declaration ([WasmRenderSpec.parameters], [WasmRenderSpec.lights]); bulk
/// data is `(ptr, len)` in the module's memory, copied by the host during
/// the call and never kept. A step module's imports are refused to a render
/// module and a render module's to a step module, by name.
///
/// **An instance of its own**, outside the run's save and its digest: a
/// client that draws and a server that never does stay one run. Its fuel
/// is counted per frame ([WasmLimits.fuelPerFrame]); a trap switches its
/// step's node off, with the plugin named, and the module is not called
/// again.
library;

export 'abi.dart';
export 'interpreter.dart';
export 'js_runtime_stub.dart'
    if (dart.library.js_interop) 'js_runtime_web.dart';
export 'module.dart' show WasmModule;
export 'render.dart';
export 'system.dart';
