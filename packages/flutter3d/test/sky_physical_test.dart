/// The physical sky and the height fog — `P5`.
///
///     flutter test test/sky_physical_test.dart
///
/// The sky exists three times: in `sky_physical.frag`, in `PhysicalSky.look`
/// for the things that cannot ask a GPU, and in the software rasteriser's
/// `SkyPhysicalShader`. The frames here are drawn by the third and checked
/// against the second, which is what catches a varying read from the wrong
/// lane: the picture stays a plausible sky and only the comparison moves.
///
/// The rest are claims about the air that hold whatever the coefficients are
/// tuned to: a sunset is red towards the sun, the stars come out at night and
/// not at noon, and fog that lies on the ground is thinner looking up.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Odd, so that the centre pixel's centre is the camera's axis. With an even
// size it sits half a pixel off, which near the horizon at dusk is enough
// height for the blue to move by more than the comparison allows.
const int _width = 97;
const int _height = 73;

/// A unit vector [degrees] above the horizon, towards +x.
Vector3 _sunAt(double degrees) {
  final radians = degrees * math.pi / 180.0;
  return Vector3(math.cos(radians), math.sin(radians), 0.0);
}

SkySettings _sky({
  bool enabled = true,
  double sunDegrees = 30.0,
  double sunIntensity = 0.0,
  PhysicalSky air = const PhysicalSky(),
}) => SkySettings(
  enabled: enabled,
  directionToSun: _sunAt(sunDegrees),
  sunAngularRadiusDegrees: 2.0,
  sunSoftnessDegrees: 0.5,
  sunIntensity: sunIntensity,
  physical: air,
);

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

