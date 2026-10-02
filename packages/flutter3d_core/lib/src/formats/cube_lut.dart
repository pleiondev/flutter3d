/// A colour table in the `.cube` format — `P2`.
///
/// **The format every grading tool writes**: Resolve, Premiere, Photoshop and
/// OCIO all export it. Plain text: a few keywords, then one line of three
/// numbers per entry, red running fastest, then green, then blue. A table is
/// either 3D (`LUT_3D_SIZE N`, N³ lines) or 1D (`LUT_1D_SIZE N`, one curve
/// per channel), and `DOMAIN_MIN`/`DOMAIN_MAX` say what input the first and
/// last entries stand for.
///
/// The engine grades through a strip — N slices of N×N, `LookSettings.lut` —
/// so [CubeLut.toStrip] resamples whatever the file holds into one, the same
/// layout `buildIdentityLut` writes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// A parsed `.cube` file.
final class CubeLut {
  CubeLut._({
    required this.title,
    required this.size,
    required this.isOneD,
    required this.domainMin,
    required this.domainMax,
    required this._values,
  });

  /// Reads [text], a `.cube` file's contents. Throws a [FormatException]
  /// naming the line when it is not one: a missing size, a line that is not
  /// three numbers, too few or too many entries, a domain that is empty.
  factory CubeLut.parse(String text) {
    String? title;
    int? size3;
    int? size1;
    var domainMin = (0.0, 0.0, 0.0);
    var domainMax = (1.0, 1.0, 1.0);
    final values = <double>[];
    final lines = text.split(RegExp(r'\r\n|\r|\n'));

    (double, double, double) triple(List<String> words, int line) {
      if (words.length != 3) {
        throw FormatException('line $line: expected three numbers');
      }
      final parsed = words.map(double.tryParse).toList();
      if (parsed.contains(null)) {
        throw FormatException(
          'line $line: "${words.join(' ')}" is not three '
          'numbers',
        );
      }
      return (parsed[0]!, parsed[1]!, parsed[2]!);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = i + 1;
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final words = trimmed.split(RegExp(r'\s+'));
      switch (words.first) {
        case 'TITLE':
          final quoted = RegExp(r'"(.*)"').firstMatch(trimmed);
          title = quoted?.group(1) ?? words.skip(1).join(' ');
        case 'LUT_3D_SIZE':
          size3 = int.tryParse(words.length == 2 ? words[1] : '');
          if (size3 == null || size3 < 2 || size3 > 256) {
            throw FormatException('line $line: LUT_3D_SIZE must be 2 to 256');
          }
        case 'LUT_1D_SIZE':
          size1 = int.tryParse(words.length == 2 ? words[1] : '');
          if (size1 == null || size1 < 2 || size1 > 65536) {
            throw FormatException('line $line: LUT_1D_SIZE must be 2 to 65536');
          }
        case 'DOMAIN_MIN':
          domainMin = triple(words.sublist(1), line);
        case 'DOMAIN_MAX':
          domainMax = triple(words.sublist(1), line);
        // Written by some tools and meaningless to a table read here.
        case 'LUT_3D_INPUT_RANGE' || 'LUT_1D_INPUT_RANGE':
          final range = words.skip(1).map(double.tryParse).toList();
          if (range.length != 2 || range.contains(null)) {
            throw FormatException('line $line: an input range is two numbers');
          }
          domainMin = (range[0]!, range[0]!, range[0]!);
          domainMax = (range[1]!, range[1]!, range[1]!);
        default:
          final (r, g, b) = triple(words, line);
          values
            ..add(r)
            ..add(g)
            ..add(b);
      }
    }

    if (size3 != null && size1 != null) {
      throw const FormatException('a table is 3D or 1D, not both');
    }
    final size = size3 ?? size1;
    if (size == null) {
      throw const FormatException('no LUT_3D_SIZE or LUT_1D_SIZE');
    }
    final expected = size3 != null ? size * size * size : size;
    if (values.length != expected * 3) {
      throw FormatException(
        'expected $expected entries for a '
        '${size3 != null ? '3D' : '1D'} table of $size, found '
        '${values.length ~/ 3}',
      );
    }
    if (domainMax.$1 <= domainMin.$1 ||
        domainMax.$2 <= domainMin.$2 ||
        domainMax.$3 <= domainMin.$3) {
      throw const FormatException('DOMAIN_MAX must be above DOMAIN_MIN');
    }
    return CubeLut._(
      title: title,
      size: size,
      isOneD: size1 != null,
      domainMin: domainMin,
      domainMax: domainMax,
      values: Float32List.fromList(values),
    );
  }

