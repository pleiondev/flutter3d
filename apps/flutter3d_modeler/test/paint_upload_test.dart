/// `PaintUpload` — `pro-pt-03`: one write per stroke, over the rectangle the
/// stroke changed.
///
///     flutter test test/paint_upload_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/paint_upload.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stack of one layer over a [canvas]-wide square, with [tiles] painted.
PaintStack stackOf(int canvas, List<(int, int)> tiles) {
  final int across = (canvas / paintTileSize).ceil();
  var layer = PaintLayer(tilesX: across, tilesY: across);
  for (final (int tx, int ty) in tiles) {
    layer = layer.paintTile(
      tx,
      ty,
      Uint8List(paintTileSize * paintTileSize * 4)..fillRange(0, 16, 255),
    );
  }
  return PaintStack(<PaintLayer>[layer]);
}

void main() {
  late GraphicsDevice device;
  late TextureHandle texture;

  TextureHandle square(int side) => device.createTextureFromPixels(
    width: side,
    height: side,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(side * side * 4),
  )!;

  setUp(() {
    device = FakeBackend();
    texture = square(128);
  });

  test('writes the tiles the stroke changed, and only those', () async {
    // Four tiles a side, and a stroke that touched one of them in the
    // middle: a bounding rectangle over two diagonal corners of a 2×2
    // canvas is the whole canvas, which says nothing.
    final TextureHandle wide = square(256);
    final PaintUpload upload = PaintUpload(device: device);
    upload.opened(stackOf(256, <(int, int)>[(0, 0)]), canvas: 256);

    final int written = await upload.flush(
      wide,
      stackOf(256, <(int, int)>[(0, 0), (1, 1)]),
      Uint8List(256 * 256 * 4),
    );

    // **Mutation: upload the whole canvas.** The picture is identical and
    // the cost is the whole texture per stroke — the difference between
    // painting and waiting, which is the clause this closes.
    expect(written, (2 * paintTileSize) * (2 * paintTileSize));
    expect(written, lessThan(256 * 256));
  });

  test('a stroke that changed nothing writes nothing', () async {
    final PaintUpload upload = PaintUpload(device: device);
    final PaintStack stack = stackOf(128, <(int, int)>[(0, 0)]);
    upload.opened(stack, canvas: 128);
    expect(await upload.flush(texture, stack, Uint8List(128 * 128 * 4)), 0);
  });

  test('and a stroke onto an empty material writes what it painted', () async {
    final PaintUpload upload = PaintUpload(device: device)
      ..opened(null, canvas: 128);
    final int written = await upload.flush(
      texture,
      stackOf(128, <(int, int)>[(0, 0)]),
      Uint8List(128 * 128 * 4),
    );
    expect(written, paintTileSize * paintTileSize);
  });

  test('the rectangle stops at the canvas rather than past it', () async {
    // A canvas that is not a whole number of tiles: the last tile hangs off
    // the edge, and a write that sent its full width would ask the device
    // for texels the texture does not have.
    final TextureHandle small = square(100);
    final PaintUpload upload = PaintUpload(device: device)
      ..opened(null, canvas: 100);
    final int written = await upload.flush(
      small,
      stackOf(100, <(int, int)>[(1, 1)]),
      Uint8List(100 * 100 * 4),
    );
    expect(written, (100 - paintTileSize) * (100 - paintTileSize));
  });

  test('and nothing opened is nothing written', () async {
    expect(
      await PaintUpload(device: device).flush(
        texture,
        stackOf(128, <(int, int)>[(0, 0)]),
        Uint8List(128 * 128 * 4),
      ),
      0,
    );
  });
}
