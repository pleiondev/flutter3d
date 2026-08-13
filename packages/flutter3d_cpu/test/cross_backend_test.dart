/// How far the software backend lands from the hardware one, per scene.
///
///     flutter test test/cross_backend_test.dart
///
/// A comparison of two committed reference sets — this package's, in
/// `test/goldens`, against Impeller's, in `flutter3d/test/goldens` — so it
/// needs no device, no application and no twelve minutes. Recording either set
/// does; reading them does not.
///
/// **Why two sets rather than one.** Held against Impeller's pictures directly
/// the software backend can never reach zero: it answers
/// `preferredSampleCount` of one and means it, so every silhouette in every
/// scene differs. A shared reference set would therefore need a tolerance, and
/// a tolerance is a threshold that stops watching. So each backend is held to
/// zero against its own references — `tool/golden.sh` and `tool/golden.sh
/// --cpu` — which answers "did this backend change", and the distance between
/// the two sets is measured here, which answers "do they still draw the same
/// picture".
///
/// The budgets below are measurements, not guesses, and they are deliberately
/// close to what was measured. A budget far above the observed value has
/// stopped watching, which this repository has learned twice.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Per-scene ceiling on the share of pixels differing by more than [_channel].
///
/// Most of these are the same number — around a fifth of a percent — and that
/// number is multisampling. On `lighting-unlit`, 92% of the differing pixels
/// lie on the sphere's silhouette. A scene's budget is larger when it has more
/// edge: `normal-mapping` is a grid of tiles and every internal boundary is
/// one, which is the whole of its one percent.
///
/// The particle scenes were the exception and are not any more. They sat at
/// 4.85% and 10.3% while this backend honoured `setDepthWrite(false)` and
/// `flutter_gpu` ignored it; mirroring the engine's behaviour deliberately —
/// see `CpuEncoder.setDepthWrite` — brought `particle-stack` to the same
/// 0.431% as the scene with no particles in it at all, which is the cube's
/// silhouette and nothing else. The burst sits a little above that floor
/// because two hundred and twenty quads have edges of their own.
///
/// When the SDK is fixed these three will move and this table is what says so.
const Map<String, double> _budgets = <String, double>{
  'particle-stack': 0.50,
  'particles-burst': 0.70,
  // A pool that has been round several times, which every other particle
  // fixture is blind to. Slightly above the burst because more of its quads
  // are near an edge.
  'particles-recycled': 0.55,
  'particles-plain': 0.70,
  'normal-mapping': 1.1,
  'cube-shadow-mover': 0.55,
  'cube-shadow-lit': 0.55,
  'shadow-teapot': 0.52,
  'particle-one': 0.50,
  'particles-none': 0.50,
  'cube-shadow-gap': 0.45,
  'view-model-point-shadow': 0.40,
  'view-model-overlay': 0.40,
  'lighting-unlit': 0.27,
  'teapot-generated-normals': 0.27,
  'lighting-normals': 0.26,
  'lighting-toon': 0.26,
  'bloom-sphere': 0.25,
  'lighting-blinnphong': 0.24,
  'lighting-lambert': 0.24,
  'lighting-pbr': 0.24,
  'skinned-figure': 0.22,
  'debug-overlay': 0.21,
  'surface-buffer': 0.02,
  'cube-shadow': 0.02,
  'cube-shadow-crowded': 0.02,
  'cube-shadow-many': 0.02,
  'shadow-map': 0.02,
};

/// How far apart two channels may be before the pixel counts as differing.
///
/// Eight, which is what `tool/golden.sh` uses, so the two comparisons mean the
/// same thing by "differ".
const int _channel = 8;

Future<Uint8List> _rgba(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mine = Directory('test/goldens');
  final theirs = Directory('../flutter3d/test/goldens');

  test('every recorded scene has a budget and every budget a scene', () {
    // Both directions. A scene recorded and never compared is a picture nobody
    // looks at; a budget for a scene that no longer exists is a line that can
    // never fail and will outlive everyone who understood it.
    final recorded = mine
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.png') && !n.endsWith('.actual.png'))
        .map((n) => n.substring(0, n.length - 4))
        .toSet();
    expect(recorded.difference(_budgets.keys.toSet()), isEmpty,
        reason: 'recorded by tool/golden.sh --cpu and not compared here');
    expect(_budgets.keys.toSet().difference(recorded), isEmpty,
        reason: 'a budget for a scene this backend has no reference for');
  });

  for (final entry in _budgets.entries) {
    test('cpu and impeller draw ${entry.key} the same picture', () async {
      final a = File('${mine.path}/${entry.key}.png');
      final b = File('${theirs.path}/${entry.key}.png');
      expect(a.existsSync(), isTrue, reason: '${a.path} is missing');
      expect(b.existsSync(), isTrue, reason: '${b.path} is missing');

      final pa = await _rgba(a);
      final pb = await _rgba(b);
      expect(pa.length, pb.length, reason: 'the two are different sizes');

      var differing = 0;
      var worst = 0;
      for (var i = 0; i < pa.length; i += 4) {
        var d = 0;
        for (var c = 0; c < 3; c++) {
          final delta = (pa[i + c] - pb[i + c]).abs();
          if (delta > d) d = delta;
        }
        if (d > _channel) differing++;
        if (d > worst) worst = d;
      }
      final pixels = pa.length ~/ 4;
      final percent = 100.0 * differing / pixels;

      // Printed whether it passes or not. A comparison whose number nobody
      // sees is a threshold nobody can judge.
      // ignore: avoid_print
      print('${entry.key}: $differing of $pixels differ by more than '
          '$_channel (${percent.toStringAsFixed(3)}%, budget '
          '${entry.value}%), worst channel $worst');

      expect(percent, lessThanOrEqualTo(entry.value),
          reason: 'the software backend moved away from the hardware one');
    });
  }
}
