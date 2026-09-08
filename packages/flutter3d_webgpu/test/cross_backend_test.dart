/// How far this backend lands from the hardware one, per scene.
///
///     flutter test test/cross_backend_test.dart
///
/// A comparison of two committed reference sets — this package's, in
/// `test/goldens`, against Impeller's, in `flutter3d/test/goldens` — so it needs
/// no browser, no device and no build. Recording either set does; reading them
/// does not. `flutter3d_webgl/test/cross_backend_test.dart` and
/// `flutter3d_cpu/test/cross_backend_test.dart` ask the same question of their
/// own sets, and this is deliberately their third sibling.
///
/// **Impeller as the reference, and here that choice is nearly free.** The other
/// two siblings measure a backend against a rasteriser that disagrees with it
/// about multisampling, about the framebuffer's origin, or about the clip
/// range, so their tables are pages of tenths of a percent explaining
/// silhouettes. This backend shares all three answers with Impeller — top-left
/// origin, depth in `[0, 1]`, four samples — and both end up as Metal shaders on
/// the same Apple GPU: Impeller's through impellerc, these through the WGSL the
/// translator writes and Chrome's own compiler. What that produces is in the
/// table below, and it is not a tenth of a percent. It is zero — `0 of 172800`
/// on forty of the forty-two pictures this set holds, with a worst channel of
/// zero on all but two of them.
///
/// `probe-car` is the newest of the forty and the one that had least right to
/// land there. It is six views of a room captured into a cube and convolved
/// down a chain of levels on the device, arithmetic that the other browser
/// backend lands a quarter of a percent away from Impeller with; here the
/// mirrored ball's reflection is the same picture to the texel, because the
/// convolution runs from the same GLSL through two Metal compilers on one GPU.
///
/// The other two are the two cube-atlas scenes, and what stands between them and
/// zero is on Impeller's side rather than this one: their references there were
/// recorded from a scene that was still being built, this backend now draws the
/// finished one, and the difference is the size of that. Their entries say it
/// with numbers.
///
/// **A table of zeroes is a strong instrument and a demanding one.** There is no
/// silhouette noise here for a change to hide in, so anything that moves at all
/// shows up whole; the price is that a picture only belongs in it if the backend
/// draws the same one twice. One of the forty-three does not qualify, and
/// [_refused] says which and why. It was four: two came back as a coin toss and
/// were left unrecorded rather than have one face of it written down, and one
/// came back without the reflection it exists to show. The toss has since been
/// explained and stopped, the reflection has since been turned on, and all
/// three are recorded.
///
/// **What is *not* in this table, and was expected to be.** Two shaders feed
/// `gl_FragCoord.xy` to a hash — the interleaved gradient noise that rotates the
/// point-shadow filter in `lib/surface.glsl`, and the film grain in
/// `post/composite.frag` — so a backend whose fragment coordinate counts rows
/// from the other end draws a different noise pattern by construction, not by
/// mistake. That is a real difference between the two *browser* backends: WebGL2
/// puts row zero at the bottom. It is not one here. WGSL's
/// `@builtin(position)`, which is what the translator hands `gl_FragCoord`,
/// counts rows from the top exactly as Metal does, and the device says so —
/// `framebufferOrigin` is `topLeft` on this backend and on Impeller, and
/// `bottomLeft` only on WebGL2. The scenes that would have shown it are
/// `cube-shadow-lit`, `cube-shadow-gap`, `cube-shadow-mover`, `spot-shadow` and
/// `view-model-point-shadow` — the ones that light through a point or spot
/// shadow and so run the rotated filter — and all five are at zero. The grain
/// never entered it at all: `LookSettings.grain` defaults to zero and no scene
/// in this suite turns it on, so that second hash is dead code in every picture
/// here and was never going to show a difference either way. A tolerance
/// written for any of this would have been a tolerance for nothing, sitting
/// over the one comparison in this repository that can afford to demand
/// equality.
///
/// **`@TestOn('vm')`, and that is not incidental.** Every other test in this
/// package runs in a browser, because the thing under test is a browser backend;
/// this one reads two directories of PNGs and needs `dart:io`, which a browser
/// does not have. `tool/ci.sh` runs the package both ways — the package loop
/// headless for the files, a named step in Chrome for the pictures — and without
/// the annotation the browser pass drags this in and every case fails on a
/// missing library rather than on a picture.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_cpu/flutter3d_cpu.dart' show compareFrames;
import 'package:flutter_test/flutter_test.dart';

