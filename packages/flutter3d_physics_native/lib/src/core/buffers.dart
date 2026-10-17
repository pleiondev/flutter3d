/// Blocks of the core's memory by element — P9, phase 12.
///
/// An address with the element's width: what a `Pointer<Float>` was, read
/// and written by index, handed to a call as the address it is, and freed
/// back to the core. The same natively and in the browser.
library;

import 'dart:typed_data';

import 'memory.dart';

/// Floats.
extension type const F32s(int address) implements int {
  F32s.alloc(int count) : address = coreAlloc(count * 4);
  double operator [](int i) => readF32(address + i * 4);
  void operator []=(int i, double value) => writeF32(address + i * 4, value);
  Float32List copy(int count) => copyF32s(address, count);
  void setAll(List<double> values) => setF32s(address, values);
  void free() => coreFree(address);
}

/// Doubles.
extension type const F64s(int address) implements int {
  F64s.alloc(int count) : address = coreAlloc(count * 8);
  double operator [](int i) => readF64(address + i * 8);
  void operator []=(int i, double value) => writeF64(address + i * 8, value);
  void free() => coreFree(address);
}

/// Bytes.
extension type const U8s(int address) implements int {
  U8s.alloc(int count) : address = coreAlloc(count);
  int operator [](int i) => readU8(address + i);
  void operator []=(int i, int value) => writeU8(address + i, value);
  Uint8List copy(int count) => copyU8s(address, count);
  void setAll(List<int> values) => setU8s(address, values);
  void free() => coreFree(address);
}

/// Unsigned 32-bit words.
extension type const U32s(int address) implements int {
  U32s.alloc(int count) : address = coreAlloc(count * 4);
  int operator [](int i) => readU32(address + i * 4);
  void operator []=(int i, int value) => writeU32(address + i * 4, value);
  void free() => coreFree(address);
}

/// Signed 32-bit words.
extension type const I32s(int address) implements int {
  I32s.alloc(int count) : address = coreAlloc(count * 4);
  int operator [](int i) => readI32(address + i * 4);
  void operator []=(int i, int value) => writeI32(address + i * 4, value);
  void free() => coreFree(address);
}

/// Unsigned 64-bit words: body and joint handles.
extension type const U64s(int address) implements int {
  U64s.alloc(int count) : address = coreAlloc(count * 8);
  int operator [](int i) => readU64(address + i * 8);
  void operator []=(int i, int value) => writeU64(address + i * 8, value);
  void free() => coreFree(address);
}
