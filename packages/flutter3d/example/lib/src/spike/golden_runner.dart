import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d/flutter3d.dart';
import 'package:path/path.dart' as p;

import 'golden_scene.dart';
import 'golden_scenes.dart';
import 'golden_store.dart';
import 'png.dart';

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
  /// **Zero**, and it was not always. It stood at 0.002 — 345 pixels of this
  /// frame — on the argument that MSAA resolve order and the driver's own
  /// floating-point choices move a handful of edge pixels between runs. The
  /// measurement says otherwise: every scene has reported *0 of 172800*
  /// differing since the composite became a node, so the slack was never
  /// absorbing driver noise. It was absorbing changes, and it absorbed a real
  /// shader change for two commits before anybody read a count.
  ///
  /// What the driver's noise actually moves is [channelTolerance], not this.
  /// `surface-buffer` regularly reports a worst channel of 3 while differing in
  /// no pixels at all — a value under the channel limit is not a differing
  /// pixel, so the count stays zero and the run stays honest. That is the knob
  /// that pays for hardware variance, and it stays where it is.
  static const double pixelTolerance = 0.0;

  /// How far one channel may move before a pixel counts as different.
  ///
  /// This is where driver variance is paid for, and why [pixelTolerance] does
  /// not have to. Eight is comfortably above the worst any scene has shown
  /// (three, on the surface buffer) and far below anything a person would call
  /// a change in the picture.
  static const int channelTolerance = 8;

  int _seen = 0;
  bool _done = false;

  /// Null unless `FLUTTER3D_GOLDEN` names a scene.
  static GoldenRunner? fromEnvironment() {
    // The URL wins where there is one, so a single web build can be walked
    // through every scene. Empty everywhere means this is not a golden run.
    const defined = String.fromEnvironment('FLUTTER3D_GOLDEN');
    final name = sceneOverride ?? defined;
    if (name.isEmpty) return null;

    final scene = goldenSceneNamed(name);
    if (scene == null) {
      printLine(
        'FLUTTER3D_GOLDEN: no scene named "$name". Known scenes:\n'
        '${kGoldenScenes.map((s) => '  ${s.name}').join('\n')}',
      );
      finish(2);
    }

    const configured =
        String.fromEnvironment('FLUTTER3D_GOLDEN_DIR', defaultValue: '');
    // Only where a directory means something. In a browser the references come
    // over HTTP from the server that served the page, so there is no path to
    // validate — and demanding one is how a golden run in a browser ends before
    // it renders anything.
    if (needsReferenceDirectory &&
        (configured.isEmpty || !p.isAbsolute(configured))) {
      // Not a default worth guessing at. A macOS application bundle runs with
      // its working directory set to the root of the filesystem, so a relative
      // path here resolves somewhere unwritable and the failure arrives as a
      // permission error three seconds into a render.
      printLine(
        'FLUTTER3D_GOLDEN_DIR must be an absolute path to the reference '
        'directory. tool/golden.sh passes one; a bare `flutter run` has to be '
        'given it by hand.',
      );
      finish(2);
    }

    return GoldenRunner._(
      scene,
      update: const bool.fromEnvironment('FLUTTER3D_GOLDEN_UPDATE'),
      directory: configured,
    );
  }

  /// Which frame to grab.
  ///
  /// Late enough for the model to have loaded and for the ticker to have settled;
  /// the scene's own clip time is pinned separately, so this only has to be
  /// "after everything is ready" rather than a specific moment.
  static const int captureFrame = 90;

  void offer(GraphicsDevice device, FrameResult frame) {
    if (_done) return;
    if (++_seen < captureFrame) return;
    _done = true;
    unawaited(_run(device, frame));
  }

  Future<void> _run(GraphicsDevice device, FrameResult frame) async {
    try {
      // Off the handle, not off an image: the texture carries its own
      // description, so this no longer needs the frame to have been turned
      // into something Flutter can draw before it can be measured.
      final target = frame.frame;
      if (target.width != scene.width || target.height != scene.height) {
        printLine(
          'GOLDEN ${scene.name}: rendered ${target.width}x${target.height}, '
          'expected ${scene.width}x${scene.height}. The golden path must fix '
          'the render size, or the result depends on the window.',
        );
        finish(1);
      }

      final actual = await device.readPixels(target);
      if (actual == null) {
        printLine('GOLDEN ${scene.name}: the frame read back as nothing.');
        finish(1);
      }

      if (update) {
        final png = await encodePng(actual, target.width, target.height);
        final path = await writeReference(directory, scene.name, png!);
        printLine('GOLDEN ${scene.name}: recorded $path');
        finish(0);
      }

      final referenceBytes = await readReference(directory, scene.name);
      if (referenceBytes == null) {
        printLine(
          'GOLDEN ${scene.name}: no reference at '
          '${describe(directory, scene.name)}. Record one with '
          'tool/golden.sh --update.',
        );
        finish(1);
      }

      final expected = await _decode(referenceBytes);
      final result = _compare(expected, actual.buffer.asUint8List());

      if (result.withinTolerance) {
        printLine(
          'GOLDEN ${scene.name}: PASS '
          '(${result.differing} of ${result.total} pixels differ, worst '
          '${result.worstChannel})',
        );
        finish(0);
      }

      // The actual frame is written beside the reference so the two can be
      // opened side by side. A number alone does not say whether the lighting
      // shifted or the model moved.
      final png = await encodePng(actual, target.width, target.height);
      final actualPath = await writeActual(directory, scene.name, png!);

      printLine(
        'GOLDEN ${scene.name}: FAIL — ${result.differing} of ${result.total} '
        'pixels differ by more than $channelTolerance '
        '(${(result.fraction * 100).toStringAsFixed(3)}%, limit '
        '${(pixelTolerance * 100).toStringAsFixed(3)}%), worst channel delta '
        '${result.worstChannel}.\n'
        '  expected ${describe(directory, scene.name)}\n'
        '  actual   $actualPath',
      );
      finish(1);
    } catch (error, stack) {
      printLine('GOLDEN ${scene.name}: threw $error\n$stack');
      finish(2);
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


/// Where a golden run says what happened.
///
/// `print` rather than stdout/stderr: those are `dart:io`, and this runs in a
/// browser too. `flutter run` forwards print to the console the harness reads,
/// so the desktop path is unchanged.
void printLine(String message) {
  // ignore: avoid_print
  print(message);
  // And onto the page, where a browser can show it. See golden_store_web.dart:
  // print alone does not survive a release web build.
  reportLine(message);
}
