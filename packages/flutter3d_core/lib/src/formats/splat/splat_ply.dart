/// Reading a fitted cloud out of a binary PLY — `gfx-80n`.
///
/// **This is the format captures actually ship in.** The 3D Gaussian Splatting
/// work published its results as PLY point clouds with a fixed set of named
/// scalar properties, and every trainer and viewer since has kept those names:
/// `x y z`, `f_dc_0..2`, `opacity`, `scale_0..2`, `rot_0..3`. The container is
/// ordinary PLY — a text header, then the rows — so the interesting part is not
/// the parsing but the three conventions the header does not mention.
///
/// **Those three, stated once.** `opacity` is a logit and needs a logistic;
/// `scale_*` are logarithms and need an exponential; `f_dc_*` are the zeroth
/// spherical-harmonic band and need the constant in [kSplatShC0] plus a half.
/// A reader that skips any of them produces a cloud that loads, draws, and is
/// wrong in a way that reads as a bad capture rather than a bad reader — which
/// is why they are named here rather than left to the call site.
///
/// Higher spherical-harmonic bands (`f_rest_*`) are skipped deliberately: they
/// are what makes a splat change colour with the viewing angle, they are
/// forty-five floats a splat, and a first implementation that carried them
/// would be four times the memory for a difference nothing here can yet show.
/// The row says so too.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'splat_cloud.dart';

/// Thrown when a file is not a PLY this can read, with the reason in it.
final class SplatPlyException implements Exception {
  const SplatPlyException(this.message);
  final String message;
  @override
  String toString() => 'SplatPlyException: $message';
}

/// How wide each PLY scalar type is, and how to read it.
const Map<String, int> _scalarBytes = <String, int>{
  'char': 1, 'int8': 1, 'uchar': 1, 'uint8': 1, //
  'short': 2, 'int16': 2, 'ushort': 2, 'uint16': 2, //
  'int': 4, 'int32': 4, 'uint': 4, 'uint32': 4, 'float': 4, 'float32': 4, //
  'double': 8, 'float64': 8,
};

/// One property of the vertex element, as the header declared it.
typedef _Property = ({String name, String type, int offset});

/// The cloud in [bytes], or a thrown [SplatPlyException] saying why not.
SplatCloud parseSplatPly(Uint8List bytes) {
  final header = _readHeader(bytes);
  final stride = header.stride;
  final count = header.count;
  final data = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes + header.dataStart,
    bytes.lengthInBytes - header.dataStart,
  );

  double read(_Property p, int row) {
    final at = row * stride + p.offset;
    return switch (p.type) {
      'float' || 'float32' => data.getFloat32(at, Endian.little),
      'double' || 'float64' => data.getFloat64(at, Endian.little),
      'char' || 'int8' => data.getInt8(at).toDouble(),
      'uchar' || 'uint8' => data.getUint8(at).toDouble(),
      'short' || 'int16' => data.getInt16(at, Endian.little).toDouble(),
      'ushort' || 'uint16' => data.getUint16(at, Endian.little).toDouble(),
      'int' || 'int32' => data.getInt32(at, Endian.little).toDouble(),
      'uint' || 'uint32' => data.getUint32(at, Endian.little).toDouble(),
      _ => throw SplatPlyException('unreadable scalar type ${p.type}'),
    };
  }

  _Property need(String name) {
    final found = header.properties[name];
    if (found == null) {
      throw SplatPlyException(
        'The vertex element has no `$name` property, so this is a point cloud '
        'rather than a fitted Gaussian cloud. A splat PLY carries x, y, z, '
        'f_dc_0..2, opacity, scale_0..2 and rot_0..3.',
      );
    }
    return found;
  }

  final x = need('x'), y = need('y'), z = need('z');
  final dc0 = need('f_dc_0'), dc1 = need('f_dc_1'), dc2 = need('f_dc_2');
  final opacity = need('opacity');
  final s0 = need('scale_0'), s1 = need('scale_1'), s2 = need('scale_2');
  final r0 = need('rot_0'), r1 = need('rot_1');
  final r2 = need('rot_2'), r3 = need('rot_3');

  if (header.dataStart + count * stride > bytes.lengthInBytes) {
    throw SplatPlyException(
      'The header claims $count vertices of $stride bytes, which runs past the '
      'end of a ${bytes.lengthInBytes}-byte file.',
    );
  }

  final centres = Float32List(count * 3);
  final colours = Float32List(count * 4);
  final scales = Float32List(count * 3);
  final rotations = Float32List(count * 4);

  for (var i = 0; i < count; i++) {
    centres[i * 3] = read(x, i);
    centres[i * 3 + 1] = read(y, i);
    centres[i * 3 + 2] = read(z, i);

    colours[i * 4] = splatChannel(read(dc0, i));
    colours[i * 4 + 1] = splatChannel(read(dc1, i));
    colours[i * 4 + 2] = splatChannel(read(dc2, i));
    colours[i * 4 + 3] = splatOpacity(read(opacity, i));

    scales[i * 3] = math.exp(read(s0, i));
    scales[i * 3 + 1] = math.exp(read(s1, i));
    scales[i * 3 + 2] = math.exp(read(s2, i));

    // **The file's quaternion is `w` first; this engine's is `w` last.** Not a
    // preference: `Quaternion` in `vector_math` takes xyzw, and a cloud read
    // in the file's order turns every splat by whatever rotation the
    // misreading happens to name — which looks like a capture full of streaks
    // rather than like a swapped component.
    final w = read(r0, i);
    final qx = read(r1, i);
    final qy = read(r2, i);
    final qz = read(r3, i);
    // Normalised on the way in: a trainer writes whatever it converged to, and
    // an unnormalised quaternion scales the ellipsoid as well as turning it.
    final length = math.sqrt(w * w + qx * qx + qy * qy + qz * qz);
    final scale = length > 1e-12 ? 1.0 / length : 0.0;
    rotations[i * 4] = qx * scale;
    rotations[i * 4 + 1] = qy * scale;
    rotations[i * 4 + 2] = qz * scale;
    // A zero-length quaternion is not a rotation; the identity is the only
    // answer that is not a division by nothing.
    rotations[i * 4 + 3] = length > 1e-12 ? w * scale : 1.0;
  }

  return SplatCloud(
    centres: centres,
    colours: colours,
    scales: scales,
    rotations: rotations,
  );
}

