/// The core's memory natively: an address is a pointer — P9, phase 12.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'calls_native.g.dart' as c;

/// [bytes] of the core's memory, zeroed; throws when there is none to give.
int coreAlloc(int bytes) {
  final size = bytes < 16 ? 16 : bytes;
  final address = c.f3d_buffer_alloc(size);
  if (address == 0) {
    throw StateError('the physics core has no memory for $size bytes');
  }
  Pointer<Uint8>.fromAddress(address).asTypedList(size).fillRange(0, size, 0);
  return address;
}

/// Frees a block [coreAlloc] gave back to the core.
void coreFree(int address) => c.f3d_buffer_free(address);

/// Reads the float at [address].
double readF32(int address) => Pointer<Float>.fromAddress(address).value;

/// Writes [value], rounded to a float, at [address].
void writeF32(int address, double value) =>
    Pointer<Float>.fromAddress(address).value = value;

/// Reads the double at [address].
double readF64(int address) => Pointer<Double>.fromAddress(address).value;

/// Writes the double [value] at [address].
void writeF64(int address, double value) =>
    Pointer<Double>.fromAddress(address).value = value;

/// Reads the byte at [address], from nought to 255.
int readU8(int address) => Pointer<Uint8>.fromAddress(address).value;

/// Writes the low eight bits of [value] at [address].
void writeU8(int address, int value) =>
    Pointer<Uint8>.fromAddress(address).value = value;

/// Reads the unsigned 32-bit word at [address].
int readU32(int address) => Pointer<Uint32>.fromAddress(address).value;

/// Writes [value] as an unsigned 32-bit word at [address].
void writeU32(int address, int value) =>
    Pointer<Uint32>.fromAddress(address).value = value;

/// Reads the signed 32-bit word at [address].
int readI32(int address) => Pointer<Int32>.fromAddress(address).value;

/// Writes [value] as a signed 32-bit word at [address].
void writeI32(int address, int value) =>
    Pointer<Int32>.fromAddress(address).value = value;

/// Reads the unsigned 64-bit word at [address]: a body or joint handle.
int readU64(int address) => Pointer<Uint64>.fromAddress(address).value;

/// Writes [value] as a 64-bit word at [address].
void writeU64(int address, int value) =>
    Pointer<Uint64>.fromAddress(address).value = value;

/// [count] floats from [address], copied out into a list of Dart's own.
Float32List copyF32s(int address, int count) => Float32List.fromList(
  Pointer<Float>.fromAddress(address).asTypedList(count),
);

/// Writes [values] as floats from [address] on.
void setF32s(int address, List<double> values) => Pointer<Float>.fromAddress(
  address,
).asTypedList(values.length).setAll(0, values);

/// [count] bytes from [address], copied out into a list of Dart's own.
Uint8List copyU8s(int address, int count) =>
    Uint8List.fromList(Pointer<Uint8>.fromAddress(address).asTypedList(count));

/// Writes [values] as bytes from [address] on.
void setU8s(int address, List<int> values) => Pointer<Uint8>.fromAddress(
  address,
).asTypedList(values.length).setAll(0, values);
