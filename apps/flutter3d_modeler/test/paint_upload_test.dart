/// `PaintUpload` — `pro-pt-03`: one write per stroke, over the rectangle the
/// stroke changed.
///
///     flutter test test/paint_upload_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/material_pool.dart';
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

  test('a finished stroke leaves the texture with its whole chain', () async {
    // **The clause that was open on `pro-pt-03`, and the path it takes.**
    // Nothing writes a mip level below zero — `overwriteTexture` refuses —
    // so the chain comes from a whole upload, and the whole upload is the
    // one `MaterialPool` already does when a material's version moves.
    // `withPaint` moves it, so a refresh after the stroke is the rebuild.
    final fake = device as FakeBackend;
    final pool = MaterialPool(device: fake);

    final Uint8List before = encodeCompressedPng(
      64,
      64,
      Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 40),
    );
    var project = const ModelProject().copyWith(
      images: <EncodedImage>[
        EncodedImage(bytes: before, name: 'albedo', mimeType: 'image/png'),
      ],
      materials: <ProjectMaterial>[
        ProjectMaterial(
          surface: SurfaceMaterial(
            name: 'painted',
            baseColorTexture: TextureBinding(imageIndex: 0),
          ),
        ),
      ],
    );
    await pool.refresh(project);
    final int uploadsBefore = fake.uploadedMipLevels.length;

    // The stroke: new bytes in the slot, and a material version that moved.
    final Uint8List after = encodeCompressedPng(
      64,
      64,
      Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 200),
    );
    project = project.copyWith(
      images: <EncodedImage>[
        EncodedImage(bytes: after, name: 'albedo', mimeType: 'image/png'),
      ],
      materials: <ProjectMaterial>[
        project.materials.single.withPaint(stackOf(64, <(int, int)>[(0, 0)])),
      ],
    );
    await pool.refresh(project);

    expect(
      fake.uploadedMipLevels.length,
      greaterThan(uploadsBefore),
      reason: 'the repainted image was never uploaded again',
    );
    // 64 down to 1 is six levels below the base. **Mutation: upload with
    // `mipLevels: null`.** The picture is identical at arm's length and the
    // surface shimmers the moment it is seen at an angle, which is the whole
    // of what a chain is for.
    expect(fake.uploadedMipLevels.last, hasLength(6));
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
