/// The physics core's WebAssembly module in the browser — P9, phase 12.
///
/// Loaded once, before the first world: [loadPhysicsCore]. Its exports are
/// the core's calls; its memory is where every address points.
///
/// Asked for threads where the page has SharedArrayBuffer — served
/// cross-origin isolated, with COOP and COEP — it loads the threads build
/// instead, on a shared memory, and starts the workers it steps on: Web
/// Workers from `f3d_worker.js`, each an instance of the module on that
/// memory with a stack of its own. Elsewhere it loads the single-threaded
/// build, and a world asked for more than one thread says no.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('WebAssembly.compile')
external JSPromise<JSObject> _compile(JSArrayBuffer bytes);

@JS('WebAssembly.instantiate')
external JSPromise<JSObject> _instantiate(JSObject module, JSObject imports);

@JS('WebAssembly.Memory')
extension type _Memory._(JSObject _) implements JSObject {
  external factory _Memory(JSObject descriptor);
  external JSObject get buffer;
}

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url);
  external void postMessage(JSAny message);
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _Core(JSObject _) implements JSObject {
  @JS('f3d_wasm_high')
  external JSNumber high();
  @JS('f3d_wasm_workers_ready')
  external JSNumber workersReady();
  @JS('f3d_buffer_alloc')
  external JSNumber alloc(JSNumber bytes);
}

JSObject? _exports;
JSObject? _memory;
int _threads = 1;

/// Where the modules and the worker are fetched from when
/// [loadPhysicsCore] is given nothing: as a Flutter web app serves this
/// package's assets.
const String defaultPhysicsCoreUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_physics.wasm';
const String defaultPhysicsCoreThreadsUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_physics_threads.wasm';
const String defaultPhysicsWorkerUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_worker.js';

/// Each worker's stack, bytes.
const int _stackBytes = 1 << 20;

Future<JSArrayBuffer> _load(String url) async {
  final response = await _fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('fetching $url: HTTP ${response.status}');
  }
  return response.arrayBuffer().toDart;
}

JSObject _object(Map<String, JSAny?> fields) {
  final o = JSObject();
  for (final entry in fields.entries) {
    o.setProperty(entry.key.toJS, entry.value);
  }
  return o;
}

/// Whether the page can share memory with workers.
bool get _canShare => globalContext.has('SharedArrayBuffer');

/// Loads the core. With [threads] above one and a page that can share
/// memory, the threads build from [threadsUrl] and that many workers from
/// [workerUrl], the caller being one of them; else the single-threaded
/// build, from [bytes] when given or [url]. Done once; later calls return
/// at once.
Future<void> loadPhysicsCore({
  Uint8List? bytes,
  String url = defaultPhysicsCoreUrl,
  int threads = 1,
  String threadsUrl = defaultPhysicsCoreThreadsUrl,
  String workerUrl = defaultPhysicsWorkerUrl,
}) async {
  if (_exports != null) return;
  if (threads > 1 && _canShare) {
    final module = await _compile(await _load(threadsUrl)).toDart;
    final memory = _Memory(
      _object(<String, JSAny?>{
        'initial': 256.toJS,
        'maximum': 32768.toJS,
        'shared': true.toJS,
      }),
    );
    final instance = await _instantiate(
      module,
      _object(<String, JSAny?>{
        'env': _object(<String, JSAny?>{'memory': memory}),
      }),
    ).toDart;
    final exports = instance.getProperty<JSObject>('exports'.toJS);
    final core = exports as _Core;
    for (var i = 0; i < threads - 1; i++) {
      final stack = core.alloc(_stackBytes.toJS).toDartInt;
      _Worker(workerUrl.toJS).postMessage(
        _object(<String, JSAny?>{
          'module': module,
          'memory': memory,
          'index': i.toJS,
          'top': (stack + _stackBytes).toJS,
        }),
      );
    }
    while (core.workersReady().toDartInt < threads - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    _memory = memory;
    _exports = exports;
    _threads = threads;
    return;
  }
  final JSArrayBuffer source;
  if (bytes != null) {
    source = Uint8List.fromList(bytes).buffer.toJS;
  } else {
    source = await _load(url);
  }
  final module = await _compile(source).toDart;
  final instance = await _instantiate(module, JSObject()).toDart;
  final exports = instance.getProperty<JSObject>('exports'.toJS);
  _memory = exports.getProperty<JSObject>('memory'.toJS);
  _exports = exports;
  _threads = 1;
}

/// Whether [loadPhysicsCore] has run.
bool get physicsCoreLoaded => _exports != null;

/// The most threads a world can step on: the workers [loadPhysicsCore]
/// started and the caller.
int get physicsCoreThreads => _threads;

/// The module's exports.
JSObject get coreExports =>
    _exports ??
    (throw StateError(
      'the physics core is not loaded: await loadPhysicsCore() first',
    ));

/// The module's memory's buffer as it is now — replaced whenever it grows —
/// and its length.
JSObject coreBufferObject() {
  coreExports;
  return (_memory! as _Memory).buffer;
}

int coreBufferLength(JSObject buffer) =>
    buffer.getProperty<JSNumber>('byteLength'.toJS).toDartInt;

const int _two32 = 4294967296;

/// The low and high 32-bit halves of a 64-bit handle, and one put back
/// together — by arithmetic, which JavaScript's numbers keep exact to 2⁵³.
int lowHalf(int value) => value % _two32;
int highHalf(int value) => (value - lowHalf(value)) ~/ _two32;
int joinHalves(int low, int high) =>
    high.toUnsigned(32) * _two32 + low.toUnsigned(32);

/// The high half of the 64-bit value the last call gave.
int highResult() => (coreExports as _Core).high().toDartInt;
