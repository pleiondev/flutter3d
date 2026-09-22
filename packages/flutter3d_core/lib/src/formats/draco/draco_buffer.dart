/// Reading a Draco bitstream — `gfx-82n`.
///
/// **Transcribed from the decoder, not reconstructed from a description.** The
/// Draco container is not published as a prose specification; what exists is
/// the reference decoder, and this file follows `core/decoder_buffer.h`,
/// `compression/entropy/ans.h` and `compression/entropy/rans_symbol_decoder.h`
/// operation for operation. That is the same choice `inflate.dart` and
/// `zstd.dart` make about their own tables — and `zstd.dart` is also the reason
/// it is not optional here: four bugs on that row all looked right and were
/// caught only because a real encoder disagreed.
///
/// **Two ways of reading, and they interleave.** Most of a Draco stream is
/// byte-aligned: little-endian scalars and varints. Inside it are runs of bits
/// packed least-significant-first, which a reader switches into and back out
/// of, rounding up to the next byte on the way out. `DecoderBuffer` in the
/// reference does both and so does [DracoBuffer]; keeping them in one object is
/// what makes the position bookkeeping match.
library;

import 'dart:typed_data';

/// Thrown when a stream is not one this decodes, with the reason in it.
final class DracoException implements Exception {
  const DracoException(this.message);
  final String message;
  @override
  String toString() => 'DracoException: $message';
}

Never _fail(String message) => throw DracoException(message);

/// A cursor over a Draco stream.
final class DracoBuffer {
  DracoBuffer(this.bytes, [this.start = 0]) : position = start {
    _view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  }

  final Uint8List bytes;
  final int start;
  late final ByteData _view;
  int position;

  /// Where the next byte-aligned read will happen.
  int get remaining => bytes.lengthInBytes - position;

  int readUint8() {
    if (position >= bytes.lengthInBytes) {
      _fail('read past the end of the stream');
    }
    return bytes[position++];
  }

  int readInt8() {
    final value = readUint8();
    return value > 127 ? value - 256 : value;
  }

  int readUint16() {
    final value = _view.getUint16(position, Endian.little);
    position += 2;
    return value;
  }

  int readUint32() {
    final value = _view.getUint32(position, Endian.little);
    position += 4;
    return value;
  }

  int readInt32() {
    final value = _view.getInt32(position, Endian.little);
    position += 4;
    return value;
  }

  double readFloat32() {
    final value = _view.getFloat32(position, Endian.little);
    position += 4;
    return value;
  }

  /// A LEB128 unsigned integer, which is what Draco 2.x uses for every count.
  int readVarUint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = readUint8();
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) _fail('varint longer than 64 bits');
    }
  }

  Uint8List readBytes(int count) {
    if (position + count > bytes.lengthInBytes) _fail('read past the end');
    final out = Uint8List.sublistView(bytes, position, position + count);
    position += count;
    return out;
  }

  // ---------------------------------------------------------------------
  // The bit reader
  // ---------------------------------------------------------------------

  int _bitOffset = 0;
  int _bitBase = 0;
  bool _bitMode = false;

  /// Switches to reading individual bits, starting at the current byte.
  void startBitDecoding() {
    _bitMode = true;
    _bitBase = position;
    _bitOffset = 0;
  }

  /// Switches back, rounding the position up to the next whole byte.
  ///
  /// The rounding is the contract: a bit run that ended part way through a byte
  /// still consumed that byte, and a reader that resumed mid-byte would read
  /// the next scalar shifted.
  void endBitDecoding() {
    _bitMode = false;
    position = _bitBase + ((_bitOffset + 7) >> 3);
  }

  /// [count] bits, least significant first — the order the encoder wrote them.
  int readBits(int count) {
    if (!_bitMode) _fail('bit read outside a bit-decoding run');
    var value = 0;
    for (var bit = 0; bit < count; bit++) {
      final off = _bitOffset;
      final byte = _bitBase + (off >> 3);
      // Past the end reads as zero, which is what the reference does: the
      // encoder pads the final byte and a decoder that threw here would refuse
      // a well-formed stream.
      final one = byte < bytes.lengthInBytes
          ? (bytes[byte] >> (off & 7)) & 1
          : 0;
      value |= one << bit;
      _bitOffset = off + 1;
    }
    return value;
  }
}

