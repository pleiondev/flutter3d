/// `EXT_meshopt_compression`'s own vertex-buffer codec, format version 0.
///
/// **Read against a reference this repository did not write.** The
/// extension's own encoder ships only as compiled WebAssembly — no readable
/// source exists to port — but its decoder ships as plain, commented
/// JavaScript (`meshopt_decoder_reference.js`, in the `meshoptimizer` npm
/// package, MIT, by Arseny Kapoulkine and Jasper St. Pierre). [decodeMeshoptVertexBufferV0]
/// below is a direct, line-for-line port of that file's `decodeVertexBuffer`;
/// [encodeMeshoptVertexBufferV0] is not a port of anything — nothing
/// readable to port from exists — it is this codec's own design, built to
/// satisfy exactly what the decoder (and, by the format's own claim, the
/// real production decoder) requires, and checked against the reference
/// decoder itself running under Node rather than only against this file's
/// own inverse — see `meshopt_vertex_codec_test.dart`.
///
/// **Version 0 only.** The format also has a version 1, which groups four
/// bytes at a time into wider "channels" (16-bit or rotated 32-bit-XOR
/// deltas) for better compression on some data. Both versions are correct,
/// and a decoder reads either from the same header byte — nothing here
/// claims v1 does not exist, only that this encoder does not produce it,
/// because v0's own per-byte delta scheme already compresses the common
/// case (positions, normals, texture coordinates — all locally coherent
/// between neighbouring vertices) well enough to clear this ticket's own
/// bar, and every byte v1 would save is a second, separate design this
/// codec does not need to get right today.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The one header byte a version-0 vertex buffer starts with.
const int kMeshoptVertexHeaderV0 = 0xa0;

/// `(v & 1) != 0 ? ~(v >> 1) : v >> 1` — the exact arithmetic the reference
/// decoder's own `dezig` does, turning a non-negative byte code back into a
/// small signed delta.
int _dezig(int v) => (v >> 1) ^ -(v & 1);

/// [_dezig]'s own inverse: a small signed delta (from -128 to 127, the only
/// range [encodeMeshoptVertexBufferV0] ever hands this) becomes a
/// non-negative byte code.
int _zigzag(int v) => (v << 1) ^ (v >> 31);

/// How many elements one compressed block covers — the same arithmetic the
/// reference decoder computes before it reads anything, so an encoder and a
/// decoder agree on block boundaries without either naming them in the
/// file.
int _maxBlockElements(int byteStride) =>
    math.min((0x2000 ~/ byteStride) & ~0x000f, 0x100);

/// Decodes one `EXT_meshopt_compression` vertex buffer [source] wrote,
/// version 0 only — [encodeMeshoptVertexBufferV0]'s own inverse, and the
/// reference decoder's `decodeVertexBuffer` with its filters and its
/// version-1 channel logic removed, since this codec produces neither.
///
/// Throws [FormatException] for anything it cannot decode, a truncated
/// stream included.
Uint8List decodeMeshoptVertexBufferV0(
  Uint8List source,
  int elementCount,
  int byteStride,
) {
  if (source.isEmpty || source[0] != kMeshoptVertexHeaderV0) {
    throw const FormatException(
      'not a version-0 meshopt vertex buffer (wrong header byte)',
    );
  }
  // Past 256 bytes a block holds no elements, and the block loop below would
  // never advance.
  if (byteStride <= 0 || byteStride > 256 || elementCount < 0) {
    throw FormatException(
      'meshopt vertex buffer: $elementCount elements of $byteStride bytes',
    );
  }
  try {
    return _decodeVertexBufferV0(source, elementCount, byteStride);
  } on RangeError {
    // A truncated stream indexes past its own end somewhere in the block
    // loop; the caller was promised one kind of exception.
    throw const FormatException(
      'meshopt vertex buffer: the stream ends part way through',
    );
  }
}

