/// Texels as bytes and back: what `writeTexture`, the buffer–texture copies
/// and a storage texture's store need from a format.
///
/// **One statement of every layout this backend can hold**, because the
/// texture store is four floats a texel whatever the format says, and the
/// format only matters at the edges — where bytes arrive, where bytes leave,
/// and where a stage writes a value the format could not have kept. A second
/// decoder for one of those edges is how an upload and a copy come to
/// disagree about the same bytes.
///
/// The eight-bit colour formats keep the byte order they arrive in, sRGB and
/// BGRA included: that is what `createTextureFromPixels` has always stored,
/// and a `writeTexture` of the same bytes must store the same floats. The
/// 32-bit integer formats are not here at all — a 32-bit float cannot hold
/// every 32-bit integer, so the store cannot keep them, and
/// `CpuDevice.textureFormatSupport` answers none for them.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_texture.dart';

/// Reads one texel of [format] at [offset] in [bytes] into `into[at..at+3]`.
///
/// Channels the format does not have read as nought, alpha as one — what
/// sampling such a format means on every backend. Throws an
/// [UnsupportedError] for a format with no colour layout here.
void decodeTexel(
  TextureFormat format,
  ByteData bytes,
  int offset,
  Float32List into,
  int at,
) {
  void put(double r, double g, double b, double a) {
    into[at] = r;
    into[at + 1] = g;
    into[at + 2] = b;
    into[at + 3] = a;
  }

  double u8(int i) => bytes.getUint8(offset + i).toDouble();
  double s8(int i) => bytes.getInt8(offset + i).toDouble();
  double h(int i) =>
      halfToDouble(bytes.getUint16(offset + i * 2, Endian.little));
  double f(int i) => bytes.getFloat32(offset + i * 4, Endian.little);
  double sn(int i) {
    final v = s8(i) / 127.0;
    return v < -1.0 ? -1.0 : v;
  }

  switch (format) {
    case TextureFormat.a8UNormInt:
      put(0, 0, 0, u8(0) / 255.0);
    case TextureFormat.r8UNormInt:
      put(u8(0) / 255.0, 0, 0, 1);
    case TextureFormat.r8g8UNormInt:
      put(u8(0) / 255.0, u8(1) / 255.0, 0, 1);
    case TextureFormat.r8g8b8a8UNormInt ||
        TextureFormat.r8g8b8a8UNormIntSRGB ||
        TextureFormat.b8g8r8a8UNormInt ||
        TextureFormat.b8g8r8a8UNormIntSRGB:
      put(u8(0) / 255.0, u8(1) / 255.0, u8(2) / 255.0, u8(3) / 255.0);
    case TextureFormat.r8g8b8a8SNormInt:
      put(sn(0), sn(1), sn(2), sn(3));
    case TextureFormat.r8g8b8a8UInt:
      put(u8(0), u8(1), u8(2), u8(3));
    case TextureFormat.r8g8b8a8SInt:
      put(s8(0), s8(1), s8(2), s8(3));
    case TextureFormat.r16Float:
      put(h(0), 0, 0, 1);
    case TextureFormat.r16g16Float:
      put(h(0), h(1), 0, 1);
    case TextureFormat.r16g16b16a16Float:
      put(h(0), h(1), h(2), h(3));
    case TextureFormat.r16g16b16a16UInt:
      double u16(int i) =>
          bytes.getUint16(offset + i * 2, Endian.little).toDouble();
      put(u16(0), u16(1), u16(2), u16(3));
    case TextureFormat.r16g16b16a16SInt:
      double s16(int i) =>
          bytes.getInt16(offset + i * 2, Endian.little).toDouble();
      put(s16(0), s16(1), s16(2), s16(3));
    case TextureFormat.r32Float:
      put(f(0), 0, 0, 1);
    case TextureFormat.r32g32Float:
      put(f(0), f(1), 0, 1);
    case TextureFormat.r32g32b32a32Float:
      put(f(0), f(1), f(2), f(3));
    case TextureFormat.r10g10b10a2UNormInt:
      final bits = bytes.getUint32(offset, Endian.little);
      put(
        (bits & 0x3FF) / 1023.0,
        ((bits >> 10) & 0x3FF) / 1023.0,
        ((bits >> 20) & 0x3FF) / 1023.0,
        ((bits >> 30) & 0x3) / 3.0,
      );
    case TextureFormat.r11g11b10UFloat:
      final bits = bytes.getUint32(offset, Endian.little);
      put(
        _smallFloat(bits & 0x7FF, 6),
        _smallFloat((bits >> 11) & 0x7FF, 6),
        _smallFloat((bits >> 22) & 0x3FF, 5),
        1,
      );
    case TextureFormat.r9g9b9e5UFloat:
      final bits = bytes.getUint32(offset, Endian.little);
      final scale = _twoTo(((bits >> 27) & 0x1F) - 15 - 9);
      put(
        (bits & 0x1FF) * scale,
        ((bits >> 9) & 0x1FF) * scale,
        ((bits >> 18) & 0x1FF) * scale,
        1,
      );
    default:
      throw UnsupportedError(
        'the software rasteriser has no texel layout for '
        'TextureFormat.${format.name}',
      );
  }
}

