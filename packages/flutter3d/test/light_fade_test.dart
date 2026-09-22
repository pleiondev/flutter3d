/// `gfx-05n`: the edge of a draw's light list stops being a cliff.
///
///     flutter test test/light_fade_test.dart
///
/// **What ranking correctly does not fix.** `light_selection_test.dart` covers
/// the choice: with more lights than the shader's eight slots, each object is
/// told about the eight that actually reach it, scored by the shader's own
/// attenuation term. That is the right eight — and it is still a hard cut-off.
/// Walk a camera down a corridor of forty torches and the eighth slot changes
/// hands every few metres; the light leaving was contributing whatever the
/// ranking said it was, and the next frame it contributes nothing. The pop
/// belongs to the cut-off, not to the ranking, and no better ranking removes
/// it.
///
/// `RenderSettings.lightFadeBand` replaces the cliff with a ramp measured
/// against the strongest score the selection *rejected*. The two claims here
/// are the two halves of the row: a band of nought is the old behaviour byte
/// for byte, which is what lets this ship without moving a recorded frame on
/// the three backends that cannot be re-recorded on this machine; and with a
/// band set, two neighbouring frames of a moving camera differ by less than
/// the two per cent the row asks for, where without one they do not.
///
/// The mutations these catch: measuring the water line against the weakest
/// *chosen* score rather than the strongest rejected one, which fades the
/// eighth light to nothing always and is a list of seven rather than a fade at
/// the edge of one; fading a directional light, which has no position, is
/// never ranked, and would be the one selection artefact everybody sees; and
/// scaling nothing at all when the band is nought, which the golden sets on
/// three backends rest on.
///
/// **One mutation these do not catch, said rather than hidden:** replacing the
/// smoothstep in `_edgeFade` with a straight ramp passes every line here. The
/// difference is a kink in the derivative at the top of the band — a second,
/// much smaller pop in place of the one being removed — and it is below what
/// a mean over a 96×48 frame can resolve. The smoothstep is kept because it is
/// free and correct, not because a fixture here would notice it going.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 48;

/// Forty lamps in a line along X, a metre apart, each within range of only a
/// few of its neighbours' stretch of floor.
///
/// A range rather than unbounded lamps: an unbounded lamp reaches everything,
/// so every object scores all forty and the selection never turns over as the
/// camera moves — which is the situation this row is about.
List<LightNode> _corridor() => <LightNode>[
  for (var i = 0; i < 40; i++)
    LightNode(type: LightType.point, intensity: 4.0, range: 6.0)
      ..setPosition(i.toDouble() - 19.5, 1.6, 0.0),
];

/// Eighty lamps a metre apart, each reaching far enough that more of them than
/// a draw can hold compete for its places — `gfx-74n`.
///
/// [_corridor] above reaches about thirteen lamps, which filled eight slots
/// with five to spare; with the light list carrying twenty-four more, that
/// corridor turns nothing away and has no water line at all. This one keeps the
/// same shape — an object standing *on* a lamp, so the pair either side of any
/// boundary scores exactly alike — and stretches it until the boundary is the
/// end of the list rather than the end of the slots.
List<LightNode> _longCorridor() => <LightNode>[
  for (var i = 0; i < 80; i++)
    LightNode(type: LightType.point, intensity: 4.0, range: 25.0)
      ..setPosition(i.toDouble() - 39.5, 1.6, 0.0),
];

