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
/// mutable globals — because the browser keeps the rest out of reach. A
/// module that keeps state in a global it does not export is not restored
/// whole here.
final class _BrowserRuntime extends WasmRuntime {
  const _BrowserRuntime();

  @override
  String get name => 'browser';

  @override
  bool get isMetered => false;

  @override
  WasmInstance instantiate(
    WasmModule module,
    WasmImports imports,
    WasmLimits limits,
  ) {
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
    final importObject = JSObject()..['f3d'] = f3d;
    final _JsInstance instance;
    try {
      instance = _JsInstance(_JsModule(module.bytes.toJS), importObject);
    } on WasmTrapException {
      rethrow;
    } on Object catch (error) {
      throw WasmTrapException('the browser stopped the module: $error');
    }
    final runtime = _BrowserInstance(module, instance.exports);
    final abi = runtime._call('f3d_abi', const <int>[]);
    final refusal = wasmAbiRefusal(abi, module.importNames);
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
    } on Object catch (error) {
      throw WasmTrapException('the module trapped: $error');
    }
  }

  @override
  void step(int step, int dtFixed) =>
      _call('f3d_step', <int>[step.toSigned(32), dtFixed.toSigned(32)]);

  _JsMemory? get _memory {
    final name = _module.memoryExport;
    return name == null ? null : _exports[name] as _JsMemory?;
  }

  List<String> get _globals => <String>[
    for (final MapEntry(key: name, value: index)
        in _module.globalExports.entries)
      if (_module.globals[index].mutable) name,
  ];

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
      'globals': <int>[
        for (final name in _globals)
          ((_exports[name]! as JSObject)['value']! as JSNumber).toDartInt,
      ],
    };
  }

  @override
  void restore(Map<String, Object?> state) {
    final pages = state['pages'];
    final saved = state['memory'];
    final globals = state['globals'];
    if (pages is! int || saved is! String || globals is! List<Object?>) {
      throw const WasmFormatException('not the state of this Wasm module');
    }
    final memory = _memory;
    if (memory != null) {
      final now = memory.buffer.toDart.lengthInBytes ~/ 65536;
      if (pages > now) memory.grow(pages - now);
      final bytes = memory.buffer.toDart.asUint8List();
      final restored = base64Decode(saved);
      bytes
        ..fillRange(0, bytes.length, 0)
        ..setRange(0, restored.length, restored);
    }
    final names = _globals;
    for (var i = 0; i < names.length && i < globals.length; i++) {
      (_exports[names[i]]! as JSObject)['value'] = (globals[i]! as int).toJS;
    }
  }
}