CameraNode _camera(Vector3 looking) {
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.3,
      far: 500.0,
    ),
  )..lookAt(looking);
  return camera;
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  CameraNode camera, {
  SkySettings sky = const SkySettings(),
}) async {
  final scene = Scene()..add(camera);
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      sky: sky,
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// The pixel at the centre of [frame], which is where the camera points.
Vector3 _centre(Uint8List frame) {
  final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return Vector3(
    frame[at] / 255.0,
    frame[at + 1] / 255.0,
    frame[at + 2] / 255.0,
  );
}

/// The composite pass's encode, which is where linear light becomes bytes.
double _linearToSrgb(double value) {
  final clamped = value.clamp(0.0, 1.0);
  return clamped <= 0.0031308
      ? clamped * 12.92
      : 1.055 * math.pow(clamped, 1.0 / 2.4).toDouble() - 0.055;
}

/// [SkySettings.sample] in [direction], put through what the frame puts the
/// shader's answer through: the default exposure, then the encode.
Vector3 _expected(SkySettings sky, Vector3 direction) {
  final linear = sky.sample(direction)..scale(1.6);
  return Vector3(
    _linearToSrgb(linear.x),
    _linearToSrgb(linear.y),
    _linearToSrgb(linear.z),
  );
}

/// Pixels brighter than their four neighbours by [margin] in green: points
/// of light, which a smooth sky has none of.
int _points(Uint8List frame, {int margin = 30}) {
  int at(int x, int y) => frame[(y * _width + x) * 4 + 1];
  var count = 0;
  for (var y = 1; y < _height - 1; y++) {
    for (var x = 1; x < _width - 1; x++) {
      final here = at(x, y);
      final around = math.max(
        math.max(at(x - 1, y), at(x + 1, y)),
        math.max(at(x, y - 1), at(x, y + 1)),
      );
      if (here > around + margin) count++;
    }
  }
  return count;
}

void main() {
  group('the sky', () {
    test('switched off, it draws nothing, air or no air', () async {
      // Mutation: test `physical != null` in the sky pass before `enabled`.
      // Every golden scene that sets no sky would stay as it is, and a game
      // that turned its sky off at night would keep drawing it.
      final camera = _camera(Vector3(0.0, 0.2, 1.0));
      final off = await _draw(_engine(), camera);
      final unset = await _draw(_engine(), camera, sky: _sky(enabled: false));
      expect(unset, off);
    });

    for (final (name, sunDegrees, looking, intensity)
        in <(String, double, Vector3, double)>[
          ('noon, away from the sun', 50.0, Vector3(-1.0, 0.15, 0.3), 0.0),
          ('noon, straight up', 50.0, Vector3(0.001, 1.0, 0.0), 0.0),
          ('dusk, into the setting sun', 3.0, _sunAt(3.0), 4.0),
          ('the ground, below the horizon', 40.0, Vector3(0.0, -0.4, 1.0), 0.0),
        ]) {
      test('the software stage draws what the model says: $name', () async {
        // Mutation: read any lane of the vertices one place over in
        // `SkyPhysicalShader` — the Mie scale height as the extinction, say.
        // The sky stays a sky, a little hazier or a little bluer, and only
        // this comparison sees it.
        final sky = _sky(sunDegrees: sunDegrees, sunIntensity: intensity);
        final frame = await _draw(_engine(), _camera(looking), sky: sky);
        final drawn = _centre(frame);
        final expected = _expected(sky, looking);
        for (final channel in <int>[0, 1, 2]) {
          expect(
            (drawn[channel] - expected[channel]).abs(),
            lessThan(0.02),
            reason: 'channel $channel: drawn $drawn, the model $expected',
          );
        }
      });
    }

    test('noon is blue overhead and dusk is red towards the sun', () {
      // Mutation: give Rayleigh the same coefficient in every channel, or
      // drop the extinction of the light on its way in. Either way the sky
      // keeps its brightness and loses the colours that make it a time of day.
      const air = PhysicalSky();
      final zenith = air.radiance(Vector3(0.0, 1.0, 0.0), _sunAt(50.0));
      expect(zenith.z, greaterThan(zenith.x * 2.5), reason: '$zenith');

      final sunset = air.radiance(_sunAt(5.0), _sunAt(2.0));
      expect(sunset.x, greaterThan(sunset.z * 3.0), reason: '$sunset');

      // Towards and away at the same height above the horizon: lower down
      // the path through the air is longer and the sky brighter, so a pair
      // at different heights measures the height as much as the sun. The
      // model gives about a quarter; haze that scattered every way alike
      // would give three quarters.
      final towards = air.radiance(Vector3(1.0, 0.05, 0.0), _sunAt(2.0));
      final away = air.radiance(Vector3(-1.0, 0.05, 0.0), _sunAt(2.0));
      expect(
        away.x + away.y + away.z,
        lessThan((towards.x + towards.y + towards.z) / 3.0),
        reason: 'the sky away from a setting sun is the dark half',
      );
    });

    test('the sun goes red as it sets, and out below the horizon', () {
      // Mutation: draw the disc without the air in front of it, which is how
      // the gradient sky draws its own. A noon sun at the horizon.
      const air = PhysicalSky();
      final high = air.sunlight(_sunAt(60.0));
      final low = air.sunlight(_sunAt(2.0));
      expect(high.x / high.z, lessThan(1.3), reason: 'white at noon: $high');
      expect(low.x / low.z, greaterThan(4.0), reason: 'red at dusk: $low');
      expect(air.sunlight(_sunAt(-3.0)).length, 0.0);

      final sky = _sky(sunDegrees: 2.0, sunIntensity: 10.0);
      final disc = sky.sample(_sunAt(2.0));
      final beside = sky.sample(_sunAt(8.0));
      expect(
        disc.x - beside.x,
        greaterThan((disc.z - beside.z) * 4.0),
        reason: 'the disc adds red, not white: $disc against $beside',
      );
    });

    test('the ground is lit while the sun is up and dark once it is down', () {
      // Mutation: drop the ground term. The lower half of an environment map
      // built from the sky goes black at noon, and every floor that reflects
      // it reflects a hole.
      const air = PhysicalSky();
      final down = Vector3(0.3, -1.0, 0.0);
      final day = air.look(down, _sunAt(40.0));
      final night = air.look(down, _sunAt(-15.0));
      expect(day.ground, isTrue);
      expect(day.radiance.y, greaterThan(0.05), reason: '${day.radiance}');
      expect(night.radiance.y, lessThan(1e-4), reason: '${night.radiance}');
    });

    test('stars come out at night, and not by day', () async {
      // Mutation: drop the night fade, or test the sun's height the wrong
      // way round. Stars at noon are points brighter than a smooth sky, and
      // a night with no stars is a black frame.
      final up = _camera(Vector3(0.2, 1.0, 0.4));
      final night = await _draw(_engine(), up, sky: _sky(sunDegrees: -20.0));
      final day = await _draw(_engine(), up, sky: _sky(sunDegrees: 40.0));
      final none = await _draw(
        _engine(),
        up,
        sky: _sky(
          sunDegrees: -20.0,
          air: const PhysicalSky(starBrightness: 0.0),
        ),
      );
      expect(_points(night), greaterThan(5));
      expect(_points(day), 0);
      expect(_points(none), 0);
    });

    test('the sample a probe or a fog colour takes has no stars in it', () {
      // Mutation: add the stars to `SkySettings.sample`. An environment map
      // thirty-two texels a side turns one star into a bright texel, and a
      // night floor reflects it as a lamp.
      final sky = _sky(sunDegrees: -20.0);
      final starless = _sky(
        sunDegrees: -20.0,
        air: const PhysicalSky(starBrightness: 0.0),
      );
      for (var i = 0; i < 64; i++) {
        final direction = Vector3(
          math.cos(i * 0.37),
          0.3 + (i % 7) * 0.1,
          math.sin(i * 0.37),
        );
        expect(sky.sample(direction), starless.sample(direction));
      }
    });

    test('the depth the sky sits at matches sky.vert', () {
      // Read out of the shader source: the physical stage is the gradient's
      // depth by a second copy of a literal, and a second copy is a second
      // chance for the sky to sit in front of the world.
      String depthIn(String file) =>
          RegExp(r'gl_Position = vec4\(position, ([0-9.]+), 1\.0\);')
              .firstMatch(
                File('../flutter3d_shaders/shaders/$file').readAsStringSync(),
              )!
              .group(1)!;
      expect(depthIn('sky_physical.vert'), depthIn('sky.vert'));
    });
  });

  group('height fog', () {
    test('thins upwards from its base height', () {
      // Mutation: fold the base height in with the wrong sign. The fog lies
      // on the ceiling.
      const fog = FogSettings(
        density: 0.1,
        heightFalloff: 0.5,
        baseHeight: 3.0,
      );
      expect(fog.densityAt(3.0), closeTo(0.1, 1e-12));
      expect(fog.densityAt(5.0), closeTo(0.1 * math.exp(-1.0), 1e-12));
      expect(fog.densityAt(1.0), closeTo(0.1 * math.exp(1.0), 1e-12));
      expect(const FogSettings(density: 0.1).densityAt(1000.0), 0.1);
      expect(
        const FogSettings(density: 0.1, heightFalloff: -1.0).densityAt(9.0),
        0.1,
        reason: 'a negative falloff is held at nought',
      );
    });

    test('a ray through it is fogged by the air it crosses', () async {
      // The closed form in `ApplyFog` against the integral done the long
      // way: a wall seen up a slope through a height fog has to come out as
      // a wall seen through a flat fog of the mean density along that ray.
      //
      // Mutation: take `k` from the eye down to the surface instead of up to
      // it, or drop the integral and fog by the density at the eye. The
      // first fogs a hill as thick as a valley; the second is a flat fog.
      const distance = 60.0;
      final slope = Vector3(0.0, 0.25, 1.0).normalized();
      const height = FogSettings(density: 0.03, heightFalloff: 0.12);

      // The mean density over the ray, by the midpoint rule.
      const steps = 4000;
      var sum = 0.0;
      for (var i = 0; i < steps; i++) {
        sum += height.densityAt(slope.y * distance * (i + 0.5) / steps);
      }
      final flat = FogSettings(density: sum / steps);

      final up = await _wallMean(height, slope, distance);
      final even = await _wallMean(flat, slope, distance);
      final eye = await _wallMean(
        const FogSettings(density: 0.03),
        slope,
        distance,
      );
      expect((up - even).abs(), lessThan(1.5), reason: 'up $up, even $even');
      expect(up, greaterThan(eye + 20.0), reason: 'thinner than at the eye');
    });

    test('with no falloff it is the flat fog, to the byte', () async {
      // The property every golden with fog in it rests on.
      final slope = Vector3(0.0, 0.25, 1.0).normalized();
      final a = await _wallMean(const FogSettings(density: 0.03), slope, 60.0);
      final b = await _wallMean(
        const FogSettings(density: 0.03, baseHeight: 40.0),
        slope,
        60.0,
      );
      expect(a, b);
    });
  });
}

/// The mean of the red channel over a grey wall facing the camera,
/// [distance] metres along [looking], through [fog] of black.
Future<double> _wallMean(
  FogSettings fog,
  Vector3 looking,
  double distance,
) async {
  final it = _engine();
  final scene = Scene();
  final camera = _camera(looking);
  scene
    ..add(camera)
    ..add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3(2.0, 2.0, 0.1)).build(),
        ),
        engine.Material(
          name: 'wall',
          baseColor: Vector4(0.5, 0.5, 0.5, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'wall',
      )..setPosition(
        looking.x * distance,
        looking.y * distance,
        looking.z * distance,
      ),
    );
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      fog: fog.copyWith(color: Vector3.zero()),
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = (await it.device.readPixels(
    result.frame,
  ))!.buffer.asUint8List();
  // The centre pixel only: the wall is small at sixty metres, and the
  // centre is where the ray is the one the integral was taken along.
  return pixels[((_height ~/ 2) * _width + _width ~/ 2) * 4].toDouble();
}
