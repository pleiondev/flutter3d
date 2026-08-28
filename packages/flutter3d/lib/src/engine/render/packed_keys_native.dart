/// Packed keys on a platform with real 64-bit integers.
///
/// See `packed_keys.dart` for why there are two of these.
library;

import 'dart:typed_data';

import 'key_sort.dart';

/// A growable buffer of (key, payload) pairs, sorted ascending by key.
///
/// Key and payload live in one integer here — the payload in the low bits, so
/// that a single sort orders the draws and, being stable with the payload
/// least significant, equal keys keep submission order for free.
final class PackedKeys {
  PackedKeys([int capacity = 128])
    : _buffer = Int64List(capacity),
      _scratch = Int64List(capacity);

  Int64List _buffer;
  Int64List _scratch;
  final Uint32List _histogram = Uint32List(256);

  /// Grows to hold at least [count] entries, doubling rather than fitting
  /// exactly so a frame that keeps growing stops reallocating.
  void ensure(int count) {
    if (count <= _buffer.length) return;
    var capacity = _buffer.length;
    while (capacity < count) {
      capacity *= 2;
    }
    _buffer = Int64List(capacity);
    _scratch = Int64List(capacity);
  }

  void setEntry(int index, int key, int payload) {
    _buffer[index] = (key << kPayloadBits) | payload;
  }

  void sort(int count) =>
      sortPackedKeys(_buffer, _scratch, count, counts: _histogram);

  int payloadAt(int index) => _buffer[index] & kPayloadMask;
}
