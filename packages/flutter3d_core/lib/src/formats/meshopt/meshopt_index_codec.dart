/// `EXT_meshopt_compression`'s own triangle-index codec.
///
/// **The decoder is a full, direct port** of `meshopt_decoder_reference.js`'s
/// `decodeIndexBuffer` (`meshoptimizer` npm package, MIT, Arseny
/// Kapoulkine and Jasper St. Pierre) — it reads every shape a real,
/// FIFO-optimising encoder can write, since a file this package reads back
/// may have been compressed by that encoder, not this one.
///
/// **The encoder exploits the format's edge FIFO, and that is where its
/// compression comes from.** A triangle list in any reasonable draw order
/// shares an edge with a triangle a few places back; the format's own answer
/// is to name that edge's position in a thirty-two-entry history, which
/// costs *one byte* for the whole triangle against the six or seven the
/// explicit path spends. Every triangle is tried against every edge in that
/// history, in all three rotations, and takes the shortcut when one matches.
///
/// **The third vertex then takes the cheapest of five spellings**, which is
/// the rest of it: the next unseen index, a position in a sixteen-entry
/// vertex history, one below or one above the last index written, or — when
/// none of those — an explicit delta. The first four cost nothing beyond the
/// code byte already being written.
///
/// **What is still not exploited is the no-shared-edge path's own
/// shortcuts.** A triangle with no edge in the history takes the format's
/// always-correct fallback — code `0xff`, a data byte of `0xff`, three
/// LEB128 zigzag deltas — where the format would also let it name fresh or
/// recently-seen vertices in the data byte's nibbles. That path is left
/// alone deliberately: its cheapest spelling is a data byte of `0x00`, which
/// the decoder reads as "restart numbering at zero" (`if (e == 0x00)
/// next = 0`), and an encoder that produces one without meaning it corrupts
/// every index after it. The shortcut it would buy applies to the minority
/// of triangles that share no edge at all, and the hazard is silent.
///
/// **The decoder is a full, direct port** and reads every shape a real
/// encoder can write, which is what makes the asymmetry safe: a file this
/// package reads back may have been compressed by `meshoptimizer` itself.
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
///
/// Throws [FormatException] for anything it cannot decode, a truncated
/// stream included.
Uint32List decodeMeshoptIndexBuffer(Uint8List source, int count) {
  if (source.isEmpty || source[0] != kMeshoptIndexHeader) {
    throw const FormatException(
      'not a meshopt index buffer (wrong header byte)',
    );
  }
  if (count < 0 || count % 3 != 0) {
    throw FormatException(
      'a triangle list has a multiple of 3 indices, and this one has $count',
    );
  }
  try {
    return _decodeIndexBuffer(source, count);
  } on RangeError {
    throw const FormatException(
      'meshopt index buffer: the stream ends part way through',
    );
  }
}

