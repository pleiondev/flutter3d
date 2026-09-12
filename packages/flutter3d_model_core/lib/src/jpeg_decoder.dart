/// [decodeJpeg]: `mat-09n`'s pure-Dart baseline-JPEG half, beside
/// [decodePng] — markers walked, Huffman-coded MCUs decoded, quantized
/// coefficients inverse-DCT'd, chroma upsampled and converted to plain
/// RGBA8. No `dart:ui`, no `package:image`, for the same reason
/// `png_decoder.dart` gives: this package has no window, and a texture
/// node's own bake (`mat-11`) needs pixels somewhere that does not.
///
/// **What this reads.** Baseline sequential DCT (SOF0) only — 8-bit
/// samples, Huffman entropy coding, 1 to 4 components, any of the
/// horizontal/vertical sampling-factor combinations a real encoder writes
/// (4:4:4, 4:2:2, 4:2:0, and a single-component grey JPEG with no
/// subsampling to speak of). Restart markers (`DRI`/`RSTn`) are honoured —
/// a decoder that ignored them would desync on the first restart interval
/// a real encoder inserts into anything larger than a few MCUs.
///
/// **What this does not.** Progressive (SOF2) and extended/lossless
/// variants (SOF1, SOF3+): refused, the same "named in the return value"
/// contract [decodePng] uses for interlacing — nothing this repository
/// bakes writes progressive JPEGs, and a second coefficient-refinement pass
/// is real work this row's own acceptance never asks for. Arithmetic
/// coding: refused; every baseline encoder in practice writes Huffman.
/// Chroma upsampling here is nearest-neighbour (each subsampled sample
/// repeated across the pixels it covers), not the "fancy" triangle-filter
/// upsampling some references default to — the two differ by a few levels
/// at a subsampled edge, which is why the app-level parity test compares
/// with a documented tolerance on subsampled fixtures rather than demanding
/// an exact match no two independent JPEG decoders actually share.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A JPEG decoded down to plain RGBA8 — top row first, four bytes a pixel,
/// `width * height * 4` bytes long. Reuses [DecodedImage] from
/// `png_decoder.dart` are not done here on purpose: import that file's own
/// type instead of declaring a second one with the same shape.
import 'png_decoder.dart' show DecodedImage;

const List<int> _zigzag = <int>[
  0, 1, 8, 16, 9, 2, 3, 10,
  17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34,
  27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36,
  29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46,
  53, 60, 61, 54, 47, 55, 62, 63,
];

final class _Component {
  _Component({
    required this.id,
    required this.h,
    required this.v,
    required this.quantTable,
  });

  final int id;
  final int h;
  final int v;
  final int quantTable;
  int dcTable = 0;
  int acTable = 0;
  int dcPredictor = 0;

  /// One sample per position in this component's own (possibly subsampled)
  /// plane, `planeWidth * planeHeight` long, filled block by block as MCUs
  /// decode.
  Uint8List? plane;
  int planeWidth = 0;
  int planeHeight = 0;
}

final class _HuffmanTable {
  _HuffmanTable(List<int> counts, List<int> symbols) {
    var code = 0;
    var k = 0;
    for (var length = 1; length <= 16; length++) {
      for (var i = 0; i < counts[length - 1]; i++) {
        _codeToSymbol[(length << 16) | code] = symbols[k];
        code++;
        k++;
      }
      code <<= 1;
    }
  }

  final Map<int, int> _codeToSymbol = <int, int>{};

  /// The symbol for the next Huffman code [reader] is sitting on, consuming
  /// exactly the bits that code takes — one bit at a time, since a baseline
  /// table is short enough that a bit-at-a-time walk costs nothing a real
  /// image would notice.
  int? decode(_BitReader reader) {
    var code = 0;
    for (var length = 1; length <= 16; length++) {
      final bit = reader.readBit();
      if (bit == null) return null;
      code = (code << 1) | bit;
      final symbol = _codeToSymbol[(length << 16) | code];
      if (symbol != null) return symbol;
    }
    return null;
  }
}

