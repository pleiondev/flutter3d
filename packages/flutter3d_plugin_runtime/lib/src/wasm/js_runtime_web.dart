import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'abi.dart';
import 'module.dart';

/// The browser's own WebAssembly: what a web build may run a module on when
/// it wants the speed and can give up the meter.
WasmRuntime? browserWasmRuntime() => const _BrowserRuntime();

@JS('WebAssembly.Module')
extension type _JsModule._(JSObject _) implements JSObject {
  external factory _JsModule(JSUint8Array bytes);
}

@JS('WebAssembly.Instance')
extension type _JsInstance._(JSObject _) implements JSObject {
  external factory _JsInstance(_JsModule module, JSObject imports);

  external JSObject get exports;
}

extension type _JsMemory._(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;

  external int grow(int pages);
}

/// **Fast and unmetered.** The module is decoded and checked by
/// [WasmModule.decode] first, so it is refused here exactly as everywhere
/// else, and its memory is held by the maximum it declares, which must be
/// within the limit. What the browser cannot be asked is to count
/// instructions or calls: a module that loops for ever hangs the page, and
/// the fuel a step spent is not known. So a run a server replays is stepped
/// by the interpreter, and this is for a game that trusts its modules.
///
/// Its saves hold what the module exports — its memory and its exported
/// mutable globals, by name — because the browser keeps the rest out of
/// reach; the interpreter's saves hold the same, and the rest under
/// `internal`, which this ignores. A module that keeps state in a global
/// it does not export is not restored whole here. Under a bit-exact
/// profile a simulating module is refused this runtime
/// (`installWasmSystem`): a module that runs out of fuel traps only on the
/// interpreter a replay steps it on.
final class _BrowserRuntime extends WasmRuntime {
  const _BrowserRuntime();

  @override
  String get name => 'browser';

  @override
  bool get isMetered => false;

  @override
  WasmInstance instantiate(WasmInstantiation request) {
    final WasmInstantiation(:module, :imports, :limits) = request;
    final min = module.memoryMin;
    if (min != null) {
      final max = module.memoryMax;
      if (max == null || max > limits.memoryPages) {
        throw WasmException(
          'the browser cannot stop a memory from growing, so a module run '
          'there declares a maximum within ${limits.memoryPages} pages; '
          'this one declares ${max ?? 'none'}',
        );
      }
    }
    final f3d = JSObject()
      ..['field_len'] =
          ((JSNumber field) => imports.fieldLength(field.toDartInt).toJS).toJS
      ..['field_get'] =
          ((JSNumber field, JSNumber index) =>
                  imports.fieldGet(field.toDartInt, index.toDartInt).toJS)
              .toJS
      ..['field_set'] =
          ((JSNumber field, JSNumber index, JSNumber value) => imports.fieldSet(
            field.toDartInt,
            index.toDartInt,
            value.toDartInt,
          )).toJS
      ..['publish'] =
          ((JSNumber event, JSNumber a, JSNumber b) => imports.publish(
            event.toDartInt,
            a.toDartInt,
            b.toDartInt,
          )).toJS
      ..['field_frac'] =
          ((JSNumber field) => imports.fieldFractionBits(field.toDartInt).toJS)
              .toJS;
    late final _BrowserInstance running;
    if (request.render case final render?) {
      // A render module's imports (ABI 3). `param_floats` reads the floats
      // from the module's exported memory during the call and hands the
      // copy on; the browser's own memory is never handed out.
      f3d
        ..['param'] =
            ((JSNumber parameter, JSNumber component, JSNumber value) =>
                    render.param(
                      parameter.toDartInt,
                      component.toDartInt,
                      value.toDartDouble,
                    ))
                .toJS
        ..['param_floats'] =
            ((JSNumber parameter, JSNumber pointer, JSNumber length) =>
                    render.paramFloats(
                      parameter.toDartInt,
                      running._floats(pointer.toDartInt, length.toDartInt),
                    ))
                .toJS
        ..['draw'] = render.draw.toJS
        ..['time'] = (() => render.timeSeconds.toJS).toJS
        ..['view_size'] =
            ((JSNumber axis) => render.viewSize(axis.toDartInt).toJS).toJS
        ..['light_code'] =
            ((JSNumber light) => render.lightCode(light.toDartInt).toJS).toJS;
    }
    final importObject = JSObject()..['f3d'] = f3d;
    final _JsInstance instance;
    try {
      instance = _JsInstance(_JsModule(module.bytes.toJS), importObject);
    } on WasmTrapException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WasmTrapException('the browser stopped the module: $error'),
        stackTrace,
      );
    }
    final runtime = running = _BrowserInstance(module, instance.exports);
    final abi = runtime._call('f3d_abi', const <int>[]);
    final refusal = wasmAbiRefusal(abi, module.importNames, kind: module.kind);
    if (refusal != null) throw WasmException(refusal);
    runtime._abi = abi;
    return runtime;
  }
}

