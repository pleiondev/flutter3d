/// Packed keys where an integer is a double.
///
/// See `packed_keys.dart` for why there are two of these.
library;

import 'dart:typed_data';

/// A growable buffer of (key, payload) pairs, sorted ascending by key.
///
/// Key and payload are kept apart rather than packed, which is the whole trick:
/// a key is at most `kSortKeyBits` wide, so a double holds it exactly, and the
/// ordering that comes out is identical to the native one rather than a coarser
/// approximation of it.
///
/// Sorted by permuting an index list rather than by moving keys, so stability
/// costs nothing to arrange: ties fall back to the index, which is submission
/// order, which is what the native form gets from having the payload in its low
/// bits.
///
/// A comparison sort and not a radix one, deliberately. Radix over a double's
/// bit pattern would work — non-negative IEEE-754 doubles order as unsigned
/// integers — but it would mean a second byte-extraction path to keep correct
/// for a platform already an order of magnitude off native speed. The cost is
/// paid where it matters least.
final class PackedKeys {
  PackedKeys([int capacity = 128])
    : _keys = Float64List(capacity),
      _payloads = Int32List(capacity),
      _order = List<int>.filled(capacity, 0, growable: false),
      _sortedPayloads = Int32List(capacity);

  Float64List _keys;
  Int32List _payloads;
  List<int> _order;
  Int32List _sortedPayloads;

  void ensure(int count) {
    if (count <= _keys.length) return;
    var capacity = _keys.length;
    while (capacity < count) {
      capacity *= 2;
    }
    _keys = Float64List(capacity);
    _payloads = Int32List(capacity);
    _order = List<int>.filled(capacity, 0, growable: false);
    _sortedPayloads = Int32List(capacity);
  }

  void setEntry(int index, int key, int payload) {
    _keys[index] = key.toDouble();
    _payloads[index] = payload;
  }

  void sort(int count) {
    if (count < 2) {
      // Still copy: a caller reads payloadAt after every sort, and returning
      // early with the output untouched hands back last frame's entry — or a
      // zero, on the first frame, which is a valid draw index and so wrong
      // rather than obviously wrong.
      if (count == 1) _sortedPayloads[0] = _payloads[0];
      return;
    }
    for (var i = 0; i < count; i++) {
      _order[i] = i;
    }
    // A view, so the sort touches only the entries this frame filled.
    final slice = _order.sublist(0, count)
      ..sort((int a, int b) {
        final byKey = _keys[a].compareTo(_keys[b]);
        // Equal keys keep the order they arrived in. Dart's sort is not
        // guaranteed stable, so stability is arranged here rather than assumed
        // — and "manual" sort mode is exactly the case that would notice.
        return byKey != 0 ? byKey : a - b;
      });
    for (var i = 0; i < count; i++) {
      _sortedPayloads[i] = _payloads[slice[i]];
    }
  }

  int payloadAt(int index) => _sortedPayloads[index];
}
