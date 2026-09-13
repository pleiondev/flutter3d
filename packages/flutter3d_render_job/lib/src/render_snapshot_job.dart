/// `pro-rn-02`'s own row: a snapshot of a [ModelProject], drawn by the same
/// renderer the live viewport uses, off the main viewport's own device so a
/// snapshot never contends with it and never depends on one existing.
///
/// **The isolate question, decided the way `editInIsolate` already decided
/// it.** `flutter3d_mesh`'s own `meshWorkStaysHere` answers "is this a build
/// with no isolates in it" once, from `dart.library.js_interop`; reusing it
/// here is what stops a second copy of the same environment check from
/// drifting the day one of them is edited and the other is not. Native:
/// the whole tile grid renders inside one `Isolate.run`, a value in and a
/// value out, the same shape `editInIsolate` already uses for a mesh — which
/// is also why [RenderSnapshotJob.run] does not report progress mid-flight
/// on native, the same way `JobRequest.run` does not either. Web:
/// `Isolate.run` is a stub, so [RenderSnapshotJob.run] instead steps the
/// grid one tile at a time with a yield between them — "тайл за кадр на
/// вебе" — and calls `onProgress` after each.
///
/// **Chunked the same shape `apps/flutter3d_modeler/lib/src/job_runner.dart`'s
/// own `Job<T>` already is, without importing it.** A package under
/// `flutter3d_model_core` may not depend on the application that class lives
/// in (`no package depends on an application`), so this cannot construct a
/// `Job<T>` itself. What it can do, and does, is expose the same three
/// pieces that class already asks any job for — [RenderSnapshotJob.chunkCount],
/// a `Future<void> Function(int)` in [RenderSnapshotJob.renderTile], and a
/// zero-argument `combine` in [RenderSnapshotJob.finish] — so a caller that
/// already has `Job<T>` in scope (the application does) can build a
/// `Job<Uint8List>` from `job.chunkCount` and `job.renderTile` and get that
/// class's own progress and cancellation for free, rather than this one
/// reimplementing either.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart'
    show CpuDevice, CpuShaderLibrary, builtinCpuShaders;
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show meshWorkStaysHere;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

import 'render_preset.dart';
import 'scene_from_project.dart';

/// Makes the device one tile of a snapshot is drawn on, [width] × [height].
///
/// **A function, and a top-level or static one**, because on native the whole
/// grid renders inside `Isolate.run` and this travels there with the project:
/// a tear-off of a top-level function crosses an isolate, a closure over a
/// window's own device does not.
typedef TileDevice = GraphicsDevice Function(int width, int height);

/// A fresh [CpuDevice] per tile — the default, and the reason a snapshot
/// never contends with the viewport for a GPU or needs a display at all.
GraphicsDevice cpuTileDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// A snapshot of [project] at [preset], each tile rendered on a device of its
/// own from [tileDevice].
///
/// **The renderer is asked for a [GraphicsDevice], not a CPU one.** A tile is
/// drawn, read back through [GraphicsDevice.readPixels] and stitched, and none
/// of that names a backend; [cpuTileDevice] is the default because it needs no
/// GPU, and a caller with a device it would rather render on — or a test with
/// a counting fake — passes its own.
final class RenderSnapshotJob {
  RenderSnapshotJob(this.project, this.preset, {this.tileDevice = cpuTileDevice});

  final ModelProject project;
  final RenderPreset preset;

  /// Where each tile is drawn. See [TileDevice] for why it is a function.
  final TileDevice tileDevice;

  /// One chunk per tile of [RenderPreset.tilesX] × [RenderPreset.tilesY] —
  /// the grid a caller stepping through chunks on the web draws exactly one
  /// tile per frame of.
  int get chunkCount => preset.tilesX * preset.tilesY;

