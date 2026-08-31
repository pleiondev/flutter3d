/// Keeping every write into a `HostBuffer` inside one of its blocks.
///
/// **`HostBuffer.emplace` will hand out a range that runs off the end of its
/// block.** The bump allocator in `flutter_gpu` decides whether to start a new
/// block by looking at where the cursor is and not at how much is about to be
/// written:
///
/// ```dart
/// if (_offsetCursor + padding >= blockLengthInBytes) { ...new block... }
/// ```
///
/// With the default block of 1 024 000 bytes, a cursor at 1 023 232 and a
/// 4 096-byte write, that test is false: the write is placed at 1 023 232 and
/// runs 3 328 bytes past the end. `DeviceBuffer.overwrite` refuses it and
/// `emplace` throws — mid-frame, with the render pass half encoded.
///
/// What that looks like is what sent us looking: a skinned model that draws
/// correctly when you face it and breaks into flickering triangles when you
/// turn, because turning changes how many draws precede it and therefore where
/// in the block its uniforms land. The joint block is 4 KB — sixty-four
/// matrices — which is by far the largest single write this engine makes and
/// the one most likely to straddle the end. Everything smaller mostly fits, so
/// mostly nothing is wrong.
///
/// The way out without patching the SDK is to keep the allocator's cursor
/// where a straddle cannot happen, which takes two things.
///
/// **A grid.** Every write is rounded up to a granule and the block is a whole
/// number of granules, so the cursor is always on a granule boundary and the
/// alignment padding inside `emplace` is always zero. That is what makes the
/// second half possible: a cursor this side can predict exactly.
///
/// **A filler.** Rounding alone is not enough — the cursor lands on the grid,
/// but a write of sixteen granules still does not fit where two are left. So
/// [BlockCursor] mirrors the offset, and when the next write would not fit it
/// writes the rest of the block away first. That filler fits exactly, which
/// leaves the cursor on the boundary, which is the one case the allocator's
/// own test does catch — so the write after it lands at the start of a fresh
/// block.
///
/// The cost is the rounding — a 192-byte block of frame uniforms occupies 256
/// — plus one wasted write per block. Against a megabyte a frame that is
/// nothing, and it buys an invariant rather than a smaller chance of the same
/// crash.
library;

import 'dart:typed_data';

/// The granule every write is rounded up to.
///
/// At least 256 because that is the coarsest uniform alignment any backend
/// this runs on asks for, and because a granule smaller than the alignment
/// would let `emplace`'s own padding move the cursor off the grid. A backend
/// asking for more than 256 gets its own number, which is already a power of
/// two.
int granuleFor(int alignment) => alignment <= 256 ? 256 : alignment;

/// How long a block to ask a `HostBuffer` for.
///
/// A whole number of granules, which is the invariant this file exists for,
/// and about a megabyte, which is what the default was — one frame of this
/// engine's uniforms fits in a block or two.
int blockLengthFor(int granule) => granule * 4096;

/// [size] rounded up to a whole number of granules.
int roundedTo(int size, int granule) =>
    ((size + granule - 1) ~/ granule) * granule;

/// [bytes] as a view whose length is a whole number of granules.
///
/// Returns the argument untouched when it already is, which is the common case
/// for uniforms — they are allocated at the rounded size to begin with. The
/// copy is for geometry written straight from a caller's buffer, where the
/// length is whatever the caller had.
ByteData padded(ByteData bytes, int granule) {
  final wanted = roundedTo(bytes.lengthInBytes, granule);
  if (wanted == bytes.lengthInBytes) return bytes;
  final out = ByteData(wanted);
  Uint8List.sublistView(out, 0, bytes.lengthInBytes)
      .setAll(0, Uint8List.sublistView(bytes));
  return out;
}


/// Where the next write will land in a `HostBuffer`'s current block.
///
/// A mirror of the allocator's private cursor, which is exact because
/// everything written through it is on the grid: the padding the allocator
/// would add is always zero, so its arithmetic reduces to "add the length".
final class BlockCursor {
  BlockCursor({required this.blockLength, required this.granule});

  final int blockLength;
  final int granule;

  /// Bytes taken from the current block.
  int used = 0;

  /// How many bytes to write away before a write of [length], or nought when
  /// it fits.
  ///
  /// [length] is a rounded length — the caller has already been through
  /// [roundedTo]. A write longer than a whole block is the allocator's own
  /// special case: it gets a block to itself and leaves the cursor alone.
  int fillerBefore(int length) {
    if (length > blockLength) return 0;
    if (used + length <= blockLength) return 0;
    return blockLength - used;
  }

  /// Records a write of [length], having already written any [fillerBefore].
  void took(int length) {
    if (length > blockLength) return;
    if (used + length > blockLength) used = 0;
    used += length;
  }

  void reset() => used = 0;
}
