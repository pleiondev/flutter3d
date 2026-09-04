import 'dart:typed_data';

/// Number of low bits reserved for the payload an entry carries alongside its key.
///
/// The render list packs the draw's slot index here, which has two effects: one
/// sort orders the draws directly, and because the sort is stable and the payload
/// is the least significant field, equal keys keep submission order.
const int kPayloadBits = 20;

/// Mask for the payload half of a packed entry.
const int kPayloadMask = (1 << kPayloadBits) - 1;

/// Largest payload the packing can represent.
const int kMaxPayload = kPayloadMask;

/// Bits available to the sort key itself.
///
/// 63 usable bits minus the payload: the sign bit is left alone so entries stay
/// non-negative and byte-wise ordering matches numeric ordering.
const int kSortKeyBits = 63 - kPayloadBits;

/// Below this many entries a comparison sort wins.
///
/// Radix makes eight passes, each clearing a 256-entry histogram; that fixed cost
/// dwarfs the work when there are only a handful of draws, which is the common
/// case for a simple scene.
const int kRadixThreshold = 96;

/// Sorts the first [count] packed entries of [buffer] ascending.
///
/// [scratch] must be at least as long as [buffer]; it is used as the alternate
/// destination for radix passes and its contents are not meaningful afterwards.
/// [counts] is an optional reusable 256-entry histogram, so a caller sorting every
/// frame allocates nothing.
///
/// Measured on 50 000 entries, on 2026-09-04, by
/// `tool/bench/bench_frame_math.dart` run through `dart compile exe` — Dart
/// 3.13.0 AOT, Apple M3 Pro, macOS 27: a comparison sort with a closure
/// comparator over an index list took 11.4 ms, packing the payload into the key
/// and calling `Int64List.sort` took 10.3 ms, and this took 0.99 ms. That 11x
/// is why the render list does not need native code — the original cost was the
/// algorithm and the indirection, not the language.
///
/// **The date is half of the number.** What stood here before was 12.5, 11.0
/// and 0.89 ms against "Dart 3.12 AOT, Apple Silicon" and no date, so a reader
/// could not tell a measurement that still holds from one taken on an SDK the
/// repository has since left. The documents quoted this same benchmark at a
/// different pair of figures again, and with no date on either set there was no
/// way to tell which run superseded which. A number a design decision rests on
/// is re-measured, with the day it was taken, rather than adjusted until it
/// reads well.
void sortPackedKeys(
  Int64List buffer,
  Int64List scratch,
  int count, {
  Uint32List? counts,
}) {
  if (count < 2) return;

  if (count < kRadixThreshold) {
    // Sorts in place inside buffer, since a sublist view shares its storage.
    Int64List.sublistView(buffer, 0, count).sort();
    return;
  }

  radixSortPackedKeys(buffer, scratch, count, counts: counts);
}

/// Least-significant-digit radix sort over bytes, stable by construction.
///
/// Exposed separately from [sortPackedKeys] so tests can exercise it below the
/// threshold where the comparison sort would otherwise take over.
void radixSortPackedKeys(
  Int64List buffer,
  Int64List scratch,
  int count, {
  Uint32List? counts,
}) {
  if (count < 2) return;

  final histogram = counts ?? Uint32List(256);
  var from = buffer;
  var to = scratch;

  for (var shift = 0; shift < 64; shift += 8) {
    histogram.fillRange(0, 256, 0);
    for (var i = 0; i < count; i++) {
      histogram[(from[i] >> shift) & 0xFF]++;
    }

    // Every entry shares this byte, so the pass would be a straight copy. Skipping
    // it is what makes small keys cheap: with one material and no draw buckets the
    // upper bytes are constant and most passes disappear.
    if (histogram[(from[0] >> shift) & 0xFF] == count) continue;

    var total = 0;
    for (var b = 0; b < 256; b++) {
      final c = histogram[b];
      histogram[b] = total;
      total += c;
    }

    for (var i = 0; i < count; i++) {
      to[histogram[(from[i] >> shift) & 0xFF]++] = from[i];
    }

    final swap = from;
    from = to;
    to = swap;
  }

  // An odd number of executed passes leaves the result in scratch.
  if (!identical(from, buffer)) {
    buffer.setRange(0, count, from);
  }
}
