import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        Flutter3dFormatException,
        PluginException,
        RenderParameterWrite,
        RenderProgramFrame;

import 'interpreter.dart';
import 'module.dart';

/// The version of the contract between a Wasm module and the engine.
///
/// **Its own number, apart from the plugin API's**, as decision 5 of
/// `tasks/0.9-plugins.md` asks: a module is compiled by somebody else's
/// toolchain against the imports and exports listed in `wasm.dart`, and what
/// it may assume moves on its own schedule. A module exports `f3d_abi`
/// returning the number it was written for.
///
/// **A host reads a range, [wasmPluginAbiMin] to [wasmPluginAbiMax]**, and
/// this is the newest of it — what a module written today says. A module
/// outside the range is refused with the range named, and the minimum stays
/// 1 through 1.x, so a module written for ABI 1 loads on every 1.x engine.
const int wasmPluginAbi = wasmPluginAbiMax;

/// The oldest ABI this host runs a module for, which stays 1 through 1.x:
/// a module written for ABI 1 runs on every 1.x engine.
const int wasmPluginAbiMin = 1;

/// The newest ABI this host runs a module for.
///
/// 2 added the optional import `f3d.field_frac` and fields whose values
/// cross with fewer fraction bits than Q16.16 ([WasmFieldSpec.fractionBits]),
/// so a world position kilometres from the origin fits. Nothing in ABI 1
/// changed: an ABI-1 module runs under ABI 2 as it did.
///
/// 3 added render modules ([WasmModuleKind.render], [wasmRenderAbi]): a
/// module a `.f3dplugin`'s `wasmRender` declares, which computes in `i32`
/// and `f32`, exports [wasmRenderNodeExport] and drives a render step of
/// its plugin's frame by frame through the render imports. Nothing a step
/// module may do changed: ABI 1 and 2 modules run under ABI 3 as they did.
const int wasmPluginAbiMax = 3;

/// **The ABI render modules arrived in**: 3.
///
/// A render module ([WasmModuleKind.render]) says it was written for this
/// ABI or a later one; one that says less is refused at instantiation with
/// both numbers. A step module of any ABI that exports a function named
/// [wasmRenderNodeExport] is not read for it and runs as any other: what
/// makes a module a render module is the `.f3dplugin` section that
/// declares it, never a name it exports.
const int wasmRenderAbi = 3;

/// The export a render module is called through once a frame:
/// `f3d_render_node(i32 frame, i32 view)`.
const String wasmRenderNodeExport = 'f3d_render_node';

/// What a module is, which the `.f3dplugin` section that declares it says
/// and [WasmModule.decode] checks before anything runs.
///
/// **Two, told apart by where they are declared, never by what they
/// export.** A step module (`wasm`) steps the simulation: `i32` only,
/// `f3d_step` required, its memory part of the run's state, its fuel
/// counted per step. A render module (`wasmRender`) drives a render step:
/// `f32` allowed, `f3d_step` not required, [wasmRenderNodeExport] required,
/// run in an instance of its own outside the run's state and its digest,
/// its fuel counted per frame ([WasmLimits.fuelPerFrame]).
///
/// A final class with constants rather than an enum, as every open kind of
/// the engine is: a kind a later minor adds breaks no `switch` outside.
final class WasmModuleKind {
  const WasmModuleKind._(this.name, this.section, this.entry);

  /// A step system's module: `wasm` in a `.f3dplugin`.
  static const WasmModuleKind step = WasmModuleKind._(
    'step',
    'wasm',
    'f3d_step',
  );

  /// A render node's module: `wasmRender` in a `.f3dplugin`.
  static const WasmModuleKind render = WasmModuleKind._(
    'render',
    'wasmRender',
    wasmRenderNodeExport,
  );

  /// Both, in the order they arrived.
  static const List<WasmModuleKind> values = <WasmModuleKind>[step, render];

