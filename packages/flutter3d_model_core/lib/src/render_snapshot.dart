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

import 'dart:async';
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
  RenderSnapshotJob(
    this.project,
    this.preset, {
    required this.tileDevice,
    this.concurrency = 1,
  }) : assert(concurrency >= 1, 'a grid is drawn by at least one worker');

  final ModelProject project;
  final RenderPreset preset;

  /// Where each tile is drawn. See [TileDevice] for why it is a function.
  final TileDevice tileDevice;

  /// How many tiles are drawn at once, each in an isolate of its own.
  ///
  /// **One by default, which is what this did before and is not a placeholder
  /// for a better default.** The number that belongs here is the machine's
  /// core count, and this package cannot ask: it is a flat Dart package, so
  /// `dart:io`'s `Platform.numberOfProcessors` would take the web build with
  /// it. The application knows, and passes it.
  ///
  /// Above one, each tile crosses into `Isolate.run` with the project, the
  /// preset, its index and the [TileDevice] tear-off, and its pixels come back
  /// through a `TransferableTypedData` — which moves the buffer rather than
  /// copying it, the reason `editInIsolate` uses one for a mesh.
  ///
  /// **It changes no pixel.** Tiles already render independently — each builds
  /// its own device, its own scene and its own camera, and writes only its own
  /// share of the frame — so which thread draws one cannot be visible in the
  /// result. `a 2x2 tile grid stitches to the same frame as one tile` held
  /// that before any of this, and holds it still.
  ///
  /// Ignored on the web, where there are no isolates and the grid is stepped
  /// one tile at a time with a yield between them.
  final int concurrency;

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
    if (!meshWorkStaysHere && concurrency > 1) {
      final bytes = await _renderTilesInParallel(
        project,
        preset,
        tileDevice,
        concurrency,
        onProgress,
      );
      return bytes;
    }

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

/// The grid, [concurrency] tiles at a time, each in an isolate of its own.
///
/// **A bounded pool rather than one isolate per tile.** A 4x4 grid is sixteen
/// tiles and a machine has eight cores; spawning sixteen isolates would pay
/// sixteen times for building a shader library and a scene, to run eight at a
/// time anyway. The pool keeps at most [concurrency] in flight and starts the
/// next as one lands.
///
/// **The pixels come back through a `TransferableTypedData`.** That is the
/// one direction it fits: `materialize()` may be called once and the buffer
/// moves rather than copying, which is exactly a tile handing its frame back.
/// It does not fit the other direction — the project goes *to* each worker as
/// an ordinary copy, because a transferable is single-use and could not be
/// sent to a second worker at all. The project is a document and small; the
/// pixels are the large thing, and they are the ones that move.
Future<Uint8List> _renderTilesInParallel(
  ModelProject project,
  RenderPreset preset,
  TileDevice tileDevice,
  int concurrency,
  void Function(double progress)? onProgress,
) async {
  final buffer = _SnapshotBuffer(preset, tileDevice);
  final count = preset.tilesX * preset.tilesY;
  final workers = concurrency < count ? concurrency : count;

  final pool = await _TileWorkerPool.start(
    workers,
    project: project,
    preset: preset,
    tileDevice: tileDevice,
    tileWidth: buffer.tileWidth,
    tileHeight: buffer.tileHeight,
  );

  try {
    var next = 0;
    var landed = 0;

    Future<void> drive(_TileWorker worker) async {
      while (true) {
        // Read and advance in one turn: this is an event loop rather than
        // threads, so nothing runs between these two lines and no two workers
        // can take the same tile.
        final index = next;
        if (index >= count) return;
        next = index + 1;

        final tile = await worker.draw(index);
        buffer.blitTile(
          tile,
          tileX: index % preset.tilesX,
          tileY: index ~/ preset.tilesX,
        );
        landed++;
        onProgress?.call(landed / count);
      }
    }

    await Future.wait(pool.workers.map(drive));
  } finally {
    // Even if a tile threw: an isolate nobody shut down keeps the process
    // alive, which in a test runner reads as a suite that will not finish.
    pool.close();
  }
  return buffer.finish();
}

