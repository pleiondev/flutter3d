import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';

/// Prints what a frame costs, when the command line asks for it.
///
///     flutter run --profile --dart-define=FLUTTER3D_TIMINGS=true
///
/// Every [window] frames — a hundred and twenty unless
/// `FLUTTER3D_TIMINGS_WINDOW` says otherwise, which a platform drawing a
/// frame a second wants — one line: the mean and the worst of the build half
/// — the UI thread, where the renderer encodes every draw — and of the raster
/// half, where the GPU work is submitted and waited for. Two numbers rather
/// than a frame rate, because a frame rate says a frame was late and not
/// which half made it so; a reflection probe that redraws a face a frame
/// shows up in the build half first, since a view of the scene is a walk
/// over every mesh in it.
///
/// **Off unless asked for, and then off entirely.** [enabled] is a
/// compile-time constant, so a shipped game registers no callback and pays
/// nothing; the class exists so that a measurement is a flag rather than a
/// patch somebody has to write again next time.
final class FrameTimingLog {
  FrameTimingLog({this.label = 'frame', this.window = defaultWindow})
    : assert(window > 0, 'a window of no frames never reports');

  /// Whether the build asked for timings at all.
  static const bool enabled = bool.fromEnvironment('FLUTTER3D_TIMINGS');

  /// The window a log gets when its owner names none: two seconds at sixty
  /// frames, or whatever `FLUTTER3D_TIMINGS_WINDOW` said on the command line.
  static const int defaultWindow = int.fromEnvironment(
    'FLUTTER3D_TIMINGS_WINDOW',
    defaultValue: 120,
  );

  /// Who is reporting — a game's name, so two logs in one console differ.
  final String label;

  /// How many frames each line averages over.
  final int window;

  // The window in progress: real state of a hot loop, reset when it reports.
  int _frames = 0;
  int _buildMicros = 0;
  int _rasterMicros = 0;
  int _worstBuildMicros = 0;
  int _worstRasterMicros = 0;

  /// Starts listening. Nothing happens when [enabled] is false.
  void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Stops listening, for a screen that is going away.
  void stop() {
    if (!enabled) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final line = note(
        build: timing.buildDuration,
        raster: timing.rasterDuration,
      );
      if (line != null) debugPrint(line);
    }
  }

  /// Records one frame; returns the line to print when the window is full,
  /// and null otherwise.
  ///
  /// Separate from the binding so the arithmetic can be tested without a
  /// frame: what a window says is the whole of what this class is for.
  String? note({required Duration build, required Duration raster}) {
    _frames++;
    _buildMicros += build.inMicroseconds;
    _rasterMicros += raster.inMicroseconds;
    _worstBuildMicros = math.max(_worstBuildMicros, build.inMicroseconds);
    _worstRasterMicros = math.max(_worstRasterMicros, raster.inMicroseconds);
    if (_frames < window) return null;

    final line =
        '$label: over $_frames frames, build '
        '${_ms(_buildMicros ~/ _frames)} ms mean / ${_ms(_worstBuildMicros)} '
        'worst, raster ${_ms(_rasterMicros ~/ _frames)} ms mean / '
        '${_ms(_worstRasterMicros)} worst';
    _frames = 0;
    _buildMicros = 0;
    _rasterMicros = 0;
    _worstBuildMicros = 0;
    _worstRasterMicros = 0;
    return line;
  }

  static String _ms(int micros) => (micros / 1000.0).toStringAsFixed(2);
}
