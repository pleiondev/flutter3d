/// How wide the lobe `EnvironmentMap.prefilter` gathers actually is.
///
///     dart test test/engine/environment_prefilter_lobe_test.dart
///
/// **Measured against a picture whose answer is known in closed form.** Every
/// face of the source is white except +Z, which is black, and the texel read
/// looks straight at the black face. Whatever white a level reports there is
/// the share of its lobe that reaches past the face's edges, 45° out at the
/// nearest point — so the number is the lobe's width, read off directly.
///
/// The tap construction used to scale each tap's sideways part by the
/// unwarped spiral radius times one minus the warped cosine, which pulled
/// every tap far inside the lobe it was meant to sample: a level of roughness
/// one-half reported pure black here, and the fully rough level, which the lit
/// shaders read as the diffuse term, reported a fifth where a cosine
/// convolution reports nearly half.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

/// Six faces of [side], white but for a black +Z.
List<ByteData> _blackFront(int side) => <ByteData>[
  for (var face = 0; face < 6; face++)
    () {
      final level = face == 4 ? 0 : 255;
      final data = ByteData(side * side * 4);
      for (var i = 0; i < side * side; i++) {
        data
          ..setUint8(i * 4, level)
          ..setUint8(i * 4 + 1, level)
          ..setUint8(i * 4 + 2, level)
          ..setUint8(i * 4 + 3, 255);
      }
      return data;
    }(),
];

/// Red of texel ([x], [y]) of [face], as a fraction of full.
double _red(ByteData face, int side, int x, int y) =>
    face.getUint8((y * side + x) * 4) / 255.0;

/// The cosine-weighted share of the hemisphere about +Z that falls outside
/// the +Z face: one minus the view factor from the cube's centre to a square
/// of half-width one at distance one, four corner rectangles of the standard
/// parallel-rectangle form. 0.4459.
final double _lambertOutsideFace =
    1.0 - 4.0 / (math.pi * math.sqrt2) * math.atan(1.0 / math.sqrt2);

void main() {
  group('the prefilter lobe', () {
    test('at full roughness is the cosine convolution the diffuse term '
        'reads it as', () {
      // Size sixteen and four levels, so the last level is one texel a face
      // and that texel looks exactly along +Z.
      //
      // Mutation: scale the tap's sideways part by anything short of the
      // half vector's full sine (the old `radius * (1 - spread)`) — this
      // reads about 0.20 and fails.
      final chain = EnvironmentMap.prefilter(
        _blackFront(16),
        size: 16,
        levels: 4,
      )!;
      final rough = _red(chain.last[4], 1, 0, 0);
      expect(rough, closeTo(_lambertOutsideFace, 0.03));
    });

    test('at roughness one-half reaches past a face 45° away', () {
      // A GGX lobe of roughness one-half (alpha one-quarter) about a mirror
      // direction sends about a tenth of its cosine weight beyond 45°; the
      // old construction sent none. The four texels nearest the centre of a
      // sixteen-pixel level, averaged, sit five degrees off the axis.
      //
      // Mutation: the old tap construction reads 0.0 here; taking alpha as
      // the roughness itself rather than its square reads about 0.26 and
      // climbs past the ceiling.
      final chain = EnvironmentMap.prefilter(
        _blackFront(32),
        size: 32,
        levels: 2,
      )!;
      final level = chain.first[4];
      final mid =
          (_red(level, 16, 7, 7) +
              _red(level, 16, 8, 7) +
              _red(level, 16, 7, 8) +
              _red(level, 16, 8, 8)) /
          4.0;
      expect(mid, inInclusiveRange(0.07, 0.16));
    });
  });
}
