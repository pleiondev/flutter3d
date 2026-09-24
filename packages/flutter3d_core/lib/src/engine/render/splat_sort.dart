/// Putting a cloud in drawing order — `C1`.
///
/// **A counting sort over sixteen-bit keys, not a comparison sort over
/// floats.** What stood here before was `List.sort` with a closure reading a
/// `Float32List` of depths: `O(n log n)` compares, each an indirect call and
/// two loads, on a million splats every time the camera moved. A splat's
/// place in the order only has to be right to a fraction of the cloud's own
/// depth, so the depth is quantised to sixteen bits and sorted in two
/// byte-wide counting passes, each one walk over the keys and one over a
/// 256-entry histogram. That is `O(n)` with no comparator at all.
///
/// **`Uint32List`s on purpose, so native and web sort alike.** The render
/// list's `PackedKeys` packs key and payload into one 64-bit integer, which a
/// JavaScript number cannot hold, so on the web it is a different class with
/// a comparison sort behind it. Sixteen bits of key and a 32-bit index each
/// fit in a JavaScript integer exactly, so there is one implementation here
/// and the order that comes out is the same on every platform.
///
/// **By distance from the eye, the order `KHR_gaussian_splatting` names.**
/// Its `sortingMethod` is `cameraDistance`, and the choice has a consequence
/// the view-axis depth `SplatCloud.sortedBackToFront` uses does not: distance
/// does not change when the camera turns, only when it moves. So a camera
/// that looks around never re-sorts, and `SplatQuads` only has to ask
/// whether the eye has travelled far enough to matter.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../formats/splat/splat_cloud.dart';

/// The largest quantised distance: keys run `0..kSplatKeyMax`.
const int kSplatKeyMax = 0xFFFF;

/// Sorts the first [count] entries of [keys] ascending, carrying [order]
/// along, in two stable eight-bit counting passes.
///
/// Every key must be in `0..kSplatKeyMax`. [keyScratch] and [orderScratch]
/// must be at least [count] long and hold nothing afterwards; [counts] is a
/// 256-entry histogram, passed in so that a caller sorting every frame
/// allocates nothing.
///
/// **Stable, so ties keep the order they came in.** The low byte is sorted
/// first and the high byte second, and a counting pass never reorders equal
/// keys; the result is ordered by the whole sixteen bits, and two splats at
/// the same quantised distance stay in whatever order [order] gave them —
/// index order, when the caller filled it with `0, 1, 2, …`.
void sortSplatKeys(
  Uint32List keys,
  Uint32List order,
  Uint32List keyScratch,
  Uint32List orderScratch,
  int count,
  Uint32List counts,
) {
  if (count < 2) return;
  _countingPass(keys, order, keyScratch, orderScratch, count, counts, 0);
  _countingPass(keyScratch, orderScratch, keys, order, count, counts, 8);
}

void _countingPass(
  Uint32List fromKeys,
  Uint32List fromOrder,
  Uint32List toKeys,
  Uint32List toOrder,
  int count,
  Uint32List counts,
  int shift,
) {
  counts.fillRange(0, 256, 0);
  for (var i = 0; i < count; i++) {
    counts[(fromKeys[i] >> shift) & 0xFF]++;
  }
  // Counts become the first slot each byte value writes to.
  var running = 0;
  for (var b = 0; b < 256; b++) {
    final c = counts[b];
    counts[b] = running;
    running += c;
  }
  for (var i = 0; i < count; i++) {
    final key = fromKeys[i];
    final slot = counts[(key >> shift) & 0xFF]++;
    toKeys[slot] = key;
    toOrder[slot] = fromOrder[i];
  }
}

/// Keeps a cloud's back-to-front order and the scratch the sort needs.
///
/// One per drawn cloud, since the buffers are sized to it and reused: a
/// camera that moves every frame sorts every frame and allocates nothing.
final class SplatSorter {
  Uint32List _keys = Uint32List(0);
  Uint32List _order = Uint32List(0);
  Uint32List _keyScratch = Uint32List(0);
  Uint32List _orderScratch = Uint32List(0);
  final Uint32List _counts = Uint32List(256);

  /// The splat indices, farthest first, after the last [sort]. Only the
  /// first `cloud.count` entries mean anything.
  Uint32List get order => _order;

  /// The quantised keys in the same order as [order], ascending.
  Uint32List get keys => _keys;

  /// How far apart the nearest and farthest splat were at the last [sort],
  /// in world units. What `SplatQuads` measures a camera move against.
  double get lastRange => _lastRange;
  double _lastRange = 0.0;

  /// Orders [cloud] far to near by distance from [eye], with the cloud placed
  /// in the world by [model] when it is given.
  ///
  /// The distances are quantised across the range this cloud spans from
  /// this eye, not across a fixed one: sixteen bits over the cloud's own
  /// depth is what keeps a small cloud and a large one equally well ordered.
  void sort(SplatCloud cloud, Vector3 eye, {Matrix4? model}) {
    final count = cloud.count;
    if (_keys.length < count) {
      _keys = Uint32List(count);
      _order = Uint32List(count);
      _keyScratch = Uint32List(count);
      _orderScratch = Uint32List(count);
    }
    if (count == 0) {
      _lastRange = 0.0;
      return;
    }

    // Distances go in the key buffer's scratch twin first, as floats in a
    // view over it, so no second float array has to be kept alive: the
    // distances are only needed until they are quantised.
    final distances = Float32List.view(_keyScratch.buffer, 0, count);
    final centres = cloud.centres;
    final m = model?.storage;
    final ex = eye.x, ey = eye.y, ez = eye.z;
    var near = double.infinity;
    var far = double.negativeInfinity;
    for (var i = 0; i < count; i++) {
      final lx = centres[i * 3], ly = centres[i * 3 + 1];
      final lz = centres[i * 3 + 2];
      // Three conditionals rather than a record, which the VM would box on
      // every splat of a million.
      final dx =
          (m == null ? lx : m[0] * lx + m[4] * ly + m[8] * lz + m[12]) - ex;
      final dy =
          (m == null ? ly : m[1] * lx + m[5] * ly + m[9] * lz + m[13]) - ey;
      final dz =
          (m == null ? lz : m[2] * lx + m[6] * ly + m[10] * lz + m[14]) - ez;
      final d = math.sqrt(dx * dx + dy * dy + dz * dz);
      distances[i] = d;
      if (d < near) near = d;
      if (d > far) far = d;
    }

    final range = far - near;
    _lastRange = range;
    // Farthest is key 0, so ascending keys are back to front. A cloud whose
    // splats all sit at one distance is one key, and keeps index order.
    final scale = range > 0.0 ? kSplatKeyMax / range : 0.0;
    for (var i = 0; i < count; i++) {
      final q = ((far - distances[i]) * scale).floor();
      _keys[i] = q < 0 ? 0 : (q > kSplatKeyMax ? kSplatKeyMax : q);
      _order[i] = i;
    }

    sortSplatKeys(_keys, _order, _keyScratch, _orderScratch, count, _counts);
  }
}