  /// The kind called [name], or null.
  static WasmModuleKind? byName(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// What a report calls it.
  final String name;

  /// The `.f3dplugin` section that declares a module of this kind.
  final String section;

  /// The export the host calls it through.
  final String entry;

  @override
  String toString() => name;
}

/// Why a module of [kind] that says it was written for [abi], and imports
/// [imports], cannot run here; null when it can.
///
/// **The imports are feature-detected.** Each host function arrived in an
/// ABI ([wasmImportSince]); a module that imports one newer than the ABI it
/// claims is asking for something its own declaration says it does not
/// know, and is refused naming the import. A module that leaves an optional
/// import out is not refused for that: it simply never calls it. A render
/// module written for an ABI before [wasmRenderAbi] is refused naming it.
String? wasmAbiRefusal(
  int abi,
  Iterable<String> imports, {
  WasmModuleKind kind = WasmModuleKind.step,
}) {
  if (abi < wasmPluginAbiMin || abi > wasmPluginAbiMax) {
    return 'the module was written for Wasm plugin ABI $abi and this engine '
        'runs ABI $wasmPluginAbiMin to $wasmPluginAbiMax';
  }
  if (kind == WasmModuleKind.render && abi < wasmRenderAbi) {
    return 'the module is declared under "wasmRender" and says it was '
        'written for ABI $abi; render modules arrived in ABI $wasmRenderAbi, '
        'so it is a module of that ABI or a later one';
  }
  for (final name in imports) {
    final since = wasmImportSince[name] ?? wasmPluginAbiMin;
    if (since > abi) {
      return 'the module imports f3d.$name, which arrived in ABI $since, and '
          'says it was written for ABI $abi';
    }
  }
  return null;
}

/// The ABI each host function arrived in, by its import name: a step
/// module's first, then a render module's.
const Map<String, int> wasmImportSince = <String, int>{
  'field_len': 1,
  'field_get': 1,
  'field_set': 1,
  'publish': 1,
  'field_frac': 2,
  'param': 3,
  'param_floats': 3,
  'draw': 3,
  'time': 3,
  'view_size': 3,
  'light_code': 3,
};

/// The imports a render module may make, by name: what
/// [WasmRenderImports] answers. Every other entry of [wasmImportSince] is a
/// step module's.
const Set<String> wasmRenderImports = <String>{
  'param',
  'param_floats',
  'draw',
  'time',
  'view_size',
  'light_code',
};

/// The ABI each export a host calls arrived in, by its name.
///
/// **Every `f3d_` export is the host's word**: a module written for an ABI
/// before the one an export arrived in that exports a function of its name
/// is not read for it, so a minor's `f3d_init` is never called on a module
/// that happened to have one.
const Map<String, int> wasmExportSince = <String, int>{
  'f3d_abi': 1,
  'f3d_step': 1,
  wasmRenderNodeExport: 3,
};

/// How much a module may take of one step, or of one frame: memory,
/// instructions, calls.
///
/// **Counted, not timed.** A wall-clock budget would trap on a slow phone and
/// not on a fast one, and a replay of the run would part from the recording
/// at the trap. Fuel is a count of instructions executed, so a module that
/// runs out does so at the same instruction on every machine and in every
/// replay. A render module's budget is counted the same way, per frame
/// ([fuelPerFrame]), so a render node that runs away stops at the same
/// instruction on every device rather than taking a slow one's frame.
final class WasmLimits {
  /// Limits of 16 pages of memory (1 MiB), a million instructions a step, a
  /// call depth of 64 and [defaultFuelPerFrame] instructions a frame,
  /// unless given. Takes any number; [WasmLimits.fromJson] is what refuses
  /// one that is not above nought.
  const WasmLimits({
    this.memoryPages = 16,
    this.fuelPerStep = 1000000,
    this.callDepth = 64,
    this.fuelPerFrame = defaultFuelPerFrame,
  });

  /// Reads the keys [toJson] writes; a key left out keeps its default.
  /// Throws a [WasmFormatException] naming a key that is not a whole number.
  factory WasmLimits.fromJson(Map<String, Object?> json) {
    int read(String key, int fallback) => switch (json[key]) {
      null => fallback,
      final int value when value > 0 => value,
      _ => throw WasmFormatException(
        'the Wasm limit "$key" is not a whole number above nought',
      ),
    };
    return WasmLimits(
      memoryPages: read('memoryPages', 16),
      fuelPerStep: read('fuelPerStep', 1000000),
      callDepth: read('callDepth', 64),
      fuelPerFrame: read('fuelPerFrame', defaultFuelPerFrame),
    );
  }

  /// What [fuelPerFrame] is when a declaration does not say.
  static const int defaultFuelPerFrame = 200000;

  /// The most 64 KiB pages a module's memory may have, at the start and
  /// after every `memory.grow`.
  final int memoryPages;

