/// The core's memory in the browser: an address is an offset into the
/// WebAssembly module's memory — P9, phase 12.
library;

import 'dart:typed_data';

import 'calls_web.g.dart' as c;
import 'module_web.dart';

ByteData? _view;

/// The memory as it is now; a view of a buffer the memory has since grown
/// out of has no bytes left, and is made again.
ByteData get _bytes {
  final view = _view;
  if (view != null && view.lengthInBytes != 0) return view;
  return _view = coreBuffer().asByteData();
}

/// [bytes] of the core's memory, zeroed; throws when there is none to give.
int coreAlloc(int bytes) {
  final size = bytes < 16 ? 16 : bytes;
  final address = c.f3d_buffer_alloc(size);
  if (address == 0) {
    throw StateError('the physics core has no memory for $size bytes');
  }
  _view = null;
  final b = _bytes;
  for (var i = 0; i < size; i++) {
    b.setUint8(address + i, 0);
  }
  return address;
}

void coreFree(int address) => c.f3d_buffer_free(address);

double readF32(int address) => _bytes.getFloat32(address, Endian.little);
void writeF32(int address, double value) =>
    _bytes.setFloat32(address, value, Endian.little);
double readF64(int address) => _bytes.getFloat64(address, Endian.little);
void writeF64(int address, double value) =>
    _bytes.setFloat64(address, value, Endian.little);
int readU8(int address) => _bytes.getUint8(address);
void writeU8(int address, int value) => _bytes.setUint8(address, value);
int readU32(int address) => _bytes.getUint32(address, Endian.little);
void writeU32(int address, int value) =>
    _bytes.setUint32(address, value, Endian.little);
int readI32(int address) => _bytes.getInt32(address, Endian.little);
void writeI32(int address, int value) =>
    _bytes.setInt32(address, value, Endian.little);
int readU64(int address) => joinHalves(readU32(address), readU32(address + 4));
void writeU64(int address, int value) {
  writeU32(address, lowHalf(value));
  writeU32(address + 4, highHalf(value));
}

Float32List copyF32s(int address, int count) {
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = readF32(address + i * 4);
  }
  return out;
}

void setF32s(int address, List<double> values) {
  for (var i = 0; i < values.length; i++) {
    writeF32(address + i * 4, values[i]);
  }
}

Uint8List copyU8s(int address, int count) =>
    Uint8List.fromList(Uint8List.sublistView(_bytes, address, address + count));

void setU8s(int address, List<int> values) => Uint8List.sublistView(
  _bytes,
  address,
  address + values.length,
).setAll(0, values);
