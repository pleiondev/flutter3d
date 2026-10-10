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

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// The air the frames here are drawn through: the default with a sun of
/// E/π, so that under the reference camera the sky stays below white and the
/// comparisons against the model compare colours rather than two clipped
/// whites. The default sun is a real noon's, which saturates at f/4.
const PhysicalSky _dimAir = PhysicalSky(
  sunIlluminance: 20.0 * Photometric.legacyNits,
);

SkySettings _sky({
  bool enabled = true,
  double sunDegrees = 30.0,
  double sunIntensity = 0.0,
  PhysicalSky air = _dimAir,
}) => SkySettings(
  enabled: enabled,
  directionToSun: _sunAt(sunDegrees),
  sunAngularRadius: 2.0 * math.pi / 180.0,
  sunSoftness: 0.5 * math.pi / 180.0,
  sunIntensity: sunIntensity * Photometric.legacyUnit,
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
    projection: const PerspectiveProjection(fovY: 1.0, near: 0.3, far: 500.0),
  )..lookAt(looking);
  return camera;
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  CameraNode camera, {
  SkySettings sky = const SkySettings(),
  Vector3? block,
}) async {
  final scene = Scene()..add(camera);
  // A grey block lit by nothing but the ambient, which is the sky's: what
  // the renderer took the ambient from shows on it.
  if (block != null) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3.all(1.0)).build(),
        ),
        engine.RenderMaterial(
          name: 'block',
          baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.5, 1.0),
          lighting: LightingModel.lambert,
        ),
        name: 'block',
      )..setPosition(block.x, block.y, block.z),
    );
  }
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      sky: sky,
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = await it.device.readback(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels.buffer.asUint8List();
}

