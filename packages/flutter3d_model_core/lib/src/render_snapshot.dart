/// `pro-rn-02`'s own row: a snapshot of a [ModelProject], drawn by the same
/// renderer the live viewport uses, tile by tile, with a 2×2 supersample when
/// asked for, on devices the caller supplies.
///
/// **The device is asked for, not built.** This package names no backend —
/// the same rule `renderProject` beside it keeps — so a caller hands over a
/// [TileDevice]: `flutter3d_cpu`'s `CpuDevice` for a snapshot that never
/// contends with the viewport for a GPU, or whatever device a test wants to
/// count. It used to be a package of its own that defaulted to `CpuDevice`,
/// and that default was its only reason to exist.
///
/// **The isolate question, decided the way `editInIsolate` already decided
/// it.** `flutter3d_mesh`'s own `meshWorkStaysHere` answers "is this a build
/// with no isolates in it" once, from `dart.library.js_interop`; reusing it
/// here is what stops a second copy of the same environment check from
/// drifting the day one of them is edited and the other is not. Native: the
/// whole tile grid renders inside one `Isolate.run`, a value in and a value
/// out — which is also why [RenderSnapshotJob.run] does not report progress
/// mid-flight on native, the same way `JobRequest.run` does not either. Web:
/// `Isolate.run` is a stub, so [RenderSnapshotJob.run] instead steps the grid
/// one tile at a time with a yield between them and calls `onProgress` after
/// each.
///
/// **Chunked the same shape `apps/flutter3d_modeler/lib/src/job_runner.dart`'s
/// own `Job<T>` already is, without importing it.** This package may not
/// depend on the application that class lives in, so it exposes the three
/// pieces that class asks any job for — [RenderSnapshotJob.chunkCount],
/// [RenderSnapshotJob.renderTile] and [RenderSnapshotJob.finish] — and a caller
/// with `Job<T>` in scope builds one from them and gets its progress and
/// cancellation for free.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show meshWorkStaysHere;
import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'scene_from_project.dart';

/// Makes the device one tile of a snapshot is drawn on, [width] × [height].
///
/// **A top-level or static function**, because on native the whole grid
/// renders inside `Isolate.run` and this travels there with the project: a
/// tear-off of a top-level function crosses an isolate, a closure over a
/// window's own device does not.
typedef TileDevice = GraphicsDevice Function(int width, int height);

/// Where a snapshot's camera stands and what it looks at.
///
/// `ModelProject` carries no camera of its own — a live viewport's
/// `CameraNode` is the application's, not the document's — so a snapshot
/// states one rather than inventing a default a caller would have to know to
/// override. A value rather than a live [CameraNode], because each tile builds
/// its own node on its own device, and a node built on one device cannot draw
/// on another.
final class SnapshotCamera {
  const SnapshotCamera({
    required this.position,
    required this.target,
    this.up,
    this.projection = const PerspectiveProjection(),
  });

  /// Eye position, in world space.
  final Vector3 position;

  /// What the camera looks at — with [position], the look-at pair
  /// `CameraNode.lookAt` takes.
  final Vector3 target;

  /// World up, or null for `CameraNode.lookAt`'s own default.
  final Vector3? up;

  /// Perspective by default; an orthographic turntable render asks for
  /// [OrthographicProjection] just as validly.
  final Projection projection;
}

/// What a [RenderSnapshotJob] is asked for.
///
/// **Not `RenderSettings` alone.** A live viewport already has a resolution —
/// its window's — and never asks for more samples than one screen pixel. A
/// snapshot has neither: its resolution is whatever the export dialog says,
/// and supersampling is the one knob screen 12 used to call "samples" before
/// the 2026-09-09 decision named it for what it is.
final class RenderPreset {
  const RenderPreset({
    required this.width,
    required this.height,
    required this.camera,
    this.ssaa = 1,
    this.settings = const RenderSettings(),
    this.tilesX = 1,
    this.tilesY = 1,
    this.clearColor,
  }) : assert(width > 0 && height > 0, 'width and height must be positive'),
       assert(
         ssaa == 1 || ssaa == 2,
         'ssaa must be 1 or 2 — this row asks for exactly those two, and a '
         'tracer that would want more sits outside the plan (decision '
         '2026-09-09)',
       ),
       assert(tilesX > 0 && tilesY > 0, 'a grid needs at least one tile'),
       assert(
         width % tilesX == 0,
         'width must divide evenly by tilesX, or a tile would not be a '
         'whole number of pixels wide',
       ),
       assert(
         height % tilesY == 0,
         'height must divide evenly by tilesY, or a tile would not be a '
         'whole number of pixels tall',
       );

