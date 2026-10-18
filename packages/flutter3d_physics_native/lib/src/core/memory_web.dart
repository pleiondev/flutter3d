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

@JS('Float32Array')
extension type _Float32Array._(JSObject _) implements JSObject {
  external factory _Float32Array(JSObject buffer, int offset, int length);
  external JSFloat32Array slice();
  external void set(JSFloat32Array values);
}

@JS('Uint8Array')
extension type _Uint8Array._(JSObject _) implements JSObject {
  external factory _Uint8Array(JSObject buffer, int offset, int length);
  external void fill(int value);
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
  // At once rather than a byte a call: a water's block is tens of
  // thousands of bytes, and a call apiece cost more than the step.
  _Uint8Array(coreBufferObject(), address, size).fill(0);
  return address;
}

/// Frees a block [coreAlloc] gave back to the core.
void coreFree(int address) => c.f3d_buffer_free(address);

/// Reads the little-endian float at [address].
double readF32(int address) => _bytes.getFloat32(address, true);

/// Writes [value], rounded to a float, little-endian at [address].
void writeF32(int address, double value) =>
    _bytes.setFloat32(address, value, true);

/// Reads the little-endian double at [address].
double readF64(int address) => _bytes.getFloat64(address, true);

/// Writes the double [value] little-endian at [address].
void writeF64(int address, double value) =>
    _bytes.setFloat64(address, value, true);

/// Reads the byte at [address], from nought to 255.
int readU8(int address) => _bytes.getUint8(address);

/// Writes the low eight bits of [value] at [address].
void writeU8(int address, int value) => _bytes.setUint8(address, value);

/// Reads the little-endian unsigned 32-bit word at [address].
int readU32(int address) => _bytes.getUint32(address, true);

/// Writes [value] as a little-endian unsigned 32-bit word at [address].
void writeU32(int address, int value) => _bytes.setUint32(address, value, true);

/// Reads the little-endian signed 32-bit word at [address].
int readI32(int address) => _bytes.getInt32(address, true);

/// Writes [value] as a little-endian signed 32-bit word at [address].
void writeI32(int address, int value) => _bytes.setInt32(address, value, true);

/// Reads the 64-bit word at [address] as two 32-bit halves joined; exact up
/// to 2⁵³, as JavaScript's numbers are.
int readU64(int address) => joinHalves(readU32(address), readU32(address + 4));

/// Writes [value] as a 64-bit word at [address], its low half first.
void writeU64(int address, int value) {
  writeU32(address, lowHalf(value));
  writeU32(address + 4, highHalf(value));
}

/// [count] floats from [address], copied out in one go: the browser's own
/// copy of a typed array's range, which takes a shared memory too.
Float32List copyF32s(int address, int count) {
  if (count == 0) return Float32List(0);
  if (address % 4 != 0) {
    final b = _bytes;
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = b.getFloat32(address + i * 4, true);
    }
    return out;
  }
  return _Float32Array(coreBufferObject(), address, count).slice().toDart;
}

/// Writes [values] as floats from [address] on, in one go where [address]
/// is aligned to four bytes and a float at a time where it is not.
void setF32s(int address, List<double> values) {
  if (values.isEmpty) return;
  if (address % 4 != 0) {
    final b = _bytes;
    for (var i = 0; i < values.length; i++) {
      b.setFloat32(address + i * 4, values[i], true);
    }
    return;
  }
  final floats = values is Float32List ? values : Float32List.fromList(values);
  _Float32Array(coreBufferObject(), address, floats.length).set(floats.toJS);
}

/// [count] bytes from [address], copied out a byte at a time.
Uint8List copyU8s(int address, int count) {
  final b = _bytes;
  final out = Uint8List(count);
  for (var i = 0; i < count; i++) {
    out[i] = b.getUint8(address + i);
  }
  return out;
}

/// Writes [values] as bytes from [address] on, a byte at a time.
void setU8s(int address, List<int> values) {
  final b = _bytes;
  for (var i = 0; i < values.length; i++) {
    b.setUint8(address + i, values[i]);
  }
}