/// Reads entropy-coded bits from [bytes] starting at [start], undoing byte
/// stuffing (`FF 00` reads as one `FF` data byte) and stopping — without
/// consuming it — at a marker other than a stuffed `FF 00`, so a caller can
/// read the restart marker itself off [position] once one is hit.
final class _BitReader {
  _BitReader(this.bytes, this.position);

  final Uint8List bytes;
  int position;
  int _bitBuffer = 0;
  int _bitCount = 0;

  int? readBit() {
    if (_bitCount == 0) {
      if (position >= bytes.length) return null;
      final byte = bytes[position];
      if (byte == 0xFF) {
        if (position + 1 >= bytes.length) return null;
        final next = bytes[position + 1];
        if (next == 0x00) {
          position += 2;
        } else {
          // A real marker (restart or otherwise) — stop rather than eat it.
          return null;
        }
      } else {
        position += 1;
      }
      _bitBuffer = byte;
      _bitCount = 8;
    }
    _bitCount--;
    return (_bitBuffer >> _bitCount) & 1;
  }

  int? readBits(int count) {
    if (count == 0) return 0;
    var value = 0;
    for (var i = 0; i < count; i++) {
      final bit = readBit();
      if (bit == null) return null;
      value = (value << 1) | bit;
    }
    return value;
  }

  /// Drops any partial byte still buffered, so the caller's own next read
  /// (a restart marker, always byte-aligned) lands on the right byte.
  void alignToByte() {
    _bitBuffer = 0;
    _bitCount = 0;
  }
}

/// The signed value a Huffman-decoded `size` and its [count]-bit raw payload
/// stand for, per JPEG's own convention (Annex F.1.2.1): the top half of the
/// range is read as-is and positive, the bottom half is the same bits minus
/// `2^count - 1`.
int _extend(int value, int count) {
  if (count == 0) return 0;
  final threshold = 1 << (count - 1);
  return value < threshold ? value - (1 << count) + 1 : value;
}