/// Workers that outlive the tile they are drawing.
///
/// **The measurement that asked for this.** With an `Isolate.run` per tile, a
/// 4x4 grid at 1024x1024 went from 3283 ms on one worker to 993 on eight —
/// 3.3x on an 11-core machine, where the two frame sizes measured said the
/// rest was fixed cost per tile rather than contention. Each `Isolate.run`
/// spawns an isolate, copies the project into it, and builds a shader library
/// before drawing a pixel; sixteen tiles paid that sixteen times.
///
/// A worker pays it once. The project and the preset cross at startup and
/// stay; per tile only an index goes over, and pixels come back.
final class _TileWorkerPool {
  _TileWorkerPool(this.workers);

  final List<_TileWorker> workers;

  static Future<_TileWorkerPool> start(
    int count, {
    required ModelProject project,
    required RenderPreset preset,
    required TileDevice tileDevice,
    required int tileWidth,
    required int tileHeight,
  }) async {
    final started = await Future.wait(<Future<_TileWorker>>[
      for (var i = 0; i < count; i++)
        _TileWorker.start(
          project: project,
          preset: preset,
          tileDevice: tileDevice,
          tileWidth: tileWidth,
          tileHeight: tileHeight,
        ),
    ]);
    return _TileWorkerPool(started);
  }

  void close() {
    for (final worker in workers) {
      worker.close();
    }
  }
}