/// Writes `from[at..at+3]` as one texel of [format] at [offset] in [bytes],
/// rounded and clamped the way the format keeps a value. The inverse of
/// [decodeTexel], for the same formats.
void encodeTexel(
  TextureFormat format,
  Float32List from,
  int at,
  ByteData bytes,
  int offset,
) {
  double c(int i) => from[at + i];
  int unorm(double v, int max) =>
      ((v.isNaN ? 0.0 : v.clamp(0.0, 1.0)) * max).round();
  int snorm(double v) => ((v.isNaN ? 0.0 : v.clamp(-1.0, 1.0)) * 127).round();
  int integer(double v, int lo, int hi) =>
      v.isNaN ? 0 : v.round().clamp(lo, hi);
  void u8(int i, int v) => bytes.setUint8(offset + i, v);
  void half(int i, double v) =>
      bytes.setUint16(offset + i * 2, doubleToHalf(v), Endian.little);
  void f32(int i, double v) =>
      bytes.setFloat32(offset + i * 4, v, Endian.little);

  switch (format) {
    case TextureFormat.a8UNormInt:
      u8(0, unorm(c(3), 255));
    case TextureFormat.r8UNormInt:
      u8(0, unorm(c(0), 255));
    case TextureFormat.r8g8UNormInt:
      for (var i = 0; i < 2; i++) {
        u8(i, unorm(c(i), 255));
      }
    case TextureFormat.r8g8b8a8UNormInt ||
        TextureFormat.r8g8b8a8UNormIntSRGB ||
        TextureFormat.b8g8r8a8UNormInt ||
        TextureFormat.b8g8r8a8UNormIntSRGB:
      for (var i = 0; i < 4; i++) {
        u8(i, unorm(c(i), 255));
      }
    case TextureFormat.r8g8b8a8SNormInt:
      for (var i = 0; i < 4; i++) {
        bytes.setInt8(offset + i, snorm(c(i)));
      }
    case TextureFormat.r8g8b8a8UInt:
      for (var i = 0; i < 4; i++) {
        u8(i, integer(c(i), 0, 255));
      }
    case TextureFormat.r8g8b8a8SInt:
      for (var i = 0; i < 4; i++) {
        bytes.setInt8(offset + i, integer(c(i), -128, 127));
      }
    case TextureFormat.r16Float:
      half(0, c(0));
    case TextureFormat.r16g16Float:
      half(0, c(0));
      half(1, c(1));
    case TextureFormat.r16g16b16a16Float:
      for (var i = 0; i < 4; i++) {
        half(i, c(i));
      }
    case TextureFormat.r16g16b16a16UInt:
      for (var i = 0; i < 4; i++) {
        bytes.setUint16(
          offset + i * 2,
          integer(c(i), 0, 0xFFFF),
          Endian.little,
        );
      }
    case TextureFormat.r16g16b16a16SInt:
      for (var i = 0; i < 4; i++) {
        bytes.setInt16(
          offset + i * 2,
          integer(c(i), -0x8000, 0x7FFF),
          Endian.little,
        );
      }
    case TextureFormat.r32Float:
      f32(0, c(0));
    case TextureFormat.r32g32Float:
      f32(0, c(0));
      f32(1, c(1));
    case TextureFormat.r32g32b32a32Float:
      for (var i = 0; i < 4; i++) {
        f32(i, c(i));
      }
    case TextureFormat.r10g10b10a2UNormInt:
      bytes.setUint32(
        offset,
        unorm(c(0), 1023) |
            (unorm(c(1), 1023) << 10) |
            (unorm(c(2), 1023) << 20) |
            (unorm(c(3), 3) << 30),
        Endian.little,
      );
    case TextureFormat.r11g11b10UFloat:
      bytes.setUint32(
        offset,
        _toSmallFloat(c(0), 6) |
            (_toSmallFloat(c(1), 6) << 11) |
            (_toSmallFloat(c(2), 5) << 22),
        Endian.little,
      );
    case TextureFormat.r9g9b9e5UFloat:
      bytes.setUint32(
        offset,
        _toSharedExponent(c(0), c(1), c(2)),
        Endian.little,
      );
    default:
      throw UnsupportedError(
        'the software rasteriser has no texel layout for '
        'TextureFormat.${format.name}',
      );
  }
}