/// [bytes] decoded, or null on anything this reader cannot make sense of: a
/// missing `SOI`, a precision or frame type this reader does not support, a
/// Huffman code with no match, or entropy data that runs out before every
/// MCU is accounted for.
DecodedImage? decodeJpeg(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  final quantTables = <int, Uint8List>{};
  final dcTables = <int, _HuffmanTable>{};
  final acTables = <int, _HuffmanTable>{};
  var restartInterval = 0;
  int? width;
  int? height;
  List<_Component>? components;

  var offset = 2;
  while (offset + 1 < bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    var marker = bytes[offset + 1];
    offset += 2;
    while (marker == 0xFF) {
      // Fill bytes before a real marker — legal padding.
      if (offset >= bytes.length) return null;
      marker = bytes[offset];
      offset += 1;
    }

    if (marker == 0xD9) break; // EOI
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      continue; // TEM / stray restart markers outside a scan — no payload.
    }
    if (offset + 2 > bytes.length) return null;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    final segmentStart = offset + 2;
    final segmentEnd = offset + length;

    switch (marker) {
      case 0xDB: // DQT — one or more tables in one segment.
        var p = segmentStart;
        while (p < segmentEnd) {
          final precisionAndId = bytes[p++];
          final precision = precisionAndId >> 4;
          final id = precisionAndId & 0x0F;
          final table = Uint8List(64);
          if (precision == 0) {
            for (var i = 0; i < 64; i++) {
              table[_zigzag[i]] = bytes[p + i];
            }
            p += 64;
          } else {
            for (var i = 0; i < 64; i++) {
              table[_zigzag[i]] = ((bytes[p + i * 2] << 8) | bytes[p + i * 2 + 1])
                  .clamp(0, 255);
            }
            p += 128;
          }
          quantTables[id] = table;
        }
      case 0xC4: // DHT
        var p = segmentStart;
        while (p < segmentEnd) {
          final classAndId = bytes[p++];
          final tableClass = classAndId >> 4;
          final id = classAndId & 0x0F;
          final counts = bytes.sublist(p, p + 16);
          p += 16;
          var total = 0;
          for (final c in counts) {
            total += c;
          }
          final symbols = bytes.sublist(p, p + total);
          p += total;
          final table = _HuffmanTable(counts, symbols);
          if (tableClass == 0) {
            dcTables[id] = table;
          } else {
            acTables[id] = table;
          }
        }
      case 0xC0: // SOF0 — baseline.
        final precision = bytes[segmentStart];
        if (precision != 8) return null;
        height = (bytes[segmentStart + 1] << 8) | bytes[segmentStart + 2];
        width = (bytes[segmentStart + 3] << 8) | bytes[segmentStart + 4];
        if (width == 0 || height == 0) return null;
        final count = bytes[segmentStart + 5];
        components = <_Component>[];
        var p = segmentStart + 6;
        for (var i = 0; i < count; i++) {
          final id = bytes[p];
          final sampling = bytes[p + 1];
          final quant = bytes[p + 2];
          components.add(
            _Component(
              id: id,
              h: sampling >> 4,
              v: sampling & 0x0F,
              quantTable: quant,
            ),
          );
          p += 3;
        }
      case 0xC1: case 0xC2: case 0xC3: // Extended/progressive/lossless SOF.
      case 0xC5: case 0xC6: case 0xC7:
      case 0xC9: case 0xCA: case 0xCB:
      case 0xCD: case 0xCE: case 0xCF:
        return null; // Not baseline — refused, per this file's own contract.
      case 0xDD: // DRI
        restartInterval = (bytes[segmentStart] << 8) | bytes[segmentStart + 1];
      case 0xDA: // SOS — the scan itself follows the header immediately.
        if (width == null || height == null || components == null) {
          return null;
        }
        final scanCount = bytes[segmentStart];
        var p = segmentStart + 1;
        final scanComponents = <_Component>[];
        for (var i = 0; i < scanCount; i++) {
          final id = bytes[p];
          final tables = bytes[p + 1];
          final component = components.firstWhere(
            (_Component c) => c.id == id,
            orElse: () => throw StateError('unknown component'),
          );
          component.dcTable = tables >> 4;
          component.acTable = tables & 0x0F;
          scanComponents.add(component);
          p += 2;
        }
        // Ss, Se, AhAl — fixed at 0, 63, 0 for baseline; not read.
        final scanDataStart = segmentEnd;
        final decoded = _decodeScan(
          bytes: bytes,
          start: scanDataStart,
          width: width,
          height: height,
          components: components,
          quantTables: quantTables,
          dcTables: dcTables,
          acTables: acTables,
          restartInterval: restartInterval,
        );
        if (decoded == null) return null;
        return decoded;
      default:
        // APPn, COM, and anything else with a length-prefixed payload this
        // reader does not need — skipped whole.
        break;
    }
    offset = segmentEnd;
  }
  return null; // Ran off the end without a scan, or without EOI.
}

