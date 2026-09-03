/// How far this backend lands from the hardware one, per scene.
///
///     flutter test test/cross_backend_test.dart
///
/// A comparison of two committed reference sets — this package's, in
/// `test/goldens`, against Impeller's, in `flutter3d/test/goldens` — so it needs
/// no browser, no device and no build. Recording either set does; reading them
/// does not. The software backend's equivalent lives in
/// `flutter3d_cpu/test/cross_backend_test.dart` and this is deliberately its
/// twin.
///
/// **Why this backend records its own set.** Held against Impeller's pictures
/// directly it can never reach zero — a different rasteriser, a different
/// shader compiler and a different multisample resolve disagree in the last
/// bits of every silhouette. So each backend is held to zero against its own
/// references, which answers "did this backend change", and the distance
/// between the sets is measured here, which answers "do they still draw the
/// same picture". A shared set would need one tolerance doing both jobs, and a
/// tolerance is a threshold that stops watching.
///
/// **`@TestOn('vm')`, and that is not incidental.** Every other test in this
/// package runs in a browser, because the thing under test is a browser
/// backend; this one reads two directories of PNGs and needs `dart:io`, which a
/// browser does not have. `tool/ci.sh` runs the package both ways — headless for
/// the files, `--platform chrome` for the pictures — and without the annotation
/// the browser pass drags this in and every case fails on a missing library
/// rather than on a picture.
///
/// **The budgets below are measurements, and none of them is a defect any
/// more.** That distinction is the point of the file: a number near a fifth of
/// a percent is multisampling on a silhouette and nothing to do; a number in
/// whole percents is this backend drawing something else. Six scenes were in
/// the second group and every one of them has been moved to the first, so the
/// whole table is now a floor to hold rather than a list of things to fix.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_cpu/flutter3d_cpu.dart' show compareFrames;
import 'package:flutter_test/flutter_test.dart';

/// Per channel, on 0..255. The same number the other two sets are compared at.
const int _channel = 8;

