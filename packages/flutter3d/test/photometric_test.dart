/// `gfx-13n`: a lamp can be specified off its own box.
///
///     flutter test test/photometric_test.dart
///
/// **The number nothing in the renderer defined.** `LightNode.intensity` is
/// multiplied by an attenuation and handed to a tone curve, and until this row
/// nothing said what one of it was worth — so a lamp rated in lumens could
/// only be matched by eye, and two people tuning the same scene disagreed
/// about what "a table lamp" meant.
///
/// [Photometric] fixes the exchange rate at the point the row itself names: an
/// 800-lumen lamp — the ordinary bulb — comes out at the intensity this engine
/// has always defaulted to. The first group holds that sentence as arithmetic
/// and the second holds it as pixels, which is the half that would catch the
/// conversion being right on paper and wired up backwards.
///
/// The mutations these catch: spreading a point lamp's flux over a hemisphere
/// rather than a sphere (the factor-of-two error that makes every bulb twice
/// as bright); dividing a spot's flux by the *full* angle rather than the
/// solid angle of its cone; and a round trip that does not come back.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 32;
const int _height = 32;

/// A white quad facing the camera, lit by one lamp, as RGBA.
///
/// **Five metres, not the one the conversion is anchored at.** At a metre an
/// 800-lumen lamp blows the wall to 255 and every comparison below reads as
/// equal, which is a test that passes by saturating rather than by agreeing —
/// the first run of this file did exactly that, and the brighter-bulb case is
/// what caught it. Five metres puts the response in range; the anchor is
/// arithmetic and does not care where the lamp stands.
Future<Uint8List> _draw(LightNode lamp) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(4.0, 4.0, 0.2)).build(),
        ),
        Material(name: 'wall', baseColor: Vector4(1.0, 1.0, 1.0, 1.0)),
        name: 'wall',
      )..setPosition(0.0, 0.0, 0.0),
    )
    ..add(lamp);

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()..setPosition(0.0, 0.0, 9.0),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    // Every stage that would move a number between the shader and the pixel,
    // off: this measures a conversion, not a look.
    settings: const RenderSettings(
      tonemap: false,
      exposure: 1.0,
      bloom: BloomSettings(enabled: false),
      shadows: ShadowSettings(enabled: false),
    ),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

/// The green channel at the middle of the frame — the quad's lit face.
int _middle(Uint8List rgba) =>
    rgba[((_height ~/ 2) * _width + _width ~/ 2) * 4 + 1];

void main() {
  group('the exchange rate, as arithmetic', () {
    test('an 800-lumen bulb is intensity one', () {
      // The row's own sentence, and the anchor every other number here hangs
      // off. Eight hundred lumens is what replaced the sixty-watt bulb, and
      // one is what every light in this engine has defaulted to.
      expect(Photometric.fromLumens(800.0), closeTo(1.0, 1e-9));
    });

    test('a point lamp spreads over the whole sphere', () {
      // The factor-of-two mutation: over a hemisphere instead, which makes
      // every bulb in every scene twice as bright and looks plausible.
      expect(
        Photometric.fromLumens(800.0, type: LightType.point),
        closeTo(Photometric.fromCandela(800.0 / (4.0 * math.pi)), 1e-12),
      );
    });

    test('the same flux through a spot is far brighter', () {
      // A 45° cone is 1.84 steradians against the sphere's 4π, so the same
      // bulb in a spot is about seven times the intensity — which is what a
      // spot is for and what a conversion that ignored the cone would miss.
      final spot = Photometric.fromLumens(
        800.0,
        type: LightType.spot,
        outerConeAngle: math.pi / 4.0,
      );
      expect(spot / Photometric.fromLumens(800.0), closeTo(6.83, 0.01));
    });

    test('a narrower cone is brighter still, and a cone of nothing is not '
        'infinite', () {
      final wide = Photometric.fromLumens(
        800.0,
        type: LightType.spot,
        outerConeAngle: math.pi / 3.0,
      );
      final narrow = Photometric.fromLumens(
        800.0,
        type: LightType.spot,
        outerConeAngle: math.pi / 12.0,
      );
      expect(narrow, greaterThan(wide));
      // The clamp: a cone of no width has no solid angle, and one lumen
      // through it would be infinitely bright.
      expect(
        Photometric.fromLumens(
          800.0,
          type: LightType.spot,
          outerConeAngle: 0.0,
        ),
        predicate<double>((double v) => v.isFinite, 'finite'),
      );
    });

    test('lux and candela are the same number a metre away', () {
      // What makes `fromCandela` `fromLux` with the metre already in it: a
      // source of one candela lights a surface a metre off with one lux.
      expect(Photometric.fromCandela(500.0), Photometric.fromLux(500.0));
    });

    test('every conversion comes back', () {
      for (final type in LightType.values) {
        final there = Photometric.fromLumens(1500.0, type: type);
        expect(
          Photometric.toLumens(there, type: type),
          closeTo(1500.0, 1e-6),
          reason: 'lumens through $type',
        );
      }
      expect(
        Photometric.toLux(Photometric.fromLux(320.0)),
        closeTo(320.0, 1e-9),
      );
    });
  });

  group("the row's own acceptance, as pixels", () {
    test(
      'an 800-lumen lamp lights a wall exactly like the tuned one',
      () async {
        // The half that arithmetic cannot give: that the conversion is wired to
        // the field the shader actually reads, and in the right direction. The
        // two lamps below are the same lamp said two ways.
        final tuned = LightNode(type: LightType.point, intensity: 1.0)
          ..setPosition(0.0, 0.0, 5.1);
        final rated = LightNode(
          type: LightType.point,
          intensity: Photometric.fromLumens(800.0),
        )..setPosition(0.0, 0.0, 5.1);

        expect(_middle(await _draw(rated)), _middle(await _draw(tuned)));
      },
    );

    test('a brighter bulb is a brighter wall', () async {
      // Not a tautology against the test above: it says the conversion is
      // wired up, this says it is wired up the right way round. A 1600-lumen
      // bulb has to light the wall more than an 800-lumen one, and a
      // conversion that divided where it should multiply passes the equality
      // above and fails here.
      Future<int> litBy(double lumens) async => _middle(
        await _draw(
          LightNode(
            type: LightType.point,
            intensity: Photometric.fromLumens(lumens),
          )..setPosition(0.0, 0.0, 5.1),
        ),
      );

      expect(await litBy(1600.0), greaterThan(await litBy(800.0)));
      expect(await litBy(800.0), greaterThan(await litBy(200.0)));
    });
  });
}