  /// Instructions a step module may execute in one step.
  final int fuelPerStep;

  /// How deep calls may nest inside one step or one frame.
  final int callDepth;

  /// Instructions a render module may execute in one frame's call of
  /// [wasmRenderNodeExport] (ABI 3). A render node that spends it traps,
  /// and its step is switched off with the trap as the reason.
  final int fuelPerFrame;

  /// The limits as a declaration writes them: [fuelPerFrame] only where it
  /// is not [defaultFuelPerFrame], so a step system's declaration reads as
  /// it did before render modules.
  Map<String, Object?> toJson() => <String, Object?>{
    'memoryPages': memoryPages,
    'fuelPerStep': fuelPerStep,
    'callDepth': callDepth,
    if (fuelPerFrame != defaultFuelPerFrame) 'fuelPerFrame': fuelPerFrame,
  };
}

/// A Wasm system's declaration, or a module's saved state, that cannot be
/// read: the sentence names the key.
final class WasmFormatException extends Flutter3dFormatException {
  /// A refusal that [message] explains, naming the key.
  const WasmFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'WasmFormatException: $message';
}

/// A module that cannot be loaded: not Wasm, not ABI 1, or asking for more
/// than it may have. The message names the section, the opcode or the
/// import.
final class WasmException extends PluginException {
  /// A refusal to load that [message] explains, naming the section, the
  /// opcode or the import.
  const WasmException(super.message);

  @override
  String toString() => 'WasmException: $message';
}

/// A module that stopped while running: an `unreachable`, a division by
/// nought, a read past its memory, a budget spent.
final class WasmTrapException extends PluginException {
  /// A trap that [message] describes.
  const WasmTrapException(super.message);

  @override
  String toString() => 'WasmTrapException: $message';
}

/// What a module's four imports call: the world's fields, by the index the
/// module's declaration gave them, and the bus.
///
/// Implemented by `installWasmSystem` over the plugin's [WasmLimits] and
/// fields; a test implements it to hand a module numbers of its own. A
/// method throws [WasmTrapException] to stop the module.
abstract base class WasmImports {
  /// For a host's imports, which supplies [fieldLength], [fieldGet],
  /// [fieldSet] and [publish].
  const WasmImports();

  /// `field_len(field)`: how many values field [field] holds.
  int fieldLength(int field);

  /// `field_get(field, index)`: the value, in Q16.16.
  int fieldGet(int field, int index);

  /// `field_set(field, index, value)`: writes a Q16.16 value.
  void fieldSet(int field, int index, int value);

  /// `publish(event, a, b)`: publishes event [event] with two values.
  void publish(int event, int a, int b);

  /// `field_frac(field)` (ABI 2): how many fraction bits field [field]'s
  /// values cross with — 16 for Q16.16, fewer for a field declared with a
  /// wider range ([WasmFieldSpec.fractionBits]). 16 unless overridden.
  int fieldFractionBits(int field) => 16;
}

/// The imports of a step module that has none to make: what a render
/// module's instantiation carries in [WasmInstantiation.imports].
final class _NoStepImports extends WasmImports {
  const _NoStepImports();

  static Never _refuse() => throw const WasmTrapException(
    'a render module reached a step module\'s import',
  );

  @override
  int fieldLength(int field) => _refuse();

  @override
  int fieldGet(int field, int index) => _refuse();

  @override
  void fieldSet(int field, int index, int value) => _refuse();

  @override
  void publish(int event, int a, int b) => _refuse();
}

/// What a render module's imports call (ABI 3): its render step's
/// parameters, by the index the module's declaration gave them, the draw,
/// and what the frame is.
///
/// **Commands are imports with scalar arguments.** A render module calls
/// `param(1, 0, 0.5)` for the first component of the second of its
/// declaration's `parameters`; bulk data crosses as `(ptr, len)` in the
/// module's memory, which the runtime copies during the call and never
/// keeps ([paramFloats]); a resource is named by its index in the
/// declaration, never by a name or a pointer the host would have to keep.
/// Each member is one import, mirrored one to one.
///
/// **Made by the runtime, called by a [WasmRuntime].** A render node makes
/// one over its declaration and runs each frame's call [during] the
/// [RenderProgramFrame] it is handed, where every command lands. A runtime
/// calls these members from the module's imports; nobody implements them,
/// so they are a final class's, and an import a later ABI adds is a member
/// added here.
///
/// **Breaking in 1.0.0-rc.1:** a final class the runtime makes, where it
/// was an abstract class the data plugin implemented.
///
/// A member throws [WasmTrapException] to stop the module: for a parameter
/// or a light type the declaration does not have, for a command outside a
/// frame, and for whatever the frame refuses (a `PluginException`), with
/// its message.
final class WasmRenderImports {
  /// The imports of a module whose declaration names [parameters]
  /// parameters and the light types [lights], by their whole names
  /// (`acme.tube`), in the declaration's order.
  WasmRenderImports({required this.parameters, this.lights = const <String>[]});

