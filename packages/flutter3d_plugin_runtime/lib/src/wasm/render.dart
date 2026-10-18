import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'abi.dart';
import 'module.dart';
import 'system.dart' show wasmSha256Of;

/// What a render module is (ABI 3): the module, the render step of its
/// plugin it drives, and what it names by index.
///
/// ```json
/// "wasmRender": [{"module": "pulse.wasm", "step": "pulse",
///                 "parameters": ["tint", "strength"],
///                 "lights": ["tube"],
///                 "limits": {"fuelPerFrame": 50000}}]
/// ```
///
/// **The indices are the ABI**, as a step system's fields are: a module
/// calls `param(1, 0, 0.5)` for the first component of the second of
/// [parameters] and `light_code(0)` for the first of [lights]; the names
/// live here, in the declaration a person reads.
///
/// **Declared under `wasmRender`, and that is what makes it a render
/// module** ([WasmModuleKind.render]): it is decoded as one, so it may
/// compute in `f32`, needs no `f3d_step`, and is refused a step module's
/// import, at load.
final class WasmRenderSpec {
  /// A render module [module] driving the plugin's render step [step], with
  /// no parameters or lights and the default [WasmLimits] unless given. A
  /// null [sha256] is allowed only for a module in the plugin's own files.
  const WasmRenderSpec({
    required this.module,
    required this.step,
    this.parameters = const <String>[],
    this.lights = const <String>[],
    this.limits = const WasmLimits(),
    this.sha256,
    this.unknown = const <String, Object?>{},
  });

  /// Reads the keys [toJson] writes. Throws a [WasmFormatException] saying
  /// which key is wrong.
  factory WasmRenderSpec.fromJson(Map<String, Object?> json) {
    String text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => throw WasmFormatException('a Wasm render node names no "$key"'),
    };
    List<String> names(String key) => switch (json[key]) {
      null => const <String>[],
      final List<Object?> list
          when list.every((e) => e is String && e.isNotEmpty) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw WasmFormatException('"$key" is not a list of names'),
    };
    return WasmRenderSpec(
      module: text('module'),
      step: text('step'),
      parameters: names('parameters'),
      lights: names('lights'),
      limits: switch (json['limits']) {
        null => const WasmLimits(),
        final Map<String, Object?> map => WasmLimits.fromJson(map),
        _ => throw const WasmFormatException('"limits" is not an object'),
      },
      sha256: wasmSha256Of(json),
      unknown: FormatDocument.nestedUnknownIn(json, known: keys),
    );
  }

  /// The keys a declaration is written with.
  static const Set<String> keys = <String>{
    'module',
    'step',
    'parameters',
    'lights',
    'limits',
    'sha256',
  };

  /// The `.wasm`, relative to the plugin's own directory, or an `https:`
  /// URL, which needs [sha256] and the `network` permission.
  final String module;

  /// The render step of the same document it drives, by the name its
  /// `renderSteps` entry gives it (without the plugin's prefix).
  final String step;

  /// The uniforms of the step's stage the module sets, by ABI index.
  final List<String> parameters;

  /// The light types the module asks the codes of, by ABI index: a bare
  /// name is the plugin's own (`tube` is `<id>.tube`), a dotted one
  /// another's, as written.
  final List<String> lights;

  /// Its memory, its depth and its fuel per frame
  /// ([WasmLimits.fuelPerFrame]).
  final WasmLimits limits;

  /// The SHA-256 of [module]'s bytes, as a step system's
  /// ([WasmSystemSpec.sha256]): required of a module from a URL.
  final String? sha256;

  /// The keys this build does not read, as the document had them: written
  /// back after its own (`FormatDocument.nestedUnknownIn`).
  final Map<String, Object?> unknown;

  /// The declaration as a document writes it, with [unknown] written back
  /// after its own keys.
  Map<String, Object?> toJson() => FormatDocument.writeNested(<String, Object?>{
    'module': module,
    'step': step,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (lights.isNotEmpty) 'lights': lights,
    'limits': limits.toJson(),
    'sha256': ?sha256,
  }, unknown);
}

/// A render module run as a [RenderProgram]: the renderer calls [run] once
/// a frame, and the module's commands reach the step it drives.
///
/// **An instance of its own** (ABI 3), made here and shared with no step
/// system, so what a frame's call writes to its memory is in no save and no
/// digest: a client that draws and a server that never does stay one run.
///
/// **A trap switches it off, and says so.** A module that traps — a budget
/// spent, an index it does not declare, `unreachable` — throws a
/// [WasmTrapException] out of [run], which the renderer turns into the
/// node switched off with the plugin named; [trapped] keeps the message,
/// and the module is not called again.
final class WasmRenderNode extends RenderProgram {
  /// Instantiates [module], which must have been decoded as
  /// [WasmModuleKind.render], on [runtime] for [plugin]'s [spec].
  ///
  /// Throws a [WasmException] for a module that is not a render module of
  /// ABI 3 or later, or that the limits cannot hold.
  WasmRenderNode(
    this.spec,
    WasmModule module, {
    required this.plugin,
    WasmRuntime runtime = WasmRuntime.interpreter,
  }) {
    if (module.kind != WasmModuleKind.render) {
      throw WasmException(
        'plugin "$plugin": ${spec.module} was decoded as a step module, and '
        'a render node runs a module decoded as a render module',
      );
    }
    _imports = WasmRenderImports(
      parameters: spec.parameters.length,
      lights: <String>[
        for (final name in spec.lights)
          name.contains('.') ? name : '$plugin.$name',
      ],
    );
    _instance = runtime.instantiate(
      WasmInstantiation.render(module, render: _imports, limits: spec.limits),
    );
  }

  /// The declaration it was made from.
  final WasmRenderSpec spec;

  /// The id of the plugin it belongs to.
  final String plugin;

  late final WasmRenderImports _imports;
  late final WasmInstance _instance;
  final WasmRenderCall _call = WasmRenderCall();
  String? _trapped;

  /// What the module did when it trapped, or null while it runs.
  String? get trapped => _trapped;

  /// Instructions the last frame's call executed.
  int get fuelUsed => _instance.fuelUsed;

  @override
  List<String> get parameters => spec.parameters;

  @override
  void run(RenderProgramFrame frame) {
    final trapped = _trapped;
    if (trapped != null) throw WasmTrapException(trapped);
    try {
      _imports.during(
        frame,
        () => _instance.render(
          _call
            ..frame = frame.frame
            ..view = frame.view,
        ),
      );
    } on WasmTrapException catch (trap, stackTrace) {
      _trapped = trap.message;
      Error.throwWithStackTrace(
        WasmTrapException(
          'plugin "$plugin"\'s render module ${spec.module} trapped driving '
          '"${spec.step}": ${trap.message}',
        ),
        stackTrace,
      );
    }
  }
}
