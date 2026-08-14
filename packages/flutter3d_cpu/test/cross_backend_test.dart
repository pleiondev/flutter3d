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
/// **Every particle scene now sits at the same 0.431% as the scene with no
/// particles in it**, which is the cube's silhouette and nothing else. That is
/// the end of a three-stage story worth keeping in one place:
///
///  1. This backend honoured `setDepthWrite(false)` and `flutter_gpu` did not,
///     so the particle scenes sat at 4.85% and 10.3%.
///  2. This backend mirrored the engine's bug deliberately, which brought them
///     down to roughly this floor — at the cost of both backends drawing the
///     same wrong picture.
///  3. SDK 3.47 fixed the setter, the mirror came out, and both were
///     re-recorded. They agree again, and now they agree on the right picture.
///
/// Two hundred and twenty additive quads contributing *no* pixels beyond the
/// floor is not an accident: the divergence between these backends is
/// multisampling on silhouettes, and an additive quad's edge deposits too
/// little to cross a channel threshold of eight.
const Map<String, double> _budgets = <String, double>{
  // One number for all six, because all six measure the same thing now:
  // 0.431%, except `particles-recycled` at 0.417%. Set just above, which is
  // the rule this file is built on — a budget far from what was measured has
  // stopped watching.
  'particle-stack': 0.45,
  'particles-burst': 0.45,
  // A pool that has been round several times, which every other particle
  // fixture is blind to.
  'particles-recycled': 0.45,
  'particles-plain': 0.45,
  // Four sprites at four distances, each on a different level of a mip chain.
  // At the particle floor, which is the finding: the software backend picks its
  // levels from a per-triangle gradient rather than from a quad of neighbouring
  // fragments, and on quads facing the camera the two agree.
  'particles-textured': 0.47,
  // Five spheres, and therefore five curved silhouettes where every other
  // particle scene has straight-edged quads. The gap between these backends is
  // multisampling on edges, so a budget above the particle floor is the shape
  // of the fixture rather than a fault in it — measured at 0.716%.
  'particles-mesh': 0.75,
  'normal-mapping': 1.1,
  'cube-shadow-mover': 0.55,
  'cube-shadow-lit': 0.55,
  'shadow-teapot': 0.52,
  'particle-one': 0.45,
  'particles-none': 0.45,
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
