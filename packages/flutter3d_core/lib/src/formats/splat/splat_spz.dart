/// Reading a fitted cloud out of an `.spz` file — `C6`.
///
/// **What SPZ is, against the PLY a capture starts as.** The same Gaussians,
/// quantised to about a tenth of the bytes: a centre is three 24-bit fixed
/// point numbers, a scale, an opacity and a colour channel are a byte each, a
/// rotation is three or four bytes, and every higher spherical-harmonic
/// coefficient is a byte. The quantised fields are laid out attribute by
/// attribute rather than splat by splat — every centre, then every opacity,
/// and so on — and the whole is compressed: one gzip stream for versions 1
/// to 3, one zstd stream per attribute for version 4. Both decompressors are
/// this package's own (`inflate.dart`, `zstd.dart`), so the reader runs on
/// the web as it does natively.
///
/// **The reference is Niantic's own C++ library** (`nianticlabs/spz`), read
/// for this at version 4 of the format; every constant below is its number,
/// copied rather than derived, the choice `inflate.dart` makes for RFC
/// 1951's tables. The fixture the test reads was written by that library and
/// its PLY twin decoded by it (`tool/make_spz_fixture.py`), so the numbers
/// here are checked against the reference's, not against themselves.
///
/// **The axes are the file's, unless asked.** SPZ stores right, up, back —
/// OpenGL's axes and this engine's — where a PLY capture is right, down,
/// front. [SplatAxes] says which the cloud comes back in; turning between
/// the two is a half turn about X, which negates `y` and `z` of every centre
/// and every quaternion and the sign of every spherical-harmonic coefficient
/// odd in `y` and `z` together.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../image/inflate.dart';
import '../ktx2/zstd.dart';
import 'splat_cloud.dart';

/// Thrown when a file is not an SPZ this can read, with the reason in it.
final class SplatSpzException implements Exception {
  const SplatSpzException(this.message);
  final String message;
  @override
  String toString() => 'SplatSpzException: $message';
}

/// Which axes a cloud read by [parseSplatSpz] comes back in.
///
/// A class with const instances rather than an enum: the reference names
/// sixteen axis conventions, and a third one wanted here later should be an
/// addition, not a break in somebody's `switch`.
final class SplatAxes {
  const SplatAxes._(this.name, {required this.halfTurnAboutX});

  final String name;

  /// Whether reaching these axes from the stored ones negates `y` and `z`.
  final bool halfTurnAboutX;

  /// Right, up, back: what an SPZ stores — OpenGL's axes, and this engine's.
  static const SplatAxes rightUpBack = SplatAxes._(
    'rightUpBack',
    halfTurnAboutX: false,
  );

  /// Right, down, front: what a PLY capture holds, so a cloud read this way
  /// matches `parseSplatPly` on the file it was made from.
  static const SplatAxes rightDownFront = SplatAxes._(
    'rightDownFront',
    halfTurnAboutX: true,
  );

  @override
  String toString() => name;
}

/// The `NGSP` magic at the head of the packed header, little-endian.
const int _kMagic = 0x5053474e;

/// The highest format version this reads: version 4, zstd streams.
const int kSpzLatestVersion = 4;

/// The reference's `colorScale`: a stored colour byte is the zeroth-band
/// coefficient times this, times 255, plus half of 255.
const double _kColourScale = 0.15;

/// Fixed length of the version 1–3 header inside the gzip stream, and of the
/// version 4 header in the clear.
const int _kLegacyHeaderBytes = 16;
const int _kHeaderBytes = 32;

/// The extension record that moves the stored axes off right, up, back.
const int _kCoordinateSystemExtension = 0xADBE0003;