  /// The file's `TITLE`, when it has one.
  final String? title;

  /// Entries per axis: N of N³ for a 3D table, the curve's length for 1D.
  final int size;

  /// Whether this is three curves rather than a cube.
  final bool isOneD;

  /// The input the first and last entries stand for, per channel.
  final (double, double, double) domainMin;
  final (double, double, double) domainMax;

  final Float32List _values;

  /// What the table makes of ([r], [g], [b]): trilinear between the eight
  /// nearest entries of a 3D table, linear along each curve of a 1D one.
  /// Inputs outside the domain are held to its edge.
  (double, double, double) lookup(double r, double g, double b) {
    double at(double value, double min, double max) =>
        ((value - min) / (max - min)).clamp(0.0, 1.0) * (size - 1);
    final x = at(r, domainMin.$1, domainMax.$1);
    final y = at(g, domainMin.$2, domainMax.$2);
    final z = at(b, domainMin.$3, domainMax.$3);
    if (isOneD) {
      double curve(double position, int channel) {
        final lower = position.floor();
        final upper = math.min(lower + 1, size - 1);
        final t = position - lower;
        final a = _values[lower * 3 + channel];
        return a + (_values[upper * 3 + channel] - a) * t;
      }

      return (curve(x, 0), curve(y, 1), curve(z, 2));
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final z0 = z.floor();
    final x1 = math.min(x0 + 1, size - 1);
    final y1 = math.min(y0 + 1, size - 1);
    final z1 = math.min(z0 + 1, size - 1);
    final tx = x - x0;
    final ty = y - y0;
    final tz = z - z0;
    double channel(int c) {
      double entry(int i, int j, int k) =>
          _values[((k * size + j) * size + i) * 3 + c];
      double along(int j, int k) =>
          entry(x0, j, k) + (entry(x1, j, k) - entry(x0, j, k)) * tx;
      double across(int k) => along(y0, k) + (along(y1, k) - along(y0, k)) * ty;
      return across(z0) + (across(z1) - across(z0)) * tz;
    }

    return (channel(0), channel(1), channel(2));
  }

  /// [toStrip] uploaded through [device], ready for `LookSettings.lut`; null
  /// when the device refuses a texture that size.
  ///
  /// ```dart
  /// final table = CubeLut.parse(await rootBundle.loadString('grade.cube'));
  /// final look = LookSettings(lut: table.upload(device));
  /// ```
  TextureHandle? upload(GraphicsDevice device, {int? stripSize}) {
    final n = stripSize ?? (isOneD ? 33 : math.min(size, 64));
    return device.createTextureFromPixels(
      width: n * n,
      height: n,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(toStrip(stripSize: n)),
    );
  }

  /// This table as the strip `LookSettings.lut` grades through: [stripSize]
  /// slices of [stripSize]×[stripSize], blue picking the slice, red across
  /// and green down, eight bits a channel — `buildIdentityLut`'s layout.
  ///
  /// [stripSize] defaults to the table's own size for a 3D table, which
  /// copies its entries exactly when the domain is the unit cube, and to 33
  /// for a 1D one. Outputs are clamped to 0…1: the strip is read after the
  /// picture is encoded for the display, where nothing lies outside them.
  Uint8List toStrip({int? stripSize}) {
    final n = stripSize ?? (isOneD ? 33 : math.min(size, 64));
    if (n < 2) {
      throw ArgumentError.value(n, 'stripSize', 'a table needs two ends');
    }
    final width = n * n;
    final pixels = Uint8List(width * n * 4);
    final last = n - 1;
    int byte(double v) => (v.clamp(0.0, 1.0) * 255.0).round();
    double input(int i, double min, double max) => min + (max - min) * i / last;
    for (var blue = 0; blue < n; blue++) {
      for (var green = 0; green < n; green++) {
        for (var red = 0; red < n; red++) {
          final (r, g, b) = lookup(
            input(red, domainMin.$1, domainMax.$1),
            input(green, domainMin.$2, domainMax.$2),
            input(blue, domainMin.$3, domainMax.$3),
          );
          final at = ((green * width) + blue * n + red) * 4;
          pixels[at] = byte(r);
          pixels[at + 1] = byte(g);
          pixels[at + 2] = byte(b);
          pixels[at + 3] = 255;
        }
      }
    }
    return pixels;
  }
}