/// Whether [decodeTexel] and [encodeTexel] have a colour layout for [format].
bool hasColourLayout(TextureFormat format) => switch (format) {
  TextureFormat.unknown ||
  TextureFormat.s8UInt ||
  TextureFormat.d24UnormS8Uint ||
  TextureFormat.d32FloatS8UInt ||
  TextureFormat.d16UNormInt ||
  TextureFormat.d32Float ||
  TextureFormat.r32UInt ||
  TextureFormat.r32SInt ||
  TextureFormat.r32g32UInt ||
  TextureFormat.r32g32SInt ||
  TextureFormat.r32g32b32a32UInt ||
  TextureFormat.r32g32b32a32SInt => false,
  _ => !format.isCompressed,
};

final ByteData _settleBytes = ByteData(16);
final Float32List _settleIn = Float32List(4);

/// `into[at..at+3]` as [format] would have kept it: encoded and decoded
/// again, so a stage's store into an eight-bit storage texture lands on one
/// of its 256 steps, as it would on a GPU, rather than keeping every float.
void settleTexel(TextureFormat format, Float32List into, int at) {
  for (var i = 0; i < 4; i++) {
    _settleIn[i] = into[at + i];
  }
  encodeTexel(format, _settleIn, 0, _settleBytes, 0);
  decodeTexel(format, _settleBytes, 0, into, at);
}

/// Which plane of a depth or stencil [format] a copy or write reaches, or
/// null for a colour format.
///
/// **A combined depth-stencil format reaches neither**, and is refused by
/// every caller of this: its bytes have no single layout (WebGPU leaves
/// `depth24plus-stencil8` uncopyable and asks for an aspect on the others),
/// and the contract's copies name no aspect to choose one with.
({bool depth, bool stencil})? depthStencilPlanes(TextureFormat format) =>
    switch (format) {
      TextureFormat.d16UNormInt ||
      TextureFormat.d32Float => (depth: true, stencil: false),
      TextureFormat.s8UInt => (depth: false, stencil: true),
      TextureFormat.d24UnormS8Uint ||
      TextureFormat.d32FloatS8UInt => (depth: true, stencil: true),
      _ => null,
    };

