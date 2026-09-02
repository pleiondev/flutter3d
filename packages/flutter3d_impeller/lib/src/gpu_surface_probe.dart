/// `GpuImageSurface` against `Texture.asImage()`, measured on a live GPU with
/// Flutter compositing both.
///
/// **A measurement, not a feature.** flutter_gpu 3.47 added a presentable
/// surface — `createImageSurface`, `acquireNextFrame`, `present`,
/// `currentImage` — whose stated purpose is the problem this backend already
/// solves by hand: a finished frame is a texture Flutter is still reading, and
/// drawing into it again before the compositor has let go is a picture made
/// of two frames. The renderer keeps a ring of finished frames and returns one
/// to rotation when `GraphicsDevice.onFrameComplete` says the GPU is done
/// with it; the surface keeps its own pool and decides reuse from Flutter's
/// own reference count. Same job, two owners.
///
/// Whether the second owner is worth a change to the backend contract is a
/// question with numbers in it, and this file asks them. It puts the same
/// clear-only pass through each path for a run of frames, with Flutter drawing
/// the result every frame so the compositor's references are real ones, and
/// reports what each costs on the UI thread, how many textures each ends up
/// holding, and whether the picture read back is the one that was drawn. The
/// surface's own questions get a phase each: whether `present` can go through
/// a trailing empty command buffer (the shape a one-pass-per-buffer backend
/// would need), and what `resize` does to the pool and to `GpuPresentStatus`.
///
/// Written against flutter_gpu directly rather than through the HAL, on
/// purpose: the question is what the API gives, and a handle wrapping it
/// would put this backend's own bookkeeping on both sides of the comparison.
/// Nothing here constructs a `TextureHandle`, and nothing in the engine calls
/// this; `packages/flutter3d/example/lib/surface_probe_main.dart` runs it and
/// `tool/surface_probe.sh` reads what it prints. The verdict, with the numbers,
/// is in `ARCHITECTURE.md` §15.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'gpu_formats.dart';
import 'gpu_surface_probe_report.dart';
import 'gpu_texture.dart';

/// Runs the probe as soon as it is on screen, showing each frame it presents,
/// and hands the finished [SurfaceProbeReport] to [onDone].
///
/// Shown rather than run headless because half of what is being measured is
/// Flutter's hold on the image: a `ui.Image` nobody draws is one the surface
/// can reuse at once, and the pool it would report is not the pool a real
/// frame sees.
final class ImageSurfaceProbe extends StatefulWidget {
  const ImageSurfaceProbe({
    super.key,
    required this.onDone,
    this.frames = 240,
    this.width = 1280,
    this.height = 800,
  });

  final void Function(SurfaceProbeReport report) onDone;

  /// Frames per path. Four seconds at sixty hertz — long enough for a pool to
  /// settle at the size the display actually needs.
  final int frames;

  /// The frame size, in pixels. A window's worth rather than a golden's, so a
  /// texture costs what one costs.
  final int width;
  final int height;

  @override
  State<ImageSurfaceProbe> createState() => _ImageSurfaceProbeState();
}

/// How many frames the resize phase draws before and after resizing.
const int _kResizeFrames = 30;

