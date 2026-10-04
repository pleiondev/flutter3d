/// The physics core's WebAssembly module in the browser — P9, phase 12.
///
/// Loaded once, before the first world: [loadPhysicsCore]. Its exports are
/// the core's calls; its memory is where every address points.
library;

import 'dart:js_interop';
import 'dart:typed_data';

@JS('WebAssembly.instantiate')
external JSPromise<_Instantiated> _instantiate(
  JSArrayBuffer bytes,
  JSObject imports,
);

extension type _Instantiated(JSObject _) implements JSObject {
  external _Instance get instance;
}

extension type _Instance(JSObject _) implements JSObject {
  external JSObject get exports;
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('Object')
external JSObject _object();

extension type _Memory(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
}

extension type _Core(JSObject _) implements JSObject {
  @JS('f3d_wasm_high')
  external JSNumber high();
  external _Memory get memory;
}

JSObject? _exports;

/// Where the module is fetched from when [loadPhysicsCore] is given
/// nothing: as a Flutter web app serves this package's asset.
const String defaultPhysicsCoreUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_physics.wasm';

/// Loads the core, from [bytes] when given, else fetched from [url]. Done
/// once; later calls return at once.
Future<void> loadPhysicsCore({
  Uint8List? bytes,
  String url = defaultPhysicsCoreUrl,
}) async {
  if (_exports != null) return;
  final JSArrayBuffer module;
  if (bytes != null) {
    module = Uint8List.fromList(bytes).buffer.toJS;
  } else {
    final response = await _fetch(url.toJS).toDart;
    if (!response.ok) {
      throw StateError(
        'fetching the physics core from $url: HTTP ${response.status}',
      );
    }
    module = await response.arrayBuffer().toDart;
  }
  final made = await _instantiate(module, _object()).toDart;
  _exports = made.instance.exports;
}

/// Whether [loadPhysicsCore] has run.
bool get physicsCoreLoaded => _exports != null;

/// The module's exports.
JSObject get coreExports =>
    _exports ??
    (throw StateError(
      'the physics core is not loaded: await loadPhysicsCore() first',
    ));

/// The module's memory as it is now: replaced whenever it grows.
ByteBuffer coreBuffer() => (coreExports as _Core).memory.buffer.toDart;

const int _two32 = 4294967296;

/// The low and high 32-bit halves of a 64-bit handle, and one put back
/// together — by arithmetic, which JavaScript's numbers keep exact to 2⁵³.
int lowHalf(int value) => value % _two32;
int highHalf(int value) => (value - lowHalf(value)) ~/ _two32;
int joinHalves(int low, int high) =>
    high.toUnsigned(32) * _two32 + low.toUnsigned(32);

/// The high half of the 64-bit value the last call gave.
int highResult() => (coreExports as _Core).high().toDartInt;
