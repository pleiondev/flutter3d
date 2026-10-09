import 'dart:async';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a run of frames cost, frame by frame — `N3`.
///
/// **Spikes, not averages.** A frame rate is a mean, and a run whose mean is
/// sixty can still stop for a tenth of a second every few seconds; that stop
/// is what a player notices and what costs them the shot. So the numbers kept
/// are the median, the 99th percentile, the worst frame and which frame it
/// was, and every frame over [limit] — fifty milliseconds by default,
/// three frames of a 60 Hz display — by its index, so a spike can be found
/// again by replaying the tape to it.
///
/// Every time here is in seconds, as the units contract has it; [toJson]
/// writes milliseconds, which is what a person reads in a report.
final class PacingReport {
  const PacingReport._({
    required this.seconds,
    required this.limit,
    required this.p50,
    required this.p99,
    required this.max,
    required this.worstFrame,
    required this.overLimit,
  });

  /// The statistics of [seconds], one entry a frame in the order they ran.
  factory PacingReport.of(List<double> seconds, {double limit = 0.05}) {
    final sorted = List<double>.of(seconds)..sort();
    // Nearest rank: the smallest frame time at least that share of the
    // frames did not exceed. No interpolation, so every number reported is a
    // frame that actually happened.
    double rank(double share) => sorted.isEmpty
        ? 0.0
        : sorted[math.max(0, (share * sorted.length).ceil() - 1)];
    final worst = seconds.isEmpty
        ? -1
        : seconds.indexOf(sorted.isEmpty ? 0.0 : sorted.last);
    return PacingReport._(
      seconds: List<double>.unmodifiable(seconds),
      limit: limit,
      p50: rank(0.5),
      p99: rank(0.99),
      max: sorted.isEmpty ? 0.0 : sorted.last,
      worstFrame: worst,
      overLimit: List<int>.unmodifiable(<int>[
        for (var i = 0; i < seconds.length; i++)
          if (seconds[i] > limit) i,
      ]),
    );
  }

  /// Every frame's time, in seconds.
  final List<double> seconds;

  /// A frame longer than this, in seconds, is a spike.
  final double limit;

  /// The median frame, the 99th percentile and the worst, in seconds.
  final double p50;

  /// The 99th-percentile frame, in seconds.
  final double p99;

  /// The worst frame, in seconds.
  final double max;

  /// The index of the longest frame; -1 for no frames.
  final int worstFrame;

  /// The index of every frame longer than [limit], in order.
  final List<int> overLimit;

  int get frames => seconds.length;

  /// No frame over [limit].
  bool get isEven => overLimit.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'frames': frames,
    'limitMillis': limit * 1000.0,
    'p50': _millis(p50),
    'p99': _millis(p99),
    'max': _millis(max),
    'worstFrame': worstFrame,
    'overLimit': overLimit,
  };

  /// Seconds as the report's milliseconds, to a microsecond.
  static double _millis(double seconds) =>
      (seconds * 1e6).roundToDouble() / 1000.0;
}

/// Closes the frame being encoded on [device] and completes once the GPU has
/// finished every pass in it.
///
/// A frame is not over when `Renderer.render` returns: on Impeller the
/// command buffers have only been handed to the queue, and a timer stopped
/// there measures encoding and nothing the GPU did. `onFrameComplete` is the
/// one completion every backend reports, but a backend only settles a frame
/// once the next one begins, so this begins it. That is sound here, and only
/// here, because the caller draws nothing further until the frame is done:
/// the per-frame allocators `beginFrame` rotates are all free by then. On the
/// software rasteriser and WebGL the frame is done already and this returns
/// at once.
Future<void> gpuSettled(GraphicsDevice device) {
  final done = Completer<void>();
  device
    ..onFrameComplete(done.complete)
    ..beginFrame();
  return done.future;
}

/// Plays [demo]'s tape a step a frame and times each frame — `N3`.
///
/// A frame is one step and one draw: the entry is applied to [input],
/// [onStep] runs the simulation, and [drawFrame] draws the frame and
/// completes when it is finished — for a GPU device, after [gpuSettled], so
/// the time includes the GPU's share of it. Frames run back to back rather
/// than on a display's clock: what is measured is what a frame costs, not
/// how long it waited for vsync, and a frame that costs more than
/// [limit] seconds is one no display rate hides.
///
/// Serialising the CPU and GPU halves makes each frame look longer than it
/// would in a game, where the GPU draws one frame while the CPU prepares the
/// next. That is the right side to err on for a check that fails on spikes,
/// and it puts each spike on the frame that caused it.
///
/// [repeats] plays the tape that many times; [rewind], when given, runs before
/// each pass and puts the simulation back where the tape starts. The first
/// [warmUpFrames] frames are played but not counted, for a caller that wants
/// the numbers of a running level rather than of its first frame.
/// [clock] reads microseconds, and is a [Stopwatch] unless a test supplies
/// one.
Future<PacingReport> replayPacing({
  required Demo demo,
  required InputState input,
  required void Function(double dt) onStep,
  required Future<void> Function(int frame) drawFrame,
  void Function()? rewind,
  int repeats = 1,
  int warmUpFrames = 0,

  /// The step handed to [onStep], in seconds.
  double dt = 1.0 / 60.0,

  /// A frame longer than this, in seconds, is a spike.
  double limit = 0.05,
  int Function()? clock,
}) async {
  if (repeats < 1) {
    throw ArgumentError.value(repeats, 'repeats', 'at least one pass');
  }
  final now = clock ?? _stopwatch();
  final seconds = <double>[];
  var frame = 0;
  for (var pass = 0; pass < repeats; pass++) {
    rewind?.call();
    final playback = InputTapePlayback(demo.tape);
    while (!playback.isFinished) {
      final start = now();
      playback.applyTo(input);
      onStep(dt);
      input.endStep();
      await drawFrame(frame);
      final took = (now() - start) / 1e6;
      if (frame >= warmUpFrames) seconds.add(took);
      frame++;
    }
  }
  return PacingReport.of(seconds, limit: limit);
}

int Function() _stopwatch() {
  final watch = Stopwatch()..start();
  return () => watch.elapsedMicroseconds;
}
