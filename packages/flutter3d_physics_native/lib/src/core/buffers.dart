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
  /// Allocates [count] floats of the core's memory, zeroed, at least 16
  /// bytes. Throws a [StateError] when the core has no memory to give.
  F32s.alloc(int count) : address = coreAlloc(count * 4);

  /// Reads the float at index [i], four bytes apiece from [address].
  double operator [](int i) => readF32(address + i * 4);

  /// Writes [value], rounded to a float, at index [i].
  void operator []=(int i, double value) => writeF32(address + i * 4, value);

  /// Copies the first [count] floats out into a list of Dart's own.
  Float32List copy(int count) => copyF32s(address, count);

  /// Writes [values] from index nought on; the block must hold them all.
  void setAll(List<double> values) => setF32s(address, values);

  /// Frees the block back to the core; it must not be used after.
  void free() => coreFree(address);
}

/// Doubles.
extension type const F64s(int address) implements int {
  /// Allocates [count] doubles of the core's memory, zeroed, at least 16
  /// bytes. Throws a [StateError] when the core has no memory to give.
  F64s.alloc(int count) : address = coreAlloc(count * 8);

  /// Reads the double at index [i], eight bytes apiece from [address].
  double operator [](int i) => readF64(address + i * 8);

  /// Writes [value] at index [i].
  void operator []=(int i, double value) => writeF64(address + i * 8, value);

  /// Frees the block back to the core; it must not be used after.
  void free() => coreFree(address);
}

/// Bytes.
extension type const U8s(int address) implements int {
  /// Allocates [count] bytes of the core's memory, zeroed, at least 16.
  /// Throws a [StateError] when the core has no memory to give.
  U8s.alloc(int count) : address = coreAlloc(count);

  /// Reads the byte at index [i], from nought to 255.
  int operator [](int i) => readU8(address + i);

  /// Writes the low eight bits of [value] at index [i].
  void operator []=(int i, int value) => writeU8(address + i, value);

  /// Copies the first [count] bytes out into a list of Dart's own.
  Uint8List copy(int count) => copyU8s(address, count);

  /// Writes [values] from index nought on; the block must hold them all.
  void setAll(List<int> values) => setU8s(address, values);

  /// Frees the block back to the core; it must not be used after.
  void free() => coreFree(address);
}

/// Unsigned 32-bit words.
extension type const U32s(int address) implements int {
  /// Allocates [count] words of the core's memory, zeroed, at least 16
  /// bytes. Throws a [StateError] when the core has no memory to give.
  U32s.alloc(int count) : address = coreAlloc(count * 4);

  /// Reads the word at index [i], four bytes apiece from [address].
  int operator [](int i) => readU32(address + i * 4);

  /// Writes [value] as an unsigned 32-bit word at index [i].
  void operator []=(int i, int value) => writeU32(address + i * 4, value);

  /// Frees the block back to the core; it must not be used after.
  void free() => coreFree(address);
}

/// Signed 32-bit words.
extension type const I32s(int address) implements int {
  /// Allocates [count] words of the core's memory, zeroed, at least 16
  /// bytes. Throws a [StateError] when the core has no memory to give.
  I32s.alloc(int count) : address = coreAlloc(count * 4);

  /// Reads the word at index [i], four bytes apiece from [address].
  int operator [](int i) => readI32(address + i * 4);

  /// Writes [value] as a signed 32-bit word at index [i].
  void operator []=(int i, int value) => writeI32(address + i * 4, value);

  /// Frees the block back to the core; it must not be used after.
  void free() => coreFree(address);
}

/// Unsigned 64-bit words: body and joint handles.
extension type const U64s(int address) implements int {
  /// Allocates [count] words of the core's memory, zeroed, at least 16
  /// bytes. Throws a [StateError] when the core has no memory to give.
  U64s.alloc(int count) : address = coreAlloc(count * 8);

  /// Reads the word at index [i], eight bytes apiece from [address].
  int operator [](int i) => readU64(address + i * 8);

  /// Writes [value] as a 64-bit word at index [i].
  void operator []=(int i, int value) => writeU64(address + i * 8, value);

  /// Frees the block back to the core; it must not be used after.
  void free() => coreFree(address);
}