typedef _Header = ({
  int count,
  int stride,
  int dataStart,
  Map<String, _Property> properties,
});

_Header _readHeader(Uint8List bytes) {
  // The header is ASCII and ends at `end_header`, so it is read as lines out of
  // the front of the file rather than by decoding the whole thing — a capture
  // is hundreds of megabytes and almost none of it is text.
  const limit = 1 << 16;
  final window = bytes.sublist(0, math.min(limit, bytes.length));
  final text = latin1.decode(window, allowInvalid: true);
  final endIndex = text.indexOf('end_header');
  if (!text.startsWith('ply')) {
    throw const SplatPlyException('not a PLY file: no `ply` magic');
  }
  if (endIndex < 0) {
    throw const SplatPlyException(
      'no `end_header` in the first 64 KiB, so this is not a PLY header',
    );
  }
  // Past the word and its line ending, whichever the writer used.
  var dataStart = endIndex + 'end_header'.length;
  if (dataStart < bytes.length && bytes[dataStart] == 0x0D) dataStart++;
  if (dataStart < bytes.length && bytes[dataStart] == 0x0A) dataStart++;

  final lines = text.substring(0, endIndex).split(RegExp(r'\r?\n'));
  var format = '';
  var count = -1;
  var inVertex = false;
  var stride = 0;
  final properties = <String, _Property>{};

  for (final line in lines) {
    final words = line.trim().split(RegExp(r'\s+'));
    switch (words.first) {
      case 'format':
        if (words.length > 1) format = words[1];
      case 'element':
        if (words.length < 3) continue;
        inVertex = words[1] == 'vertex';
        if (inVertex) count = int.tryParse(words[2]) ?? -1;
      case 'property':
        if (!inVertex || words.length < 3) continue;
        if (words[1] == 'list') {
          throw const SplatPlyException(
            'the vertex element has a list property, which a fitted cloud does '
            'not use and which would make the rows a variable width',
          );
        }
        final width = _scalarBytes[words[1]];
        if (width == null) {
          throw SplatPlyException('unknown scalar type `${words[1]}`');
        }
        properties[words[2]] = (name: words[2], type: words[1], offset: stride);
        stride += width;
    }
  }

  if (format != 'binary_little_endian') {
    throw SplatPlyException(
      'format is `$format`; only binary_little_endian is read here. An ASCII '
      'PLY of a million splats is a hundred times the file for the same '
      'numbers, and no trainer writes one.',
    );
  }
  if (count < 0) {
    throw const SplatPlyException('the header declares no vertex element');
  }

  return (
    count: count,
    stride: stride,
    dataStart: dataStart,
    properties: properties,
  );
}