/// One isolate, kept alive across tiles.
///
/// **One reply outstanding at a time, so the bookkeeping is one field.** A
/// worker draws the tile it was given and is handed the next only once that
/// one has landed — the pool's loop is what serialises it — so there is never
/// a second reply in flight to tell apart from the first. A queue here would
/// be machinery for a case the caller cannot produce.
final class _TileWorker {
  _TileWorker(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  Completer<Object?>? _pending;

  static Future<_TileWorker> start({
    required ModelProject project,
    required RenderPreset preset,
    required TileDevice tileDevice,
    required int tileWidth,
    required int tileHeight,
  }) async {
    final fromWorker = ReceivePort();
    final ready = Completer<SendPort>();
    late final _TileWorker worker;

    fromWorker.listen((Object? message) {
      if (!ready.isCompleted) {
        // The worker's first message is the port to send tile indices to. It
        // arrives once the project and the preset are in place there, so a
        // caller holding a worker has one that is ready to draw.
        ready.complete(message! as SendPort);
        return;
      }
      final pending = worker._pending;
      worker._pending = null;
      pending?.complete(message);
    });

    final isolate = await Isolate.spawn(
      _tileWorkerMain,
      _TileWorkerSetup(
        reply: fromWorker.sendPort,
        project: project,
        preset: preset,
        tileDevice: tileDevice,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
      ),
    );
    worker = _TileWorker(isolate, await ready.future, fromWorker);
    return worker;
  }

  /// Draws tile [index] and brings its pixels back.
  Future<Uint8List> draw(int index) async {
    final pending = _pending = Completer<Object?>();
    _toWorker.send(index);
    final reply = await pending.future;
    if (reply is _TileFailure) {
      throw StateError(
        'a tile worker could not draw tile $index: ${reply.message}',
      );
    }
    return (reply! as TransferableTypedData).materialize().asUint8List();
  }

  void close() {
    // A negative index is the stop word rather than a message type of its
    // own: every other message is a tile index, and one sentinel is cheaper
    // to keep right than a second shape crossing the boundary.
    _toWorker.send(-1);
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// What a worker is handed when it starts.
final class _TileWorkerSetup {
  const _TileWorkerSetup({
    required this.reply,
    required this.project,
    required this.preset,
    required this.tileDevice,
    required this.tileWidth,
    required this.tileHeight,
  });

  final SendPort reply;
  final ModelProject project;
  final RenderPreset preset;
  final TileDevice tileDevice;
  final int tileWidth;
  final int tileHeight;
}

/// A tile that threw, carried back rather than left to hang the pool.
final class _TileFailure {
  const _TileFailure(this.message);
  final String message;
}

/// The worker's own loop: take an index, give back pixels.
///
/// Top-level, because that is what `Isolate.spawn` takes — and everything it
/// needs arrives in [_TileWorkerSetup] rather than being captured, for the
/// same reason `drawTile` takes plain values.
Future<void> _tileWorkerMain(_TileWorkerSetup setup) async {
  final jobs = ReceivePort();
  setup.reply.send(jobs.sendPort);

  // Built once and drawn on for every tile this worker is given. A device
  // carries a shader library, and building one per tile was the cost two
  // measurements kept pointing at: a finer grid balanced the work better and
  // still ran slower, because it paid this more times. Measured at 1024x1024
  // on eight workers, within one run: 4x4 went from 2.06x to 2.87x and 8x8
  // from 2.95x to 3.69x.
  //
  // **What this trades, said rather than discovered later.** `sceneFromProject`
  // uploads the project's meshes to whatever device it is handed, and nothing
  // releases them between tiles — so a worker's device holds one upload per
  // tile it has drawn, rather than one. For a snapshot that is a bounded
  // number of tiles of one project it is a fair trade; for a grid fine enough
  // or a project large enough that the uploads matter, the fix is a scene
  // built once per worker rather than once per tile, which is a bigger change
  // than this one and wants its own measurement.
  final device = setup.tileDevice(setup.tileWidth, setup.tileHeight);

  await for (final Object? message in jobs) {
    final index = message! as int;
    if (index < 0) break;
    try {
      final tile = await drawTile(
        setup.project,
        setup.preset,
        index,
        setup.tileDevice,
        tileWidth: setup.tileWidth,
        tileHeight: setup.tileHeight,
        on: device,
      );
      setup.reply.send(TransferableTypedData.fromList(<Uint8List>[tile]));
    } catch (error) {
      // Answered rather than thrown: an isolate that dies mid-tile leaves the
      // pool waiting on a reply that will never come, and the frame hangs
      // instead of failing.
      setup.reply.send(_TileFailure('$error'));
    }
  }
  jobs.close();
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

  /// Renders tile [index] and blits it into the supersampled frame.
  ///
  /// The drawing itself is [drawTile], a top-level function: a tile is one
  /// picture computed from plain values, so it can be computed anywhere — on
  /// this thread, or in an isolate of its own. This method is the half that
  /// owns the shared buffer, and it is the half that cannot cross.
  Future<void> renderTile(
    ModelProject project,
    RenderPreset preset,
    int index,
  ) async {
    _blit(
      await drawTile(
        project,
        preset,
        index,
        tileDevice,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
      ),
      tileX: index % preset.tilesX,
      tileY: index ~/ preset.tilesX,
    );
  }

  /// Writes one tile's pixels into its own share of the frame.
  ///
  /// Public to this library because a tile drawn in an isolate comes back as
  /// bytes with nowhere to put itself — the pool hands them here. Safe to call
  /// from several futures in turn for the same reason the grid is tiled at
  /// all: a tile's rows are its own, so no two calls touch the same byte.
  void blitTile(Uint8List tile, {required int tileX, required int tileY}) =>
      _blit(tile, tileX: tileX, tileY: tileY);

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

/// One tile of a snapshot, drawn on a device of its own, as raw RGBA bytes.
///
/// **Top-level and taking only plain values, so a tile can be drawn anywhere.**
/// Everything it needs — the project, the preset, which tile, and a tear-off
/// that makes a device — crosses an isolate; a method on a buffer holding the
/// whole frame does not. That is the split: this computes a picture, and
/// `_SnapshotBuffer` owns the one place every picture is written to.
///
/// The same eye and look-at as every other tile, with [TiledProjection]
/// cropping this one's share of the frustum — the shape
/// `packages/flutter3d/test/tiled_projection_stitch_test.dart` proves stitches
/// back byte for byte.
Future<Uint8List> drawTile(
  ModelProject project,
  RenderPreset preset,
  int index,
  TileDevice tileDevice, {
  required int tileWidth,
  required int tileHeight,
  GraphicsDevice? on,
}) async {
  final tileX = index % preset.tilesX;
  final tileY = index ~/ preset.tilesX;

  // **[on] is a device to draw on rather than one to make**, which is what
  // lets a worker pay for a shader library once instead of once per tile.
  // Every tile is the same size and the frame is cleared before each, so the
  // second tile on a device sees nothing the first left — the test that the
  // grid matches a single tile byte for byte is what holds that, and it holds
  // it whichever way the device arrived.
  final device = on ?? tileDevice(tileWidth, tileHeight);
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
  return tile.buffer.asUint8List();
}