/// The rANS decoder of `ans.h`, at a precision chosen from the alphabet size.
///
/// **Read backwards, like every asymmetric numeral system.** The encoder wrote
/// its state into the end of its own buffer and renormalised towards the start,
/// so a decoder begins at the last byte and walks down. The two top bits of
/// that last byte say how many bytes the initial state occupies, which is the
/// one piece of framing the format has.
final class RAnsDecoder {
  RAnsDecoder(this.precisionBits)
    : precision = 1 << precisionBits,
      _lut = Uint32List(1 << precisionBits);

  /// `(3 * bitLength) / 2`, clamped to 12..20 — `rans_symbol_coding.h`.
  static int precisionFor(int uniqueSymbolsBitLength) {
    final unclamped = (3 * uniqueSymbolsBitLength) ~/ 2;
    if (unclamped < 12) return 12;
    if (unclamped > 20) return 20;
    return unclamped;
  }

  /// **Four times the precision, not the constant of the same name.** `ans.h`
  /// has a `DRACO_ANS_L_BASE` of 4096 used by the *binary* coder, and the rANS
  /// decoder's own `l_rans_base` is `rans_precision * 4` — a different number
  /// wherever the precision is not 1024. Taking the constant made the state
  /// renormalise too rarely, so a tag stream that should have ended exactly on
  /// the base ran out of bytes with nineteen bits of symbols still unread, and
  /// the attribute after it started two bytes early.
  int get _lRansBase => precision * 4;

  static const int _ioBase = 256;

  final int precisionBits;
  final int precision;
  final Uint32List _lut;

  late Uint32List _probability;
  late Uint32List _cumulative;

  late Uint8List _buffer;
  int _bufferOffset = 0;
  int _state = 0;

  /// Builds the lookup table from a probability per symbol.
  void buildLookUpTable(Uint32List probabilities) {
    _probability = Uint32List(probabilities.length);
    _cumulative = Uint32List(probabilities.length);
    var cumulative = 0;
    var filled = 0;
    for (var i = 0; i < probabilities.length; i++) {
      _probability[i] = probabilities[i];
      _cumulative[i] = cumulative;
      cumulative += probabilities[i];
      if (cumulative > precision) {
        _fail('rANS probabilities sum past the precision');
      }
      for (var j = filled; j < cumulative; j++) {
        _lut[j] = i;
      }
      filled = cumulative;
    }
  }

  /// Positions the decoder at the end of [data], which is where a rANS stream
  /// starts.
  void readInit(Uint8List data) {
    if (data.isEmpty) _fail('empty rANS stream');
    _buffer = data;
    final offset = data.length;
    final x = data[offset - 1] >> 6;
    switch (x) {
      case 0:
        _bufferOffset = offset - 1;
        _state = data[offset - 1] & 0x3F;
      case 1:
        _bufferOffset = offset - 2;
        _state = (data[offset - 2] | (data[offset - 1] << 8)) & 0x3FFF;
      case 2:
        _bufferOffset = offset - 3;
        _state =
            (data[offset - 3] |
                (data[offset - 2] << 8) |
                (data[offset - 1] << 16)) &
            0x3FFFFF;
      default:
        _bufferOffset = offset - 4;
        _state =
            (data[offset - 4] |
                (data[offset - 3] << 8) |
                (data[offset - 2] << 16) |
                (data[offset - 1] << 24)) &
            0x3FFFFFFF;
    }
    _state += _lRansBase;
    if (_state >= _lRansBase * _ioBase) {
      _fail('rANS initial state out of range');
    }
  }