  /// Renders every tile and returns the encoded PNG.
  ///
  /// [onProgress], when given, is told how far through [chunkCount] this is
  /// — on the web, after every tile; on native, once, when the whole grid
  /// finishes inside its own isolate, for the reason this library's own doc
  /// comment gives.
  Future<Uint8List> run({void Function(double progress)? onProgress}) async {
    if (!meshWorkStaysHere) {
      final TileDevice device = tileDevice;
      final bytes = await Isolate.run(
        () => _renderAllTiles(project, preset, device),
      );
      onProgress?.call(1.0);
      return bytes;
    }

    final buffer = _buffer ??= _SnapshotBuffer(preset, tileDevice);
    for (var index = 0; index < chunkCount; index++) {
      await buffer.renderTile(project, preset, index);
      onProgress?.call((index + 1) / chunkCount);
      // Yields the event loop between tiles rather than finishing the whole
      // grid in one uninterrupted stretch — the whole reason a web build
      // chunks a job at all is so a frame can land between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    return buffer.finish();
  }

  _SnapshotBuffer? _buffer;

  /// Chunk [index]'s own share of the work, for a caller driving this job
  /// through its own runner (`apps/flutter3d_modeler/lib/src/job_runner.dart`'s
  /// `Job<T>`) rather than through [run] — see this library's own doc
  /// comment for the shape that mirrors.
  Future<void> renderTile(int index) async {
    final buffer = _buffer ??= _SnapshotBuffer(preset, tileDevice);
    await buffer.renderTile(project, preset, index);
  }

  /// The PNG [renderTile] built, once every chunk up to [chunkCount] has run.
  Uint8List finish() {
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError(
        'finish() was called before any tile was rendered — call renderTile '
        'for every index up to chunkCount first, the same way a Job<T> only '
        'calls its own combine after every chunk has run.',
      );
    }
    return buffer.finish();
  }
}

/// The whole grid, off this isolate — [Isolate.run]'s own computation on
/// native. Top-level so the closure [RenderSnapshotJob.run] builds carries
/// only [project], [preset] and [tileDevice], the same reason
/// `editInIsolate`'s own `_apply` is top-level.
Future<Uint8List> _renderAllTiles(
  ModelProject project,
  RenderPreset preset,
  TileDevice tileDevice,
) async {
  final buffer = _SnapshotBuffer(preset, tileDevice);
  for (var index = 0; index < preset.tilesX * preset.tilesY; index++) {
    await buffer.renderTile(project, preset, index);
  }
  return buffer.finish();
}

/// The supersampled frame, filled in one tile at a time and resolved once
/// every tile has landed.
final class _SnapshotBuffer {
  _SnapshotBuffer(this.preset, this.tileDevice)
    : superWidth = preset.width * preset.ssaa,
      superHeight = preset.height * preset.ssaa,
      tileWidth = (preset.width * preset.ssaa) ~/ preset.tilesX,
      tileHeight = (preset.height * preset.ssaa) ~/ preset.tilesY,
      _pixels = Uint8List(
        preset.width * preset.ssaa * preset.height * preset.ssaa * 4,
      );

  final RenderPreset preset;
  final TileDevice tileDevice;
  final int superWidth;
  final int superHeight;
  final int tileWidth;
  final int tileHeight;
  final Uint8List _pixels;

  /// Renders tile [index] on its own fresh device and blits it into the
  /// supersampled frame — the same eye and look-at as every other tile,
  /// [TiledProjection] cropping this one's own share of the frustum
  /// (`pro-eng-04`), the same shape
  /// `packages/flutter3d_cpu/test/tiled_projection_stitch_test.dart` already
  /// proves stitches back byte for byte.
  Future<void> renderTile(
    ModelProject project,
    RenderPreset preset,
    int index,
  ) async {
    final tileX = index % preset.tilesX;
    final tileY = index ~/ preset.tilesX;

    final device = tileDevice(tileWidth, tileHeight);
    final albedo = _texel(device, const <int>[255, 255, 255, 255]);
    final normal = _texel(device, const <int>[128, 128, 255, 255]);
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: albedo,
      fallbackNormal: normal,
    );

