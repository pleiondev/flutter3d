/// A baked lightmap: the light a level's walls receive from each other,
/// stored beside the level and read at load.
///
/// ## What is in it
///
/// Irradiance per texel, in the units the shaders light with — the same
/// `colour × intensity × attenuation × cos` a point light contributes — so
/// the fragment shader adds `albedo × lightmap` beside its direct terms and
/// nothing has to be rescaled. Indirect light only, by default: the direct
/// light and its shadows stay dynamic, so a torch can flicker and a door
/// can open, and what the map carries is the part that does not move — the
/// glow a lit wall throws on the floor.
///
/// ## RGBM
///
/// Eight bits a channel cannot hold a floor lit at four and a corner lit at
/// a twentieth, so each texel is stored as colour over a shared multiplier:
/// `rgb × a × kScale`. It decodes in one multiply in the shader, uploads as
/// the plain RGBA8 every backend takes, and keeps precision where it is
/// dark, which is where a lightmap spends most of its texels.
///
/// ## The sidecar
///
/// `<level>.lightmap.bin`: a magic, a version, the size, the density, a hash
/// of everything the bake read, then the pixels. The layout is not stored —
/// see `LightmapLayout` — and the hash is what refuses a map baked from a
/// wall that has since moved.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'level.dart';

final class Lightmap {
  Lightmap({
    required this.width,
    required this.height,
    required this.texelsPerMetre,
    required this.levelHash,
    Uint8List? pixels,
  }) : pixels = pixels ?? Uint8List(width * height * 4) {
    if (this.pixels.length != width * height * 4) {
      throw ArgumentError(
        'a $width by $height lightmap is ${width * height * 4} bytes, not '
        '${this.pixels.length}',
      );
    }
  }

  static const int formatVersion = 1;

  /// The multiplier's range: a texel can hold up to this much irradiance.
  static const double kScale = 8.0;

  /// `F3DL`, the four bytes a sidecar starts with.
  static const List<int> magic = <int>[0x46, 0x33, 0x44, 0x4C];

  static const int _headerBytes = 4 + 4 + 4 + 4 + 4 + 4;

  final int width;
  final int height;
  final double texelsPerMetre;

  /// [hashOf] the level this was baked from.
  final int levelHash;

  /// RGBM, four bytes a texel, row-major from the top-left.
  final Uint8List pixels;

  int get texelCount => width * height;

  bool isStaleFor(Level level) => levelHash != hashOf(level);

  /// The irradiance stored at a texel.
  Vector3 irradianceAt(int x, int y) {
    final at = (y * width + x) * 4;
    final m = pixels[at + 3] / 255.0 * kScale;
    return Vector3(
      pixels[at] / 255.0 * m,
      pixels[at + 1] / 255.0 * m,
      pixels[at + 2] / 255.0 * m,
    );
  }

  /// Stores an irradiance at a texel, clamped to what RGBM can hold.
  void setIrradiance(int x, int y, double r, double g, double b) {
    final at = (y * width + x) * 4;
    final brightest = math.max(r, math.max(g, b));
    if (brightest <= 0.0) {
      pixels[at] = 0;
      pixels[at + 1] = 0;
      pixels[at + 2] = 0;
      pixels[at + 3] = 0;
      return;
    }
    // The multiplier rounds up, so the colour channels round to a fraction
    // of a whole multiplier and nothing clips inside the texel.
    final multiplier = (brightest / kScale).clamp(0.0, 1.0);
    final quantised = (multiplier * 255.0).ceil().clamp(1, 255);
    final m = quantised / 255.0 * kScale;
    int channel(double value) => (value / m * 255.0).round().clamp(0, 255);
    pixels[at] = channel(r);
    pixels[at + 1] = channel(g);
    pixels[at + 2] = channel(b);
    pixels[at + 3] = quantised;
  }

  /// The sidecar's bytes.
  Uint8List toBytes() {
    final out = Uint8List(_headerBytes + pixels.length);
    final view = ByteData.view(out.buffer);
    out.setRange(0, 4, magic);
    view
      ..setUint32(4, formatVersion, Endian.little)
      ..setUint32(8, width, Endian.little)
      ..setUint32(12, height, Endian.little)
      ..setFloat32(16, texelsPerMetre, Endian.little)
      ..setUint32(20, levelHash, Endian.little);
    out.setRange(_headerBytes, out.length, pixels);
    return out;
  }

  /// Reads a sidecar. Throws [FormatException] naming what is wrong rather
  /// than returning a map of the wrong shape.
  factory Lightmap.fromBytes(Uint8List bytes) {
    if (bytes.length < _headerBytes) {
      throw const FormatException('too short for a lightmap header');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const FormatException('not a lightmap: the magic is wrong');
      }
    }
    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final version = view.getUint32(4, Endian.little);
    if (version != formatVersion) {
      throw FormatException(
        'lightmap format $version, and this reader knows $formatVersion',
      );
    }
    final width = view.getUint32(8, Endian.little);
    final height = view.getUint32(12, Endian.little);
    final expected = width * height * 4;
    if (bytes.length - _headerBytes != expected) {
      throw FormatException(
        'a $width by $height lightmap needs $expected bytes of pixels, and '
        'the file has ${bytes.length - _headerBytes}',
      );
    }
    return Lightmap(
      width: width,
      height: height,
      texelsPerMetre: view.getFloat32(16, Endian.little),
      levelHash: view.getUint32(20, Endian.little),
      pixels: Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes + _headerBytes, expected),
      ),
    );
  }

  /// A hash of everything a bake reads: every brush, the lights, and the
  /// materials' colours. Anything else changing leaves the map valid.
  ///
  /// Every brush, not only the solid ones, and each brush's material name
  /// along with its box. `LightmapLayout.plan` packs a rectangle for every
  /// face `BrushGeometry.blockFaces` yields, and that walks the whole brush
  /// list — so a decorative moulding, which stops nothing and so never
  /// reaches the collision world, still shifts the shelves under every face
  /// packed after it. And the bounce reflects `level.materialFor(brush)`, so
  /// moving a wall from `stone` to `soot` changes the light in the room
  /// while both materials, and every box, stay exactly as they were. Neither
  /// is visible to `LevelVisibility.hashBrushes`, which hashes what decides
  /// *visibility* — solid boxes only — and is right to.
  static int hashOf(Level level) {
    var hash = 0x811C9DC5;
    void mix(String text) {
      for (final unit in text.codeUnits) {
        hash ^= unit;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      hash ^= 0x7C;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    for (final brush in level.brushes) {
      mix(brush.centre.x.toStringAsFixed(4));
      mix(brush.centre.y.toStringAsFixed(4));
      mix(brush.centre.z.toStringAsFixed(4));
      mix(brush.size.x.toStringAsFixed(4));
      mix(brush.size.y.toStringAsFixed(4));
      mix(brush.size.z.toStringAsFixed(4));
      final ramp = brush.ramp;
      mix(ramp == null ? '-' : '${ramp.x},${ramp.z}');
      // Solidity is not a face, but it is an occluder: a brush that stops
      // nothing stops no ray either.
      mix(brush.solid ? 'solid' : 'open');
      mix(brush.material);
    }
    for (final light in level.lights) {
      mix(light.type.name);
      mix(light.position.toString());
      mix(light.direction.toString());
      mix(light.color.toString());
      mix(light.intensity.toString());
      mix(light.range.toString());
    }
    for (final entry in level.materials.entries) {
      mix(entry.key);
      mix(entry.value.baseColor.toString());
      mix(entry.value.albedo ?? '');
    }
    return hash;
  }
}
