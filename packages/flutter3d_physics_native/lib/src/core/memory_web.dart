/// The core's memory in the browser: an address is an offset into the
/// WebAssembly module's memory — P9, phase 12.
///
/// Read and written through a JavaScript DataView, which takes the threads
/// build's SharedArrayBuffer as readily as an ArrayBuffer.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'calls_web.g.dart' as c;
import 'module_web.dart';

@JS('DataView')
extension type _DataView._(JSObject _) implements JSObject {
  external factory _DataView(JSObject buffer);
  external double getFloat32(int at, bool little);
  external void setFloat32(int at, double value, bool little);
  external double getFloat64(int at, bool little);
  external void setFloat64(int at, double value, bool little);
  external int getUint8(int at);
  external void setUint8(int at, int value);
  external int getUint32(int at, bool little);
  external void setUint32(int at, int value, bool little);
  external int getInt32(int at, bool little);
  external void setInt32(int at, int value, bool little);
}

_DataView? _view;
int _viewLength = -1;

/// The memory as it is now. Growing, the memory hands over a new, longer
/// buffer — the old one detached, or for a shared memory left short — so
/// the view is kept while the memory's buffer is as long as it was.
_DataView get _bytes {
  final buffer = coreBufferObject();
  final length = coreBufferLength(buffer);
  final view = _view;
  if (view != null && length == _viewLength) return view;
  _viewLength = length;
  return _view = _DataView(buffer);
}

/// [bytes] of the core's memory, zeroed; throws when there is none to give.
int coreAlloc(int bytes) {
  final size = bytes < 16 ? 16 : bytes;
  final address = c.f3d_buffer_alloc(size);
  if (address == 0) {
    throw StateError('the physics core has no memory for $size bytes');
  }
  final b = _bytes;
  for (var i = 0; i < size; i++) {
    b.setUint8(address + i, 0);
  }
  return address;
}

void coreFree(int address) => c.f3d_buffer_free(address);

double readF32(int address) => _bytes.getFloat32(address, true);
void writeF32(int address, double value) =>
    _bytes.setFloat32(address, value, true);
double readF64(int address) => _bytes.getFloat64(address, true);
void writeF64(int address, double value) =>
    _bytes.setFloat64(address, value, true);
int readU8(int address) => _bytes.getUint8(address);
void writeU8(int address, int value) => _bytes.setUint8(address, value);
int readU32(int address) => _bytes.getUint32(address, true);
void writeU32(int address, int value) => _bytes.setUint32(address, value, true);
int readI32(int address) => _bytes.getInt32(address, true);
void writeI32(int address, int value) => _bytes.setInt32(address, value, true);
int readU64(int address) => joinHalves(readU32(address), readU32(address + 4));
void writeU64(int address, int value) {
  writeU32(address, lowHalf(value));
  writeU32(address + 4, highHalf(value));
}

Float32List copyF32s(int address, int count) {
  final b = _bytes;
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = b.getFloat32(address + i * 4, true);
  }
  return out;
}

void setF32s(int address, List<double> values) {
  final b = _bytes;
  for (var i = 0; i < values.length; i++) {
    b.setFloat32(address + i * 4, values[i], true);
  }
}

Uint8List copyU8s(int address, int count) {
  final b = _bytes;
  final out = Uint8List(count);
  for (var i = 0; i < count; i++) {
    out[i] = b.getUint8(address + i);
  }
  return out;
}

void setU8s(int address, List<int> values) {
  final b = _bytes;
  for (var i = 0; i < values.length; i++) {
    b.setUint8(address + i, values[i]);
  }
}