/// Writes a [width] × [height] block of [format] texels from [source] —
/// rows [bytesPerRow] apart from [offset] — into [plane] at ([x], [y]).
///
/// The depth formats land in the plane's depth buffer and the stencil in
/// its stencil buffer; a combined format is an [ArgumentError], for the
/// reason [depthStencilPlanes] gives.
void writeTexels(
  CpuTexture plane,
  TextureFormat format,
  ByteData source,
  int offset, {
  required int x,
  required int y,
  required int width,
  required int height,
  required int bytesPerRow,
}) {
  final texel = format.bytesPerTexel;
  final planes = depthStencilPlanes(format);
  if (planes != null && planes.depth && planes.stencil) {
    throw ArgumentError.value(
      format,
      'format',
      'is a combined depth-stencil format, whose bytes have no single layout '
          'to write; write a depth-only or stencil-only format',
    );
  }
  for (var row = 0; row < height; row++) {
    final from = offset + row * bytesPerRow;
    for (var col = 0; col < width; col++) {
      final at = from + col * texel;
      final index = (y + row) * plane.width + x + col;
      if (planes == null) {
        decodeTexel(format, source, at, plane.pixels, index * 4);
      } else if (planes.depth) {
        plane.depthBuffer()[index] = format == TextureFormat.d16UNormInt
            ? source.getUint16(at, Endian.little) / 65535.0
            : source.getFloat32(at, Endian.little);
      } else {
        plane.stencilBuffer()[index] = source.getUint8(at);
      }
    }
  }
}

/// The inverse of [writeTexels]: [plane]'s block as [format] bytes into
/// [destination].
void readTexels(
  CpuTexture plane,
  TextureFormat format,
  ByteData destination,
  int offset, {
  required int x,
  required int y,
  required int width,
  required int height,
  required int bytesPerRow,
}) {
  final texel = format.bytesPerTexel;
  final planes = depthStencilPlanes(format);
  if (planes != null && planes.depth && planes.stencil) {
    throw ArgumentError.value(
      format,
      'format',
      'is a combined depth-stencil format, whose bytes have no single layout '
          'to read; copy a depth-only or stencil-only format',
    );
  }
  for (var row = 0; row < height; row++) {
    final to = offset + row * bytesPerRow;
    for (var col = 0; col < width; col++) {
      final at = to + col * texel;
      final index = (y + row) * plane.width + x + col;
      if (planes == null) {
        encodeTexel(format, plane.pixels, index * 4, destination, at);
      } else if (planes.depth) {
        final z = plane.depthBuffer()[index];
        if (format == TextureFormat.d16UNormInt) {
          destination.setUint16(
            at,
            (z.clamp(0.0, 1.0) * 65535).round(),
            Endian.little,
          );
        } else {
          destination.setFloat32(at, z, Endian.little);
        }
      } else {
        destination.setUint8(at, plane.stencilBuffer()[index]);
      }
    }
  }
}

/// One IEEE binary16 as a double.
double halfToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >> 10) & 0x1F;
  final mantissa = bits & 0x3FF;

  if (exponent == 0) return sign * mantissa * _halfSubnormal;
  if (exponent == 0x1F) {
    return mantissa == 0 ? sign * double.infinity : double.nan;
  }
  return sign * (1.0 + mantissa / 1024.0) * _twoTo(exponent - 15);
}