    final scene = sceneFromProject(project, device);
    final wholeFrame = preset.camera.projection;
    final camera =
        CameraNode(
          name: 'snapshot',
          projection: (preset.tilesX == 1 && preset.tilesY == 1)
              ? wholeFrame
              : TiledProjection(
                  wholeFrame,
                  tileX: tileX,
                  tileY: tileY,
                  tilesX: preset.tilesX,
                  tilesY: preset.tilesY,
                ),
        )..setPosition(
          preset.camera.position.x,
          preset.camera.position.y,
          preset.camera.position.z,
        );
    camera.lookAt(preset.camera.target, up: preset.camera.up);
    scene.add(camera);

    final result = renderer.render(
      width: tileWidth,
      height: tileHeight,
      scene: scene,
      views: <RenderView>[
        RenderView(
          camera: camera,
          clearColor: preset.clearColor ?? Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      ],
      settings: preset.settings,
    );

    final tile = await device.readPixels(result.frame);
    if (tile == null) {
      throw StateError(
        'tile $tileX,$tileY could not be read back from the device it was '
        'drawn on',
      );
    }
    _blit(tile.buffer.asUint8List(), tileX: tileX, tileY: tileY);
  }

  void _blit(Uint8List tile, {required int tileX, required int tileY}) {
    for (var row = 0; row < tileHeight; row++) {
      final srcOffset = row * tileWidth * 4;
      final dstY = tileY * tileHeight + row;
      final dstOffset = (dstY * superWidth + tileX * tileWidth) * 4;
      _pixels.setRange(dstOffset, dstOffset + tileWidth * 4, tile, srcOffset);
    }
  }

  /// The supersampled frame, downsampled (if [RenderPreset.ssaa] asks for
  /// it) and encoded — `flutter3d_formats`' `encodeCompressedPng`, the real
  /// compressor rather than the stored-block encoder golden tests use.
  Uint8List finish() {
    final resolved = preset.ssaa == 1
        ? _pixels
        : _downsample(_pixels, superWidth, superHeight, preset.ssaa);
    return encodeCompressedPng(preset.width, preset.height, resolved);
  }
}

TextureHandle _texel(GraphicsDevice device, List<int> rgba) =>
    device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
    )!;

/// A plain box filter, [factor] × [factor] source pixels averaged per
/// channel into one destination pixel — the downsampling half of "SSAA
/// ×2" that `pro-rn-01`'s own benchmark named as missing: that row
/// rendered straight into a target twice 4K's own linear size and called it
/// an honest proxy for supersampling's *cost*, because this engine had
/// "no dedicated supersampling flag" at the time it was measured. This is
/// that flag's other half — the resolve a real supersample needs and a
/// bigger render target alone does not give it.
///
/// Averaged in the frame's own encoded space rather than in linear light.
/// A gamma-correct resolve would look measurably better on a high-contrast
/// edge; what this row asks for is "SSAA ×2 differs by under 1% of pixels"
/// from the unsupersampled render, which a simple average already clears
/// with room to spare (see the acceptance test's own measured percentage),
/// and reaching for linear-light averaging before a golden asks for it
/// would be solving a problem this row does not have yet.
Uint8List _downsample(Uint8List src, int srcWidth, int srcHeight, int factor) {
  final dstWidth = srcWidth ~/ factor;
  final dstHeight = srcHeight ~/ factor;
  final out = Uint8List(dstWidth * dstHeight * 4);
  final samples = factor * factor;
  for (var dy = 0; dy < dstHeight; dy++) {
    for (var dx = 0; dx < dstWidth; dx++) {
      var r = 0, g = 0, b = 0, a = 0;
      for (var sy = 0; sy < factor; sy++) {
        final srcY = dy * factor + sy;
        for (var sx = 0; sx < factor; sx++) {
          final srcX = dx * factor + sx;
          final i = (srcY * srcWidth + srcX) * 4;
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          a += src[i + 3];
        }
      }
      final o = (dy * dstWidth + dx) * 4;
      out[o] = (r / samples).round();
      out[o + 1] = (g / samples).round();
      out[o + 2] = (b / samples).round();
      out[o + 3] = (a / samples).round();
    }
  }
  return out;
}