  /// How many parameters the declaration names: the indices `param` and
  /// `param_floats` take are below it.
  final int parameters;

  /// The light types the declaration names, by their whole names, at the
  /// index `light_code` takes.
  final List<String> lights;

  RenderProgramFrame? _frame;

  RenderProgramFrame get _running =>
      _frame ??
      (throw const WasmTrapException(
        'the module called a render import outside a frame',
      ));

  /// Runs [call] with every import landing on [frame], which is let go
  /// when it returns or throws: what a render node does around each
  /// frame's call into the module.
  T during<T>(RenderProgramFrame frame, T Function() call) {
    _frame = frame;
    try {
      return call();
    } finally {
      _frame = null;
    }
  }

  int _parameter(int index) {
    if (index < 0 || index >= parameters) {
      throw WasmTrapException(
        'the module set parameter $index and declares $parameters',
      );
    }
    return index;
  }

  /// [write] handed to the frame, a refusal of the frame's turned into a
  /// trap: the module asked for something its step does not have.
  void _write(RenderParameterWrite write) {
    final frame = _running;
    try {
      frame.setParameter(write);
    } on PluginException catch (refused, stackTrace) {
      Error.throwWithStackTrace(WasmTrapException(refused.message), stackTrace);
    }
  }

  /// `param(parameter, component, value)`: component [component] of the
  /// declaration's parameter [parameter] is [value] from this frame's draw
  /// on, until the module sets it again.
  void param(int parameter, int component, double value) => _write(
    RenderParameterWrite.component(_parameter(parameter), component, value),
  );

  /// `param_floats(parameter, ptr, len)`: parameter [parameter]'s
  /// components are [values], `len` bytes of 32-bit floats the module
  /// wrote at `ptr`. [values] is the runtime's copy, made for this call:
  /// read during the call and not kept.
  void paramFloats(int parameter, Float32List values) =>
      _write(RenderParameterWrite(_parameter(parameter), values));

  /// `draw()`: the step draws this frame, with its parameters as set. A
  /// frame whose call never draws leaves the picture as it found it.
  void draw() => _running.draw();

  /// `time() -> f32`: the frame's time, in seconds since the renderer
  /// began.
  double get time => _running.time;

  /// `view_size(axis) -> i32`: the view's width in pixels for axis 0, its
  /// height for 1, nought for any other.
  int viewSize(int axis) => switch (axis) {
    0 => _running.width,
    1 => _running.height,
    _ => 0,
  };

  /// `light_code(light) -> i32`: the code the declaration's light type
  /// [light] is packed with this frame — what a lit stage tells it apart
  /// by — or -1 when no hook packs it.
  int lightCode(int light) {
    if (light < 0 || light >= lights.length) {
      throw WasmTrapException(
        'the module asked for light type $light and declares '
        '${lights.length}',
      );
    }
    return _running.lightCode(lights[light]) ?? -1;
  }
}

/// Something that runs an ABI 1 module.
///
/// Two ship: [interpreter], plain Dart on every platform and metered, and
/// `browserWasmRuntime()`, the browser's own WebAssembly, which is not.
abstract base class WasmRuntime {
  /// For a runtime, which supplies [name], [isMetered] and [instantiate].
  const WasmRuntime();

  /// The interpreter: the default, and the runtime a replay is held to.
  static const WasmRuntime interpreter = WasmInterpreter();

  /// What this runtime is called in a report.
  String get name;

  /// Whether [WasmLimits.fuelPerStep] and [WasmLimits.callDepth] are held.
  bool get isMetered;

  /// The request's module, ready to step, with its imports behind the
  /// module's imports. Runs its start function and checks `f3d_abi`; throws
  /// [WasmException] for a module the request's limits cannot hold and
  /// [WasmTrapException] for a start function that traps.
  WasmInstance instantiate(WasmInstantiation request);
}

/// What [WasmRuntime.instantiate] is handed.
///
/// **One object, so a minor can hand a runtime more** — a module's
/// declared fields, a debug hook — without breaking a runtime written
/// against 1.0.
final class WasmInstantiation {
  /// A step module ([WasmModuleKind.step]) whose imports call [imports],
  /// held to [limits]; [render] is null.
  const WasmInstantiation(
    this.module, {
    required this.imports,
    required this.limits,
  }) : render = null;

