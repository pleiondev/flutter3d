/// A fixed camera move, timed, so a viewport can be compared with itself.
///
/// **Numbers rather than an impression, which is what `p0-01` asks for.** "It
/// feels smooth on my laptop" is not something a browser or a handset can be
/// held to, and neither is a frame rate read off a HUD by eye while somebody
/// drags the mouse differently each time. This turns the camera through the
/// same arc every run and reports what the frames cost, so macOS, Chrome and a
/// phone are answering one question.
///
/// It reports two things and they are not the same: the render's own CPU cost,
/// which is `FrameResult.cpuMicros` and is the engine, and the wall clock
/// between frames, which is everything — build, raster, and whatever else the
/// platform was doing. A viewport can be cheap and still stutter, and only the
/// second number says so.
library;

import 'dart:math' as math;

import 'staging.dart';

/// What a run of [OrbitRun] measured.
typedef OrbitReport = ({
  int frames,
  double meanFrameMs,
  double worstFrameMs,
  double meanRenderMs,
  double worstRenderMs,
  int slowFrames,
});

/// Turns the camera a full circle over [frames] frames and times each one.
final class OrbitRun {
  OrbitRun({required this.frames, required this.stage});

  /// How many frames the arc is spread over. 600 is ten seconds at sixty,
  /// which is long enough for a driver to settle and short enough that nobody
  /// walks away from it.
  final int frames;

  final ModelerStage stage;

  int _frame = 0;
  int _lastMicros = 0;
  final List<double> _wall = <double>[];
  final List<double> _render = <double>[];

  bool get done => _frame >= frames;

  /// Advances the camera one step and records what the previous frame cost.
  ///
  /// [elapsedMicros] is the ticker's own clock, and [renderMicros] is what the
  /// renderer reported for the frame just drawn — null before there is one.
  void step(int elapsedMicros, int? renderMicros) {
    if (done) return;

    if (_lastMicros != 0) {
      _wall.add((elapsedMicros - _lastMicros) / 1000.0);
      if (renderMicros != null) _render.add(renderMicros / 1000.0);
    }
    _lastMicros = elapsedMicros;

    // A full turn and a slow nod, so the subject is seen from every side and
    // from above and below — a fixed angle would measure one view of it.
    _frame++;
    final t = _frame / frames;
    stage.orbit
      ..yaw = t * 2 * math.pi
      ..pitch = 0.35 + 0.3 * math.sin(t * 2 * math.pi)
      ..apply();
  }

  /// What the run measured, with the first frames left out.
  ///
  /// The first ten are dropped rather than averaged in: they carry the shader
  /// compile, the first upload and the window's own first paint, and a mean
  /// that includes them is a mean nobody can compare with a second run.
  OrbitReport report() {
    final wall = _wall.length > 10 ? _wall.sublist(10) : _wall;
    final render = _render.length > 10 ? _render.sublist(10) : _render;
    double mean(List<double> of) =>
        of.isEmpty ? 0 : of.reduce((a, b) => a + b) / of.length;
    double worst(List<double> of) =>
        of.isEmpty ? 0 : of.reduce((a, b) => a > b ? a : b);
    return (
      frames: wall.length,
      meanFrameMs: mean(wall),
      worstFrameMs: worst(wall),
      meanRenderMs: mean(render),
      worstRenderMs: worst(render),
      // A frame over 16.6 ms is a frame the display did not get in time at
      // sixty hertz. Counted rather than averaged away, because a mean of 12
      // with a tenth of the frames at 40 is not a viewport anybody would call
      // smooth.
      slowFrames: wall.where((double ms) => ms > 16.6).length,
    );
  }

  /// One line per number, in the shape `ARCHITECTURE.md` §14 asks for: what was
  /// measured, on what, and with what in front of the camera.
  static String describe(OrbitReport report, {required String what}) =>
      'orbit: $what\n'
      '  frames        ${report.frames}\n'
      '  frame  mean   ${report.meanFrameMs.toStringAsFixed(2)} ms\n'
      '  frame  worst  ${report.worstFrameMs.toStringAsFixed(2)} ms\n'
      '  render mean   ${report.meanRenderMs.toStringAsFixed(2)} ms\n'
      '  render worst  ${report.worstRenderMs.toStringAsFixed(2)} ms\n'
      '  over 16.6 ms  ${report.slowFrames}';
}