Uint8List _decodeVertexBufferV0(
  Uint8List source,
  int elementCount,
  int byteStride,
) {
  final target = Uint8List(elementCount * byteStride);
  final maxBlockElements = _maxBlockElements(byteStride);
  final deltas = Uint8List(maxBlockElements * byteStride);

  final tailSizePadded = math.max(byteStride, 32);
  final tailDataOffs = source.length - byteStride;
  final tempData = Uint8List.fromList(
    source.sublist(tailDataOffs, tailDataOffs + byteStride),
  );

  var srcOffs = 1; // Skip the header byte.
  const headerModes = <int>[0, 2, 4, 8];

  for (
    var dstElemBase = 0;
    dstElemBase < elementCount;
    dstElemBase += maxBlockElements
  ) {
    final attrBlockElementCount = math.min(
      elementCount - dstElemBase,
      maxBlockElements,
    );
    final groupCount = ((attrBlockElementCount + 0x0f) & ~0x0f) >> 4;
    final headerByteCount = ((groupCount + 0x03) & ~0x03) >> 2;

    deltas.fillRange(0, deltas.length, 0);

    for (var byte = 0; byte < byteStride; byte++) {
      final deltaBase = byte * attrBlockElementCount;
      final headerBitsOffs = srcOffs;
      srcOffs += headerByteCount;

      for (var group = 0; group < groupCount; group++) {
        final mode =
            (source[headerBitsOffs + (group >> 2)] >> ((group & 0x03) << 1)) &
            0x03;
        final modeBits = headerModes[mode];
        final deltaOffs = deltaBase + (group << 4);

        if (modeBits == 0) {
          // Every one of these 16 deltas is zero; nothing was written.
        } else if (modeBits == 2) {
          // 2-bit codes, 4 per byte: a 4-byte header, not 2.
          final srcBase = srcOffs;
          srcOffs += 0x04;
          for (var m = 0; m < 0x10; m++) {
            final shift = 6 - ((m & 0x03) << 1);
            var delta = (source[srcBase + (m >> 2)] >> shift) & 0x03;
            if (delta == 3) delta = source[srcOffs++];
            deltas[deltaOffs + m] = delta;
          }
        } else if (modeBits == 4) {
          // 4-bit codes, 2 per byte: an 8-byte header, not 4.
          final srcBase = srcOffs;
          srcOffs += 0x08;
          for (var m = 0; m < 0x10; m++) {
            final shift = 4 - ((m & 0x01) << 2);
            var delta = (source[srcBase + (m >> 1)] >> shift) & 0x0f;
            if (delta == 0xf) delta = source[srcOffs++];
            deltas[deltaOffs + m] = delta;
          }
        } else {
          deltas.setRange(deltaOffs, deltaOffs + 0x10, source, srcOffs);
          srcOffs += 0x10;
        }
      }
    }

    for (var elem = 0; elem < attrBlockElementCount; elem++) {
      final dstElem = dstElemBase + elem;
      for (var byte = 0; byte < byteStride; byte++) {
        final delta = _dezig(deltas[byte * attrBlockElementCount + elem]);
        final temp = (tempData[byte] + delta) & 0xff;
        target[dstElem * byteStride + byte] = temp;
        tempData[byte] = temp;
      }
    }
  }

  if (srcOffs != source.length - tailSizePadded) {
    throw const FormatException(
      'meshopt vertex buffer: data did not end where its own tail begins',
    );
  }
  return target;
}

