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

void coreFree(int address) => c.f3d_buffer_free(address);

double readF32(int address) => Pointer<Float>.fromAddress(address).value;
void writeF32(int address, double value) =>
    Pointer<Float>.fromAddress(address).value = value;
double readF64(int address) => Pointer<Double>.fromAddress(address).value;
void writeF64(int address, double value) =>
    Pointer<Double>.fromAddress(address).value = value;
int readU8(int address) => Pointer<Uint8>.fromAddress(address).value;
void writeU8(int address, int value) =>
    Pointer<Uint8>.fromAddress(address).value = value;
int readU32(int address) => Pointer<Uint32>.fromAddress(address).value;
void writeU32(int address, int value) =>
    Pointer<Uint32>.fromAddress(address).value = value;
int readI32(int address) => Pointer<Int32>.fromAddress(address).value;
void writeI32(int address, int value) =>
    Pointer<Int32>.fromAddress(address).value = value;
int readU64(int address) => Pointer<Uint64>.fromAddress(address).value;
void writeU64(int address, int value) =>
    Pointer<Uint64>.fromAddress(address).value = value;

Float32List copyF32s(int address, int count) => Float32List.fromList(
  Pointer<Float>.fromAddress(address).asTypedList(count),
);
void setF32s(int address, List<double> values) => Pointer<Float>.fromAddress(
  address,
).asTypedList(values.length).setAll(0, values);
Uint8List copyU8s(int address, int count) =>
    Uint8List.fromList(Pointer<Uint8>.fromAddress(address).asTypedList(count));
void setU8s(int address, List<int> values) => Pointer<Uint8>.fromAddress(
  address,
).asTypedList(values.length).setAll(0, values);
