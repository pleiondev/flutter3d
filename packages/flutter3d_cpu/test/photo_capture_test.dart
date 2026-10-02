/// Photo mode's capture — `N8`: a picture of any size drawn in tiles on the
/// game's own device, finished over the whole frame and written out a strip
/// at a time.
///
///     dart test test/photo_capture_test.dart
///
/// The reference every claim is held to is the same scene drawn as one frame
/// on one device, with the settings the capture says it used.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 480;
const int _height = 360;

/// Two cubes off the axes, one of them bright enough to bloom, so a tile edge
/// in the wrong place moves geometry and a tile edge with no margin cuts a
/// glow.
({Scene scene, CameraNode camera}) _scene(GraphicsDevice device) {
  final scene = Scene()
    ..add(
      LightNode(type: LightType.directional, name: 'key')
        ..intensity = 3.0
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.4)).build()),
        Material(
          lighting: LightingModel.pbr,
          baseColor: Vector4(0.8, 0.3, 0.2, 1.0),
        ),
        name: 'a',
      )..setPosition(0.6, 0.2, 0.0),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.5)).build()),
        Material(
          lighting: LightingModel.unlit,
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          emissive: Vector3.all(12.0),
        ),
        name: 'lamp',
      )..setPosition(-0.55, 0.15, 0.4),
    );
  final camera =
      CameraNode(
          name: 'eye',
          projection: const PerspectiveProjection(fovYRadians: 0.9),
        )
        ..setPosition(2.2, 1.4, 3.4)
        ..lookAt(Vector3.zero());
  scene.add(camera);
  return (scene: scene, camera: camera);
}

({Renderer renderer, Scene scene, CameraNode camera}) _game() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final built = _scene(device);
  return (
    renderer: Renderer.create(device: device),
    scene: built.scene,
    camera: built.camera,
  );
}

/// The scene as one frame, opaque, with [settings] as they stand.
Future<Uint8List> _whole(RenderSettings settings) async {
  final game = _game();
  final result = game.renderer.render(
    width: _width,
    height: _height,
    scene: game.scene,
    views: <RenderView>[RenderView(camera: game.camera)],
    settings: settings,
  );
  final pixels = (await game.renderer.device.readPixels(
    result.frame,
  ))!.buffer.asUint8List();
  for (var i = 3; i < pixels.length; i += 4) {
    pixels[i] = 255;
  }
  return pixels;
}

/// The capture, stitched back into one buffer.
Future<({Uint8List pixels, PhotoCaptureReport report, CameraNode camera})>
_capture(
  RenderSettings settings, {
  PhotoFilter filter = PhotoFilter.none,
  int margin = 32,
}) async {
  final game = _game();
  final out = Uint8List(_width * _height * 4);
  final report = await capturePhoto(
    renderer: game.renderer,
    scene: game.scene,
    camera: game.camera,
    width: _width,
    height: _height,
    settings: settings,
    filter: filter,
    // Ragged on purpose: three columns of 200, 200 and 80, three rows of 152,
    // 152 and 56. Multiples of four, so the composite's 4x4 dither cell lines
    // up across tiles and is not a difference this file has to explain.
    tileWidth: 200,
    tileHeight: 152,
    margin: margin,
    onRows: (rgba, top, rows) =>
        out.setRange(top * _width * 4, (top + rows) * _width * 4, rgba),
  );
  return (pixels: out, report: report, camera: game.camera);
}

/// The worst difference in any channel, over the pixels within [band] of a
/// tile edge.
int _worstAtSeams(Uint8List a, Uint8List b, {int band = 3}) {
  bool nearEdge(int v, int tile, int size) {
    for (var edge = tile; edge < size; edge += tile) {
      if ((v - edge).abs() <= band) return true;
    }
    return false;
  }

  var worst = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (!nearEdge(x, 200, _width) && !nearEdge(y, 152, _height)) continue;
      for (var c = 0; c < 3; c++) {
        final i = (y * _width + x) * 4 + c;
        final d = (a[i] - b[i]).abs();
        if (d > worst) worst = d;
      }
    }
  }
  return worst;
}

const RenderSettings _noBloom = RenderSettings(
  bloom: BloomSettings(enabled: false),
);