/// Signs a half turn about X gives each higher-band coefficient, in the
/// order bands 1 to 4 list them (lowest `m` first).
///
/// Each real spherical harmonic is a polynomial in `x, y, z`, so negating
/// `y` and `z` multiplies it by `(-1)^(power of y + power of z)`. The
/// reference's own table (`coordinateConverter`) agrees for bands 1 to 3; for
/// band 4 its last entry is `y`, where `x⁴ − 6x²y² + y⁴` is even in `y` and
/// the sign is `+1` — this follows the polynomial.
const List<double> _kHalfTurnXSigns = <double>[
  -1, -1, 1, // band 1: y, z, x
  -1, 1, 1, -1, 1, // band 2: xy, yz, 3z²−1, xz, x²−y²
  -1, 1, -1, -1, 1, -1, 1, // band 3
  -1, 1, -1, 1, 1, -1, 1, -1, 1, // band 4
];

/// The cloud in [bytes], or a thrown [SplatSpzException] saying why not.
///
/// Reads versions 1 to [kSpzLatestVersion]. [axes] turns the cloud into a
/// PLY's axes when asked. [keepHigherBands] false drops the spherical
/// harmonics above band 0 — a third of an SPZ's decoded floats at degree 3,
/// which nothing in the draw evaluates yet. [colourSpace] is what the colour
/// bytes were fitted in, sRGB unless told otherwise, as for a PLY — see
/// [splatColour].
SplatCloud parseSplatSpz(
  Uint8List bytes, {
  SplatAxes axes = SplatAxes.rightUpBack,
  bool keepHigherBands = true,
  SplatColourSpace colourSpace = SplatColourSpace.srgb,
}) {
  final packed = _unpack(bytes);
  return _decode(packed, axes, keepHigherBands, colourSpace);
}

/// Whether [bytes] starts the way an SPZ does: the version 4 magic in the
/// clear, or a gzip stream, which is what versions 1 to 3 are.
bool looksLikeSpz(Uint8List bytes) =>
    (bytes.length >= 4 && _u32(bytes, 0) == _kMagic) ||
    (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b);

/// The quantised attribute arrays, as the file stores them.
typedef _Packed = ({
  int version,
  int count,
  int shDegree,
  int fractionalBits,
  Uint8List positions,
  Uint8List alphas,
  Uint8List colours,
  Uint8List scales,
  Uint8List rotations,
  Uint8List sh,
});

/// Coefficients above band 0 for [degree]: 0, 3, 8, 15 or 24.
int _shDim(int degree) => (degree + 1) * (degree + 1) - 1;

_Packed _unpack(Uint8List bytes) {
  if (bytes.length >= 4 && _u32(bytes, 0) == _kMagic) return _unpackV4(bytes);
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return _unpackLegacy(_gunzip(bytes));
  }
  throw const SplatSpzException(
    'neither the NGSP magic of version 4 nor the gzip magic of versions 1 '
    'to 3, so this is not an SPZ file',
  );
}

/// The header fields both layouts share, checked the same way.
({int version, int count, int shDegree, int fractionalBits, int flags}) _header(
  Uint8List bytes, {
  required bool v4,
}) {
  final version = _u32(bytes, 4);
  final count = _u32(bytes, 8);
  final shDegree = bytes[12];
  final fractionalBits = bytes[13];
  final flags = bytes[14];
  final (low, high) = v4 ? (4, 4) : (1, 3);
  if (version < low || version > high) {
    throw SplatSpzException(
      v4
          ? 'an NGSP header names version $version; a clear header is '
                'version 4, and versions 1 to 3 are gzip streams'
          : 'the packed header names version $version, which is not one of '
                'the gzip versions 1 to 3',
    );
  }
  if (shDegree > 4) {
    throw SplatSpzException(
      'spherical-harmonic degree $shDegree; the format carries 0 to 4',
    );
  }
  if (fractionalBits > 23) {
    throw SplatSpzException(
      '$fractionalBits fractional bits in a 24-bit fixed point number',
    );
  }
  return (
    version: version,
    count: count,
    shDegree: shDegree,
    fractionalBits: fractionalBits,
    flags: flags,
  );
}