final class _ImageSurfaceProbeState extends State<ImageSurfaceProbe> {
  ui.Image? _shown;
  String _phase = 'starting';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _shown?.dispose();
    super.dispose();
  }

  /// The colour format every texture here uses. Asked once, through the
  /// backend's own cache, because the context stops answering after the first
  /// second — see `defaultColorFormatOfContext`.
  late final gpu.PixelFormat _format = defaultColorFormatOfContext.toGpu();

  int get _bytesPerTexture => widget.width * widget.height * 4;

  Future<void> _run() async {
    final paths = <PresentPathMeasurement>[
      await _ringPath(),
      await _surfacePath(name: 'surface', trailing: false),
      await _surfacePath(name: 'trailing', trailing: true),
      await _surfacePath(name: 'churn', trailing: false, churn: true),
    ];
    final resize = await _resizePhase();
    if (!mounted) return;
    widget.onDone(
      SurfaceProbeReport(
        width: widget.width,
        height: widget.height,
        frames: widget.frames,
        paths: paths,
        resize: resize,
      ),
    );
  }

  /// Shows [image] and resolves once Flutter has built and painted a frame
  /// with it, so the next step runs at the display's pace and the compositor
  /// really does hold the picture while the next one is drawn.
  ///
  /// The previous image is disposed here, the way `GpuFrameImage` disposes
  /// its own: a handle closed while the raster thread still draws it is fine —
  /// the engine keeps the picture alive until the layer tree lets go — and a
  /// handle left open pins the texture past that.
  Future<void> _show(ui.Image image, String phase) {
    final painted = Completer<void>();
    setState(() {
      _shown?.dispose();
      _shown = image;
      _phase = phase;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => painted.complete());
    return painted.future;
  }

  /// The colour frame [i] clears to. Every channel moves on its own period,
  /// so a frame shown in place of its neighbour would read back wrong.
  static vm.Vector4 _colourOf(int i) =>
      vm.Vector4(((i % 7) + 1) / 8, ((i % 5) + 1) / 6, ((i % 3) + 1) / 4, 1.0);

  /// One clear-only pass into [target], the same for every path.
  static gpu.CommandBuffer _clearTo(gpu.Texture target, vm.Vector4 colour) {
    final buffer = gpu.gpuContext.createCommandBuffer();
    buffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: target, clearValue: colour),
      ),
    );
    return buffer;
  }

  /// Whether the centre texel of [image] is [colour], within the rounding an
  /// eight-bit channel allows.
  static Future<bool> _holds(ui.Image image, vm.Vector4 colour) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return false;
    final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    bool near(int channel, double want) =>
        (bytes.getUint8(offset + channel) - (want * 255).round()).abs() <= 3;
    return near(0, colour.r) &&
        near(1, colour.g) &&
        near(2, colour.b) &&
        near(3, colour.a);
  }

  /// The renderer's own arrangement, reduced to its mechanism: a list of
  /// textures this side owns, one taken per frame, each returned when the
  /// command buffer that wrote it reports completion, and a new one made
  /// when none is free. Presented with `asImage()`.
  Future<PresentPathMeasurement> _ringPath() async {
    final owned = <gpu.Texture>[];
    final free = <gpu.Texture>[];
    final step = <int>[];
    final image = <int>[];
    final interval = <int>[];
    final between = Stopwatch()..start();
    var lastImage = _shown;
    var lastColour = _colourOf(0);

    for (var i = 0; i < widget.frames; i++) {
      if (i > 0) interval.add(between.elapsedMicroseconds);
      between.reset();
      final clock = Stopwatch()..start();

      final gpu.Texture target;
      if (free.isNotEmpty) {
        target = free.removeLast();
      } else {
        target = gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          widget.width,
          widget.height,
          format: _format,
        );
        owned.add(target);
      }
      final colour = _colourOf(i);
      _clearTo(
        target,
        colour,
      ).submit(completionCallback: (_) => free.add(target));
      final mint = Stopwatch()..start();
      final minted = target.asImage();
      mint.stop();
      clock.stop();

      step.add(clock.elapsedMicroseconds);
      image.add(mint.elapsedMicroseconds);
      lastImage = minted;
      lastColour = colour;
      await _show(minted, 'ring ${i + 1}/${widget.frames}');
      if (!mounted) break;
    }

    return PresentPathMeasurement(
      name: 'ring',
      stepMicros: MicrosSamples(step),
      imageMicros: MicrosSamples(image),
      intervalMicros: MicrosSamples(interval),
      textures: owned.length,
      bytesPerTexture: _bytesPerTexture,
      readbackOk: lastImage != null && await _holds(lastImage, lastColour),
    );
  }

  /// The surface's arrangement: acquire, clear, present, submit, and show
  /// `currentImage`. With [trailing], `present` goes through a second, empty
  /// command buffer submitted after the one that drew — the shape a backend
  /// with one pass per buffer and no say over which pass is last would need.
  ///
  /// With [churn], every frame also allocates and drops [_kChurnBytes] of
  /// small objects, which is not a present path at all: it is the control
  /// for a pool that grows. The surface counts a texture as reusable only
  /// when nothing but its own records hold it, and among the holders are the
  /// native halves of the Dart `Texture`, `RenderPass` and `CommandBuffer`
  /// every frame makes — which the collector frees, on its own schedule. A
  /// pool that shrinks under churn and grows without it is a pool paced by
  /// the garbage collector.
  Future<PresentPathMeasurement> _surfacePath({
    required String name,
    required bool trailing,
    bool churn = false,
  }) async {
    final surface = gpu.gpuContext.createImageSurface(
      widget.width,
      widget.height,
      format: _format,
    );
    final step = <int>[];
    final image = <int>[];
    final interval = <int>[];
    final between = Stopwatch()..start();
    var textures = 0;
    var lastImage = _shown;
    var lastColour = _colourOf(0);
    var note = '';

    for (var i = 0; i < widget.frames; i++) {
      if (i > 0) interval.add(between.elapsedMicroseconds);
      between.reset();
      final clock = Stopwatch()..start();

      final colour = _colourOf(i);
      final frame = surface.acquireNextFrame();
      final drew = _clearTo(frame.colorTexture, colour);
      try {
        if (trailing) {
          final tail = gpu.gpuContext.createCommandBuffer();
          frame.present(tail);
          drew.submit();
          tail.submit();
        } else {
          frame.present(drew);
          drew.submit();
        }
      } catch (error) {
        // The shape does not work, and that is the finding. Said once, and
        // the frame given back so the surface is not left with a lease.
        note = 'present threw: $error';
        frame.discard();
        break;
      }
      final mint = Stopwatch()..start();
      final minted = surface.currentImage;
      mint.stop();
      clock.stop();
      if (minted == null) {
        note = 'currentImage was null after present';
        break;
      }

      step.add(clock.elapsedMicroseconds);
      image.add(mint.elapsedMicroseconds);
      if (surface.debugBackingTextureCount > textures) {
        textures = surface.debugBackingTextureCount;
      }
      lastImage = minted;
      lastColour = colour;
      if (churn) _churn();
      await _show(minted, '$name ${i + 1}/${widget.frames}');
      if (!mounted) break;
    }

    return PresentPathMeasurement(
      name: name,
      stepMicros: MicrosSamples(step),
      imageMicros: MicrosSamples(image),
      intervalMicros: MicrosSamples(interval),
      textures: textures,
      bytesPerTexture: _bytesPerTexture,
      readbackOk:
          note.isEmpty &&
          lastImage != null &&
          await _holds(lastImage, lastColour),
      note: churn && note.isEmpty
          ? 'with ${_garbage.length ~/ 1024} MB of short-lived allocations '
                'per frame'
          : note,
    );
  }

  /// Short-lived allocations per churned frame: enough small objects to fill
  /// the young generation every frame or two, so a scavenge — and the
  /// finalisers that free native wrappers — runs at the display's pace.
  static const int _kChurnBytes = 4 << 20;

  /// The churn itself: kept in a field so the allocation is not dead code,
  /// and replaced every frame so the last lot becomes garbage.
  List<Uint8List> _garbage = const <Uint8List>[];

  void _churn() {
    _garbage = List<Uint8List>.generate(
      _kChurnBytes ~/ 1024,
      (_) => Uint8List(1024),
      growable: false,
    );
  }

  /// What `resize` says while a frame is out: the error's text, or `no error`.
  String _resizeWhileHeld(gpu.GpuImageSurface surface) {
    try {
      surface.resize(widget.width ~/ 2, widget.height ~/ 2);
      return 'no error';
    } catch (error) {
      return '$error';
    }
  }

  /// A surface drawn at one size, resized to half, and drawn again: what
  /// `present` reports on either side, what the pool does with the textures
  /// of the old size, and whether `resize` refuses while a frame is out.
  Future<ResizeOutcome> _resizePhase() async {
    final surface = gpu.gpuContext.createImageSurface(
      widget.width,
      widget.height,
      format: _format,
    );

    Future<(gpu.GpuPresentStatus, ui.Image?)> draw(int i, String phase) async {
      final frame = surface.acquireNextFrame();
      final drew = _clearTo(frame.colorTexture, _colourOf(i));
      final status = frame.present(drew);
      drew.submit();
      final minted = surface.currentImage;
      if (minted != null) await _show(minted, phase);
      return (status, minted);
    }

    var statusBefore = gpu.GpuPresentStatus.success;
    for (var i = 0; i < _kResizeFrames; i++) {
      final (status, _) = await draw(i, 'resize before ${i + 1}');
      statusBefore = status;
      if (!mounted) break;
    }

    final held = surface.acquireNextFrame();
    final whileAcquired = _resizeWhileHeld(surface);
    held.discard();

    final backingBefore = surface.debugBackingTextureCount;
    surface.resize(widget.width ~/ 2, widget.height ~/ 2);
    final backingJustAfter = surface.debugBackingTextureCount;

    var statusAfter = gpu.GpuPresentStatus.success;
    ui.Image? lastImage;
    var lastColour = _colourOf(0);
    for (var i = 0; i < _kResizeFrames; i++) {
      final colour = _colourOf(_kResizeFrames + i);
      final (status, minted) = await draw(
        _kResizeFrames + i,
        'resize after ${i + 1}',
      );
      if (i == 0) statusAfter = status;
      lastImage = minted;
      lastColour = colour;
      if (!mounted) break;
    }

    return ResizeOutcome(
      statusBefore: statusBefore.name,
      statusAfter: statusAfter.name,
      backingBefore: backingBefore,
      backingJustAfter: backingJustAfter,
      backingSettled: surface.debugBackingTextureCount,
      whileAcquired: whileAcquired,
      readbackOk:
          lastImage != null &&
          lastImage.width == widget.width ~/ 2 &&
          await _holds(lastImage, lastColour),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      if (_shown case final ui.Image image)
        RawImage(image: image, fit: BoxFit.contain),
      Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _phase,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      ),
    ],
  );
}
