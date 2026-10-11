import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// What a texture of the null backend holds: four floats a texel, for each
/// layer and level, whatever its format.
///
/// One representation for every format the device holds, so a clear, an
/// upload and a readback are each written once. A backend over a real API
/// keeps its texture in that API instead; this is the part of a backend
/// such an API does for it.
final class NullTexels {
  NullTexels({
    required this.width,
    required this.height,
    required int layers,
    required int levels,
  }) : _levels = <List<Float32List>>[
         for (var layer = 0; layer < layers; layer++)
           <Float32List>[
             for (var level = 0; level < levels; level++)
               Float32List(_side(width, level) * _side(height, level) * 4),
           ],
       ];

  final int width;
  final int height;
  final List<List<Float32List>> _levels;

  /// The width of [level].
  int widthAt(int level) => _side(width, level);

  /// A side of [level], halved per level and never below one texel.
  static int _side(int base, int level) =>
      base >> level < 1 ? 1 : base >> level;

  Float32List _at(int layer, int level) {
    RangeError.checkValidIndex(layer, _levels, 'layer');
    RangeError.checkValidIndex(level, _levels[layer], 'level');
    return _levels[layer][level];
  }

  /// Every texel of [layer] at [level] set to one colour: what a clear does,
  /// whatever the scissor says.
  void fill({
    required int layer,
    required int level,
    required double r,
    required double g,
    required double b,
    required double a,
  }) {
    final texels = _at(layer, level);
    for (var i = 0; i < texels.length; i += 4) {
      texels
        ..[i] = r
        ..[i + 1] = g
        ..[i + 2] = b
        ..[i + 3] = a;
    }
  }

  /// [bytes], laid out as [format], into the whole of [layer] at [level].
  void decode(
    TextureFormat format,
    ByteData bytes, {
    required int layer,
    required int level,
  }) {
    final w = widthAt(level);
    _decodeInto(
      format,
      bytes,
      ScreenRect(width: w, height: _at(layer, level).length ~/ 4 ~/ w),
      _at(layer, level),
      w,
    );
  }

  /// [bytes], eight-bit [format], into [rect] of the base level.
  void decodeRegion(TextureFormat format, ByteData bytes, ScreenRect rect) =>
      _decodeInto(format, bytes, rect, _at(0, 0), width);

  void _decodeInto(
    TextureFormat format,
    ByteData bytes,
    ScreenRect rect,
    Float32List into,
    int rowLength,
  ) {
    final size = format.bytesPerTexel;
    for (var y = 0; y < rect.height; y++) {
      for (var x = 0; x < rect.width; x++) {
        final from = (y * rect.width + x) * size;
        final to = ((rect.y + y) * rowLength + rect.x + x) * 4;
        final rgba = _read(format, bytes, from);
        into.setRange(to, to + 4, rgba);
      }
    }
  }

  /// A [width] by [height] box of [source], from [from], written at [to]:
  /// what a texture-to-texture copy does.
  void copyFrom(
    NullTexels source, {
    required TextureCopyLocation from,
    required TextureCopyLocation to,
    required int width,
    required int height,
  }) {
    final reading = source._at(from.z, from.mipLevel);
    final writing = _at(to.z, to.mipLevel);
    final readRow = source.widthAt(from.mipLevel);
    final writeRow = widthAt(to.mipLevel);
    for (var y = 0; y < height; y++) {
      final at = ((from.y + y) * readRow + from.x) * 4;
      writing.setRange(
        ((to.y + y) * writeRow + to.x) * 4,
        ((to.y + y) * writeRow + to.x + width) * 4,
        reading,
        at,
      );
    }
  }

  /// [rect] of the base level of the first layer, laid out as [format]:
  /// eight-bit RGBA or BGRA, row zero at the top.
  ByteData encode(TextureFormat format, ScreenRect rect) {
    final texels = _at(0, 0);
    final out = Uint8List(rect.width * rect.height * 4);
    final swap = format == TextureFormat.b8g8r8a8UNormInt;
    int byte(double v) => (v.clamp(0.0, 1.0) * 255.0).round();
    for (var y = 0; y < rect.height; y++) {
      for (var x = 0; x < rect.width; x++) {
        final from = ((rect.y + y) * width + rect.x + x) * 4;
        final to = (y * rect.width + x) * 4;
        out
          ..[to] = byte(texels[from + (swap ? 2 : 0)])
          ..[to + 1] = byte(texels[from + 1])
          ..[to + 2] = byte(texels[from + (swap ? 0 : 2)])
          ..[to + 3] = byte(texels[from + 3]);
      }
    }
    return out.buffer.asByteData();
  }
}

/// One texel of [format] at [at] in [bytes], as four floats.
List<double> _read(TextureFormat format, ByteData bytes, int at) {
  double unorm(int i) => bytes.getUint8(at + i) / 255.0;
  double half(int i) =>
      _halfToDouble(bytes.getUint16(at + i * 2, Endian.little));
  double single(int i) => bytes.getFloat32(at + i * 4, Endian.little);
  return switch (format) {
    TextureFormat.r8g8b8a8UNormInt => <double>[
      unorm(0),
      unorm(1),
      unorm(2),
      unorm(3),
    ],
    TextureFormat.b8g8r8a8UNormInt => <double>[
      unorm(2),
      unorm(1),
      unorm(0),
      unorm(3),
    ],
    TextureFormat.r16g16b16a16Float => <double>[
      half(0),
      half(1),
      half(2),
      half(3),
    ],
    TextureFormat.r32g32b32a32Float => <double>[
      single(0),
      single(1),
      single(2),
      single(3),
    ],
    TextureFormat.r32Float ||
    TextureFormat.d32Float => <double>[single(0), 0.0, 0.0, 1.0],
    _ => throw ArgumentError.value(format, 'format', 'is not held here'),
  };
}

/// An IEEE half-precision float, from its sixteen bits.
double _halfToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >> 10) & 0x1f;
  final mantissa = bits & 0x3ff;
  return switch (exponent) {
    0 => sign * mantissa * math.pow(2, -24),
    0x1f => mantissa == 0 ? sign * double.infinity : double.nan,
    _ => sign * (1 + mantissa / 1024) * math.pow(2, exponent - 15),
  };
}
