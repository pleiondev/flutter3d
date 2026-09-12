import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

Uint8List _solidTile(List<int> rgba) {
  final pixels = Uint8List(paintTileSize * paintTileSize * 4);
  for (var i = 0; i < paintTileSize * paintTileSize; i++) {
    pixels[i * 4] = rgba[0];
    pixels[i * 4 + 1] = rgba[1];
    pixels[i * 4 + 2] = rgba[2];
    pixels[i * 4 + 3] = rgba[3];
  }
  return pixels;
}

PaintLayer _solidLayer(BlendMode mode, List<int> rgba) => PaintLayer(
  tilesX: 1,
  tilesY: 1,
  blendMode: mode,
).paintTile(0, 0, _solidTile(rgba));

void main() {
  group('blend modes, both layers opaque', () {
    // Bottom (200,150,90,255) is fixed across normal/multiply/add/screen so
    // each mode's own arithmetic is the only thing changing between cases.
    const top = <int>[200, 150, 90, 255];
    const bottom = <int>[150, 80, 60, 255];

    Uint8List flattenOf(BlendMode mode) => PaintStack(<PaintLayer>[
      _solidLayer(BlendMode.normal, bottom),
      _solidLayer(mode, top),
    ]).flatten();

    test('normal passes the top color through', () {
      final out = flattenOf(BlendMode.normal);
      expect(out.sublist(0, 4), equals(top));
    });

    test('multiply is top*bottom per channel', () {
      final out = flattenOf(BlendMode.multiply);
      expect(out.sublist(0, 4), equals(<int>[118, 47, 21, 255]));
    });

    test('add is top+bottom per channel', () {
      final out = flattenOf(BlendMode.add);
      expect(out.sublist(0, 4), equals(<int>[255, 230, 150, 255]));
    });

    test('add clips at 255 rather than wrapping', () {
      final out = PaintStack(<PaintLayer>[
        _solidLayer(BlendMode.normal, <int>[100, 5, 0, 255]),
        _solidLayer(BlendMode.add, <int>[200, 10, 0, 255]),
      ]).flatten();
      expect(out.sublist(0, 4), equals(<int>[255, 15, 0, 255]));
    });

    test('screen is 1-(1-top)*(1-bottom) per channel', () {
      final out = flattenOf(BlendMode.screen);
      expect(out.sublist(0, 4), equals(<int>[232, 183, 129, 255]));
    });
  });

  group('overlay, both branches of its own condition', () {
    const top = <int>[200, 120, 60, 255];

    test('multiplies where the base is dark', () {
      final out = PaintStack(<PaintLayer>[
        _solidLayer(BlendMode.normal, <int>[150, 40, 30, 255]),
        _solidLayer(BlendMode.overlay, top),
      ]).flatten();
      expect(out.sublist(0, 4), equals(<int>[210, 38, 14, 255]));
    });

    test('screens where the base is light', () {
      final out = PaintStack(<PaintLayer>[
        _solidLayer(BlendMode.normal, <int>[150, 200, 220, 255]),
        _solidLayer(BlendMode.overlay, top),
      ]).flatten();
      expect(out.sublist(0, 4), equals(<int>[210, 197, 201, 255]));
    });
  });

  test('a semi-transparent top layer mixes by its own alpha', () {
    final out = PaintStack(<PaintLayer>[
      _solidLayer(BlendMode.normal, <int>[0, 255, 0, 255]),
      _solidLayer(BlendMode.normal, <int>[255, 0, 0, 128]),
    ]).flatten();
    expect(out.sublist(0, 4), equals(<int>[128, 127, 0, 255]));
  });

  test('layer order changes the result, not just which layer is on top', () {
    final bottom = _solidLayer(BlendMode.normal, <int>[255, 0, 0, 255]);
    final blue = _solidLayer(BlendMode.normal, <int>[0, 0, 255, 128]);
    final green = _solidLayer(BlendMode.normal, <int>[0, 255, 0, 128]);

    final blueOnTop = PaintStack(<PaintLayer>[bottom, green, blue]).flatten();
    final greenOnTop = PaintStack(<PaintLayer>[bottom, blue, green]).flatten();

    expect(blueOnTop.sublist(0, 4), equals(<int>[63, 64, 128, 255]));
    expect(greenOnTop.sublist(0, 4), equals(<int>[63, 128, 64, 255]));
    expect(blueOnTop, isNot(equals(greenOnTop)));
  });

  group('copy-on-write tiles', () {
    test(
      'painting one tile leaves every other tile\'s own bytes untouched',
      () {
        final original = PaintLayer(
          tilesX: 2,
          tilesY: 1,
        ).paintTile(0, 0, _solidTile(<int>[10, 20, 30, 255]));
        final withSecondTile = original.paintTile(
          1,
          0,
          _solidTile(<int>[40, 50, 60, 255]),
        );

        final branch = withSecondTile.paintTile(
          1,
          0,
          _solidTile(<int>[99, 99, 99, 255]),
        );

        expect(
          identical(branch.tileAt(0, 0), withSecondTile.tileAt(0, 0)),
          isTrue,
          reason: 'an untouched tile keeps its original instance',
        );
        expect(
          identical(branch.tileAt(1, 0), withSecondTile.tileAt(1, 0)),
          isFalse,
        );
      },
    );

    test(
      'painting a branch does not mutate the layer it was branched from',
      () {
        final original = PaintLayer(
          tilesX: 1,
          tilesY: 1,
        ).paintTile(0, 0, _solidTile(<int>[10, 20, 30, 255]));
        final untouchedPixels = original.tileAt(0, 0)!.pixels;

        original.paintTile(0, 0, _solidTile(<int>[200, 200, 200, 255]));

        expect(original.tileAt(0, 0)!.pixels, same(untouchedPixels));
        expect(original.tileAt(0, 0)!.pixels[0], 10);
      },
    );
  });
}