Uint32List _decodeIndexBuffer(Uint8List source, int count) {
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
/// See this file's own top comment for which of the format's shortcuts this
/// takes — the edge FIFO and the third vertex's five spellings — and which
/// it leaves alone, and why that one is left alone.
Uint8List encodeMeshoptIndexBuffer(List<int> indices) {
  if (indices.length % 3 != 0) {
    throw ArgumentError('a triangle list has a multiple of 3 indices');
  }
  final triCount = indices.length ~/ 3;

  final codes = Uint8List(triCount);
  final data = BytesBuilder(copy: false);
  var last = 0;

  // The encoder keeps the decoder's own state, move for move. Anything that
  // drifts here is a file that decodes to different triangles than it was
  // given, so the two loops are written to be read side by side.
  var next = 0;
  final edgefifo = _Fifo(32);
  final vertexfifo = _Fifo(16);

  // **How much of each history has actually been written**, and the reason it
  // has to be counted. A `_Fifo` is a `Uint32List`, so before anything is
  // pushed it reads back as zeros — and an encoder that searches the whole
  // ring finds an "edge" `(0, 0)` in a history nobody has pushed to. On
  // ordinary geometry that phantom never matches, which is why it survived a
  // round trip against this file's own decoder; on a mesh whose first
  // triangle is `(0, 0, 0)` it matched immediately and `meshoptimizer`'s own
  // decoder read the result as index 4294967295. Counting is what makes the
  // search look only at what is really there.
  var edgePushes = 0;
  var vertexPushes = 0;

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

  /// Where `(a, b)` sits in the edge history, or -1.
  ///
  /// Fifteen slots, because `b0 == 0x0f` is the escape that means "no shared
  /// edge" — the history holds thirty-two entries and only the first fifteen
  /// pairs are addressable.
  int edgeSlot(int a, int b) {
    final int live = edgePushes < 32 ? edgePushes : 32;
    for (var slot = 0; slot * 2 + 1 < live && slot < 0x0f; slot++) {
      if (edgefifo.read(slot * 2) == a && edgefifo.read(slot * 2 + 1) == b) {
        return slot;
      }
    }
    return -1;
  }

  /// Where [value] sits in the vertex history as `b1` can name it, or -1.
  ///
  /// One to twelve: `b1 == 0` means "the next unseen index" and `0x0d`
  /// upwards are the three other spellings, so the most recent push — which
  /// `read(0)` would be — has no code of its own.
  int vertexSlot(int value) {
    final int live = vertexPushes < 16 ? vertexPushes : 16;
    for (var slot = 1; slot < live && slot < 0x0d; slot++) {
      if (vertexfifo.read(slot) == value) return slot;
    }
    return -1;
  }

  for (var t = 0; t < triCount; t++) {
    final i0 = indices[t * 3 + 0];
    final i1 = indices[t * 3 + 1];
    final i2 = indices[t * 3 + 2];

    // All three rotations, because a shared edge is shared in one winding
    // and the triangle is the same triangle whichever of its corners is
    // called first.
    var a = i0, b = i1, c = i2;
    var slot = edgeSlot(a, b);
    if (slot < 0) {
      a = i1;
      b = i2;
      c = i0;
      slot = edgeSlot(a, b);
    }
    if (slot < 0) {
      a = i2;
      b = i0;
      c = i1;
      slot = edgeSlot(a, b);
    }

    if (slot >= 0) {
      final int b1;
      if (c == next) {
        b1 = 0x00;
        next++;
        vertexfifo.push(c);
        vertexPushes++;
      } else if (vertexSlot(c) >= 0) {
        // Named out of the history and not pushed again, which is what the
        // decoder does on this branch: re-pushing would shift every other
        // slot and the two would stop agreeing on the next triangle.
        b1 = vertexSlot(c);
      } else if (c == last - 1) {
        b1 = 0x0d;
        last = c;
        vertexfifo.push(c);
        vertexPushes++;
      } else if (c == last + 1) {
        b1 = 0x0e;
        last = c;
        vertexfifo.push(c);
        vertexPushes++;
      } else {
        b1 = 0x0f;
        writeIndex(c);
        vertexfifo.push(c);
        vertexPushes++;
      }

      codes[t] = (slot << 4) | b1;
      edgefifo
        ..push(b)
        ..push(c)
        ..push(c)
        ..push(a);
      edgePushes += 4;
    } else {
      // b1 == 0xf, z == 0xf, w == 0xf: every one of a/b/c is a fresh,
      // explicitly delta-coded index, and this data byte's own high/low
      // nibbles select exactly that for b and c ("a" is always this path
      // once b1 == 0xf and b1 != 0xe).
      a = i0;
      b = i1;
      c = i2;
      codes[t] = 0xff;
      data.addByte(0xff);
      writeIndex(a);
      writeIndex(b);
      writeIndex(c);

      vertexfifo
        ..push(a)
        ..push(b)
        ..push(c);
      vertexPushes += 3;
      edgefifo
        ..push(a)
        ..push(b)
        ..push(b)
        ..push(c)
        ..push(c)
        ..push(a);
      edgePushes += 6;
    }
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