void main() {
  test('a ragged grid of tiles stitches into the whole frame', () async {
    final capture = await _capture(_noBloom, margin: 0);
    final reference = await _whole(_noBloom);
    // Mutation: build the crop from the aspect the renderer hands
    // `CropProjection.toMatrix` — the tile's — instead of `frameAspect`. The
    // 200 x 152 tiles and the 80-pixel column each squash the cubes their own
    // way, and thousands of pixels move.
    //
    // Within one step, as `tiled_projection_stitch_test.dart` explains: a
    // crop folded into the matrix interpolates through different arithmetic.
    final difference = compareFrames(
      capture.pixels,
      reference,
      channel: 1,
      alpha: true,
    );
    expect(difference.differing, 0, reason: '$difference');
  });

  test('a margin round each tile takes the seams out of a bloom', () async {
    const bloom = RenderSettings(
      bloom: BloomSettings(enabled: true, intensity: 0.6),
    );
    final reference = await _whole(bloom);
    final bare = await _capture(bloom, margin: 0);
    final framed = await _capture(bloom, margin: 32);
    final bareSeam = _worstAtSeams(bare.pixels, reference);
    final framedSeam = _worstAtSeams(framed.pixels, reference);
    // Mutation: crop the tile without the margin (`from` at row `row`, column
    // 0). The glow is cut off at every tile edge it reaches, which is the
    // seam with no margin at all.
    expect(
      framedSeam,
      lessThan(bareSeam),
      reason: 'seams: $bareSeam without a margin, $framedSeam with one',
    );
    expect(framedSeam, lessThanOrEqualTo(6), reason: 'seam $framedSeam');
  });

  test(
    'the vignette darkens the picture\'s corners, not every tile\'s',
    () async {
      final look = const RenderSettings(
        bloom: BloomSettings(enabled: false),
      ).copyWith(look: const LookSettings(vignette: 0.6));
      final capture = await _capture(look, margin: 0);
      final reference = await _whole(look);
      // Mutation: leave `vignette` in the tiles' look in `photoSettings`. Every
      // tile darkens its own corners, and the picture has nine vignettes — the
      // centre of the frame, a tile corner, comes out darker than its edges.
      //
      // Within two steps: the reference darkens linear light before the
      // encode, the finish decodes a byte, darkens it and encodes again.
      final difference = compareFrames(
        capture.pixels,
        reference,
        channel: 2,
        alpha: true,
      );
      expect(difference.differing, 0, reason: '$difference');
    },
  );

  test('a capture says what it could not carry over, and puts the camera '
      'back', () async {
    final settings = const RenderSettings(
      bloom: BloomSettings(enabled: false),
      autoExposure: AutoExposureSettings(enabled: true),
      motionBlur: MotionBlurSettings(enabled: true),
    );
    final capture = await _capture(settings, filter: PhotoFilter.noir);
    // Mutation: drop the `finally` that restores the projection. The game's
    // next frame is drawn through the last tile's crop — the bottom-right
    // corner of the picture, magnified to fill the screen.
    expect(capture.camera.projection, isA<PerspectiveProjection>());
    expect(capture.report.tilesX, 3);
    expect(capture.report.tilesY, 3);
    expect(
      capture.report.setAside.join('\n'),
      allOf(contains('auto exposure is held'), contains('motion blur')),
    );
  });

  test('a filter composes onto the game\'s own look', () {
    const game = LookSettings(saturation: 0.8, temperature: -0.2);
    final graded = PhotoFilter.warm.applyTo(game);
    // Mutation: replace the game's look with the filter's. A night level
    // graded cold turns orange under "warm" rather than a little less cold.
    expect(graded.temperature, closeTo(0.15, 1e-12));
    expect(graded.saturation, closeTo(0.84, 1e-12));
    expect(PhotoFilter.named('noir'), same(PhotoFilter.noir));
    expect(PhotoFilter.named('gone in this build'), same(PhotoFilter.none));
  });

  group('PngStripWriter', () {
    Uint8List gradient(int width, int height) {
      final out = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          out
            ..[i] = x * 7 & 0xFF
            ..[i + 1] = y * 11 & 0xFF
            ..[i + 2] = (x ^ y) & 0xFF
            ..[i + 3] = 255 - x;
        }
      }
      return out;
    }

    test('three strips read back as one picture, checksum and all', () {
      const width = 37;
      const height = 23;
      final pixels = gradient(width, height);
      final file = BytesBuilder();
      final writer = PngStripWriter(
        width: width,
        height: height,
        sink: file.add,
      );
      for (final (top, rows) in const [(0, 10), (10, 1), (11, 12)]) {
        writer.addRows(Uint8List.sublistView(pixels, top * width * 4), rows);
      }
      writer.close();
      final bytes = file.toBytes();

      final decoded = decodePng(bytes)!;
      expect(decoded.width, width);
      expect(decoded.rgba, pixels);

      // The decoder above does not check the Adler-32; zlib does. Mutation:
      // fold the filter bytes out of the running checksum, and a picture
      // that decodes perfectly is refused by every browser.
      final idat = BytesBuilder();
      var at = 8;
      while (at < bytes.length) {
        final length = ByteData.sublistView(bytes, at).getUint32(0);
        final type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
        if (type == 'IDAT') idat.add(bytes.sublist(at + 8, at + 8 + length));
        at += 12 + length;
      }
      expect(ZLibDecoder().convert(idat.toBytes()), hasLength(height * 149));
    });

    test('a file closed short is refused rather than written damaged', () {
      final writer = PngStripWriter(width: 4, height: 4, sink: (_) {});
      writer.addRows(Uint8List(4 * 2 * 4), 2);
      // Mutation: let `close` write the end with rows missing. The file is a
      // valid-looking PNG that every reader rejects at the end of the data.
      expect(writer.close, throwsStateError);
      expect(() => writer.addRows(Uint8List(4 * 3 * 4), 3), throwsStateError);
    });
  });
}