  /// The snapshot's own width, after any supersampling has been resolved back
  /// down — the size the returned PNG is encoded at.
  final int width;

  final int height;

  final SnapshotCamera camera;

  /// 1 for no supersampling, 2 for a linear 2×2 supersample resolved back down
  /// to [width] × [height].
  final int ssaa;

  /// Everything a frame already takes a setting for — bloom, shadows, ambient
  /// occlusion, reflections. Reused as-is: a snapshot is still one frame.
  final RenderSettings settings;

  /// The grid a large snapshot renders as, one tile at a time — `pro-eng-04`'s
  /// own [TiledProjection], stitched afterwards. `(1, 1)` is one tile the size
  /// of the whole frame, the same code path with nothing to stitch.
  final int tilesX;
  final int tilesY;

  final Vector4? clearColor;
}

/// A snapshot of [project] at [preset], each tile rendered on a device of its
/// own from [tileDevice].
final class RenderSnapshotJob {
  RenderSnapshotJob(this.project, this.preset, {required this.tileDevice});

  final ModelProject project;
  final RenderPreset preset;

  /// Where each tile is drawn. See [TileDevice] for why it is a function.
  final TileDevice tileDevice;

  /// One chunk per tile of [RenderPreset.tilesX] × [RenderPreset.tilesY] — the
  /// grid a caller stepping through chunks on the web draws one tile per frame
  /// of.
  int get chunkCount => preset.tilesX * preset.tilesY;

  /// Renders every tile and returns the encoded PNG.
  ///
  /// [onProgress], when given, is told how far through [chunkCount] this is —
  /// on the web after every tile, on native once, when the whole grid finishes
  /// inside its own isolate.
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
      // Yields the event loop between tiles — the whole reason a web build
      // chunks a job at all is so a frame can land between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    return buffer.finish();
  }

  _SnapshotBuffer? _buffer;

  /// Chunk [index]'s own share of the work, for a caller driving this job
  /// through its own runner rather than through [run].
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
/// only [project], [preset] and [tileDevice].
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
  /// supersampled frame — the same eye and look-at as every other tile, with
  /// [TiledProjection] cropping this one's share of the frustum, the shape
  /// `packages/flutter3d/test/tiled_projection_stitch_test.dart` proves
  /// stitches back byte for byte.
  Future<void> renderTile(
    ModelProject project,
    RenderPreset preset,
    int index,
  ) async {
    final tileX = index % preset.tilesX;
    final tileY = index ~/ preset.tilesX;

    final device = tileDevice(tileWidth, tileHeight);
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: _texel(device, const <int>[255, 255, 255, 255]),
      fallbackNormal: _texel(device, const <int>[128, 128, 255, 255]),
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

  /// The supersampled frame, downsampled (if [RenderPreset.ssaa] asks for it)
  /// and encoded with `flutter3d_formats`' `encodeCompressedPng`.
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

/// A plain box filter, [factor] × [factor] source pixels averaged per channel
/// into one destination pixel — the resolve half of "SSAA ×2" that
/// `pro-rn-01`'s benchmark named as missing when it rendered into a target
/// twice 4K's linear size as a proxy for the cost.
///
/// Averaged in the frame's own encoded space rather than in linear light: a
/// gamma-correct resolve would look measurably better on a high-contrast edge,
/// and the row asks only that ×2 differ from ×1 by under 1 % of pixels, which a
/// plain average already clears.
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
          final i = (srcY * srcWidth + dx * factor + sx) * 4;
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