/// A plank walking down a corridor, seen from above, with two far lamps
/// fighting over the eighth slot — the frame at position [at], as RGBA.
///
/// **Two competing lamps rather than forty, and the first fixture here was
/// forty.** A corridor of identical lamps a metre apart turned out to show
/// nothing at all: the selection swaps two lights exactly when their scores
/// are equal, so the *total* light arriving is continuous through a swap by
/// construction, and a symmetric corridor swaps a lamp on the left for its
/// mirror image on the right. Measured, that walk moved 0.02% of the frame
/// with the hard edge — under the row's threshold without any fade at all,
/// which would have made the acceptance vacuous.
///
/// What actually pops is *where* the light comes from. Two lamps with equal
/// relevance at an object's bounding sphere light very different parts of a
/// long object, so this fixture makes that the whole difference: seven dim
/// lamps directly over the plank hold seven slots for good, and one bright
/// lamp at each end of the corridor competes for the last one. The plank
/// crosses the halfway point, the eighth slot changes hands, and the lit end
/// of the plank jumps from one to the other.
Future<Uint8List> _frameAt(double at, {required double fadeBand}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();

  // Long, so that the two far lamps reach different parts of it. A ground
  // plane would be worse still — the row's own doc comment says why — and
  // that is the same effect at the scale where it is measurable.
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(8.0, 0.2, 2.0)).build(),
      ),
      Material(name: 'plank', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      name: 'plank',
    )..setPosition(at, 0.0, 0.0),
  );
  // **Thirty-one rather than seven, and at a fifth of a metre — `gfx-74n`.**
  // The cliff this fixture exists to contain is where a light stops
  // contributing, and that used to be the eighth slot. It is the end of the
  // light list now: eight slots and twenty-four rows, so thirty-one lamps hold
  // every place but one and the two bright ones at the ends compete for it.
  //
  // The spacing is the part that had to be measured rather than guessed. A lamp
  // scores by attenuation to the *surface* of the object's sphere, so one
  // directly over the plank scores its ceiling and one out past the sphere's
  // radius — 4.12 metres here — falls off a cliff of its own. At a spacing of
  // 0.3 the outer lamps of the row land beyond it, score below the two bright
  // ones, and both bright lamps stay in the top thirty-two: no hand-over, and
  // the walk measured 0.02% with the hard edge. At 0.2 every lamp of the row is
  // inside the sphere, the two bright ones are the weakest, and exactly one of
  // them is turned away — which is the hand-over this file is about.
  for (var i = 0; i < 31; i++) {
    scene.add(
      LightNode(type: LightType.point, intensity: 0.08, range: 20.0)
        ..setPosition(at + (i - 15) * 0.2, 2.0, 0.0),
    );
  }
  for (final x in <double>[-10.0, 10.0]) {
    scene.add(
      LightNode(type: LightType.point, intensity: 150.0, range: 40.0)
        ..setPosition(x, 2.0, 0.0),
    );
  }

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()
          ..setPosition(at, 9.0, 0.01)
          ..lookAt(Vector3(at, 0.0, 0.0)),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    // Bloom off for the reason `light_channels_test` gives: its glow spreads a
    // bright patch across the whole frame and would carry one end of the plank
    // into the measurement of the other. Shadows off because nine lamps and a
    // shadow budget of a handful is a second selection artefact on top of the
    // one being measured.
    settings: RenderSettings(
      tonemap: false,
      lightFadeBand: fadeBand,
      bloom: const BloomSettings(enabled: false),
      shadows: const ShadowSettings(enabled: false),
    ),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

/// How far apart two frames are, as a fraction of full brightness.
///
/// The mean absolute difference over every channel of every pixel. A maximum
/// would measure one pixel on one edge, which moves whenever the camera does
/// and says nothing about a light arriving; a mean says how much of the
/// picture changed.
double _difference(Uint8List a, Uint8List b) {
  var total = 0;
  for (var i = 0; i < a.length; i++) {
    total += (a[i] - b[i]).abs();
  }
  return total / (a.length * 255.0);
}

