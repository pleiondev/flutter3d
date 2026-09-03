/// What the image-surface probe measured, and the words it reports in.
///
/// Kept apart from the probe itself because this half has no GPU in it: the
/// statistics and the report are plain Dart over lists of microseconds, and
/// that is the half a headless test can hold still. The other half —
/// `surface_probe.dart` — needs Impeller under it and runs as an
/// application, the way the conformance suite does on that backend.
library;

/// A list of measurements in microseconds, and the three summaries that
/// matter.
///
/// The median says what a frame usually costs and the 95th percentile says
/// what the bad ones cost, which is the number a frame budget is actually
/// held to. A mean hides both. The worst sample is kept beside them because a
/// single forty-millisecond hitch in two hundred and forty frames is invisible
/// at the 95th percentile and is exactly the kind of thing a present path is
/// suspected of.
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

  /// `ring`, `ring held`, `surface`, `trailing` or `churn` — see the probe
  /// for what each does.
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
  /// cleared to.
  ///
  /// A sanity check on the wrapper, and worth no more than that: the read
  /// goes through `ui.Image.toByteData` into the texture the path itself
  /// owns, once, after the run — so it says the image handed to Flutter is
  /// over the texture the path drew, and says nothing about what the
  /// compositor sampled. The race a present path exists to prevent — a frame
  /// overwritten while the raster thread still reads it — is not a thing this
  /// can come back wrong on, on either path.
  final bool readbackOk;

  /// Anything the path wants said next to its numbers.
  final String note;

  /// The peak, as memory.
  double get megabytes => texturesPeak * bytesPerTexture / (1024 * 1024);
}

/// What happened when the surface was resized between frames.
///
/// What `present` returned is deliberately not here. In flutter_gpu 3.47
/// `GpuImageSurfaceFrame.present` ends with `return GpuPresentStatus.success;`
/// — the value is a constant in the Dart wrapper, not something the engine is
/// asked — so a `success -> success` printed on either side of a resize would
/// be a measurement that cannot come out any other way. That question is
/// answered by reading the SDK, and `ARCHITECTURE.md` §15 says so.
final class ResizeOutcome {
  const ResizeOutcome({
    required this.backingBefore,
    required this.backingJustAfter,
    required this.backingAfterThirtyFrames,
    required this.whileAcquired,
    required this.readbackOk,
  });

  /// `debugBackingTextureCount` at three moments: before the resize, right
  /// after it, and after thirty more frames drawn at the new size.
  ///
  /// Those thirty run under the same allocation churn the `churn` path uses,
  /// so the collector has been through the native wrappers several times over
  /// by the third reading. Without that the third number says nothing about
  /// the surface — a pool that has not shrunk is a pool nothing has collected
  /// yet, which is what every other phase of this probe shows anyway.
  final int backingBefore;
  final int backingJustAfter;
  final int backingAfterThirtyFrames;

  /// What `resize` did while a frame was acquired: the error's text, or
  /// `no error` if it allowed it.
  ///
  /// Asked with a size the phase does not itself resize to, so a permitted
  /// resize leaves a state the counts below would plainly be measuring
  /// nothing from, rather than one that looks like a measurement.
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

  /// How many of the yes-or-no questions came back no: one readback per
  /// present path and one for the resized surface, each of that phase's last
  /// frame.
  ///
  /// The numbers are for reading; these are for a script. A path whose image
  /// does not wrap what it drew, or a resize that leaves the surface showing
  /// the wrong picture, is a failure whatever the timings say — while a path
  /// that tears under the compositor passes this, for the reason
  /// [PresentPathMeasurement.readbackOk] gives.
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
      '${_label(path.name)}'
      'step p50 ${_us(path.stepMicros.median)} '
      'p95 ${_us(path.stepMicros.p95)} '
      'max ${_us(path.stepMicros.max)}  '
      'image p50 ${_us(path.imageMicros.median)} '
      'p95 ${_us(path.imageMicros.p95)} '
      'max ${_us(path.imageMicros.max)}  '
      'interval p50 ${_ms(path.intervalMicros.median)} '
      'p95 ${_ms(path.intervalMicros.p95)} '
      'max ${_ms(path.intervalMicros.max)}  '
      'textures ${path.texturesPeak} peak '
      '(${path.megabytes.toStringAsFixed(1)} MB) '
      '${path.texturesAtEnd} at end  '
      'readback ${path.readbackOk ? 'ok' : 'WRONG'}'
      '${path.note.isEmpty ? '' : '  ${path.note}'}';

  String get _resizeLine =>
      '${_label('resize')}'
      'backing ${resize.backingBefore} -> ${resize.backingJustAfter} '
      '-> ${resize.backingAfterThirtyFrames}  '
      'while acquired: ${resize.whileAcquired}  '
      'readback ${resize.readbackOk ? 'ok' : 'WRONG'}';

  /// The name a line opens with, in a column wide enough for the longest of
  /// them and one space clear of the numbers.
  static String _label(String name) => name.padRight(10);

  static String _us(int micros) => '${micros}us'.padLeft(7);
  static String _ms(int micros) =>
      '${(micros / 1000).toStringAsFixed(1)}ms'.padLeft(7);
}