/// Per channel, on 0..255. The same number the other three sets are compared
/// at, so "differ" means one thing across all of them.
const int _channel = 8;

/// Per-scene ceiling on the share of pixels differing by more than [_channel].
///
/// Measured on 2026-09-08 against the set Impeller recorded on the same SDK, by
/// recording this whole set in one pass of
/// `flutter3d_webgl/tool/golden_web.sh --backend=webgpu --update`, and the two
/// cube-atlas scenes in a second pass of the same command on the same day, once
/// they had stopped drawing two pictures. `probe-car` is a third pass of it, on
/// the day `supportsRenderToMip` became true, and was compared three times over
/// against the same reference before its number was written down.
///
/// **A hundredth of a percent is what an exact agreement is written as.** It is
/// the floor the sibling files already use for a scene that came out at zero,
/// and the reason for a floor rather than a literal zero is the same here as
/// there: a budget of zero between two rasterisers fails on the next driver
/// update rather than on a mistake. A hundredth of a percent of this frame is
/// seventeen pixels, which no driver has ever moved and no change worth catching
/// stays under.
///
/// So every entry below is that floor, and every one is that floor because the
/// measurement was `0 of 172800` — not a rounded small number. Two came back
/// with a worst channel of one rather than zero, `lightmapped-room` and
/// `lighting-normals`, which is a single unit in a single channel and not a
/// differing pixel at any threshold this repository uses.
///
/// **Two entries are not that floor, and neither of them is this backend.**
/// `cube-shadow-many` and `cube-shadow-crowded` are the pair whose atlas rows
/// used to be handed out before the model had landed — see the paragraph
/// on each. The demo now holds a golden's surface back until the scene it names
/// is staged, so both are drawn the same way every run, on every backend; what
/// they are compared against is the picture Impeller recorded before that, and
/// the number on each line is the size of the arrangement that changed. Both go
/// to the floor the moment `flutter3d/tool/golden.sh --update` is run over the
/// pair, and until it is, the honest reading of these two lines is "the
/// reference on the other side is older than the fix", not "this backend is
/// three per cent away from Impeller".
///
/// Kept one per line and in the suite's own order rather than collapsed into a
/// loop over a list: a scene that starts disagreeing gets its number and its
/// paragraph on the line where its name already is, which is how the two
/// siblings grew every explanation they carry.
const Map<String, double> _budgets = <String, double>{
  'teapot-generated-normals': 0.01,
  'shadow-teapot': 0.01,
  'bloom-sphere': 0.01,
  'normal-mapping': 0.01,
  'skinned-figure': 0.01,
  'morph-cube': 0.01,
  'morph-skinned': 0.01,
  'debug-overlay': 0.01,
  'particles-burst': 0.01,
  'particles-none': 0.01,
  'particles-recycled': 0.01,
  'particles-textured': 0.01,
  'particles-mesh': 0.01,
  'instanced-field': 0.01,
  // A bundle handed to this backend as bytes rather than compiled into it: the
  // packers write a `webgpu` section beside the other two now, and the stage in
  // it draws the same picture Impeller draws from the same GLSL.
  'loaded-shader': 0.01,
  'lightmapped-room': 0.01,
  'anisotropic-floor': 0.01,
  'stencil-xray': 0.01,
  'probe-car': 0.01,
  'particle-stack': 0.01,
  'particle-one': 0.01,
  'particles-plain': 0.01,
  'view-model-overlay': 0.01,
  'view-model-point-shadow': 0.01,
  'surface-buffer': 0.01,
  'shadow-map': 0.01,
  'cube-shadow': 0.01,
  'cube-shadow-lit': 0.01,
  'cube-shadow-many': 0.01,
  'cube-shadow-mover': 0.01,
  'cube-shadow-gap': 0.01,
  'spot-shadow': 0.01,
  'cube-shadow-crowded': 0.01,
  'sky': 0.01,
  'auto-exposure': 0.01,
  'screen-space-reflections': 0.01,
  'ambient-occlusion-corner': 0.01,
  'lighting-unlit': 0.01,
  'lighting-lambert': 0.01,
  'lighting-blinnphong': 0.01,
  'lighting-pbr': 0.01,
  'lighting-toon': 0.01,
  'lighting-normals': 0.01,
};