DecodedImage? _decodeScan({
  required Uint8List bytes,
  required int start,
  required int width,
  required int height,
  required List<_Component> components,
  required Map<int, Uint8List> quantTables,
  required Map<int, _HuffmanTable> dcTables,
  required Map<int, _HuffmanTable> acTables,
  required int restartInterval,
}) {
  var maxH = 1;
  var maxV = 1;
  for (final c in components) {
    if (c.h > maxH) maxH = c.h;
    if (c.v > maxV) maxV = c.v;
  }
  final mcuWidth = maxH * 8;
  final mcuHeight = maxV * 8;
  final mcusAcross = (width + mcuWidth - 1) ~/ mcuWidth;
  final mcusDown = (height + mcuHeight - 1) ~/ mcuHeight;

  for (final c in components) {
    c.planeWidth = mcusAcross * c.h * 8;
    c.planeHeight = mcusDown * c.v * 8;
    c.plane = Uint8List(c.planeWidth * c.planeHeight);
    if (!quantTables.containsKey(c.quantTable) ||
        !dcTables.containsKey(c.dcTable) ||
        !acTables.containsKey(c.acTable)) {
      return null;
    }
  }

  final reader = _BitReader(bytes, start);
  final block = Int32List(64);
  var mcusSinceRestart = 0;
  final totalMcus = mcusAcross * mcusDown;

  for (var mcuIndex = 0; mcuIndex < totalMcus; mcuIndex++) {
    final mcuX = mcuIndex % mcusAcross;
    final mcuY = mcuIndex ~/ mcusAcross;

    for (final c in components) {
      final quant = quantTables[c.quantTable]!;
      final dcTable = dcTables[c.dcTable]!;
      final acTable = acTables[c.acTable]!;
      for (var by = 0; by < c.v; by++) {
        for (var bx = 0; bx < c.h; bx++) {
          block.fillRange(0, 64, 0);
          if (!_decodeBlock(reader, dcTable, acTable, c, block)) return null;
          final pixels = _idctBlock(block, quant);
          final planeX = (mcuX * c.h + bx) * 8;
          final planeY = (mcuY * c.v + by) * 8;
          _writeBlock(c.plane!, c.planeWidth, planeX, planeY, pixels);
        }
      }
    }

    mcusSinceRestart++;
    if (restartInterval > 0 &&
        mcusSinceRestart == restartInterval &&
        mcuIndex != totalMcus - 1) {
      reader.alignToByte();
      // Expect FF Dn — skip it if present; a truncated/odd stream without
      // one is treated as a hard failure rather than guessed past.
      if (reader.position + 1 < bytes.length &&
          bytes[reader.position] == 0xFF &&
          (bytes[reader.position + 1] & 0xF8) == 0xD0) {
        reader.position += 2;
      } else {
        return null;
      }
      for (final c in components) {
        c.dcPredictor = 0;
      }
      mcusSinceRestart = 0;
    }
  }

  final rgba = Uint8List(width * height * 4);
  if (components.length == 1) {
    final y = components[0];
    for (var py = 0; py < height; py++) {
      final sy = py * y.planeHeight ~/ (mcusDown * y.v * 8);
      for (var px = 0; px < width; px++) {
        final sx = px * y.planeWidth ~/ (mcusAcross * y.h * 8);
        final g = y.plane![sy * y.planeWidth + sx];
        final out = (py * width + px) * 4;
        rgba[out] = g;
        rgba[out + 1] = g;
        rgba[out + 2] = g;
        rgba[out + 3] = 255;
      }
    }
  } else {
    final yc = components[0];
    final cb = components[1];
    final cr = components[2];
    for (var py = 0; py < height; py++) {
      for (var px = 0; px < width; px++) {
        final yv = yc.plane![_planeYFor(py, yc, maxV) * yc.planeWidth +
            _planeXFor(px, yc, maxH)];
        final cbv = cb.plane![_planeYFor(py, cb, maxV) * cb.planeWidth +
            _planeXFor(px, cb, maxH)];
        final crv = cr.plane![_planeYFor(py, cr, maxV) * cr.planeWidth +
            _planeXFor(px, cr, maxH)];
        final out = (py * width + px) * 4;
        final rgb = _ycbcrToRgb(yv, cbv, crv);
        rgba[out] = rgb.$1;
        rgba[out + 1] = rgb.$2;
        rgba[out + 2] = rgb.$3;
        rgba[out + 3] = 255;
      }
    }
  }

  return DecodedImage(width: width, height: height, rgba: rgba);
}

/// [component]'s own plane row a full-resolution row [y] maps to under
/// nearest-neighbour upsampling — component samples cover `maxV / v` output
/// rows each.
int _planeYFor(int y, _Component component, int maxV) =>
    y * component.v ~/ maxV;

int _planeXFor(int x, _Component component, int maxH) =>
    x * component.h ~/ maxH;

