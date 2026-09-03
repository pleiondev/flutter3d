/// What the image-surface probe measured, and the words it reports in.
///
/// Kept apart from the probe itself because this half has no GPU in it: the
/// statistics and the report are plain Dart over lists of microseconds, and
/// that is the half a headless test can hold still. The other half —
/// `surface_probe.dart` — needs Impeller under it and runs as an
/// application, the way the conformance suite does on that backend.
library;

/// A list of measurements in microseconds, and the two summaries that matter.
///
/// The median says what a frame usually costs and the 95th percentile says
/// what the bad ones cost, which is the number a frame budget is actually
/// held to. A mean hides both.
final class MicrosSamples {
  const MicrosSamples(this.samples);

  final List<int> samples;

  /// The value [fraction] of the samples sit at or below, by nearest rank.
  ///
  /// Zero for no samples rather than a throw, because a phase that recorded
  /// nothing is still a phase worth printing — with a zero that is plainly a
  /// zero rather than a crash in the report's own arithmetic.
  int percentile(double fraction) {
    if (samples.isEmpty) return 0;
    final sorted = List<int>.of(samples)..sort();
    final index = ((sorted.length - 1) * fraction).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  int get median => percentile(0.5);
  int get p95 => percentile(0.95);
  int get max => samples.isEmpty ? 0 : samples.reduce((a, b) => a > b ? a : b);
}

/// One way of putting a frame on screen, measured over a run of frames.
final class PresentPathMeasurement {
  const PresentPathMeasurement({
    required this.name,
    required this.stepMicros,
    required this.imageMicros,
    required this.intervalMicros,
    required this.texturesPeak,
    required this.texturesAtEnd,
    required this.bytesPerTexture,
    required this.readbackOk,
    this.note = '',
  });

  /// `ring`, `surface`, `trailing` or `churn` — see the probe for what each
  /// does.
  final String name;

  /// The whole of one frame's work on the UI thread: take a target, encode
  /// the pass, submit, and mint the image Flutter will draw.
  final MicrosSamples stepMicros;

  /// Just the last of those — `Texture.asImage()` against
  /// `GpuImageSurface.currentImage` — which is the direct comparison.
  final MicrosSamples imageMicros;

  /// Wall-clock time between one frame's step and the next, which is the
  /// display's own pace unless something in the path stalls it.
  final MicrosSamples intervalMicros;

  /// The most finished-frame textures the path held at once, sampled after
  /// each frame, and how many it held when the run ended. For the ring the
  /// two are the same number, since it never lets one go; a surface's pool
  /// shrinks when the collector runs, so its end can sit below its peak.
  final int texturesPeak;
  final int texturesAtEnd;

  /// What one of them costs, so [texturesPeak] can be read as memory.
  final int bytesPerTexture;

  /// Whether the last frame's image, read back, held the colour it was
  /// cleared to — the one correctness question a present path has to answer.
  final bool readbackOk;

  /// Anything the path wants said next to its numbers.
  final String note;

  /// The peak, as memory.
  double get megabytes => texturesPeak * bytesPerTexture / (1024 * 1024);
}

/// What happened when the surface was resized between frames.
final class ResizeOutcome {
  const ResizeOutcome({
    required this.statusBefore,
    required this.statusAfter,
    required this.backingBefore,
    required this.backingJustAfter,
    required this.backingSettled,
    required this.whileAcquired,
    required this.readbackOk,
  });

  /// `GpuPresentStatus` of the last present before the resize and the first
  /// after it, as the enum's name; `none` if that side drew nothing.
  final String statusBefore;
  final String statusAfter;

  /// `debugBackingTextureCount` at three moments: before the resize, right
  /// after it, and after enough frames for the old-size textures to be let go.
  final int backingBefore;
  final int backingJustAfter;
  final int backingSettled;

  /// What `resize` did while a frame was acquired: the error's text, or
  /// `no error` if it allowed it.
  final String whileAcquired;

  /// Whether a frame at the new size read back with its clear colour.
  final bool readbackOk;
}

/// Everything one run of the probe found.
final class SurfaceProbeReport {
  const SurfaceProbeReport({
    required this.width,
    required this.height,
    required this.frames,
    required this.paths,
    required this.resize,
  });

  final int width;
  final int height;

  /// Frames each path was run for.
  final int frames;

  final List<PresentPathMeasurement> paths;
  final ResizeOutcome resize;

  /// How many of the yes-or-no questions came back no.
  ///
  /// The numbers are for reading; these are for a script. A present path
  /// whose image does not hold what was drawn, or a resize that leaves the
  /// surface showing the wrong picture, is a failure whatever the timings say.
  int get failures =>
      paths.where((PresentPathMeasurement p) => !p.readbackOk).length +
      (resize.readbackOk ? 0 : 1);

  /// The report, one line per finding, ending with the verdict line
  /// `packages/flutter3d_impeller/tool/surface_probe.sh` reads.
  List<String> get lines => <String>[
    'surface-probe  ${width}x$height, $frames frames per path',
    for (final path in paths) _pathLine(path),
    _resizeLine,
    '=== surface probe done, $failures failed ===',
  ];

  static String _pathLine(PresentPathMeasurement path) =>
      '${path.name.padRight(9)}'
      'step p50 ${_us(path.stepMicros.median)} '
      'p95 ${_us(path.stepMicros.p95)}  '
      'image p50 ${_us(path.imageMicros.median)} '
      'p95 ${_us(path.imageMicros.p95)}  '
      'interval p50 ${_ms(path.intervalMicros.median)} '
      'p95 ${_ms(path.intervalMicros.p95)}  '
      'textures ${path.texturesPeak} peak '
      '(${path.megabytes.toStringAsFixed(1)} MB) '
      '${path.texturesAtEnd} at end  '
      'readback ${path.readbackOk ? 'ok' : 'WRONG'}'
      '${path.note.isEmpty ? '' : '  ${path.note}'}';

  String get _resizeLine =>
      'resize   '
      'status ${resize.statusBefore} -> ${resize.statusAfter}  '
      'backing ${resize.backingBefore} -> ${resize.backingJustAfter} '
      '-> ${resize.backingSettled}  '
      'while acquired: ${resize.whileAcquired}  '
      'readback ${resize.readbackOk ? 'ok' : 'WRONG'}';

  static String _us(int micros) => '${micros}us'.padLeft(7);
  static String _ms(int micros) =>
      '${(micros / 1000).toStringAsFixed(1)}ms'.padLeft(7);
}
