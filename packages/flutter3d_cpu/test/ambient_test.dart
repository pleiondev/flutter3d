/// Ambient comes from the sky, and from which way a surface faces.
///
///     flutter test test/ambient_test.dart
///
/// It used to be one grey scalar, and `Scene.ambientColor` sat beside it
/// unread — declared, public, documented, and wired to nothing. What a scalar
/// cannot say is that the sky is above and the ground below: every upward face
/// and every downward face were lifted by the same amount, in the same colour,
/// which reads as the model being flat and gets blamed on its normals.
///
/// Two things have to hold at once, and they pull against each other:
///
///   * a scene with no sky must shade exactly as it did — the whole set of
///     goldens is recorded against that path, and `mix(white, white, t)` being
///     white for every t is what makes it free rather than merely close;
///   * a scene with a sky must be lit by it, differently above than below.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// A ball lit by nothing at all, so every photon in the frame is ambient.
///
/// No lights on purpose. With even one directional light the term under test is
/// six per cent of the picture and any measurement of it is a measurement of
/// the other ninety-four.
///
/// Close enough that the ball fills the frame, which is not framing but
/// correctness: with a sky enabled the background *is* the sky, and a band
/// average that caught any of it would be measuring the thing that lights the
/// ball rather than the ball. The first version of this file did exactly that
/// and reported the sun disc leaking into ambient when nothing of the kind was
/// happening.
///
/// A mid grey rather than white, and half strength rather than full, to stay
/// off the shoulder of the tone curve — two bands that are both saturated agree
/// with each other whatever the ambient did.
({Scene scene, CameraNode camera}) _ball({double ambient = 0.5}) {
  final scene = Scene()..ambientIntensity = ambient;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, SphereShape(radius: 1.0).build()),
      Material(
        name: 'ball',
        baseColor: Vector4(0.6, 0.6, 0.6, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'ball',
    ),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, -1.6)
    ..lookAt(Vector3.zero());
  return (scene: scene, camera: camera);
}

Future<Uint8List> _pixels(
  ({Scene scene, CameraNode camera}) room,
  RenderSettings settings,
) async {
  final engine = _engine();
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: settings,
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

/// Average colour of a horizontal band, as fractions of 255.
///
/// A band rather than one pixel: a single pixel on a sphere is a sample of one
/// normal, and the question here is about a whole face of the ball.
Vector3 _band(Uint8List rgba, double top, double bottom) {
  var r = 0.0, g = 0.0, b = 0.0;
  var n = 0;
  for (var y = (top * _height).round(); y < (bottom * _height).round(); y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      // Only the ball, not the cleared background behind it.
      if (rgba[i] + rgba[i + 1] + rgba[i + 2] < 12) continue;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
  }
  expect(n, greaterThan(0), reason: 'the band caught none of the ball');
  return Vector3(r / n / 255.0, g / n / 255.0, b / n / 255.0);
}

const RenderSettings _noSky =
    RenderSettings(bloom: BloomSettings(enabled: false));

/// A sky that could not be mistaken for grey: blue above, orange below.
final RenderSettings _colouredSky = RenderSettings(
  bloom: const BloomSettings(enabled: false),
  sky: SkySettings(
    enabled: true,
    zenith: Vector3(0.05, 0.15, 0.7),
    horizon: Vector3(0.1, 0.2, 0.6),
    nadir: Vector3(0.6, 0.3, 0.05),
  ),
);

void main() {
  test('no sky shades exactly as one grey scalar did', () async {
    // The claim the whole set of goldens rests on. `ambientColor` defaults to
    // white and both ends of the hemisphere resolve to it, so the mix is white
    // at every normal and the product is the scalar it always was — not
    // approximately, bit for bit.
    //
    // Mutation: default either end of the hemisphere to anything but white.
    // Thirty-one goldens move at once.
    final lit = await _pixels(_ball(), _noSky);
    final top = _band(lit, 0.15, 0.35);
    final bottom = _band(lit, 0.65, 0.85);

    expect(top.x, closeTo(top.y, 1 / 255), reason: 'a grey ambient is grey');
    expect(top.y, closeTo(top.z, 1 / 255));
    expect(bottom.x, closeTo(top.x, 1 / 255),
        reason: 'with no sky, up and down receive the same light');
  });

  test('a sky lights the top of a ball differently from the bottom', () async {
    // Mutation: drop the `mix` and use one end for every normal. The two bands
    // below come out the same colour, which is the failure this replaces —
    // it looked like flat shading and was blamed on the normals.
    final lit = await _pixels(_ball(), _colouredSky);
    final top = _band(lit, 0.15, 0.35);
    final bottom = _band(lit, 0.65, 0.85);

    // Stated as a gradient rather than as "the underside is orange", and the
    // difference is not pedantry. A sphere seen head-on shows the hemisphere
    // facing the camera, whose normals lean towards it rather than up or down:
    // `n.y` runs over roughly the middle half of its range, never reaching
    // either end. So the bottom of this ball is not warm, it is *less blue*,
    // and an absolute test would have to be satisfied by geometry that does not
    // exist in the frame. The first draft asserted the absolute form and failed
    // on correct output.
    expect(top.z - top.x, greaterThan(bottom.z - bottom.x),
        reason: 'the top is no bluer than the bottom: the hemisphere is not '
            'being blended by the normal at all');
    expect(bottom.x, greaterThan(top.x),
        reason: 'the underside picks up none of the warm bounce');
  });

  test('the sky is read as a gradient, not sampled through the sun',
      () async {
    // The trap in building this from `SkySettings.sample`: that function adds
    // the sun disc, whose intensity sits far above white by design. A sun near
    // the zenith would then hand every upward face the disc, and the scene
    // would blow out with nothing in the picture to explain it.
    //
    // Mutation: build the sky end from `sample(up)` instead of the gradient.
    final overhead = RenderSettings(
      bloom: const BloomSettings(enabled: false),
      sky: SkySettings(
        enabled: true,
        zenith: Vector3(0.05, 0.15, 0.7),
        horizon: Vector3(0.1, 0.2, 0.6),
        nadir: Vector3(0.6, 0.3, 0.05),
        // Straight up, and blindingly bright.
        directionToSun: Vector3(0.0, 1.0, 0.0),
        sunIntensity: 400.0,
      ),
    );

    final calm = await _pixels(_ball(), _colouredSky);
    final blazing = await _pixels(_ball(), overhead);

    final before = _band(calm, 0.15, 0.35);
    final after = _band(blazing, 0.15, 0.35);
    expect(after.x, closeTo(before.x, 2 / 255),
        reason: 'a sun overhead changed the ambient: the disc is reaching it');
    expect(after.z, closeTo(before.z, 2 / 255));
  });

  test('ambientColor tints both ends and is no longer dead', () async {
    // It was declared, public, documented — and read by nothing. A field like
    // that is worse than a missing one: it answers "can I tint the ambient?"
    // with yes, and then does nothing.
    //
    // Mutation: drop the tint from `_updateAmbient`. This test is the only
    // thing in the repository that would notice.
    final plain = await _pixels(_ball(), _noSky);
    final tinted = _ball()..scene.ambientColor = Vector3(1.0, 0.2, 0.2);
    final red = await _pixels(tinted, _noSky);

    final was = _band(plain, 0.3, 0.7);
    final now = _band(red, 0.3, 0.7);
    expect(now.x, closeTo(was.x, 2 / 255), reason: 'the red channel is untinted');
    expect(now.y, lessThan(was.y * 0.7),
        reason: 'green was tinted to a fifth and did not fall');
  });
}
