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
/// was, and every frame over [limitMillis] — fifty milliseconds by default,
/// three frames of a 60 Hz display — by its index, so a spike can be found
/// again by replaying the tape to it.
final class FramePacing {
  const FramePacing._({
    required this.millis,
    required this.limitMillis,
    required this.p50,
    required this.p99,
    required this.max,
    required this.worstFrame,
    required this.overLimit,
  });

  /// The statistics of [millis], one entry a frame in the order they ran.
  factory FramePacing.of(List<double> millis, {double limitMillis = 50.0}) {
    final sorted = List<double>.of(millis)..sort();
    // Nearest rank: the smallest frame time at least that share of the
    // frames did not exceed. No interpolation, so every number reported is a
    // frame that actually happened.
    double rank(double share) => sorted.isEmpty
        ? 0.0
        : sorted[math.max(0, (share * sorted.length).ceil() - 1)];
    final worst = millis.isEmpty
        ? -1
        : millis.indexOf(sorted.isEmpty ? 0.0 : sorted.last);
    return FramePacing._(
      millis: List<double>.unmodifiable(millis),
      limitMillis: limitMillis,
      p50: rank(0.5),
      p99: rank(0.99),
      max: sorted.isEmpty ? 0.0 : sorted.last,
      worstFrame: worst,
      overLimit: List<int>.unmodifiable(<int>[
        for (var i = 0; i < millis.length; i++)
          if (millis[i] > limitMillis) i,
      ]),
    );
  }

  /// Every frame's time, in milliseconds.
  final List<double> millis;

  /// A frame longer than this is a spike.
  final double limitMillis;

  final double p50;
  final double p99;
  final double max;

  /// The index of the longest frame; -1 for no frames.
  final int worstFrame;

  /// The index of every frame longer than [limitMillis], in order.
  final List<int> overLimit;

  int get frames => millis.length;

  /// No frame over [limitMillis].
  bool get even => overLimit.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'frames': frames,
    'limitMillis': limitMillis,
    'p50': _round(p50),
    'p99': _round(p99),
    'max': _round(max),
    'worstFrame': worstFrame,
    'overLimit': overLimit,
  };

  static double _round(double ms) => (ms * 1000.0).roundToDouble() / 1000.0;
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
/// [limitMillis] is one no display rate hides.
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
Future<FramePacing> replayPacing({
  required Demo demo,
  required InputState input,
  required void Function(double dt) onStep,
  required Future<void> Function(int frame) drawFrame,
  void Function()? rewind,
  int repeats = 1,
  int warmUpFrames = 0,
  double dt = 1.0 / 60.0,
  double limitMillis = 50.0,
  int Function()? clock,
}) async {
  if (repeats < 1) {
    throw ArgumentError.value(repeats, 'repeats', 'at least one pass');
  }
  final now = clock ?? _stopwatch();
  final millis = <double>[];
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
      final took = (now() - start) / 1000.0;
      if (frame >= warmUpFrames) millis.add(took);
      frame++;
    }
  }
  return FramePacing.of(millis, limitMillis: limitMillis);
}

int Function() _stopwatch() {
  final watch = Stopwatch()..start();
  return () => watch.elapsedMicroseconds;
}
