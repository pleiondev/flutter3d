import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../engine/render/renderer.dart';
import 'golden_scenes.dart';

/// Renders one [GoldenScene] and compares it against a stored reference.
///
/// Runs inside the app rather than under `flutter test`, because the test runner
/// is headless and every pixel here comes from a real Metal device. That is not
/// an inconvenience to work around — it is the point. The shader bundle format
/// is tied to the Flutter version, so the failure this guards against is an SDK
/// update quietly changing what the GPU produces, and only the GPU can show it.
///
/// Driven by `--dart-define=FLUTTER3D_GOLDEN=<name>`, with
/// `FLUTTER3D_GOLDEN_UPDATE=true` to record instead of compare. The process
/// exits 0 on a match and 1 on a mismatch, so `tool/golden.dart` can just run it
/// and read the code.
final class GoldenRunner {
  GoldenRunner._(this.scene, {required this.update, required this.directory});

  final GoldenScene scene;
  final bool update;
  final String directory;

  /// Fraction of pixels allowed to differ beyond [channelTolerance].
  ///
  /// Not zero, and not because exactness would be nice to have. MSAA resolve
  /// order and the driver's own floating-point choices move a handful of edge
  /// pixels between runs on the same machine, so an exact comparison flakes —
  /// and a flaky golden gets disabled, which is worse than a loose one.
  static const double pixelTolerance = 0.002;

  /// How far one channel may move before a pixel counts as different.
  static const int channelTolerance = 8;

  int _seen = 0;
  bool _done = false;

  /// Null unless `FLUTTER3D_GOLDEN` names a scene.
  static GoldenRunner? fromEnvironment() {
    const name = String.fromEnvironment('FLUTTER3D_GOLDEN');
    if (name.isEmpty) return null;

    final scene = goldenSceneNamed(name);
    if (scene == null) {
      stderr.writeln(
        'FLUTTER3D_GOLDEN: no scene named "$name". Known scenes:\n'
        '${kGoldenScenes.map((s) => '  ${s.name}').join('\n')}',
      );
      exit(2);
    }

    const directory =
        String.fromEnvironment('FLUTTER3D_GOLDEN_DIR', defaultValue: 'test/goldens');
    return GoldenRunner._(
      scene,
      update: const bool.fromEnvironment('FLUTTER3D_GOLDEN_UPDATE'),
      directory: directory,
    );
  }

  /// Which frame to grab.
  ///
  /// Late enough for the model to have loaded and for the ticker to have settled;
  /// the scene's own clip time is pinned separately, so this only has to be
  /// "after everything is ready" rather than a specific moment.
  static const int captureFrame = 90;

  void offer(FrameResult frame) {
    if (_done) return;
    if (++_seen < captureFrame) return;
    _done = true;
    unawaited(_run(frame));
  }

  Future<void> _run(FrameResult frame) async {
    try {
      final image = frame.image;
      if (image.width != scene.width || image.height != scene.height) {
        stderr.writeln(
          'GOLDEN ${scene.name}: rendered ${image.width}x${image.height}, '
          'expected ${scene.width}x${scene.height}. The golden path must fix '
          'the render size, or the result depends on the window.',
        );
        exit(1);
      }

      final actual = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (actual == null) {
        stderr.writeln('GOLDEN ${scene.name}: the frame read back as nothing.');
        exit(1);
      }

      final reference = File('$directory/${scene.name}.png');

      if (update) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        reference.parent.createSync(recursive: true);
        reference.writeAsBytesSync(png!.buffer.asUint8List());
        stdout.writeln('GOLDEN ${scene.name}: recorded ${reference.path}');
        exit(0);
      }

      if (!reference.existsSync()) {
        stderr.writeln(
          'GOLDEN ${scene.name}: no reference at ${reference.path}. Record one '
          'with tool/golden.dart --update.',
        );
        exit(1);
      }

      final expected = await _decode(reference.readAsBytesSync());
      final result = _compare(expected, actual.buffer.asUint8List());

      if (result.withinTolerance) {
        stdout.writeln(
          'GOLDEN ${scene.name}: PASS '
          '(${result.differing} of ${result.total} pixels differ, worst '
          '${result.worstChannel})',
        );
        exit(0);
      }

      // The actual frame is written beside the reference so the two can be
      // opened side by side. A number alone does not say whether the lighting
      // shifted or the model moved.
      final actualPath = '$directory/${scene.name}.actual.png';
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(actualPath).writeAsBytesSync(png!.buffer.asUint8List());

      stderr.writeln(
        'GOLDEN ${scene.name}: FAIL — ${result.differing} of ${result.total} '
        'pixels differ by more than $channelTolerance '
        '(${(result.fraction * 100).toStringAsFixed(3)}%, limit '
        '${(pixelTolerance * 100).toStringAsFixed(3)}%), worst channel delta '
        '${result.worstChannel}.\n'
        '  expected ${reference.path}\n'
        '  actual   $actualPath',
      );
      exit(1);
    } catch (error, stack) {
      stderr.writeln('GOLDEN ${scene.name}: threw $error\n$stack');
      exit(2);
    }
  }

  Future<Uint8List> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      throw StateError('the reference image decoded to nothing');
    }
    return data.buffer.asUint8List();
  }

  _Comparison _compare(Uint8List expected, Uint8List actual) {
    if (expected.length != actual.length) {
      return _Comparison(
        differing: actual.length ~/ 4,
        total: actual.length ~/ 4,
        worstChannel: 255,
      );
    }

    var differing = 0;
    var worst = 0;
    for (var i = 0; i < actual.length; i += 4) {
      var delta = 0;
      // Alpha is compared too: a pass that stopped writing it would otherwise
      // go unnoticed until something tried to composite the result.
      for (var c = 0; c < 4; c++) {
        final d = (actual[i + c] - expected[i + c]).abs();
        if (d > delta) delta = d;
      }
      if (delta > worst) worst = delta;
      if (delta > channelTolerance) differing++;
    }

    return _Comparison(
      differing: differing,
      total: actual.length ~/ 4,
      worstChannel: worst,
    );
  }
}

final class _Comparison {
  const _Comparison({
    required this.differing,
    required this.total,
    required this.worstChannel,
  });

  final int differing;
  final int total;
  final int worstChannel;

  double get fraction => total == 0 ? 0.0 : differing / total;

  bool get withinTolerance => fraction <= GoldenRunner.pixelTolerance;
}