_Packed _unpackLegacy(Uint8List data) {
  if (data.length < _kLegacyHeaderBytes || _u32(data, 0) != _kMagic) {
    throw const SplatSpzException(
      'a gzip stream, but what it holds does not start with the NGSP magic',
    );
  }
  final h = _header(data, v4: false);
  final n = h.count;
  final sizes = <int>[
    n * 3 * (h.version == 1 ? 2 : 3),
    n,
    n * 3,
    n * 3,
    n * (h.version >= 3 ? 4 : 3),
    n * _shDim(h.shDegree) * 3,
  ];
  final needed = sizes.fold(_kLegacyHeaderBytes, (int a, int b) => a + b);
  if (needed > data.length) {
    throw SplatSpzException(
      'the header claims $n splats, which is $needed bytes of attributes; '
      'the stream holds ${data.length}',
    );
  }
  final streams = <Uint8List>[
    for (
      var s = 0, at = _kLegacyHeaderBytes;
      s < sizes.length;
      at += sizes[s++]
    )
      Uint8List.sublistView(data, at, at + sizes[s]),
  ];
  // Extension records, when the flag says there are some, follow the
  // attributes; only the one that moves the axes changes what is read.
  if ((h.flags & 0x2) != 0) _checkExtensions(data, needed, data.length);
  return _packed(h, streams);
}

_Packed _unpackV4(Uint8List bytes) {
  if (bytes.length < _kHeaderBytes) {
    throw const SplatSpzException('an NGSP header, but shorter than one');
  }
  final h = _header(bytes, v4: true);
  final streamCount = bytes[15];
  final toc = _u32(bytes, 16);
  if (toc < _kHeaderBytes || toc + streamCount * 16 > bytes.length) {
    throw SplatSpzException(
      'the table of contents at byte $toc for $streamCount streams does not '
      'fit a ${bytes.length}-byte file',
    );
  }
  if ((h.flags & 0x2) != 0) _checkExtensions(bytes, _kHeaderBytes, toc);

  final n = h.count;
  // The writer's order, with an empty attribute — the harmonics at degree
  // 0 — written as no stream at all rather than as an empty one.
  final sizes = <int>[
    n * 9,
    n,
    n * 3,
    n * 3,
    n * 4,
    n * _shDim(h.shDegree) * 3,
  ].where((int size) => size > 0).toList();
  if (sizes.length != streamCount) {
    throw SplatSpzException(
      'the header names $streamCount streams; $n splats at degree '
      '${h.shDegree} are ${sizes.length}',
    );
  }

  final streams = <Uint8List>[];
  var at = toc + streamCount * 16;
  for (var s = 0; s < streamCount; s++) {
    final compressed = _u64(bytes, toc + s * 16);
    final size = _u64(bytes, toc + s * 16 + 8);
    if (size != sizes[s]) {
      throw SplatSpzException(
        'stream $s says it inflates to $size bytes; $n splats need '
        '${sizes[s]}',
      );
    }
    if (compressed > bytes.length - at) {
      throw SplatSpzException('stream $s runs past the end of the file');
    }
    final inflated = zstdDecode(
      Uint8List.sublistView(bytes, at, at + compressed),
      sizeHint: size,
    );
    if (inflated == null || inflated.length != size) {
      throw SplatSpzException('stream $s is not a zstd frame this decodes');
    }
    streams.add(inflated);
    at += compressed;
  }
  if (streams.length == 5) streams.add(Uint8List(0));
  return _packed(h, streams);
}

_Packed _packed(
  ({int version, int count, int shDegree, int fractionalBits, int flags}) h,
  List<Uint8List> streams,
) => (
  version: h.version,
  count: h.count,
  shDegree: h.shDegree,
  fractionalBits: h.fractionalBits,
  positions: streams[0],
  alphas: streams[1],
  colours: streams[2],
  scales: streams[3],
  rotations: streams[4],
  sh: streams[5],
);