  /// Whether the stream ended exactly where the encoder left it.
  ///
  /// **Worth keeping, because it is the one self-check rANS offers.** A decode
  /// that drifted still produces symbols; it simply produces the wrong ones and
  /// runs out early. This came back false while the state base was wrong, and
  /// that was the whole diagnosis.
  ///
  /// **Renormalised first, or it refuses streams that are fine.** [read] pulls
  /// bytes in *before* each symbol, so after the last one the state is wherever
  /// that symbol left it — and if the encoder had to shift bytes out before
  /// coding its very first symbol, which it does whenever that symbol is rare,
  /// those bytes are still unread and the state is still short of the base.
  /// Comparing without pulling them in passed the first fixtures by their
  /// first symbols happening to be common, and refused the default encoding of
  /// a thousand-face mesh whose tag stream opened with a rare one.
  bool get endedCleanly {
    while (_state < _lRansBase && _bufferOffset > 0) {
      _state = _state * _ioBase + _buffer[--_bufferOffset];
    }
    return _state == _lRansBase;
  }

  /// One symbol.
  int read() {
    // Renormalise first: pull bytes back in until the state is large enough to
    // carry a symbol out of it.
    while (_state < _lRansBase && _bufferOffset > 0) {
      _state = _state * _ioBase + _buffer[--_bufferOffset];
    }
    final quotient = _state ~/ precision;
    final remainder = _state % precision;
    final symbol = _lut[remainder];
    _state = quotient * _probability[symbol] + remainder - _cumulative[symbol];
    return symbol;
  }
}

/// The binary coder of `ans.h` — `RAnsBitDecoder` in the reference.
///
/// **A different coder from [RAnsDecoder], with a different base.** This one
/// codes single bits against one probability — the chance of a zero, out of
/// 256 — and it is the one `DRACO_ANS_L_BASE` of 4096 actually belongs to: the
/// constant [RAnsDecoder] was wrong to borrow is right here. The edgebreaker
/// path is made of these: whether a component started on an interior face,
/// whether an edge is an attribute seam, whether a parallelogram crosses a
/// crease, which way a predicted normal faces.
///
/// No `endedCleanly` here, deliberately. The symbol coder ends on its base
/// because the encoder flushes exactly what it wrote; the bit coder is asked
/// for a number of bits the *caller* knows, and the reference encoder pads, so
/// the final state says nothing a caller could check.
final class RAnsBitDecoder {
  /// Reads the probability and the length-prefixed stream from [buffer], and
  /// leaves [buffer] after it.
  RAnsBitDecoder(DracoBuffer buffer) : _probabilityOfZero = buffer.readUint8() {
    final size = buffer.readVarUint();
    if (size > buffer.remaining) _fail('rANS bit stream runs past the end');
    final data = buffer.readBytes(size);
    if (size < 1) _fail('empty rANS bit stream');
    // The top two bits of the last byte say how wide the initial state is.
    // Three is not a width this coder has — the symbol coder's fourth case
    // does not exist here, and a stream that claims it is not one.
    final (int offset, int state) = switch (data[size - 1] >> 6) {
      0 => (size - 1, data[size - 1] & 0x3F),
      1 when size >= 2 => (
        size - 2,
        (data[size - 2] | (data[size - 1] << 8)) & 0x3FFF,
      ),
      2 when size >= 3 => (
        size - 3,
        (data[size - 3] | (data[size - 2] << 8) | (data[size - 1] << 16)) &
            0x3FFFFF,
      ),
      _ => _fail('rANS bit stream has no valid initial state'),
    };
    _data = data;
    _offset = offset;
    _state = state + _lBase;
    if (_state >= _lBase * _ioBase) {
      _fail('rANS bit stream initial state out of range');
    }
  }

  static const int _lBase = 4096;
  static const int _ioBase = 256;
  static const int _precision = 256;

  final int _probabilityOfZero;
  late final Uint8List _data;
  int _offset = 0;
  int _state = 0;

  /// One bit — `rabs_desc_read`.
  bool readBit() {
    final p = _precision - _probabilityOfZero;
    if (_state < _lBase && _offset > 0) {
      _state = _state * _ioBase + _data[--_offset];
    }
    final quotient = _state ~/ _precision;
    final remainder = _state % _precision;
    final one = remainder < p;
    _state = one ? quotient * p + remainder : _state - quotient * p - p;
    return one;
  }
}