/// Encodes [source] — [elementCount] elements of [byteStride] bytes each,
/// row-major — as a version-0 `EXT_meshopt_compression` vertex buffer.
///
/// **Every group of 16 elements in one byte lane is coded at whichever
/// width fits it smallest**, chosen by [_bestGroupWidth]: zero when a whole
/// group of deltas is zero, 2 or 4 bits with the top code as a per-value
/// escape to a full byte when most deltas are small and a few are not, or
/// the 16 bytes verbatim when neither sentinel width would save anything.
/// This is the encoder's only real decision — the container shape
/// everything else sits in (header byte, block size, per-group mode bits,
/// tail) is fixed by what [decodeMeshoptVertexBufferV0] (and the real
/// decoder it stands in for) requires.
Uint8List encodeMeshoptVertexBufferV0(
  Uint8List source,
  int elementCount,
  int byteStride,
) {
  if (source.length != elementCount * byteStride) {
    throw ArgumentError(
      'source is ${source.length} bytes; $elementCount elements of '
      '$byteStride bytes each is ${elementCount * byteStride}',
    );
  }

  final maxBlockElements = _maxBlockElements(byteStride);
  final out = BytesBuilder(copy: false)..addByte(kMeshoptVertexHeaderV0);

  // What the first element's own delta is measured against — its own raw
  // bytes, so the first element of the whole buffer costs nothing to code.
  // `running` carries each lane's own previous value forward as encoding
  // proceeds; `tempData` is the frozen copy the file's own tail records,
  // since a decoder starts from it before applying a single delta.
  final tempData = elementCount == 0
      ? Uint8List(byteStride)
      : Uint8List.fromList(source.sublist(0, byteStride));
  final running = Uint8List.fromList(tempData);

  for (
    var blockBase = 0;
    blockBase < elementCount;
    blockBase += maxBlockElements
  ) {
    final blockElementCount = math.min(
      elementCount - blockBase,
      maxBlockElements,
    );
    final groupCount = ((blockElementCount + 0x0f) & ~0x0f) >> 4;
    final headerByteCount = ((groupCount + 0x03) & ~0x03) >> 2;

    // Zigzag-coded deltas for every element in this block, one byte lane at
    // a time — `running` carries each lane's own previous value forward
    // exactly the way the decoder's own `tempData` does, so a lane's delta
    // at element i is always against element i-1 (or, for the block's own
    // first element, against wherever the lane stood at the end of the
    // block before it).
    final laneDeltas = Uint8List(byteStride * blockElementCount);
    for (var byte = 0; byte < byteStride; byte++) {
      var prev = running[byte];
      for (var elem = 0; elem < blockElementCount; elem++) {
        final value = source[(blockBase + elem) * byteStride + byte];
        // The delta that lands exactly on `value` when added to `prev` mod
        // 256, chosen in (-128, 128] so it always zigzag-encodes into one
        // byte — the same range a single code byte can `_dezig` back out
        // of.
        var delta = (value - prev) & 0xff;
        if (delta > 127) delta -= 256;
        laneDeltas[byte * blockElementCount + elem] = _zigzag(delta) & 0xff;
        prev = value;
      }
      running[byte] = prev;
    }

    for (var byte = 0; byte < byteStride; byte++) {
      final deltaBase = byte * blockElementCount;
      final modes = Uint8List(groupCount);
      final headerBytes = Uint8List(headerByteCount);

      for (var group = 0; group < groupCount; group++) {
        final groupStart = deltaBase + (group << 4);
        final groupLen = math.min(0x10, blockElementCount - (group << 4));
        modes[group] = _bestGroupWidth(laneDeltas, groupStart, groupLen);
        headerBytes[group >> 2] |= modes[group] << ((group & 0x03) << 1);
      }
      out.add(headerBytes);

      for (var group = 0; group < groupCount; group++) {
        final groupStart = deltaBase + (group << 4);
        final groupLen = math.min(0x10, blockElementCount - (group << 4));
        _writeGroup(out, laneDeltas, groupStart, groupLen, modes[group]);
      }
    }
  }

  final dataLength = out.length;
  final tailSizePadded = math.max(byteStride, 32);
  final padding = tailSizePadded - byteStride;
  if (padding > 0) out.add(Uint8List(padding));
  out.add(tempData);

  assert(
    out.length == dataLength + tailSizePadded,
    'the tail this wrote is not the size the header this wrote promises',
  );
  return out.toBytes();
}

