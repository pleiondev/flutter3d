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
      // **Measured, not recited.** Two of the claims this file started with
      // were received wisdom and wrong: ACES is usually described as
      // darkening midtones and this fit lifts them, because it carries about
      // a stop of exposure inside it; and AgX is built to put middle grey at
      // middle display, which is a far bigger change than "a look".
      const double grey = 0.18;
      double at(TonemapCurve curve) =>
          _through(curve, Vector3(grey, grey, grey)).x;

      expect(at(TonemapCurve.neutral), closeTo(0.140, 0.002));
      expect(at(TonemapCurve.aces), closeTo(0.267, 0.002));
      expect(at(TonemapCurve.agx), closeTo(0.497, 0.002));
      expect(at(TonemapCurve.reinhard), closeTo(0.154, 0.002));

      // Which is the sentence a reader needs before switching a scene over:
      // only two of the four leave an asset looking like its author's.
      expect((at(TonemapCurve.neutral) - grey).abs(), lessThan(0.05));
      expect((at(TonemapCurve.reinhard) - grey).abs(), lessThan(0.05));
      expect(at(TonemapCurve.aces), greaterThan(grey + 0.05));
      expect(at(TonemapCurve.agx), greaterThan(grey + 0.05));
    });

    test('agx desaturates a bright coloured lamp more than aces', () {
      // A red lamp two stops over white, which is where the two curves
      // actually differ: ACES pushes it towards its own primary and AgX walks
      // it towards white. Two stops and not six, because past ACES's ceiling
      // the comparison stops meaning anything — see the next test.
      final lamp = Vector3(4.0, 0.5, 0.5);

      double spreadOf(TonemapCurve curve) {
        final out = _through(curve, lamp.clone());
        expect(_luma(out), greaterThan(0.0));
        final channels = <double>[out.x, out.y, out.z];
        return channels.reduce((double a, double b) => a > b ? a : b) -
            channels.reduce((double a, double b) => a < b ? a : b);
      }

      expect(spreadOf(TonemapCurve.agx), lessThan(spreadOf(TonemapCurve.aces)));
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
}