/// Walks the extension records in `[from, to)` and refuses the one that
/// stores the cloud in other axes — reading past it would draw the capture
/// turned or mirrored with nothing to say why. Every other record is a
/// vendor's metadata and is skipped by its length, as the format intends.
void _checkExtensions(Uint8List bytes, int from, int to) {
  var at = from;
  while (at + 8 <= to) {
    final type = _u32(bytes, at);
    final length = _u32(bytes, at + 4);
    if (type == _kCoordinateSystemExtension) {
      throw const SplatSpzException(
        'the file carries SPZ_ADOBE_coordinate_system, so its axes are not '
        'the right, up, back this reader assumes; that extension is not read '
        'here yet',
      );
    }
    at += 8 + length;
  }
}

SplatCloud _decode(
  _Packed p,
  SplatAxes axes,
  bool keepHigherBands,
  SplatColourSpace colourSpace,
) {
  final n = p.count;
  final flip = axes.halfTurnAboutX ? -1.0 : 1.0;

  final centres = Float32List(n * 3);
  if (p.version == 1) {
    // Never released, the reference says, but its reader still takes it:
    // half floats rather than fixed point.
    final halves = ByteData.sublistView(p.positions);
    for (var i = 0; i < n * 3; i++) {
      centres[i] = _half(halves.getUint16(i * 2, Endian.little));
    }
  } else {
    final unit = 1.0 / (1 << p.fractionalBits);
    for (var i = 0; i < n * 3; i++) {
      final b = p.positions;
      final raw = b[i * 3] | (b[i * 3 + 1] << 8) | (b[i * 3 + 2] << 16);
      // Sign-extended from 24 bits by arithmetic rather than by a shift, so
      // the web's 32-bit bitwise operators give the same answer.
      final fixed = raw >= 0x800000 ? raw - 0x1000000 : raw;
      centres[i] = fixed * unit;
    }
  }
  for (var i = 0; i < n; i++) {
    centres[i * 3 + 1] *= flip;
    centres[i * 3 + 2] *= flip;
  }

  final colours = Float32List(n * 4);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < 3; c++) {
      final coefficient = (p.colours[i * 3 + c] / 255.0 - 0.5) / _kColourScale;
      // A byte of nought is a coefficient of about −3.3, below the −1.77
      // where the channel crosses zero: the clamp is not hypothetical here.
      colours[i * 4 + c] = splatColour(coefficient, colourSpace);
    }
    // The byte is the opacity already through the logistic: the reference
    // takes its logit only for a PLY, which wants one.
    colours[i * 4 + 3] = p.alphas[i] / 255.0;
  }

  final scales = Float32List(n * 3);
  for (var i = 0; i < n * 3; i++) {
    scales[i] = math.exp(p.scales[i] / 16.0 - 10.0);
  }

  final rotations = Float32List(n * 4);
  final q = Float64List(4);
  for (var i = 0; i < n; i++) {
    if (p.version >= 3) {
      _smallestThree(p.rotations, i * 4, q);
    } else {
      _firstThree(p.rotations, i * 3, q);
    }
    final length = math.sqrt(
      q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3],
    );
    final scale = length > 1e-12 ? 1.0 / length : 0.0;
    rotations[i * 4] = q[0] * scale;
    rotations[i * 4 + 1] = q[1] * scale * flip;
    rotations[i * 4 + 2] = q[2] * scale * flip;
    rotations[i * 4 + 3] = length > 1e-12 ? q[3] * scale : 1.0;
  }

  final degree = keepHigherBands ? p.shDegree : 0;
  final dim = _shDim(degree);
  final stored = _shDim(p.shDegree);
  final shRest = Float32List(n * dim * 3);
  for (var i = 0; i < n; i++) {
    for (var k = 0; k < dim; k++) {
      final sign = flip < 0 ? _kHalfTurnXSigns[k] : 1.0;
      for (var c = 0; c < 3; c++) {
        final byte = p.sh[(i * stored + k) * 3 + c];
        shRest[(i * dim + k) * 3 + c] = sign * (byte - 128) / 128.0;
      }
    }
  }

  return SplatCloud(
    centres: centres,
    colours: colours,
    scales: scales,
    rotations: rotations,
    shDegree: degree,
    shRest: shRest,
  );
}