/// The pixel at the centre of [frame], which is where the camera points.
Vector3 _center(Uint8List frame) {
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

    test('a sky nobody coloured is the physical one', () async {
      // Mutation: make `resolvedPhysical` return `physical` alone, or read
      // `physical` in the sky pass, the ambient or `sample` instead of the
      // resolved air. The first leaves every uncoloured sky a gradient; the
      // others draw one sky and light or fog the world from another, and
      // only a comparison against the named air sees it.
      expect(const SkySettings().resolvedPhysical, same(const PhysicalSky()));
      const named = PhysicalSky(starBrightness: 0.0);
      expect(
        SkySettings(
          physical: named,
          zenith: LinearColor.black,
        ).resolvedPhysical,
        same(named),
        reason: 'air that was named wins over colours',
      );

      final looking = Vector3(-1.0, 0.15, 0.3);
      final block = Vector3(-1.0, -0.25, 0.3).normalized()..scale(4.0);
      final plain = SkySettings(enabled: true, directionToSun: _sunAt(50.0));
      final air = await _draw(
        _engine(),
        _camera(looking),
        sky: plain.copyWith(physical: const PhysicalSky()),
        block: block,
      );
      final drawn = await _draw(
        _engine(),
        _camera(looking),
        sky: plain,
        block: block,
      );
      expect(drawn, air, reason: 'the sky and the block lit by it');

      // And the sample a fog colour or an environment map takes is the same
      // air's, or the fog meets a sky of another colour at the horizon.
      for (final direction in <Vector3>[
        looking,
        Vector3(0.0, 1.0, 0.0),
        Vector3(0.3, -0.5, 1.0),
      ]) {
        expect(
          plain.sample(direction),
          plain.copyWith(physical: const PhysicalSky()).sample(direction),
        );
      }
    });

    test('a coloured sky keeps the gradient it was given', () async {
      // Mutation: drop the colours from the test in `resolvedPhysical`. Every
      // level that chose its three colours would come up in the default air.
      for (final coloured in <SkySettings>[
        SkySettings(zenith: LinearColor(0.1, 0.2, 0.5)),
        SkySettings(horizon: LinearColor(0.4, 0.5, 0.6)),
        SkySettings(nadir: LinearColor(0.1, 0.1, 0.1)),
        SkySettings(sunColor: LinearColor(1.0, 0.9, 0.8)),
      ]) {
        expect(coloured.resolvedPhysical, isNull);
      }

      // The default zenith written out: the gradient the engine always drew,
      // asked for by naming one of its colours.
      final looking = Vector3(-1.0, 0.15, 0.3);
      final sky = SkySettings(
        enabled: true,
        directionToSun: _sunAt(50.0),
        zenith: LinearColor(0.10, 0.22, 0.52),
      );
      final frame = await _draw(_engine(), _camera(looking), sky: sky);
      final drawn = _center(frame);
      final gradient = _expected(sky, looking);
      final air = _expected(
        sky.copyWith(physical: const PhysicalSky()),
        looking,
      );
      for (final channel in <int>[0, 1, 2]) {
        expect(
          (drawn[channel] - gradient[channel]).abs(),
          lessThan(0.02),
          reason: 'channel $channel: drawn $drawn, the gradient $gradient',
        );
      }
      expect(
        (drawn - air).length,
        greaterThan(0.05),
        reason: 'and not the air, $air, which would make the check above moot',
      );
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
        final drawn = _center(frame);
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

    test('the sky is luminance: thin air overhead reads E·β·H·p in nits', () {
      // Mutation: carry the sunlight on the illuminance scale again
      // (`luxToEngine` in `PhysicalSky._sun` or the sky pass), which is what
      // the sky did before 1.0-rc.1: the same blue, π times too dark.
      //
      // Optically thin air, no haze, no ozone, sun and eye both straight up:
      // single scattering is the sunlight times the column of air above the
      // eye, β·H·e^(−altitude/H), times Rayleigh's phase function looking
      // back along the beam, 3/(8π) per steradian.
      const e = 100000.0;
      const beta = 1.0e-8;
      const height = 8000.0;
      final air = PhysicalSky(
        rayleigh: Vector3.all(beta),
        rayleighScaleHeight: height,
        mie: 0.0,
        mieAbsorption: 0.0,
        ozone: 0.0,
        sunIlluminance: e,
      );
      final up = Vector3(0.0, 1.0, 0.0);
      final nits = air.radiance(up, up).y * Photometric.legacyNits;
      final column =
          beta *
          height *
          (math.exp(-200.0 / height) - math.exp(-60000.0 / height));
      final expected = e * column * 3.0 / (8.0 * math.pi);
      expect(nits, closeTo(expected, expected * 0.05));
    });

    test('ozone keeps the zenith blue at dusk and leaves noon alone', () {
      // Mutation: drop ozone from `Through`. The dusk zenith turns grey, since
      // the green and red that ozone takes on the sunlight's long way in stay.
      const ozone = PhysicalSky();
      const none = PhysicalSky(ozone: 0.0);
      final up = Vector3(0.001, 1.0, 0.0);
      final dusk = ozone.radiance(up, _sunAt(2.0));
      final duskNone = none.radiance(up, _sunAt(2.0));
      expect(dusk.z / dusk.y, greaterThan(duskNone.z / duskNone.y * 1.2));
      final noon = ozone.radiance(up, _sunAt(60.0));
      final noonNone = none.radiance(up, _sunAt(60.0));
      expect((noon.y / noonNone.y - 1.0).abs(), lessThan(0.06));
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
          air: _dimAir.copyWith(starBrightness: 0.0),
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
        air: _dimAir.copyWith(starBrightness: 0.0),
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
      // Read out of the shader source. Since `A2.8` the depth rides on the
      // vertices with the corner (one at the far plane either way round), so
      // both stages must take it from there and neither may keep a literal:
      // a second copy of a number is a second chance for the sky to sit in
      // front of the world.
      String positionIn(String file) =>
          RegExp(r'gl_Position = (vec4\([^;]*\));')
              .firstMatch(
                File('../flutter3d_shaders/shaders/$file').readAsStringSync(),
              )!
              .group(1)!;
      expect(positionIn('sky.vert'), 'vec4(position, 1.0)');
      expect(positionIn('sky_physical.vert'), positionIn('sky.vert'));
    });
  });

  group('height fog', () {
    test('is what a fog gets unless it asks for a flat one', () async {
      // Mutation: put the constructor's default back to nought. A fog that
      // names only its density is then flat, and the wall up the slope is as
      // fogged as one at the eye's height.
      expect(
        const FogSettings().heightFalloff,
        FogSettings.defaultHeightFalloff,
      );
      expect(FogSettings.defaultHeightFalloff, greaterThan(0.0));

      final slope = Vector3(0.0, 0.25, 1.0).normalized();
      final byDefault = await _wallMean(
        const FogSettings(density: 0.03),
        slope,
        60.0,
      );
      final asked = await _wallMean(
        const FogSettings(
          density: 0.03,
          heightFalloff: FogSettings.defaultHeightFalloff,
        ),
        slope,
        60.0,
      );
      final flat = await _wallMean(
        const FogSettings(density: 0.03, heightFalloff: 0.0),
        slope,
        60.0,
      );
      expect(byDefault, asked);
      expect(byDefault, greaterThan(flat + 5.0), reason: 'flat $flat');
    });

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
      expect(
        const FogSettings(density: 0.1, heightFalloff: 0.0).densityAt(1000.0),
        0.1,
        reason: 'nought, asked for, is the same fog at every height',
      );
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
      final flat = FogSettings(density: sum / steps, heightFalloff: 0.0);

      final up = await _wallMean(height, slope, distance);
      final even = await _wallMean(flat, slope, distance);
      final eye = await _wallMean(
        const FogSettings(density: 0.03, heightFalloff: 0.0),
        slope,
        distance,
      );
      expect((up - even).abs(), lessThan(1.5), reason: 'up $up, even $even');
      expect(up, greaterThan(eye + 20.0), reason: 'thinner than at the eye');
    });

    test('with no falloff it is the flat fog, to the byte', () async {
      // The property a golden recorded with a flat fog rests on: asking for
      // nought gives back the fog from before `P5`, wherever its base is.
      final slope = Vector3(0.0, 0.25, 1.0).normalized();
      final a = await _wallMean(
        const FogSettings(density: 0.03, heightFalloff: 0.0),
        slope,
        60.0,
      );
      final b = await _wallMean(
        const FogSettings(density: 0.03, heightFalloff: 0.0, baseHeight: 40.0),
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
        engine.RenderMaterial(
          name: 'wall',
          baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.5, 1.0),
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
      RenderView(camera: camera, clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      fog: fog.copyWith(color: LinearColor.black),
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = (await it.device.readback(result.frame)).buffer.asUint8List();
  // The centre pixel only: the wall is small at sixty metres, and the
  // centre is where the ray is the one the integral was taken along.
  return pixels[((_height ~/ 2) * _width + _width ~/ 2) * 4].toDouble();
}