/// Copies [pixels] (an 8×8 spatial block, row-major) into [plane] at
/// ([x], [y]) — [planeWidth] wide, no clipping needed since every plane's
/// own size is already rounded up to a whole number of 8×8 blocks.
void _writeBlock(
  Uint8List plane,
  int planeWidth,
  int x,
  int y,
  Uint8List pixels,
) {
  for (var row = 0; row < 8; row++) {
    final destStart = (y + row) * planeWidth + x;
    plane.setRange(destStart, destStart + 8, pixels, row * 8);
  }
}

(int, int, int) _ycbcrToRgb(int y, int cb, int cr) {
  final cbShifted = cb - 128;
  final crShifted = cr - 128;
  final r = y + (1.402 * crShifted);
  final g = y - (0.344136 * cbShifted) - (0.714136 * crShifted);
  final b = y + (1.772 * cbShifted);
  return (_clamp(r), _clamp(g), _clamp(b));
}

int _clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

bool _decodeBlock(
  _BitReader reader,
  _HuffmanTable dcTable,
  _HuffmanTable acTable,
  _Component component,
  Int32List block,
) {
  final dcSize = dcTable.decode(reader);
  if (dcSize == null) return false;
  final dcBits = dcSize == 0 ? 0 : reader.readBits(dcSize);
  if (dcSize != 0 && dcBits == null) return false;
  final diff = dcSize == 0 ? 0 : _extend(dcBits!, dcSize);
  component.dcPredictor += diff;
  block[0] = component.dcPredictor;

  var k = 1;
  while (k < 64) {
    final rs = acTable.decode(reader);
    if (rs == null) return false;
    final run = rs >> 4;
    final size = rs & 0x0F;
    if (size == 0) {
      if (run == 15) {
        k += 16; // ZRL — sixteen zeros, no value.
        continue;
      }
      break; // EOB
    }
    k += run;
    if (k >= 64) return false;
    final bits = reader.readBits(size);
    if (bits == null) return false;
    block[_zigzag[k]] = _extend(bits, size);
    k++;
  }
  return true;
}

/// [block] (natural order, DC first) dequantized by [quant] (also natural
/// order — [quantTables] above already un-zigzags it on read) and
/// inverse-DCT'd to an 8×8 spatial block, level-shifted back to 0–255.
///
/// A direct, unoptimized separable float IDCT rather than a fast integer
/// one (AAN, or similar): this decoder's own fixtures are a handful of
/// small test images, not a video's worth of frames a millisecond budget
/// would matter for, and the direct form is far easier to check against the
/// specification's own formula by eye.
Uint8List _idctBlock(Int32List block, Uint8List quant) {
  final dequant = Float64List(64);
  for (var i = 0; i < 64; i++) {
    dequant[i] = (block[i] * quant[i]).toDouble();
  }

  final temp = Float64List(64);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      var sum = 0.0;
      for (var u = 0; u < 8; u++) {
        final cu = u == 0 ? _invSqrt2 : 1.0;
        sum += cu * dequant[y * 8 + u] * _cosTable[x][u];
      }
      temp[y * 8 + x] = sum * 0.5;
    }
  }

  final spatial = Uint8List(64);
  for (var x = 0; x < 8; x++) {
    for (var y = 0; y < 8; y++) {
      var sum = 0.0;
      for (var v = 0; v < 8; v++) {
        final cv = v == 0 ? _invSqrt2 : 1.0;
        sum += cv * temp[v * 8 + x] * _cosTable[y][v];
      }
      spatial[y * 8 + x] = _clamp(sum * 0.5 + 128.0);
    }
  }
  return spatial;
}

const double _invSqrt2 = 0.7071067811865476;

/// `_cosTable[x][u] = cos((2x+1) * u * pi / 16)`, precomputed once.
final List<List<double>> _cosTable = List<List<double>>.generate(
  8,
  (int x) => List<double>.generate(
    8,
    (int u) => math.cos((2 * x + 1) * u * math.pi / 16),
  ),
);
