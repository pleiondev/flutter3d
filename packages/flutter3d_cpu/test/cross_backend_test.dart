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

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
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
  // 0.633% measured. Screen-space reflections are a march, and the two
  // rasterisers disagree about where a ray ends — an edge inside the
  // reflection rather than an edge in the scene. The first number this feature
  // has ever produced on two backends: it was advertised for months and
  // compared nowhere.
  'screen-space-reflections': 0.65,
  // **7.647% measured, and this one is a defect budget rather than a floor.**
  // It belongs with the six below that were not multisampling, and it is here
  // for the same reason: the number is written down so that whoever fixes it
  // can watch it fall.
  //
  // The disagreement is not noise. The software rasteriser is *lighter* in
  // 12,842 of the 13,214 differing pixels — it occludes less than Impeller
  // does — the difference reaches 77 of 255 on a channel, and it sits in the
  // middle of the frame where the corner is, not around silhouettes. So the
  // two transcriptions of `ssao.frag` compute different amounts of occlusion,
  // and one of them is wrong.
  //
  // Found in the first minute the two were ever compared, which is the whole
  // argument for this scene existing: the effect shipped, was drawn by three
  // backends, and had a picture check on one.
  //
  // ## What it is not
  //
  // **Not the depth convention.** The browser had that bug and it was most of
  // its 4.861%: both passes that read the surface buffer were handed a
  // view-projection adjusted to the *device's* clip range, and compared the
  // result against `gl_FragCoord.z`, which is `[0, 1]` everywhere. This
  // backend's range is `[0, 1]` like Impeller's, so it never had it, and
  // fixing it moved this number by nothing at all.
  //
  // **Not the storage precision, which was worth measuring and was wrong.**
  // `CpuTexture` keeps every channel as a `double` whatever the format says,
  // so a target declared `r16g16b16a16Float` holds eleven bits of mantissa on
  // a GPU and fifty-three here — and the occlusion pass compares a stored
  // depth against a computed one twelve times a pixel. Rounding every write to
  // half precision made the disagreement **worse**, 7.647% to 10.694%, and
  // turned the systematic lightness into symmetric noise: 12,842 lighter
  // against 372 became 9,698 against 8,782. Quantising does not remove a
  // difference below the quantum, it promotes it — two values a hair apart
  // land either side of a half-step and disagree by the whole step. So the
  // bias is not precision, and a faithful-storage change would have to be made
  // for its own sake and measured again.
  //
  // What is left to try: the taps themselves. The frame's map says the
  // difference sits on the subject rather than on its silhouette, and this
  // backend occludes *less* — so the next thing to count is how many of the
  // twelve taps each backend rejects, and at which of the four `continue`s.
  'ambient-occlusion-corner': 7.7,

  // One number for all six, because all six measure the same thing now:
  // 0.431%, except `particles-recycled` at 0.417%. Set just above, which is
  // the rule this file is built on — a budget far from what was measured has
  // stopped watching.
  // The sky itself agrees exactly — every pixel of gradient, lobe and disc is
  // the same number on both backends, which is what a transcription is for.
  // What differs is the teapot's silhouette against it: 392 pixels of edge,
  // where one backend multisamples and the other does not. Measured 0.227%.
  'sky': 0.24,
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
  'instanced-field': 1.15,
  // 0.318% measured: the room is two lit quads, and the edge of each is the
  // whole of what the two backends disagree about.
  'lightmapped-room': 0.4,
  // 3.811% measured, and the one budget in this file that is a feature
  // rather than a floor. Impeller takes eight taps along the floor and this
  // backend answers `maxAnisotropy` of one and takes one — see
  // `CpuDevice.maxAnisotropy` — so the middle distance of the checkerboard
  // is sharp on one set and blurred on the other, on purpose; the far
  // reaches melt to one tone on both, which is why the number is not
  // larger. Set just above the measurement all the same: a narrower gap is
  // the filter being lost on Impeller, a wider one is a change in something
  // other than the filter.
  'anisotropic-floor': 4.0,
  // 0.614% measured. Three boxes on a floor, each with a shadow, and a
  // silhouette whose edge is the far cube's against the wall: more edge than
  // the one-cube scenes, and edges are what the two backends disagree on.
  // The silhouette's interior agrees exactly, as a flat colour has to.
  // Re-measured when the near cube was raised to overlap the far one on
  // screen, which is what the scene is recorded for: 0.641% before, 0.614%
  // after, so the notch costs these two backends nothing to agree on.
  'stencil-xray': 0.63,
  // 0.491% measured: two balls, five quads and the reflections in the balls,
  // and every differing pixel on a silhouette or on the rim of a reflection
  // where a face meets its neighbour — the same band the cube-shadow scenes
  // sit in. The probe's own chain agrees, which is the finding: a lobe
  // sampled bilinearly on one side and nearest on the other is still the
  // same lobe.
  'probe-car': 0.52,
  // 1.417% measured once model textures started carrying a mip chain. The rise
  // is the one difference this backend cannot close: it picks a level from a
  // per-triangle gradient, where hardware differences a quad of neighbouring
  // fragments — stated in `BoundTexture.sample`'s own docstring. Before the
  // chain existed every sample came from the base level, so the two backends
  // agreed by having nothing to disagree about.
  'normal-mapping': 1.5,
  // 0.490% measured. Shadow edges are where these two backends differ most,
  // one having multisampling and the other not, so anything that sharpens an
  // edge moves this number: fitting the volume to casters only pushed it to
  // 0.582%, and three cascades at a 1024 tile brought it back down, the near
  // cascade covering less world than one 2048 tile did. Set just above the
  // measurement, as every budget in this file is.
  // 0.398% measured, which is the number worth reading here rather than the
  // budget: it sits inside the band the cube-shadow scenes occupy (0.39 to
  // 0.49), and a cone that borrowed the point path correctly is a cone that
  // disagrees between backends by exactly as much as that path already did.
  // A spot that had gone its own way somewhere would show up as a scene with
  // its own noise floor.
  'spot-shadow': 0.46,
  // 0.495% measured. The teapot's silhouette, and then every band edge on
  // it: the loaded stage is a `step` over the normal's height, so the stripe
  // boundaries are one more set of edges for multisampling to soften on one
  // backend and not the other. The stage itself agrees — the bundle's Dart
  // twin is the GLSL line for line — which is what a transcription is for.
  'loaded-shader': 0.52,
  // 0.581% measured: the teapot on its floor with the exposure metered from
  // the frame. `shadow-teapot` is the same model on the same floor at the
  // setting's exposure and sits at 0.454%, so the two meters — one reading a
  // GPU's luminance target, one a transcription's — asked for exposures a
  // sixteenth of a stop apart at most, which is the byte they encode in, and
  // the extra tenth of a percent is the floor's gradient crossing the channel
  // threshold where the silhouette alone would not. Set just above, as every
  // budget in this file is.
  'auto-exposure': 0.6,
  'cube-shadow-mover': 0.56,
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
  // 0.361%, up from 0.21% when the scene drew neither normals nor a frustum.
  // Both are thin lines a pixel wide, which is the one thing two rasterisers
  // never place identically; the caption on the site says the picture has them
  // because it does now.
  'debug-overlay': 0.37,
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
    expect(
      recorded.difference(_budgets.keys.toSet()),
      isEmpty,
      reason: 'recorded by tool/golden.sh --cpu and not compared here',
    );
    expect(
      _budgets.keys.toSet().difference(recorded),
      isEmpty,
      reason: 'a budget for a scene this backend has no reference for',
    );
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

      final difference = compareFrames(pa, pb, channel: _channel);

      // Printed whether it passes or not. A comparison whose number nobody
      // sees is a threshold nobody can judge.
      // ignore: avoid_print
      print(
        '${entry.key}: $difference by more than $_channel, budget '
        '${entry.value}%',
      );

      expect(
        difference.percent,
        lessThanOrEqualTo(entry.value),
        reason: 'the software backend moved away from the hardware one',
      );
    });
  }
}
