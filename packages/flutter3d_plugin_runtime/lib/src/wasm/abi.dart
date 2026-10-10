import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException, PluginException;

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
/// outside the range is refused with the range named, so a module written
/// for ABI 1 keeps loading on every engine whose minimum is still 1.
const int wasmPluginAbi = wasmPluginAbiMax;

/// The oldest ABI this host runs a module for.
const int wasmPluginAbiMin = 1;

/// The newest ABI this host runs a module for.
///
/// 2 added the optional import `f3d.field_frac` and fields whose values
/// cross with fewer fraction bits than Q16.16 ([WasmFieldSpec.fractionBits]),
/// so a world position kilometres from the origin fits. Nothing in ABI 1
/// changed: an ABI-1 module runs under ABI 2 as it did.
const int wasmPluginAbiMax = 2;

/// Why a module that says it was written for [abi], and imports [imports],
/// cannot run here; null when it can.
///
/// **The imports are feature-detected.** Each host function arrived in an
/// ABI ([wasmImportSince]); a module that imports one newer than the ABI it
/// claims is asking for something its own declaration says it does not
/// know, and is refused naming the import. A module that leaves an optional
/// import out is not refused for that: it simply never calls it.
String? wasmAbiRefusal(int abi, Iterable<String> imports) {
  if (abi < wasmPluginAbiMin || abi > wasmPluginAbiMax) {
    return 'the module was written for Wasm plugin ABI $abi and this engine '
        'runs ABI $wasmPluginAbiMin to $wasmPluginAbiMax';
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

/// The ABI each host function arrived in, by its import name.
const Map<String, int> wasmImportSince = <String, int>{
  'field_len': 1,
  'field_get': 1,
  'field_set': 1,
  'publish': 1,
  'field_frac': 2,
};

/// How much a module may take of one step: memory, instructions, calls.
///
/// **Counted, not timed.** A wall-clock budget would trap on a slow phone and
/// not on a fast one, and a replay of the run would part from the recording
/// at the trap. Fuel is a count of instructions executed, so a module that
/// runs out does so at the same instruction on every machine and in every
/// replay.
final class WasmLimits {
  const WasmLimits({
    this.memoryPages = 16,
    this.fuelPerStep = 1000000,
    this.callDepth = 64,
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
    );
  }

  /// The most 64 KiB pages a module's memory may have, at the start and
  /// after every `memory.grow`.
  final int memoryPages;

  /// Instructions a module may execute in one step.
  final int fuelPerStep;

  /// How deep calls may nest inside one step.
  final int callDepth;

  Map<String, Object?> toJson() => <String, Object?>{
    'memoryPages': memoryPages,
    'fuelPerStep': fuelPerStep,
    'callDepth': callDepth,
  };
}

/// A Wasm system's declaration, or a module's saved state, that cannot be
/// read: the sentence names the key.
final class WasmFormatException extends Flutter3dFormatException {
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
  const WasmException(super.message);

  @override
  String toString() => 'WasmException: $message';
}

/// A module that stopped while running: an `unreachable`, a division by
/// nought, a read past its memory, a budget spent.
final class WasmTrapException extends PluginException {
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

/// Something that runs an ABI 1 module.
///
/// Two ship: [interpreter], plain Dart on every platform and metered, and
/// `browserWasmRuntime()`, the browser's own WebAssembly, which is not.
abstract base class WasmRuntime {
  const WasmRuntime();

  /// The interpreter: the default, and the runtime a replay is held to.
  static const WasmRuntime interpreter = WasmInterpreter();

  /// What this runtime is called in a report.
  String get name;

  /// Whether [WasmLimits.fuelPerStep] and [WasmLimits.callDepth] are held.
  bool get isMetered;

  /// [module], ready to step, with [imports] behind its imports. Runs its
  /// start function and checks `f3d_abi`; throws [WasmException] for a module
  /// these [limits] cannot hold and [WasmTrapException] for a start function that
  /// traps.
  WasmInstance instantiate(
    WasmModule module,
    WasmImports imports,
    WasmLimits limits,
  );
}

/// One running module.
abstract base class WasmInstance {
  const WasmInstance();

  /// Calls the module's `f3d_step(step, dt)`, [dtFixed] in Q16.16. Throws
  /// [WasmTrapException] when the module traps.
  void step(int step, int dtFixed);

  /// The module's state — its memory and its globals — as a document a
  /// snapshot can hold and `StateDigest` can fold: numbers, strings and
  /// lists only.
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