  /// A render module ([WasmModuleKind.render], ABI 3), its imports behind
  /// [render]: an instance of its own, which no step system shares.
  const WasmInstantiation.render(
    this.module, {
    required WasmRenderImports this.render,
    required this.limits,
  }) : imports = const _NoStepImports();

  /// The decoded module.
  final WasmModule module;

  /// What a step module's imports call.
  final WasmImports imports;

  /// What a render module's imports call; null for a step module.
  final WasmRenderImports? render;

  /// The fuel, depth and memory the module is held to.
  final WasmLimits limits;
}

/// One running module.
abstract base class WasmInstance {
  /// For a runtime's instance, which supplies [step] and [save] at least.
  const WasmInstance();

  /// Calls the module's `f3d_step(step, dt)` with the step's
  /// [WasmStep.step] and [WasmStep.dtFixed]. Throws [WasmTrapException]
  /// when the module traps.
  void step(WasmStep step);

  /// Calls a render module's `f3d_render_node(frame, view)` with the
  /// call's [WasmRenderCall.frame] and [WasmRenderCall.view], its imports
  /// answered by [WasmInstantiation.render] and its fuel counted against
  /// [WasmLimits.fuelPerFrame]. Throws [WasmTrapException] when the module
  /// traps, and a [WasmException] on a runtime that runs no render module,
  /// which a runtime written before ABI 3 is.
  void render(WasmRenderCall call) =>
      throw const WasmException('this Wasm runtime runs no render module');

  /// The module's state — its memory and its globals — as a document a
  /// snapshot can hold and `StateDigest` can fold: numbers, strings, lists
  /// and maps only.
  ///
  /// **One shape for every runtime**, since a run one runtime recorded is
  /// replayed on another: `pages`, `memory` (base64, to its last byte that
  /// is not nought) and `globals`, each mutable global the module exports
  /// by its export name. A runtime that can reach the globals the module
  /// keeps to itself writes them as `internal`, by index, which a digest
  /// leaves out and another runtime ignores.
  Map<String, Object?> save();

  /// Puts back what [save] wrote.
  void restore(Map<String, Object?> state);

  /// Instructions the last [step] executed; nought for a runtime that does
  /// not meter.
  int get fuelUsed;

  /// The ABI the module said it was written for, read from `f3d_abi` when
  /// it was instantiated. [wasmPluginAbiMin] unless a runtime says.
  int get abi => wasmPluginAbiMin;
}

/// What [WasmInstance.step] is handed: the step and its length.
///
/// **One object, so a minor can hand a module's step more**, for the
/// reason [WasmInstantiation] gives. **Reused**: the system that steps a
/// module owns one and sets it before every step, so a step allocates
/// nothing; an instance reads it during [WasmInstance.step] and does not
/// keep it.
final class WasmStep {
  /// A step call at step nought with a length of nought, for the owner to
  /// set before each step.
  WasmStep({this.step = 0, this.dtFixed = 0});

  /// The simulation step being run.
  int step;

  /// The step's length in seconds, in Q16.16.
  int dtFixed;
}

/// What [WasmInstance.render] is handed: the frame and the view.
///
/// **One object, so a minor can hand a render call more**, for the reason
/// [WasmInstantiation] gives. **Reused**, as [WasmStep] is: the render
/// node that calls a module owns one and sets it before every frame.
final class WasmRenderCall {
  /// A render call for frame nought and view nought, for the owner to set
  /// before each frame.
  WasmRenderCall({this.frame = 0, this.view = 0});

  /// The frame being drawn, counted by the renderer from nought.
  int frame;

  /// The view being drawn, by its index in the frame.
  int view;
}