/// [value] as IEEE binary16 bits, rounded to nearest even: what a half
/// format keeps of a float.
int doubleToHalf(double value) {
  _scratch.setFloat32(0, value);
  final x = _scratch.getUint32(0);
  final sign = (x >> 16) & 0x8000;
  final rawExponent = (x >> 23) & 0xFF;
  final mantissa = x & 0x7FFFFF;
  if (rawExponent == 0xFF) {
    return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0);
  }
  final exponent = rawExponent - 127 + 15;
  if (exponent >= 0x1F) return sign | 0x7C00;
  if (exponent <= 0) {
    if (exponent < -10) return sign;
    final full = mantissa | 0x800000;
    final shift = 14 - exponent;
    final kept = full >> shift;
    final rest = full & ((1 << shift) - 1);
    final halfway = 1 << (shift - 1);
    final up = rest > halfway || (rest == halfway && (kept & 1) == 1);
    return sign | (up ? kept + 1 : kept);
  }
  final kept = (exponent << 10) | (mantissa >> 13);
  final rest = mantissa & 0x1FFF;
  final up = rest > 0x1000 || (rest == 0x1000 && (kept & 1) == 1);
  // A carry out of the mantissa rolls into the exponent, which is the
  // correct rounding — up to infinity at the top.
  return sign | (up ? kept + 1 : kept);
}

final ByteData _scratch = ByteData(8);

/// An unsigned float of five exponent bits and [mantissaBits], as the
/// packed `r11g11b10` channels are.
double _smallFloat(int bits, int mantissaBits) {
  final exponent = bits >> mantissaBits;
  final mantissa = bits & ((1 << mantissaBits) - 1);
  final scale = (1 << mantissaBits).toDouble();
  if (exponent == 0) return mantissa / scale * _twoTo(-14);
  if (exponent == 0x1F) return mantissa == 0 ? double.infinity : double.nan;
  return (1.0 + mantissa / scale) * _twoTo(exponent - 15);
}

/// The inverse of [_smallFloat]: negative and NaN-free values clamp at
/// nought, values past the largest finite one clamp to it.
int _toSmallFloat(double value, int mantissaBits) {
  if (value.isNaN) return (0x1F << mantissaBits) | 1;
  if (value <= 0.0) return 0;
  final halfBits = doubleToHalf(value) & 0x7FFF;
  final shift = 10 - mantissaBits;
  final rounded = (halfBits + (1 << (shift - 1))) >> shift;
  final largest = (0x1E << mantissaBits) | ((1 << mantissaBits) - 1);
  return rounded > largest ? largest : rounded;
}

/// `r9g9b9e5`'s encoding, as the shared-exponent specification gives it.
int _toSharedExponent(double r, double g, double b) {
  const n = 9;
  const bias = 15;
  final largest = (511 / 512) * _twoTo(31 - bias);
  double clamp(double v) =>
      v.isNaN || v <= 0.0 ? 0.0 : (v > largest ? largest : v);
  final rc = clamp(r);
  final gc = clamp(g);
  final bc = clamp(b);
  final maxc = [rc, gc, bc].reduce((a, b) => a > b ? a : b);
  final floorLog = maxc == 0.0 ? -bias - 1 : _floorLog2(maxc);
  final candidate = (floorLog < -bias - 1 ? -bias - 1 : floorLog) + 1 + bias;
  final maxs = (maxc / _twoTo(candidate - bias - n) + 0.5).floor();
  final exponent = maxs == 1 << n ? candidate + 1 : candidate;
  final step = _twoTo(exponent - bias - n);
  int mantissa(double v) => (v / step + 0.5).floor();
  return mantissa(rc) |
      (mantissa(gc) << 9) |
      (mantissa(bc) << 18) |
      (exponent << 27);
}

/// The exponent of [value]'s leading bit, read from its bits rather than a
/// logarithm, which can land one off at a power of two.
int _floorLog2(double value) {
  _scratch.setFloat64(0, value);
  final exponent = (_scratch.getUint32(0) >> 20) & 0x7FF;
  return exponent - 1023;
}

/// 2⁻²⁴, the step between subnormal halves.
const double _halfSubnormal = 1.0 / 16777216.0;

double _twoTo(int power) {
  var value = 1.0;
  for (var i = 0; i < power.abs(); i++) {
    value *= 2.0;
  }
  return power < 0 ? 1.0 / value : value;
}