/// Version 2's rotation: `xyz` a byte each, `w` the non-negative remainder.
void _firstThree(Uint8List r, int at, Float64List q) {
  var squares = 0.0;
  for (var k = 0; k < 3; k++) {
    q[k] = r[at + k] / 127.5 - 1.0;
    squares += q[k] * q[k];
  }
  q[3] = math.sqrt(math.max(0.0, 1.0 - squares));
}

/// Versions 3 and 4: two bits name the largest component, which is left out
/// and rebuilt; the other three are nine bits of magnitude over `1/√2` and a
/// sign, packed from the last component down.
void _smallestThree(Uint8List r, int at, Float64List q) {
  // Read as a sum rather than or-ed shifts: the top byte shifted by 24 is
  // negative in the web's 32-bit bitwise arithmetic.
  var comp =
      r[at] + r[at + 1] * 0x100 + r[at + 2] * 0x10000 + r[at + 3] * 0x1000000;
  const mask = (1 << 9) - 1;
  final largest = comp ~/ 0x40000000;
  var squares = 0.0;
  for (var k = 3; k >= 0; k--) {
    if (k == largest) continue;
    final magnitude = comp % 512;
    final negative = (comp ~/ 512) % 2 == 1;
    comp = comp ~/ 1024;
    final value = math.sqrt1_2 * magnitude / mask;
    q[k] = negative ? -value : value;
    squares += value * value;
  }
  q[largest] = math.sqrt(math.max(0.0, 1.0 - squares));
}

/// An IEEE half float as a double.
double _half(int h) {
  final sign = (h & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (h >> 10) & 0x1f;
  final mantissa = h & 0x3ff;
  return switch (exponent) {
    0 => sign * mantissa * math.pow(2, -24),
    31 => mantissa == 0 ? sign * double.infinity : double.nan,
    _ => sign * (1 + mantissa / 1024) * math.pow(2, exponent - 15),
  };
}

/// A gzip member (RFC 1952) inflated: the header's optional fields skipped,
/// the DEFLATE body handed to [inflate], the trailer left unread.
Uint8List _gunzip(Uint8List bytes) {
  if (bytes.length < 18 || bytes[2] != 8) {
    throw const SplatSpzException('a gzip header, but not a DEFLATE one');
  }
  final flags = bytes[3];
  var at = 10;
  if ((flags & 0x04) != 0) at += 2 + (bytes[at] | (bytes[at + 1] << 8));
  if ((flags & 0x08) != 0) at = bytes.indexOf(0, at) + 1; // name
  if ((flags & 0x10) != 0) at = bytes.indexOf(0, at) + 1; // comment
  if ((flags & 0x02) != 0) at += 2; // header CRC
  if (at <= 0 || at >= bytes.length) {
    throw const SplatSpzException('a gzip header that runs off its own end');
  }
  final inflated = inflate(Uint8List.sublistView(bytes, at));
  if (inflated == null) {
    throw const SplatSpzException('the gzip stream does not inflate');
  }
  return inflated;
}

int _u32(Uint8List b, int at) =>
    b[at] + b[at + 1] * 0x100 + b[at + 2] * 0x10000 + b[at + 3] * 0x1000000;

/// A little-endian `u64` that has to fit a Dart integer on every platform,
/// which any real length does.
int _u64(Uint8List b, int at) => _u32(b, at) + _u32(b, at + 4) * 0x100000000;
