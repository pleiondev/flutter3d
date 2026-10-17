/// The idle staging textures a readback keeps, held to a number.
library;

import 'dart:collection';

/// Idle values by key, at most [capacity] of them in all, the one given back
/// longest ago dropped first.
///
/// **Why a bound.** The readback pool kept every staging texture it ever
/// made, by size and format, for the device's life: a tool that read regions
/// of many sizes, or a window resized through a hundred sizes with an
/// exposure meter reading each frame, kept one texture per size it had ever
/// seen. flutter_gpu has no dispose, so a texture the pool drops is one the
/// collector frees; a texture it keeps is one nothing can. A meter and a
/// pick need two or three; [capacity] holds a few more, and past it the
/// oldest idle one goes.
final class StagingPool<K extends Object, T extends Object> {
  /// A pool keeping at most [capacity] idle values.
  StagingPool({this.capacity = 8}) : assert(capacity >= 0, 'a count');

  /// How many idle values the pool keeps, across every key.
  final int capacity;

  /// Idle values, oldest given back first, each with its key.
  final LinkedHashMap<T, K> _idle = LinkedHashMap<T, K>.identity();

  /// How many values are idle now.
  int get idle => _idle.length;

  /// An idle value for [key], the one given back most recently, or null
  /// when there is none and the caller makes one.
  T? take(K key) {
    T? found;
    for (final MapEntry(key: value, value: k) in _idle.entries) {
      if (k == key) found = value;
    }
    if (found != null) _idle.remove(found);
    return found;
  }

  /// Gives [value] back as idle under [key]; when that is one more than
  /// [capacity], the value given back longest ago is dropped, and handed to
  /// [onDropped] for a backend that can free it.
  void give(K key, T value, {void Function(T dropped)? onDropped}) {
    _idle[value] = key;
    while (_idle.length > capacity) {
      final oldest = _idle.keys.first;
      _idle.remove(oldest);
      onDropped?.call(oldest);
    }
  }
}
