/// `EXT_meshopt_compression`'s own triangle-index codec.
///
/// **The decoder is a full, direct port** of `meshopt_decoder_reference.js`'s
/// `decodeIndexBuffer` (`meshoptimizer` npm package, MIT, Arseny
/// Kapoulkine and Jasper St. Pierre) — it reads every shape a real,
/// FIFO-optimising encoder can write, since a file this package reads back
/// may have been compressed by that encoder, not this one.
///
/// **The encoder does not exploit the format's own FIFO reuse.** The real
/// format tracks a small history of recently-seen edges and vertices so a
/// triangle sharing one with its neighbour can be coded in a single byte —
/// that history, and choosing when a triangle qualifies, is a second,
/// separate design on top of the one [meshopt_vertex_codec.dart] already
/// took on, and the risk of a subtle bookkeeping bug in a *decoder* nobody
/// else has to trust adds nothing this ticket asked for. Every triangle here
/// takes the format's own always-correct fallback path instead — three
/// LEB128, zigzag-delta-coded indices — which a conformant decoder reads
/// identically and which still compresses an ordinary mesh well, since
/// neighbouring triangles in a reasonable draw order name nearby indices.
/// What is given up is the extra ratio a full FIFO encoder would add on top,
/// not correctness or interoperability with one.
library;

import 'dart:typed_data';

/// The one header byte an index buffer starts with.
const int kMeshoptIndexHeader = 0xe1;

int _dezig(int v) => (v >> 1) ^ -(v & 1);
int _zigzag(int v) => (v << 1) ^ (v >> 31);

class _Fifo {
  _Fifo(int length) : _data = Uint32List(length);
  final Uint32List _data;
  int _offset = 0;

  int read(int n) => _data[(_offset - 1 - n) & (_data.length - 1)];

  void push(int n) {
    _data[_offset] = n;
    _offset = (_offset + 1) & (_data.length - 1);
  }
}

/// Decodes one `EXT_meshopt_compression` index buffer — every shape the
/// format's own reference decoder reads, not only what
/// [encodeMeshoptIndexBuffer] produces.
Uint32List decodeMeshoptIndexBuffer(Uint8List source, int count) {
  if (source.isEmpty || source[0] != kMeshoptIndexHeader) {
    throw const FormatException(
      'not a meshopt index buffer (wrong header byte)',
    );
  }
  if (count % 3 != 0) {
    throw ArgumentError('a triangle list has a multiple of 3 indices');
  }

  final dst = Uint32List(count);
  final triCount = count ~/ 3;

  var codeOffs = 1;
  var dataOffs = codeOffs + triCount;
  final codeauxOffs = source.length - 0x10;

  int readLEB128() {
    var n = 0;
    var shift = 0;
    while (true) {
      final b = source[dataOffs++];
      n |= (b & 0x7f) << shift;
      if (b < 0x80) return n;
      shift += 7;
    }
  }

  var next = 0;
  var last = 0;
  final edgefifo = _Fifo(32);
  final vertexfifo = _Fifo(16);

  int decodeIndex(int v) => last += _dezig(v);

  var dstOffs = 0;
  for (var i = 0; i < triCount; i++) {
    final code = source[codeOffs++];
    final b0 = code >> 4;
    final b1 = code & 0x0f;

    if (b0 < 0x0f) {
      final a = edgefifo.read((b0 << 1) + 0);
      final b = edgefifo.read((b0 << 1) + 1);
      int c;

      if (b1 == 0x00) {
        c = next++;
        vertexfifo.push(c);
      } else if (b1 < 0x0d) {
        c = vertexfifo.read(b1);
      } else if (b1 == 0x0d) {
        c = --last;
        vertexfifo.push(c);
      } else if (b1 == 0x0e) {
        c = ++last;
        vertexfifo.push(c);
      } else {
        c = decodeIndex(readLEB128());
        vertexfifo.push(c);
      }

      edgefifo
        ..push(b)
        ..push(c)
        ..push(c)
        ..push(a);

      dst[dstOffs++] = a;
      dst[dstOffs++] = b;
      dst[dstOffs++] = c;
    } else {
      int a, b, c;

      if (b1 < 0x0e) {
        final e = source[codeauxOffs + b1];
        final z = e >> 4;
        final w = e & 0x0f;

        a = next++;
        b = z == 0x00 ? next++ : vertexfifo.read(z - 1);
        c = w == 0x00 ? next++ : vertexfifo.read(w - 1);

        vertexfifo.push(a);
        if (z == 0x00) vertexfifo.push(b);
        if (w == 0x00) vertexfifo.push(c);
      } else {
        final e = source[dataOffs++];
        if (e == 0x00) next = 0;

        final z = e >> 4;
        final w = e & 0x0f;

        a = b1 == 0x0e ? next++ : decodeIndex(readLEB128());
        b = z == 0x00
            ? next++
            : (z == 0x0f ? decodeIndex(readLEB128()) : vertexfifo.read(z - 1));
        c = w == 0x00
            ? next++
            : (w == 0x0f ? decodeIndex(readLEB128()) : vertexfifo.read(w - 1));

        vertexfifo.push(a);
        if (z == 0x00 || z == 0x0f) vertexfifo.push(b);
        if (w == 0x00 || w == 0x0f) vertexfifo.push(c);
      }

      edgefifo
        ..push(a)
        ..push(b)
        ..push(b)
        ..push(c)
        ..push(c)
        ..push(a);

      dst[dstOffs++] = a;
      dst[dstOffs++] = b;
      dst[dstOffs++] = c;
    }
  }

  return dst;
}

