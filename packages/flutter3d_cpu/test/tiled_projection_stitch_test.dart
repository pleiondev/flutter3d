/// `TiledProjection`'s own acceptance — `pro-eng-04`: four tiles, rendered
/// one at a time and stitched, matching the one frame they are pieces of,
/// byte for byte.
///
///     flutter test test/tiled_projection_stitch_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _fullWidth = 480;
const int _fullHeight = 360;
const int _tiles = 2;
const int _tileWidth = _fullWidth ~/ _tiles;
const int _tileHeight = _fullHeight ~/ _tiles;

/// The scene every render in this file draws: two cubes, off the axes, lit
/// from one side — enough shape that a tile boundary landing in the wrong
/// place shows up as a seam rather than as a uniform background agreeing
/// with itself by coincidence.
({Scene scene, CameraNode camera}) _scene(GraphicsDevice device) {
  final scene = Scene();
  scene.add(
    LightNode(type: LightType.directional, name: 'key')
      ..intensity = 3.0
      ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
  );
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.4)).build()),
      Material(lighting: LightingModel.pbr, baseColor: Vector4(0.8, 0.3, 0.2, 1.0)),
      name: 'a',
    )..setPosition(0.6, 0.2, 0.0),
  );
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.9)).build()),
      Material(lighting: LightingModel.pbr, baseColor: Vector4(0.2, 0.4, 0.9, 1.0)),
      name: 'b',
    )..setPosition(-0.8, -0.3, 0.5),
  );
  final camera = CameraNode(
    name: 'eye',
    projection: const PerspectiveProjection(fovYRadians: 0.9),
  )..setPosition(2.2, 1.4, 3.4)
   ..lookAt(Vector3.zero());
  scene.add(camera);
  return (scene: scene, camera: camera);
}

Future<Uint8List> _render(
  GraphicsDevice device,
  Renderer renderer,
  CameraNode camera,
  Scene scene, {
  required int width,
  required int height,
}) async {
  final result = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    // Bloom is a screen-space blur with no idea a tile has an edge: the same
    // bright pixel blurs differently depending on how much of its own
    // neighbourhood the frame it is drawn into actually contains, which has
    // nothing to do with `TiledProjection` and would fail this test for a
    // reason this row was never about. Off, so what is compared is the
    // projection alone.
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// Copies the [tileWidth] × [tileHeight] block at ([tileX], [tileY]) of
/// [into] out of [tile], row by row — the reverse of what a real screenshot
/// tool does to a device's own tiles, and the only part of "stitched" this
/// file has to build by hand.
void _blit(
  Uint8List into,
  Uint8List tile, {
  required int tileX,
  required int tileY,
  required int tileWidth,
  required int tileHeight,
  required int fullWidth,
}) {
  for (var row = 0; row < tileHeight; row++) {
    final srcOffset = row * tileWidth * 4;
    final dstY = tileY * tileHeight + row;
    final dstOffset = (dstY * fullWidth + tileX * tileWidth) * 4;
    into.setRange(
      dstOffset,
      dstOffset + tileWidth * 4,
      tile,
      srcOffset,
    );
  }
}

void main() {
  test('a 2x2 grid of tiles stitches into the whole frame, byte for byte', () async {
    final wholeDevice = CpuDevice(
      width: _fullWidth,
      height: _fullHeight,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final wholeRenderer = Renderer.create(device: wholeDevice);
    final whole = _scene(wholeDevice);
    final reference = await _render(
      wholeDevice,
      wholeRenderer,
      whole.camera,
      whole.scene,
      width: _fullWidth,
      height: _fullHeight,
    );

    final stitched = Uint8List(_fullWidth * _fullHeight * 4);
    for (var tileY = 0; tileY < _tiles; tileY++) {
      for (var tileX = 0; tileX < _tiles; tileX++) {
        final tileDevice = CpuDevice(
          width: _tileWidth,
          height: _tileHeight,
          shaders: CpuShaderLibrary(builtinCpuShaders()),
        );
        final tileRenderer = Renderer.create(device: tileDevice);
        final tileScene = _scene(tileDevice);
        // `_scene` already put this camera at the same eye and look-at as
        // the reference's; only the projection changes here, to the one
        // tile of it this iteration is answering for.
        tileScene.camera.projection = TiledProjection(
          whole.camera.projection,
          tileX: tileX,
          tileY: tileY,
          tilesX: _tiles,
          tilesY: _tiles,
        );

        final tile = await _render(
          tileDevice,
          tileRenderer,
          tileScene.camera,
          tileScene.scene,
          width: _tileWidth,
          height: _tileHeight,
        );
        _blit(
          stitched,
          tile,
          tileX: tileX,
          tileY: tileY,
          tileWidth: _tileWidth,
          tileHeight: _tileHeight,
          fullWidth: _fullWidth,
        );
      }
    }

    // Both cubes are on screen and off-axis, so a seam at the tile boundary
    // — a projection built from the tile's own aspect instead of the whole
    // frame's, or an off-by-one in the crop's own offset — moves real
    // geometry across it rather than leaving a background pixel unchanged.
    expect(stitched, orderedEquals(reference));
  });
}