void main() {
  group('a band of nought is the hard edge this engine has always had', () {
    test('the packed bytes are identical, not merely close', () {
      // Byte for byte, because that is the claim the golden sets rest on: an
      // Impeller frame recorded before this row must still compare at zero
      // differing pixels, and this machine cannot re-record it to find out.
      final table = LightBuffer()..gather(_corridor());
      expect(
        table.overflow,
        greaterThan(0),
        reason: 'forty lamps, eight slots',
      );

      final hard = LightBuffer()
        ..gatherNearFrom(table, Vector3(0.0, 0.0, 0.0), 0.6);
      final withZeroBand = LightBuffer()
        ..gatherNearFrom(table, Vector3(0.0, 0.0, 0.0), 0.6, fadeBand: 0.0);

      expect(withZeroBand.count, hard.count);
      expect(withZeroBand.colors, hard.colors);
      expect(withZeroBand.positions, hard.positions);
      expect(withZeroBand.directions, hard.directions);
    });

    test('a scene that fits fades nothing, band or no band', () {
      // The other half of "only overflow pays". Four lamps, eight slots,
      // nothing rejected, no water line — so there is nothing for a band to
      // measure against and every lamp packs its own intensity.
      final few = <LightNode>[
        for (var i = 0; i < 4; i++)
          LightNode(type: LightType.point, intensity: 4.0, range: 6.0)
            ..setPosition(i.toDouble(), 1.6, 0.0),
      ];
      final table = LightBuffer()..gather(few);
      final buffer = LightBuffer()
        ..gatherNearFrom(table, Vector3(1.5, 0.0, 0.0), 0.6, fadeBand: 1.0);

      expect(buffer.count, 4);
      for (var i = 0; i < buffer.count; i++) {
        expect(buffer.colors[i * 4 + 3], 4.0);
      }
    });
  });

  group('the fade itself', () {
    test('the light at the water line is dimmed and the nearest is not', () {
      // The object stands under a lamp, so the eighth slot and the ninth
      // candidate are the *pair* at four metres either side and score exactly
      // alike — the moment before a swap, held still. That is where a fade has
      // something to do, and it is worth being deliberate about: half a metre
      // away, at the origin, the eighth chosen sits comfortably above the
      // water line and this same band leaves it alone. A fade that is doing
      // its job is invisible most of the time.
      // **A longer corridor with a longer reach — `gfx-74n`.** The tie this
      // test is built on is the pair straddling the last place, and that place
      // is the thirty-second now rather than the eighth: the pair sits sixteen
      // lamps out either side, which a range of six never reached. Eighty lamps
      // at a range of twenty-five put fifty-one of them within reach, so
      // thirty-two are kept and the pair at sixteen metres is split.
      final table = LightBuffer()..gather(_longCorridor());
      final buffer = LightBuffer()
        ..gatherNearFrom(table, Vector3(0.5, 0.0, 0.0), 0.6, fadeBand: 1.0);

      // **The slots are not where the fade lives any more — `gfx-74n`.** A
      // light turned away from them goes into the tail and is still lit, so
      // the eight here are all comfortably above the water line and none of
      // them is dimmed. The light *at* the line is the weakest the tail kept,
      // and its scale is what the shader multiplies its intensity by.
      final intensities = <double>[
        for (var i = 0; i < buffer.count; i++) buffer.colors[i * 4 + 3],
      ];
      expect(intensities.reduce(math.max), closeTo(4.0, 1e-6));
      expect(intensities.reduce(math.min), closeTo(4.0, 1e-6));

      final scales = <double>[
        for (var i = 0; i < buffer.extraCount; i++) buffer.extraScales[i],
      ];
      expect(scales, isNotEmpty, reason: 'nothing reached the tail');
      expect(scales.reduce(math.max), closeTo(1.0, 1e-6));
      // Nothing, not merely less: a light tied with the best one left out is
      // exactly at the water line, and the whole point is that swapping the
      // two shows nothing.
      expect(scales.reduce(math.min), closeTo(0.0, 1e-6));
    });

    test('a list nowhere near its water line is not touched at all', () {
      // Half a metre along from the fixture above, between two lamps, the
      // eighth chosen scores about two and a half times the best one left
      // out — outside a band of one, so every slot packs its own intensity.
      // This is the line that pins the water line to the strongest *rejected*
      // score: measuring it against the weakest *chosen* one instead makes
      // the eighth light fade to nothing always, which is not a fade at the
      // edge of the list, it is a list of seven.
      final table = LightBuffer()..gather(_corridor());
      final buffer = LightBuffer()
        ..gatherNearFrom(table, Vector3(0.0, 0.0, 0.0), 0.6, fadeBand: 1.0);

      expect(buffer.count, 8);
      for (var i = 0; i < buffer.count; i++) {
        expect(buffer.colors[i * 4 + 3], 4.0);
      }
    });

    test('a directional light is never faded', () {
      // It has no position, so it is not ranked at all — it scores infinity,
      // which is above any ceiling the band can compute. The mutation this
      // catches is a fade applied before the infinity check, which would dim
      // the sun in any scene that also carries a crowd of lamps.
      final lights = <LightNode>[
        LightNode(type: LightType.directional, intensity: 2.0)
          ..lookAt(Vector3(0.0, -1.0, 0.0)),
        ..._corridor(),
      ];
      final table = LightBuffer()..gather(lights);
      final buffer = LightBuffer()
        ..gatherNearFrom(table, Vector3(0.0, 0.0, 0.0), 0.6, fadeBand: 1.0);

      expect(buffer.packed.first.type, LightType.directional);
      expect(buffer.colors[3], 2.0);
    });

    test(
      'a symmetric ring of lights around a wide object is not faded to black',
      () {
        // `many_lights.dart`'s own bug. Forty torches equidistant from a
        // floor's centre score identically against the floor's own
        // oversized bounding sphere — every one of them lands inside it, at
        // the ceiling `_relevanceIn` gives a light with nothing between it
        // and the object. The candidate that finally overflows the tail
        // then ties with every light already packed, and treating that tie
        // as a genuine loss set the water line at the same score as the
        // whole ring — fading all thirty-two kept torches to nothing
        // instead of only the eight that do not fit.
        const int torches = 40;
        final ring = <LightNode>[
          for (var i = 0; i < torches; i++)
            LightNode(type: LightType.point, intensity: 2.5, range: 3.5)
              ..setPosition(
                math.cos(i / torches * 2 * math.pi) * 6.0,
                0.6,
                math.sin(i / torches * 2 * math.pi) * 6.0,
              ),
        ];
        final table = LightBuffer()..gather(ring);
        expect(
          table.overflow,
          greaterThan(0),
          reason: 'forty lamps, eight slots',
        );

        // Wide enough that every torch lands inside its own bounding sphere,
        // which is what makes every one of them score identically.
        final buffer = LightBuffer()
          ..gatherNearFrom(table, Vector3.zero(), 14.0, fadeBand: 0.5);

        expect(buffer.count, LightBuffer.maxLights);
        for (var i = 0; i < buffer.count; i++) {
          expect(
            buffer.colors[i * 4 + 3],
            2.5,
            reason:
                'slot $i faded though nothing about it lost to a '
                'genuinely stronger light',
          );
        }
        expect(buffer.extraCount, LightBuffer.maxExtraLights);
        for (var i = 0; i < buffer.extraCount; i++) {
          expect(
            buffer.extraScales[i],
            1.0,
            reason:
                'tail light $i faded to the tie that dropped a light past it',
          );
        }
      },
    );
  });

  group("the row's own acceptance: a camera walk gives no jump", () {
    test('two neighbouring frames differ by less than two per cent', () async {
      // Twelve steps of five centimetres across the point where the eighth
      // slot changes hands. Measured on this fixture: the hard edge's worst
      // neighbouring pair moves 3.16% of the frame — over the row's own
      // threshold, which is what makes passing it mean something — and a band
      // of one brings the same step down to 0.23%.
      const double step = 0.05;
      var worstHard = 0.0;
      var worstFaded = 0.0;
      Uint8List? lastHard;
      Uint8List? lastFaded;
      for (var i = -6; i <= 6; i++) {
        final at = i * step;
        final hard = await _frameAt(at, fadeBand: 0.0);
        final faded = await _frameAt(at, fadeBand: 1.0);
        if (lastHard != null && lastFaded != null) {
          worstHard = math.max(worstHard, _difference(lastHard, hard));
          worstFaded = math.max(worstFaded, _difference(lastFaded, faded));
        }
        lastHard = hard;
        lastFaded = faded;
      }

      expect(
        worstHard,
        greaterThan(0.02),
        reason: 'the fixture has to contain the jump it claims to remove',
      );
      expect(
        worstFaded,
        lessThan(0.02),
        reason: 'the row asks for under two per cent between neighbours',
      );
      // An order of magnitude, not merely smaller. Without this a fade that
      // dimmed the whole scene towards nothing would pass the line above, and
      // the two brightnesses are what says it does not: both walks are drawn
      // from the same geometry with the same exposure.
      expect(worstFaded * 10.0, lessThan(worstHard));
    });
  });
}
