/// `encodePng`: a real, compressed PNG writer — `mat-12`'s own acceptance,
/// checked two ways: round-tripped through this package's own `decodePng`
/// (`mat-09n`), and decoded by `dart:io`'s own `ZLibCodec` at the `IDAT`
/// level, since that is the one independent check available to a package
/// with no `dart:ui` to hand a whole PNG to.
///
///     dart test test/png_encoder_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

/// The `IDAT` chunk's own bytes out of a PNG this file wrote — enough to
/// hand to `dart:io` directly without writing a second chunk-walker just
/// for tests.
Uint8List _idatOf(Uint8List png) {
  var offset = 8;
  while (true) {
    final view = ByteData.sublistView(png);
    final length = view.getUint32(offset, Endian.big);
    final type = String.fromCharCodes(png, offset + 4, offset + 8);
    final dataStart = offset + 8;
    if (type == 'IDAT') {
      return Uint8List.sublistView(png, dataStart, dataStart + length);
    }
    offset = dataStart + length + 4;
  }
}

void main() {
  group('round-trips through decodePng', () {
    test('a flat colour', () {
      const side = 8;
      final rgba = Uint8List(side * side * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 40;
        rgba[i + 1] = 90;
        rgba[i + 2] = 200;
        rgba[i + 3] = 255;
      }
      final png = encodePng(side, side, rgba);
      final decoded = decodePng(png);
      expect(decoded, isNotNull);
      expect(decoded!.width, side);
      expect(decoded.height, side);
      expect(decoded.rgba, rgba);
    });

    test('a gradient, where each row differs from the last', () {
      const side = 32;
      final rgba = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final at = (y * side + x) * 4;
          rgba[at] = x * 8;
          rgba[at + 1] = y * 8;
          rgba[at + 2] = (x + y) * 4;
          rgba[at + 3] = 255;
        }
      }
      final png = encodePng(side, side, rgba);
      expect(decodePng(png)!.rgba, rgba);
    });

    test('noise, where no filter helps much and literals dominate', () {
      const side = 40;
      var seed = 42;
      final rgba = Uint8List(side * side * 4);
      for (var i = 0; i < rgba.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        rgba[i] = seed & 0xFF;
      }
      final png = encodePng(side, side, rgba);
      expect(decodePng(png)!.rgba, rgba);
    });

    test('a single pixel', () {
      final rgba = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final png = encodePng(1, 1, rgba);
      expect(decodePng(png)!.rgba, rgba);
    });
  });

  test('the IDAT chunk is itself readable by an independent decoder', () {
    const side = 16;
    final rgba = Uint8List(side * side * 4);
    for (var i = 0; i < rgba.length; i++) {
      rgba[i] = i % 256;
    }
    final png = encodePng(side, side, rgba);
    final idat = _idatOf(png);
    // Not a pixel comparison — just proof the compressed bytes this
    // encoder wrote are a real zlib stream and not only one this
    // package's own (matching) decoder happens to accept.
    expect(() => ZLibCodec().decode(idat), returnsNormally);
  });

  test('mat-12\'s own acceptance: a 1024x1024 gradient compresses under '
      '25% of its stored size', () {
    const side = 1024;
    final rgba = Uint8List(side * side * 4);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final at = (y * side + x) * 4;
        rgba[at] = x * 255 ~/ side;
        rgba[at + 3] = 255;
      }
    }
    // This particular gradient is so redundant — 1024 pixels sharing only
    // 255 distinct values, four to a run — that LZ77 alone crushes it
    // regardless of which filter wrote the bytes; the test below is the
    // one that actually depends on `_bestFilter` choosing well.
    final png = encodePng(side, side, rgba);
    expect(png.length, lessThan(rgba.length * 0.25));
    expect(decodePng(png)!.rgba, rgba);
  });

  test('a texture where filter choice is the difference between passing '
      'and failing the 25% target', () {
    // A bounded random walk: each pixel's red channel is the last one
    // plus a small step from a fixed hash sequence, never `Random`.
    // Unfiltered, consecutive values rarely repeat — a walk visits new
    // ground — so raw LZ77 has little to find; `Sub`-filtered, the byte
    // written at each pixel is that same small step, drawn from only
    // seven possible values, which repeat constantly and let LZ77 do the
    // rest. Measured directly: adaptive filtering lands this at 21% of
    // stored size, filter type `None` throughout at 29% — on opposite
    // sides of the row's own quarter-size line.
    //
    // Mutation: skip `_bestFilter`'s own comparison and always write
    // filter type `None` — this is the one test in the file that
    // actually crosses the 25% line over it, rather than staying well
    // under regardless.
    const side = 256;
    final rgba = Uint8List(side * side * 4);
    var seed = 7;
    var value = 128;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        final step = (seed % 7) - 3;
        value = (value + step) & 0xFF;
        final at = (y * side + x) * 4;
        rgba[at] = value;
        rgba[at + 3] = 255;
      }
    }
    final png = encodePng(side, side, rgba);
    expect(png.length, lessThan(rgba.length * 0.25));
    expect(decodePng(png)!.rgba, rgba);
  });
}
