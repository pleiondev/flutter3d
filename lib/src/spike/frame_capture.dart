import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import '../engine/render/debug_draw.dart';
import '../engine/render/renderer.dart';

/// Writes one rendered frame to a PNG and quits.
///
/// The plan's verification recipes measure the picture with PIL rather than
/// judging it by eye, and that needs a file. Grabbing the window with
/// `screencapture` works only when someone is logged in with the display awake;
/// this path works over ssh, on a locked screen, and in CI, and it captures
/// exactly the texture the renderer produced instead of a scaled, composited
/// window.
///
/// Driven entirely by `--dart-define`, so a normal run carries no cost beyond
/// two constant comparisons:
///
/// ```
/// flutter run -d macos \
///   --dart-define=FLUTTER3D_CAPTURE=/tmp/shot.png \
///   --dart-define=FLUTTER3D_CAPTURE_FRAME=180 \
///   --dart-define=FLUTTER3D_DEBUG_DRAW=bounds,normals,lights,axes \
///   --dart-define=FLUTTER3D_SOURCE=obj:%20Teapot
/// ```
final class FrameCapture {
  FrameCapture._(this.path, this.atFrame);

  static const String _pathKey = 'FLUTTER3D_CAPTURE';
  static const String _frameKey = 'FLUTTER3D_CAPTURE_FRAME';

  final String path;

  /// Which frame to grab. Late enough that the model has loaded and the
  /// animation has moved, since a capture of frame 0 shows an empty scene.
  final int atFrame;

  int _seen = 0;
  bool _done = false;

  /// Null unless `FLUTTER3D_CAPTURE` was defined.
  static FrameCapture? fromEnvironment() {
    const path = String.fromEnvironment(_pathKey);
    if (path.isEmpty) return null;
    const frame = int.fromEnvironment(_frameKey, defaultValue: 120);
    return FrameCapture._(_resolve(path), frame);
  }

  /// A relative name lands in the app's temp directory.
  ///
  /// macOS Flutter apps ship sandboxed, so an absolute path anywhere outside the
  /// container fails with "Operation not permitted" — and it fails at write time,
  /// two hundred frames after the run started. Resolving relative names against
  /// [Directory.systemTemp] gives a path that always works; the run prints where
  /// the file actually went.
  static String _resolve(String path) {
    if (path.startsWith('/')) return path;
    return '${Directory.systemTemp.path}/$path';
  }

  /// Called once per rendered frame. Writes and exits on the chosen frame.
  void offer(FrameResult frame) {
    if (_done) return;
    if (++_seen < atFrame) return;
    _done = true;
    // The counters go to stdout next to the file name: a capture that looks
    // wrong is usually explained by them (nothing drawn, everything culled, the
    // overlay contributing no lines), and reading them off the on-screen panel
    // is not possible in the very situations this path exists for.
    stdout.writeln('frame capture: ${frame.drawCalls} draws, '
        '${frame.pipelineSwitches} pipeline switches, ${frame.culled} culled, '
        '${frame.lights} lights (${frame.lightsDropped} dropped), '
        '${frame.pipelines} pipelines, '
        '${frame.debugLines} debug lines, ${frame.submitMicros} us submit');
    unawaited(_write(frame.image));
  }

  Future<void> _write(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        stderr.writeln('frame capture: the image encoded to nothing');
        exit(2);
      }
      await File(path).writeAsBytes(data.buffer.asUint8List());
      stdout.writeln('frame capture: wrote $path (${image.width}x'
          '${image.height})');
      exit(0);
    } catch (error) {
      stderr.writeln('frame capture failed: $error');
      exit(2);
    }
  }
}

/// Debug overlays requested on the command line, for captures and for CI.
///
/// A comma-separated list rather than a flag per overlay: the point is to name
/// a scenario in one define, and an unknown name is a typo worth reporting
/// rather than silently ignoring.
DebugDrawOptions debugDrawFromEnvironment() {
  const spec = String.fromEnvironment('FLUTTER3D_DEBUG_DRAW');
  if (spec.isEmpty) return const DebugDrawOptions();

  var options = const DebugDrawOptions();
  for (final raw in spec.split(',')) {
    switch (raw.trim().toLowerCase()) {
      case '':
        continue;
      case 'bounds':
        options = options.copyWith(bounds: true);
      case 'normals':
        options = options.copyWith(normals: true);
      case 'lights':
        options = options.copyWith(lightGizmos: true);
      case 'axes':
        options = options.copyWith(axes: true);
      case 'frusta':
        options = options.copyWith(cameraFrustums: true);
      case 'all':
        options = const DebugDrawOptions(
          bounds: true,
          normals: true,
          lightGizmos: true,
          axes: true,
          cameraFrustums: true,
        );
      default:
        stderr.writeln('FLUTTER3D_DEBUG_DRAW: unknown overlay "$raw"');
    }
  }
  return options;
}

/// Label of the model to select at startup, empty when unset.
String startupSourceFromEnvironment() =>
    const String.fromEnvironment('FLUTTER3D_SOURCE');

/// Which of the demo's lights start switched on.
///
/// Names are matched against `LightNode.name`, comma separated; an empty define
/// leaves every light on. It exists so the "switching a light off does not
/// rebuild the pipeline" claim can be checked from a capture rather than argued
/// from the code.
Set<String> startupLightsFromEnvironment() {
  const spec = String.fromEnvironment('FLUTTER3D_LIGHTS');
  if (spec.trim().isEmpty) return const <String>{};
  return spec
      .split(',')
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
}

/// Starting orbit angles in radians, as `yaw,pitch`, or null when unset.
///
/// A capture is only comparable against another if the camera is where it was
/// last time, and some checks need a specific angle rather than any fixed one:
/// NormalTangentTest only lines up face-on, because off-axis the whole point of
/// the model is that normal mapping and real geometry stop agreeing.
({double yaw, double pitch})? startupOrbitFromEnvironment() {
  const spec = String.fromEnvironment('FLUTTER3D_ORBIT');
  if (spec.trim().isEmpty) return null;

  final parts = spec.split(',');
  if (parts.length != 2) {
    stderr.writeln('FLUTTER3D_ORBIT: expected "yaw,pitch", got "$spec"');
    return null;
  }
  final yaw = double.tryParse(parts[0].trim());
  final pitch = double.tryParse(parts[1].trim());
  if (yaw == null || pitch == null) {
    stderr.writeln('FLUTTER3D_ORBIT: "$spec" is not two numbers');
    return null;
  }
  return (yaw: yaw, pitch: pitch);
}

/// Whether the demo's turntable spin is on.
///
/// Worth a define because it is the one thing that makes two captures of the
/// same scene differ. Turning it off is what lets a capture isolate something
/// else that moves — an animation clip, a rotating light — or be compared
/// against a golden.
bool startupSpinFromEnvironment() =>
    const bool.fromEnvironment('FLUTTER3D_SPIN', defaultValue: true);
