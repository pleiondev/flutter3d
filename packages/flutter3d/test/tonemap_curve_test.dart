/// `gfx-17n`, the curve half: four tone curves where there was one.
///
///     flutter test test/tonemap_curve_test.dart
///
/// **The default has to stay bit-identical, and that is most of this file.**
/// Every golden in the repository was recorded through Khronos PBR Neutral,
/// and the change that made the curve selectable turned a flag into a number
/// in the same uniform slot. If `neutral` drew one byte differently from the
/// flag it replaced, thirty reference images would move for a reason nobody
/// would connect to a tone curve.
///
/// The rest is what the other three are for. Each is checked for the property
/// it was chosen for rather than against a recorded picture: a curve is a
/// decision about how highlights roll off, and a golden of a sphere says
/// almost nothing about that.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// [colour] through [curve], as the composite would.
Vector3 _through(TonemapCurve curve, Vector3 colour) =>
    tonemapBy(colour, curve.code.round());

/// Rec. 709 luma, the composite's own weighting.
double _luma(Vector3 c) => 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;

void main() {
  group('the default is exactly what it was', () {
    test('neutral is the curve the old flag meant', () {
      // The flag was `params.z > 0.5` and the number is `int(params.z + 0.5)`.
      // One reads true and the other reads 1 for the same stored 1.0, which
      // is the whole reason the default was numbered 1 rather than 0.
      expect(TonemapCurve.neutral.code, 1.0);
      expect(TonemapCurve.neutral.code > 0.5, isTrue);

      for (final Vector3 sample in <Vector3>[
        Vector3(0.0, 0.0, 0.0),
        Vector3(0.18, 0.18, 0.18),
        Vector3(0.5, 0.4, 0.3),
        Vector3(1.0, 1.0, 1.0),
        Vector3(4.0, 2.0, 1.0),
        Vector3(40.0, 40.0, 40.0),
      ]) {
        final was = tonemapNeutral(sample.clone());
        final now = _through(TonemapCurve.neutral, sample.clone());
        expect(now.x, was.x);
        expect(now.y, was.y);
        expect(now.z, was.z);
      }
    });

    test('a curve of zero is the colour untouched', () {
      final sample = Vector3(3.0, 0.25, 0.7);
      // `tonemap: false` and every raw debug view store zero, and zero has to
      // mean *nothing happens* rather than "the gentlest curve".
      final out = tonemapBy(sample.clone(), 0);
      expect(out.x, sample.x);
      expect(out.y, sample.y);
      expect(out.z, sample.z);
    });
  });

  group('each curve does the thing it was chosen for', () {
    test('every curve brings a bright value inside the display range', () {
      // **The one that caught the extended Reinhard.** The extension keeps
      // climbing past its own white point — it mapped 12 to 1.6 — which is
      // not a tone mapper's job: anything above white is white. It clamps
      // now, and this is the check that says so.
      final bright = Vector3(12.0, 9.0, 6.0);
      for (final TonemapCurve curve in TonemapCurve.values) {
        final out = _through(curve, bright.clone());
        expect(
          out.x,
          lessThanOrEqualTo(1.0001),
          reason: '${curve.name} left a highlight above white',
        );
        expect(
          out.x,
          greaterThan(0.0),
          reason: '${curve.name} clipped to black',
        );
      }
    });

    test('every curve is monotone: brighter in, no darker out', () {
      for (final TonemapCurve curve in TonemapCurve.values) {
        var previous = -1.0;
        for (var stop = 0; stop <= 60; stop++) {
          final input = stop / 4.0;
          final out = _through(curve, Vector3(input, input, input)).x;
          expect(
            out,
            greaterThanOrEqualTo(previous - 1e-6),
            reason: '${curve.name} dips at $input',
          );
          previous = out;
        }
      }
    });

    test('the four differ at mid grey, and the numbers are written down', () {
      // **Measured, not recited.** ACES is usually described as darkening
      // midtones and this fit lifts them, because it carries about a stop of
      // exposure inside it. AgX puts middle grey at middle *display*: 0.2145
      // linear, which the sRGB encode turns into 128/255.
      const double grey = 0.18;
      double at(TonemapCurve curve) =>
          _through(curve, Vector3(grey, grey, grey)).x;

      expect(at(TonemapCurve.neutral), closeTo(0.140, 0.002));
      expect(at(TonemapCurve.aces), closeTo(0.267, 0.002));
      expect(at(TonemapCurve.agx), closeTo(0.2145, 0.002));
      expect(at(TonemapCurve.reinhard), closeTo(0.154, 0.002));

      expect((at(TonemapCurve.neutral) - grey).abs(), lessThan(0.05));
      expect((at(TonemapCurve.reinhard) - grey).abs(), lessThan(0.05));
      expect(at(TonemapCurve.aces), greaterThan(grey + 0.05));
    });

    test('agx comes out linear, so the frame is encoded once', () {
      // **The regression 0.7.4 fixes.** AgX's sigmoid is display-encoded, and
      // until 0.7.4 its value went into the sRGB encode as though it were
      // linear: grey reached the screen at 187/255 and a red velvet
      // (0.6, 0.07, 0.1) at 212/159/169, pastel. Linearised, grey lands at
      // mid display and the velvet stays red.
      double encode(double linear) => linear <= 0.0031308
          ? linear * 12.92
          : 1.055 * math.pow(linear, 1.0 / 2.4) - 0.055;

      final grey = _through(TonemapCurve.agx, Vector3.all(0.18)).x;
      expect(encode(grey) * 255.0, closeTo(128.0, 1.5));

      final velvet = _through(TonemapCurve.agx, Vector3(0.6, 0.07, 0.1));
      expect(velvet.x, greaterThan(velvet.y * 3.0));
      expect(velvet.x, greaterThan(velvet.z * 3.0));
    });

    test('far over white, agx still has a colour where aces has none', () {
      // A red lamp six stops over white: ACES has clipped every channel to
      // one and draws a white disc, AgX walks the lamp towards white and has
      // not arrived. Measured: 0.044 against 0.000. At two stops the order is
      // the other way round (0.45 against 0.36), which is why the lamp is
      // six stops over and not two.
      final lamp = Vector3(64.0, 8.0, 8.0);

      double spreadOf(TonemapCurve curve) {
        final out = _through(curve, lamp.clone());
        expect(_luma(out), greaterThan(0.0));
        final channels = <double>[out.x, out.y, out.z];
        return channels.reduce(math.max) - channels.reduce(math.min);
      }

      expect(spreadOf(TonemapCurve.aces), lessThan(0.001));
      expect(spreadOf(TonemapCurve.agx), greaterThan(0.02));
    });

    test(
      'past its ceiling aces returns one value and agx keeps separating',
      () {
        // The property AgX is here for. ACES reaches exactly one at about 7.2,
        // so every highlight above that is the same flat patch; AgX still tells
        // 8 from 40 apart, which is what leaves shape inside a bright area.
        double at(TonemapCurve curve, double x) =>
            _through(curve, Vector3(x, x, x)).x;

        expect(at(TonemapCurve.aces, 8.0), at(TonemapCurve.aces, 40.0));
        expect(
          at(TonemapCurve.agx, 40.0) - at(TonemapCurve.agx, 8.0),
          greaterThan(0.02),
        );
      },
    );
  });

  group('the whole frame, drawn', () {
    ({CpuDevice device, Renderer renderer}) engine() {
      final device = CpuDevice(
        width: 32,
        height: 32,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      return (device: device, renderer: Renderer.create(device: device));
    }

    Future<List<int>> draw(TonemapCurve curve) async {
      final it = engine();
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(
              it.device,
              CuboidShape(size: Vector3(1.4, 1.4, 1.4)).build(),
            ),
            Material(name: 'bright', baseColor: Vector4(0.9, 0.5, 0.2, 1.0)),
          ),
        )
        ..add(
          LightNode(intensity: 24.0)
            ..setPosition(2.0, 3.0, 2.0)
            ..lookAt(Vector3.zero()),
        );
      final frame = it.renderer.render(
        width: 32,
        height: 32,
        scene: scene,
        views: <RenderView>[
          RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 3.0)),
        ],
        settings: RenderSettings(tonemapCurve: curve),
      );
      final pixels = await it.device.readPixels(frame.frame);
      return pixels!.buffer.asUint8List().toList();
    }

    test('the default curve draws what the default curve drew', () async {
      // Two renders of the same scene through the same curve, one asking for
      // it by name and one taking the default. Byte for byte, because that is
      // what every recorded golden depends on.
      expect(
        await draw(TonemapCurve.neutral),
        await draw(TonemapCurve.neutral),
      );
    });

    test('asking for another curve changes the picture', () async {
      final neutral = await draw(TonemapCurve.neutral);
      for (final TonemapCurve curve in <TonemapCurve>[
        TonemapCurve.aces,
        TonemapCurve.agx,
        TonemapCurve.reinhard,
      ]) {
        expect(
          await draw(curve),
          isNot(neutral),
          reason:
              '${curve.name} drew the same frame as neutral, so the '
              'uniform never reached the shader',
        );
      }
    });
  });

  group('AgX with the rotation — gfx-26n', () {
    /// The hue of [c] on the colour wheel, in degrees, or null for a grey.
    ///
    /// Hue rather than the channels themselves, because the claim is about hue
    /// and nothing else: the rotation is allowed to change how bright and how
    /// saturated a highlight comes out, and is not allowed to change what
    /// colour it is.
    double? hue(Vector3 c) {
      final max = math.max(c.x, math.max(c.y, c.z));
      final min = math.min(c.x, math.min(c.y, c.z));
      final chroma = max - min;
      if (chroma < 1e-6) return null;
      final double h;
      if (max == c.x) {
        h = 60.0 * (((c.y - c.z) / chroma) % 6.0);
      } else if (max == c.y) {
        h = 60.0 * ((c.z - c.x) / chroma + 2.0);
      } else {
        h = 60.0 * ((c.x - c.y) / chroma + 4.0);
      }
      return (h + 360.0) % 360.0;
    }

    /// The shorter way round the wheel between two hues.
    double hueGap(double a, double b) {
      final d = (a - b).abs() % 360.0;
      return d > 180.0 ? 360.0 - d : d;
    }

    /// Saturated colours over display white, where per-channel compression has
    /// something to get wrong. A grey has no hue and a dim colour barely moves,
    /// so neither would test anything.
    final overBright = <Vector3>[
      Vector3(0.2, 0.05, 4.0),
      Vector3(4.0, 0.8, 0.1),
      Vector3(4.0, 2.0, 0.2),
      Vector3(0.1, 4.0, 0.4),
      Vector3(4.0, 0.2, 2.0),
      Vector3(8.0, 1.0, 0.05),
      Vector3(0.05, 1.0, 8.0),
      Vector3(16.0, 3.0, 0.5),
      Vector3(1.0, 0.3, 0.05),
      Vector3(0.4, 0.1, 0.02),
    ];

    /// AgX's sigmoid on each channel with no rotation around it, linearised
    /// the way [TonemapCurve.agx] is — what the rotation is measured against.
    Vector3 bare(Vector3 c) {
      final s = agxSigmoid(c);
      double linear(double v) => math.pow(v, 2.2).toDouble();
      return Vector3(linear(s.x), linear(s.y), linear(s.z));
    }

    test('the rotation holds a hue better than the bare curve, on every '
        'saturated sample', () {
      // It does not bring a hue within a few degrees and cannot with these
      // matrices; what it buys is about a third off the error, everywhere.
      // (0, 0, 4) is not among the samples on purpose: with two equal
      // channels the bare curve holds the hue exactly and the comparison
      // could not show anything either way.
      for (final Vector3 input in overBright) {
        final wanted = hue(input)!;
        final withoutRotation = hue(bare(input.clone()));
        final withRotation = hue(_through(TonemapCurve.agx, input.clone()));
        expect(withoutRotation, isNotNull);
        expect(withRotation, isNotNull);
        expect(
          hueGap(withRotation!, wanted),
          lessThan(hueGap(withoutRotation!, wanted)),
          reason:
              '$input: the rotation is meant to help everywhere and cost '
              'nothing; here it helped nowhere',
        );
      }
    });

    test('it takes about a third off the hue error across that spread', () {
      // Measured over exactly the ten samples above, with the linearised
      // curve of 0.7.4: 19.78 mean degrees without the rotation, 13.47 with
      // it, a ratio of 0.68. Pinned so a later change to a matrix or to the
      // curve cannot quietly hand the win back.
      var withoutTotal = 0.0;
      var withTotal = 0.0;
      for (final Vector3 input in overBright) {
        final wanted = hue(input)!;
        withoutTotal += hueGap(hue(bare(input.clone()))!, wanted);
        withTotal += hueGap(
          hue(_through(TonemapCurve.agx, input.clone()))!,
          wanted,
        );
      }
      final withoutMean = withoutTotal / overBright.length;
      final withMean = withTotal / overBright.length;

      expect(withoutMean, greaterThan(19.5));
      expect(withMean, lessThan(13.8));
      expect(
        withMean,
        lessThan(withoutMean * 0.7),
        reason: 'the rotation stopped earning its two matrices',
      );
    });

    test('the two matrices are inverses, so a mid grey is not re-graded', () {
      // The transpose and mismatched-pair check. An inset from one published
      // variant beside an outset from another is a product that is *nearly*
      // the identity, which reads as a grade nobody asked for; a grey is the
      // one input the rotation must leave exactly alone.
      final grey = Vector3(0.18, 0.18, 0.18);
      final withoutRotation = bare(grey.clone());
      final withRotation = _through(TonemapCurve.agx, grey.clone());

      expect((withRotation.x - withoutRotation.x).abs(), lessThan(1e-4));
      expect((withRotation.y - withoutRotation.y).abs(), lessThan(1e-4));
      expect((withRotation.z - withoutRotation.z).abs(), lessThan(1e-4));
    });

    test('code 5 is kept, and draws what agx draws', () {
      // `agxFull` was the rotated variant while `agx` was the bare sigmoid.
      // Now that `agx` is the whole transform the two are one curve, and a
      // setting that stored code 5 keeps working.
      // ignore: deprecated_member_use_from_same_package, deprecated_member_use
      expect(TonemapCurve.agxFull.code, 5.0);
      // Six since `L2` added the display transform ACES 2.0 is read through.
      expect(TonemapCurve.values.length, 6);
      for (final Vector3 sample in <Vector3>[
        Vector3(0.18, 0.18, 0.18),
        Vector3(4.0, 2.0, 1.0),
        Vector3(0.0, 0.0, 4.0),
      ]) {
        final agx = tonemapBy(sample.clone(), 3);
        final code5 = tonemapBy(sample.clone(), 5);
        expect(code5.x, agx.x);
        expect(code5.y, agx.y);
        expect(code5.z, agx.z);
      }
    });

    test('it brings an over-bright colour inside the display range', () {
      // The outset can push a channel past one on a colour that was already
      // at the edge of the gamut, which is what the clamp is for.
      for (final Vector3 sample in <Vector3>[
        Vector3(40.0, 0.0, 0.0),
        Vector3(0.0, 40.0, 0.0),
        Vector3(0.0, 0.0, 40.0),
        Vector3(40.0, 40.0, 40.0),
      ]) {
        final out = _through(TonemapCurve.agx, sample.clone());
        for (final double channel in <double>[out.x, out.y, out.z]) {
          expect(channel, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