/// Per-scene ceiling on the share of pixels differing by more than [_channel].
///
/// Measured on 2026-08-25 against the set Impeller recorded on the same SDK,
/// and rounded up by a hair rather than to a round number: a budget far above
/// what was observed has stopped watching.
///
/// ## The six that were not multisampling
///
/// All six are fixed. They are kept here because each was a way for this
/// backend to draw the wrong picture while every check available said it was
/// drawing the right one, and that is the reusable part.
///
/// `lighting-unlit` was 11.1% — an empty frame, the sphere not drawn at all —
/// because the translated shader declared a `PointShadow` block the engine
/// correctly never bound, and WebGL2 discards every draw with an active block
/// that has no buffer under it.
///
/// `particles-mesh` was 19.1%, and the mesh particles were never the problem:
/// the checkerboard cube behind them came back a flat average of itself. The
/// mesh-particle draw is the engine's only instanced one, `vertexAttribDivisor`
/// is state of an attribute location rather than of a draw, and nothing put it
/// back — so the next frame's mesh read one texture coordinate for the whole
/// quad.
///
/// `bloom-sphere` was 7.4% and `debug-overlay` 2.5%, and they were one bug. The
/// full-screen triangle pairs clip positions with texture coordinates directly,
/// so on a backend whose row zero is at the bottom every full-screen pass turned
/// its input over. A single pass that reads the frame and writes the frame
/// survives that; the bloom chain is a threshold, a ladder down and a ladder
/// back — an odd number of passes however it is configured — so the glow was
/// composited mirrored about the middle of the frame. Every scene in the golden
/// set has its subject in the middle, which is exactly where a mirrored glow
/// lands on top of the real one.
///
/// `view-model-point-shadow` was 2.6%, `cube-shadow-mover` 1.9% and
/// `cube-shadow-lit` 1.3%, and they were one bug with the same shape. The cube
/// atlas is stored bottom-up here, so a light in slot zero is drawn into the row
/// the shader would call three and the picture inside that tile is upside down
/// as well; the lookup now turns the whole atlas over, which fixes the row and
/// the tile together. **Read that one beside the three scenes that were exactly
/// zero throughout** — `cube-shadow`, `cube-shadow-many` and
/// `cube-shadow-crowded`, which composite the atlas rather than light with it.
/// A composite is a full-screen pass, a full-screen pass turned its input over,
/// and so the view built to check the atlas cancelled the very error it was
/// pointed at and agreed with Impeller to the pixel for six sessions.
///
const Map<String, double> _budgets = <String, double>{
  'normal-mapping': 0.6,
  'cube-shadow-mover': 0.4,
  'cube-shadow-lit': 0.4,
  'shadow-teapot': 0.3,
  'spot-shadow': 0.3,
  'cube-shadow-gap': 0.3,
  'sky': 0.2,
  'teapot-generated-normals': 0.2,
  'view-model-overlay': 0.2,
  'lighting-normals': 0.2,
  'lighting-unlit': 0.2,
  'lighting-toon': 0.2,
  'lighting-pbr': 0.2,
  'lighting-blinnphong': 0.2,
  'lighting-lambert': 0.2,
  'view-model-point-shadow': 0.2,
  'bloom-sphere': 0.1,
  'skinned-figure': 0.1,
  'particles-textured': 0.1,
  'particles-mesh': 0.2,
  'instanced-field': 0.42,
  'lightmapped-room': 0.15,
  // Provisional; recorded at merge. A checkerboard floor seen along its
  // length with eight-way anisotropy on both backends — what differs is how
  // far each driver's taps reach, and that is measured once the picture is.
  //
  // Expect the measurement to land well above this, and not because of the
  // anisotropy: this backend never sets a `*_MIPMAP_*` minification filter —
  // `minMagFilterToGl` ignores `mipFilter` — so its taps are taken from the
  // base level, where Impeller's are taken across the chain. Until the
  // filter is derived from the pair (see the 0.4.3 changelog), the far half
  // of the floor here is the base level's aliasing and Impeller's is not.
  // Whoever records this: the gap is the mip filter, not the taps.
  'anisotropic-floor': 0.5,
  'cube-shadow': 0.01,
  'cube-shadow-many': 0.01,
  'cube-shadow-crowded': 0.01,
  'particle-one': 0.01,
  'particle-stack': 0.01,
  'particles-burst': 0.01,
  'particles-none': 0.01,
  'particles-plain': 0.01,
  'particles-recycled': 0.01,
  'debug-overlay': 0.01,
  'shadow-map': 0.01,
  'surface-buffer': 0.01,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mine = Directory('test/goldens');
  final theirs = Directory('../flutter3d/test/goldens');

  test('every recorded scene has a budget and every budget a scene', () {
    // Both directions, for the reason the software backend's twin gives: a
    // scene recorded and never compared is a picture nobody looks at, and a
    // budget for a scene that no longer exists is a line that can never fail.
    final recorded = mine
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.png') && !n.endsWith('.actual.png'))
        .map((n) => n.substring(0, n.length - 4))
        .toSet();
    expect(
      recorded.difference(_budgets.keys.toSet()),
      isEmpty,
      reason: 'recorded by tool/golden_web.sh --update and not compared here',
    );
    expect(
      _budgets.keys.toSet().difference(recorded),
      isEmpty,
      reason: 'a budget for a scene this backend has no reference for',
    );
  });

  for (final entry in _budgets.entries) {
    test('webgl and impeller draw ${entry.key} the same picture', () async {
      final a = File('${mine.path}/${entry.key}.png');
      final b = File('${theirs.path}/${entry.key}.png');
      expect(a.existsSync(), isTrue, reason: '${a.path} is missing');
      expect(b.existsSync(), isTrue, reason: '${b.path} is missing');

      final pa = await _rgba(a);
      final pb = await _rgba(b);
      expect(pa.length, pb.length, reason: 'the two are different sizes');

      final difference = compareFrames(pa, pb, channel: _channel);

      // Printed whether it passes or not: a comparison whose number nobody sees
      // is a threshold nobody can judge.
      // ignore: avoid_print
      print(
        '${entry.key}: $difference by more than $_channel, budget '
        '${entry.value}%',
      );

      expect(
        difference.percent,
        lessThanOrEqualTo(entry.value),
        reason: 'this backend moved away from the hardware one',
      );
    });
  }
}

Future<Uint8List> _rgba(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('${file.path} could not be read as RGBA');
  return data.buffer.asUint8List();
}