/// Encodes [indices] — a flat triangle list, length a multiple of 3 — as an
/// `EXT_meshopt_compression` index buffer.
///
/// See this file's own top comment for why every triangle takes the
/// format's always-correct fallback path (`code = 0xff`, three LEB128
/// zigzag deltas) rather than the FIFO-reuse shortcuts a full encoder would
/// reach for.
Uint8List encodeMeshoptIndexBuffer(List<int> indices) {
  if (indices.length % 3 != 0) {
    throw ArgumentError('a triangle list has a multiple of 3 indices');
  }
  final triCount = indices.length ~/ 3;

  final codes = Uint8List(triCount);
  codes.fillRange(0, triCount, 0xff);

  final data = BytesBuilder(copy: false);
  var last = 0;

  void writeLEB128(int n) {
    while (true) {
      if (n < 0x80) {
        data.addByte(n);
        return;
      }
      data.addByte((n & 0x7f) | 0x80);
      n >>= 7;
    }
  }

  void writeIndex(int value) {
    final delta = value - last;
    last = value;
    writeLEB128(_zigzag(delta) & 0xffffffff);
  }

  for (var t = 0; t < triCount; t++) {
    // b1 == 0xf, z == 0xf, w == 0xf: every one of a/b/c is a fresh,
    // explicitly delta-coded index, and this data byte's own high/low
    // nibbles select exactly that for b and c ("a" is always this path
    // once b1 == 0xf and b1 != 0xe).
    data.addByte(0xff);
    writeIndex(indices[t * 3 + 0]);
    writeIndex(indices[t * 3 + 1]);
    writeIndex(indices[t * 3 + 2]);
  }

  final out = BytesBuilder(copy: false)
    ..addByte(kMeshoptIndexHeader)
    ..add(codes)
    ..add(data.toBytes());

  // The last 16 bytes are the aux table `b1 < 0x0e` addresses — unused by
  // this encoder (every triangle takes the `b1 >= 0x0e` path instead), and
  // the reference decoder never reads past `source.length - 0x10` for
  // anything else, so sixteen zero bytes satisfy the format without
  // meaning anything.
  out.add(Uint8List(0x10));

  return out.toBytes();
}