/// Which mode index (into [decodeMeshoptVertexBufferV0]'s own
/// `headerModes`, `[0, 2, 4, 8]`) encodes `deltas[start..start+len)` in the
/// fewest bytes: 0 for all-zero, 1 for a 2-bit sentinel code, 2 for a 4-bit
/// one, 3 to write all 16 bytes verbatim.
///
/// [len] may be under 16 for a block's own last, short group — everything
/// past it in [deltas] is scratch this function must not read, since it may
/// hold a stale value left over from an earlier, longer block.
int _bestGroupWidth(Uint8List deltas, int start, int len) {
  var allZero = true;
  var escapes2 = 0;
  var escapes4 = 0;
  for (var m = 0; m < len; m++) {
    final v = deltas[start + m];
    if (v != 0) allZero = false;
    if (v >= 3) escapes2++;
    if (v >= 0xf) escapes4++;
  }
  if (allZero) return 0;

  // Fixed header-bit cost is paid once per group regardless of width and so
  // does not enter this comparison; what differs between widths is the
  // sentinel block's own size — 4 bytes of 2-bit codes, or 8 bytes of 4-bit
  // codes, or 16 bytes verbatim — plus one escape byte per value too large
  // for that width's inline codes ([4..20] and [8..24] bytes respectively,
  // matching the reference decoder's own comment on each branch).
  final total2 = 4 + escapes2;
  final total4 = 8 + escapes4;
  const total8 = 16;
  if (total2 <= total4 && total2 <= total8) return 1;
  if (total4 <= total8) return 2;
  return 3;
}

/// Writes one 16-element group at [mode] — [_bestGroupWidth]'s own choice —
/// the exact inverse of [decodeMeshoptVertexBufferV0]'s own per-mode
/// reading.
void _writeGroup(
  BytesBuilder out,
  Uint8List deltas,
  int start,
  int len,
  int mode,
) {
  int at(int m) => m < len ? deltas[start + m] : 0;

  switch (mode) {
    case 0:
      return;
    case 1:
      // modeBits == 2: sixteen 2-bit codes packed four to a byte, 3 as the
      // escape that means "read a full byte" — a 4-byte header, not 2; the
      // 1-bit sentinel scheme (a real, separate mode) never appears here
      // because v0's own `headerModes` has no entry that selects it.
      final bits = Uint8List(4);
      final escapes = <int>[];
      for (var m = 0; m < 0x10; m++) {
        final v = at(m);
        final code = v >= 3 ? 3 : v;
        if (code == 3) escapes.add(v);
        final shift = 6 - ((m & 0x03) << 1);
        bits[m >> 2] |= code << shift;
      }
      out.add(bits);
      out.add(Uint8List.fromList(escapes));
      return;
    case 2:
      // modeBits == 4: sixteen 4-bit codes packed two to a byte, 0xf as the
      // escape — an 8-byte header.
      final bits = Uint8List(8);
      final escapes = <int>[];
      for (var m = 0; m < 0x10; m++) {
        final v = at(m);
        final code = v >= 0xf ? 0xf : v;
        if (code == 0xf) escapes.add(v);
        final shift = 4 - ((m & 0x01) << 2);
        bits[m >> 1] |= code << shift;
      }
      out.add(bits);
      out.add(Uint8List.fromList(escapes));
      return;
    case 3:
    default:
      // Mode 3 in _bestGroupWidth's own numbering means "write verbatim",
      // which the container spends 16 bytes on regardless of mode 2's own
      // (unused here) 4-bit sentinel shape — decodeMeshoptVertexBufferV0
      // reads this as modeBits == 8, the last entry of its own
      // `headerModes`.
      final verbatim = Uint8List(0x10);
      for (var m = 0; m < 0x10; m++) {
        verbatim[m] = at(m);
      }
      out.add(verbatim);
  }
}