/// Scenes this set holds no picture of, and why the picture was refused.
///
/// **This is not the sibling's `_provisional`, and the difference is the whole
/// point.** There a name means "the recording has not happened yet" and the set
/// empties itself as the pictures arrive. Here a name means the recording was
/// attempted, the stand ran the scene, and what came back was not something a
/// reference could be made of — so writing one down would turn a refusal or a
/// coin toss into agreement, and the comparison would pass for ever on a frame
/// that proves nothing.
///
/// The one entry left is a frame the backend never reached, and a picture of
/// that would keep passing on the day the tooling arrives.
///
/// **`probe-car` used to be beside it, and it left the way an entry here is
/// supposed to.** It said the mirrored ball came back black because
/// `supportsRenderToMip` was false. The capability is true now, the scene
/// records, and it moved into [_budgets] at the floor — the reflection agrees
/// with Impeller's pixel for pixel. What the entry bought in the meantime is
/// the whole argument for this table: it kept a black ball from being written
/// down as agreement, and it named the capability to lift rather than leaving
/// an unexplained hole in the set.
///
/// **There was a second kind here, and it is worth remembering that there was.**
/// A pair of them came back drawn two different ways — the same silhouettes in
/// different rows of the shadow atlas, one arrangement or the other, never a
/// spread between them — and a picture of either would have failed at random,
/// which is worse than a refusal because the fix that suggests itself is to
/// record it again. They are recorded now, and what made the difference was not
/// a change to this backend at all: the demo was handing the renderer a scene
/// whose lights had not been placed yet, and this backend, whose model load
/// usually finishes before the first frame rather than after it, was the only
/// one that saw both answers. See `cube-shadow-many` in [_budgets].
///
/// Every reason below is a measurement from the recording run or from the
/// repeats that followed it, not a reading of the source.
/// **Empty, and it took four entries leaving to make it so.** Two scenes were
/// left unrecorded because the backend drew one of two atlas layouts and a
/// reference would have been one toss of that coin; the race behind it was found
/// in the demo rather than in this backend, and both were recorded once it was
/// stopped. `probe-car` came back without the reflection it exists to show,
/// because `supportsRenderToMip` was false; the capability is true now.
/// `loaded-shader` never reached a frame, because the packers wrote an
/// `impeller` section and a `webgl` section and no third one; they write WGSL
/// now. This set holds every scene the other three hold.
const Map<String, String> _refused = <String, String>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mine = Directory('test/goldens');
  final theirs = Directory('../flutter3d/test/goldens');

  test('every recorded scene has a budget and every budget a scene', () {
    // Both directions, for the reason the siblings give: a scene recorded and
    // never compared is a picture nobody looks at, and a budget for a scene
    // that no longer exists is a line that can never fail.
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
      reason:
          'recorded by golden_web.sh --backend=webgpu --update and not '
          'compared here',
    );
    expect(
      _budgets.keys.toSet().difference(recorded),
      isEmpty,
      reason: 'a budget for a scene this backend has no reference for',
    );
  });

  test('a refused scene has a reason and no picture', () {
    // The half that stops [_refused] from outliving what it describes. Record
    // the picture and leave the name here, and this fails: the refusal has been
    // lifted and the entry is a sentence that is no longer true. It is the same
    // shape as the sibling's check on `_provisional`, asking the opposite
    // question of the same directory.
    for (final entry in _refused.entries) {
      expect(
        File('${mine.path}/${entry.key}.png').existsSync(),
        isFalse,
        reason:
            'this set now holds ${entry.key}, so the refusal recorded as '
            '"${entry.value}" no longer holds. Take it out of _refused and '
            'give it a measured budget.',
      );
      expect(
        File('${theirs.path}/${entry.key}.png').existsSync(),
        isTrue,
        reason:
            '${entry.key} is refused here but Impeller has no picture of it '
            'either, so the name is stale rather than a refusal',
      );
      expect(
        _budgets.containsKey(entry.key),
        isFalse,
        reason: 'a refused scene has nothing to compare, so it has no budget',
      );
    }
  });

  for (final entry in _budgets.entries) {
    test('webgpu and impeller draw ${entry.key} the same picture', () async {
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