/// `DecodeSymbols` in `symbol_decoding.cc`: a run of integers, either tagged by
/// bit length or coded straight through rANS.
Uint32List decodeSymbols(DracoBuffer buffer, int count, int components) {
  final out = Uint32List(count);
  if (count == 0) return out;

  final scheme = buffer.readUint8();
  return switch (scheme) {
    // Tagged: an rANS stream of bit lengths, then the values themselves packed
    // at those lengths. One tag per *point*, shared by its components, which is
    // why this needs to know how many there are.
    0 => _decodeTagged(buffer, count, components, out),
    1 => _decodeRaw(buffer, count, out),
    _ => _fail('unknown symbol coding scheme $scheme'),
  };
}

Uint32List _decodeTagged(
  DracoBuffer buffer,
  int count,
  int components,
  Uint32List out,
) {
  final tags = _RAnsSymbolDecoder(5)..create(buffer);
  tags.startDecoding(buffer);
  buffer.startBitDecoding();
  var at = 0;
  for (var i = 0; i < count; i += components) {
    final bitLength = tags.decode();
    for (var j = 0; j < components; j++) {
      out[at++] = buffer.readBits(bitLength);
    }
  }
  buffer.endBitDecoding();
  _checkEnded(tags);
  return out;
}

Uint32List _decodeRaw(DracoBuffer buffer, int count, Uint32List out) {
  final maxBitLength = buffer.readUint8();
  final decoder = _RAnsSymbolDecoder(maxBitLength)..create(buffer);
  decoder.startDecoding(buffer);
  for (var i = 0; i < count; i++) {
    out[i] = decoder.decode();
  }
  _checkEnded(decoder);
  return out;
}

/// **The one self-check the format offers, and it is worth making.** A rANS
/// decode that drifted still produces symbols — it simply produces the wrong
/// ones and runs out of stream early, so the state does not come back to the
/// base it started from. Nothing downstream would notice: the values look like
/// values. This is what diagnosed the state base being wrong while the row was
/// being written, and leaving it in turns a silently wrong mesh into a refusal.
void _checkEnded(_RAnsSymbolDecoder decoder) {
  if (!decoder.rans.endedCleanly) {
    _fail(
      'the rANS stream did not end where the encoder left it, so the symbols '
      'decoded from it are not the ones that were written',
    );
  }
}

/// `RAnsSymbolDecoder`: the probability table, then the stream it indexes.
final class _RAnsSymbolDecoder {
  _RAnsSymbolDecoder(this.uniqueSymbolsBitLength)
    : rans = RAnsDecoder(RAnsDecoder.precisionFor(uniqueSymbolsBitLength));

  final int uniqueSymbolsBitLength;
  final RAnsDecoder rans;
  int numSymbols = 0;

  /// Reads the probability table.
  ///
  /// **A two-bit token per entry, and one of its four values is a run.** The
  /// low two bits say how many extra bytes the probability needs, except for
  /// the value three, which means "this many following symbols have probability
  /// zero" — an alphabet is mostly zeros and writing each as a byte would cost
  /// more than the symbols do.
  void create(DracoBuffer buffer) {
    numSymbols = buffer.readVarUint();
    final probabilities = Uint32List(numSymbols);
    for (var i = 0; i < numSymbols; i++) {
      final probData = buffer.readUint8();
      final token = probData & 3;
      if (token == 3) {
        final offset = probData >> 2;
        if (i + offset >= numSymbols) _fail('rANS zero run runs past the end');
        for (var j = 0; j < offset + 1; j++) {
          probabilities[i + j] = 0;
        }
        i += offset;
      } else {
        var probability = probData >> 2;
        for (var b = 0; b < token; b++) {
          probability |= buffer.readUint8() << (8 * (b + 1) - 2);
        }
        probabilities[i] = probability;
      }
    }
    rans.buildLookUpTable(probabilities);
  }

  void startDecoding(DracoBuffer buffer) {
    final encoded = buffer.readVarUint();
    if (encoded > buffer.remaining) _fail('rANS stream runs past the end');
    rans.readInit(buffer.readBytes(encoded));
  }

  int decode() => rans.read();
}