final class _BrowserInstance extends WasmInstance {
  _BrowserInstance(this._module, this._exports);

  final WasmModule _module;
  final JSObject _exports;

  @override
  int get fuelUsed => 0;

  int _abi = wasmPluginAbiMin;

  @override
  int get abi => _abi;

  int _call(String export, List<int> args) {
    final function = _exports[export]! as JSFunction;
    try {
      final result = switch (args.length) {
        0 => function.callAsFunction(),
        _ => function.callAsFunction(null, args[0].toJS, args[1].toJS),
      };
      return result == null ? 0 : (result as JSNumber).toDartInt;
    } on WasmTrapException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WasmTrapException('the module trapped: $error'),
        stackTrace,
      );
    }
  }

  @override
  void step(WasmStep step) => _call('f3d_step', <int>[
    step.step.toSigned(32),
    step.dtFixed.toSigned(32),
  ]);

  @override
  void render(WasmRenderCall call) => _call(wasmRenderNodeExport, <int>[
    call.frame.toSigned(32),
    call.view.toSigned(32),
  ]);

  /// [length] bytes of floats at [pointer] in the module's exported memory,
  /// copied; a trap where the module exports none or the range runs past it.
  Float32List _floats(int pointer, int length) {
    final memory = _memory;
    if (memory == null) {
      throw const WasmTrapException(
        'the module called param_floats and exports no memory to read the '
        'floats from; a render module run in the browser exports its memory',
      );
    }
    final bytes = memory.buffer.toDart.asByteData();
    final at = pointer & 0xFFFFFFFF;
    final size = length & 0xFFFFFFFF;
    if (size % 4 != 0 || at + size > bytes.lengthInBytes) {
      throw WasmTrapException(
        'the module handed param_floats $size bytes at $at, which are not '
        'whole floats inside its memory',
      );
    }
    return Float32List.fromList(<double>[
      for (var i = 0; i < size; i += 4) bytes.getFloat32(at + i, Endian.little),
    ]);
  }

  _JsMemory? get _memory {
    final name = _module.memoryExport;
    return name == null ? null : _exports[name] as _JsMemory?;
  }

  List<String> get _globals => savedGlobalsOf(_module).keys.toList();

  @override
  Map<String, Object?> save() {
    final memory = _memory;
    final bytes = memory == null
        ? Uint8List(0)
        : memory.buffer.toDart.asUint8List();
    var last = bytes.length;
    while (last > 0 && bytes[last - 1] == 0) {
      last--;
    }
    return <String, Object?>{
      'pages': bytes.length ~/ 65536,
      'memory': base64Encode(Uint8List.sublistView(bytes, 0, last)),
      'globals': <String, Object?>{
        for (final name in _globals)
          name: ((_exports[name]! as JSObject)['value']! as JSNumber).toDartInt,
      },
    };
  }

  /// Puts back what [save] wrote.
  ///
  /// **Everything is checked before anything is replaced**, as the
  /// interpreter does: pages out of the module's range, memory that is not
  /// base64 or does not fit its pages, globals that are not this module's
  /// exported ones are refused with a [WasmFormatException], and the module
  /// is left as it was. A memory never shrinks here — the browser cannot —
  /// so fewer pages than it has leaves the rest zeroed.
  @override
  void restore(Map<String, Object?> state) {
    const refused = WasmFormatException('not the state of this Wasm module');
    final pages = state['pages'];
    final saved = state['memory'];
    final globals = state['globals'];
    final names = _globals;
    final memory = _memory;
    final most = memory == null ? 0 : _module.memoryMax ?? 0;
    if (pages is! int ||
        pages < 0 ||
        pages > most ||
        saved is! String ||
        globals is! Map<String, Object?> ||
        globals.length != names.length ||
        !names.every((name) => globals[name] is int)) {
      throw refused;
    }
    final Uint8List restored;
    try {
      restored = base64Decode(saved);
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(refused, stackTrace);
    }
    if (restored.length > pages * 65536) throw refused;
    if (memory != null) {
      final now = memory.buffer.toDart.lengthInBytes ~/ 65536;
      if (pages > now) memory.grow(pages - now);
      memory.buffer.toDart.asUint8List()
        ..fillRange(0, memory.buffer.toDart.lengthInBytes, 0)
        ..setRange(0, restored.length, restored);
    }
    for (final name in names) {
      (_exports[name]! as JSObject)['value'] = (globals[name]! as int).toJS;
    }
  }
}
