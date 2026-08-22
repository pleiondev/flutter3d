/// No write into a transient buffer runs off the end of its block.
///
///     flutter test test/host_buffer_grid_test.dart
///
/// **`HostBuffer.emplace` decides whether to start a new block without looking
/// at how much is about to be written.** With a cursor near the end of a block
/// and a write larger than what is left, it hands back a range that runs past
/// the end, `DeviceBuffer.overwrite` refuses it, and `emplace` throws — in the
/// middle of encoding a frame.
///
/// The engine cannot fix the allocator, so it stays off the edge: every write
/// is rounded up to a granule and the block is a whole number of granules, so
/// a write either fits in what is left or lands exactly on the boundary, where
/// the allocator does take a new block.
///
/// The allocator's arithmetic is reproduced here rather than called, because
/// the real one needs a GPU context. It is copied from
/// `flutter_gpu/lib/src/buffer.dart`, `_allocateEmplacement`, and the first
/// test below is what says the copy is faithful: it reproduces the failure.
library;

import 'dart:typed_data';

import 'package:flutter3d_impeller/src/host_buffer_grid.dart';
import 'package:flutter_test/flutter_test.dart';

/// `flutter_gpu`'s bump allocator, as it is written today.
///
/// Returns the offset a write of [length] is placed at, having moved the
/// cursor the way the real one moves it.
final class _Allocator {
  _Allocator({required this.blockLength, required this.alignment});

  final int blockLength;
  final int alignment;

  int offset = 0;

  int place(int length) {
    if (length > blockLength) return 0; // its own block, cursor untouched
    var padding = alignment - (offset % alignment);
    padding %= alignment;
    if (offset + padding >= blockLength) {
      offset = length;
      return 0; // a fresh block
    }
    offset += padding;
    final at = offset;
    offset += length;
    return at;
  }
}

/// The blocks this engine writes in a frame, smallest to largest: fog, bloom
/// and composite parameters, the frame matrices, a material, a point light's
/// shadow, and the sixty-four joint matrices of a skinned mesh.
const List<int> _engineWrites = <int>[16, 32, 192, 896, 1792, 4096];

void main() {
  test('the allocator really does write off the end of a block', () {
    // The premise. If a later `flutter_gpu` fixes this, this test fails and
    // the rounding below can go — which is exactly the notification wanted.
    final allocator = _Allocator(blockLength: 1024000, alignment: 256);

    var straddled = false;
    for (var i = 0; i < 4000 && !straddled; i++) {
      final length = _engineWrites[i % _engineWrites.length];
      final at = allocator.place(length);
      straddled = at + length > allocator.blockLength;
    }

    expect(straddled, isTrue,
        reason: 'the allocator no longer hands out ranges past its block end');
  });

  test('and the grid alone is not enough, which is what the filler is for', () {
    // Worth stating, because rounding looks like it should be the whole
    // answer: it puts the cursor on a granule boundary, and a write of sixteen
    // granules still does not fit where two are left.
    const granule = 256;
    final block = blockLengthFor(granule);
    final allocator = _Allocator(blockLength: block, alignment: granule);

    var straddled = false;
    for (var i = 0; i < 4000 && !straddled; i++) {
      final length = roundedTo(_engineWrites[i % _engineWrites.length], granule);
      straddled = allocator.place(length) + length > block;
    }

    expect(straddled, isTrue, reason: 'rounding alone would have been enough');
  });

  test('and the cursor with the filler keeps every write inside its block', () {
    for (final alignment in <int>[16, 32, 64, 256, 512]) {
      final granule = granuleFor(alignment);
      final block = blockLengthFor(granule);
      expect(block % granule, 0, reason: 'the block is not whole granules');

      final allocator = _Allocator(blockLength: block, alignment: alignment);
      final cursor = BlockCursor(blockLength: block, granule: granule);

      for (var i = 0; i < 20000; i++) {
        final length =
            roundedTo(_engineWrites[i % _engineWrites.length], granule);
        final filler = cursor.fillerBefore(length);
        if (filler > 0) {
          final at = allocator.place(filler);
          expect(at + filler, lessThanOrEqualTo(block),
              reason: 'the filler itself ran past the end');
        }
        cursor.took(length);
        final at = allocator.place(length);
        expect(at + length, lessThanOrEqualTo(block),
            reason: 'a $length-byte write at $at runs past $block '
                '(alignment $alignment)');
        expect(at, cursor.used - length,
            reason: 'the mirrored cursor and the real one have drifted');
      }
    }
  });

  test('and geometry of any size stays inside too', () {
    // Vertex and index data arrive at whatever length the caller had, so this
    // has to survive arbitrary sizes as well as the fixed uniform blocks —
    // including ones longer than a whole block, which the allocator gives a
    // block of their own and which must not move the cursor.
    const granule = 256;
    final block = blockLengthFor(granule);
    final allocator = _Allocator(blockLength: block, alignment: granule);
    final cursor = BlockCursor(blockLength: block, granule: granule);

    var size = 1;
    for (var i = 0; i < 20000; i++) {
      size = (size * 7919 + 13) % (block + 40000) + 1;
      final length = roundedTo(size, granule);
      final filler = cursor.fillerBefore(length);
      if (filler > 0) allocator.place(filler);
      cursor.took(length);
      final at = allocator.place(length);
      expect(at + length, lessThanOrEqualTo(length > block ? length : block),
          reason: 'a $size-byte write, rounded to $length, runs past $block');
    }
  });

  test('padding leaves the bytes that were there', () {
    final bytes = ByteData(10);
    for (var i = 0; i < 10; i++) {
      bytes.setUint8(i, i + 1);
    }

    final out = padded(bytes, 256);

    expect(out.lengthInBytes, 256);
    for (var i = 0; i < 10; i++) {
      expect(out.getUint8(i), i + 1);
    }
    expect(out.getUint8(10), 0, reason: 'the padding is not zero');
    expect(identical(padded(ByteData(512), 256), padded(ByteData(512), 256)),
        isFalse);
    final already = ByteData(512);
    expect(identical(padded(already, 256), already), isTrue,
        reason: 'a write already on the grid was copied for nothing');
  });
}
