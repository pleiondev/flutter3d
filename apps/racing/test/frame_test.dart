/// The game, drawn. Not the simulation — the picture.
///
///     flutter test test/frame_test.dart
///
/// The platformer grew this file after three bugs shipped in one afternoon that
/// every one of its simulation tests passed, all of them living in the seam
/// between a simulation that was right and a picture that was wrong. This
/// circuit has the same seam and a wider one: the road here is *generated*, from
/// the same curve the car drives on, so "the car is on the track" and "the track
/// is on the screen" are two separate claims and only one of them has been
/// checked anywhere else.
///
/// `CpuDevice` is a `GraphicsDevice` with no GPU under it, and `readPixels`
/// hands the frame back as bytes. What is assembled is the real thing: the
/// shipped circuit, the real road mesh, the real chase camera. The car's model
/// is left out — it loads through an isolate and is a box in the first seconds
/// of the real game anyway.
///
/// Assertions count pixels rather than compare a golden image. A golden of a
/// kilometre of circuit fails whenever anybody moves a control point and teaches
/// nothing; "there is road under the camera" fails only when the road stops
/// being drawn, which is the bug.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing/src/looks.dart';
import 'package:racing/src/staging.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 160;
const double _dt = 1.0 / 60.0;

/// Everything `main.dart` assembles, minus the half that needs a GPU.
final class _Shown {
  _Shown._(
    this.device,
    this.renderer,
    this.track,
    this.scene,
    this.world,
    this.cars,
    this.carNodes,
    this.simulation,
    this.race,
    this.chase,
    this.camera,
    this.sky,
  );

  static Future<_Shown> build({int cars = 2, SkyPreset? sky}) async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
        )!;
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );

    // The shipped circuit, read off disk the way the game reads it. A test that
    // built its own would be a test of a circuit nobody drives.
    final document = TrackDocument.fromJson(
      jsonDecode(File('assets/tracks/ring.json').readAsStringSync())
          as Map<String, Object?>,
    );
    final track = document.track;
    final hour = sky ?? document.sky;

    final world = CollisionWorld();
    document.level?.addTo(world);

    final scene = Scene();
    // The real road, from the real bridge.
    addTrackTo(scene, track, device: device);

    // A sun, or every surface is the colour of nothing. Aimed rather than
    // given a vector: a light points along its node's local -Z, the same
    // forward axis a camera uses.
    //
    // Taken from the sky preset rather than typed out here, which is the point
    // of the preset: this file used to carry its own copy of the sun's
    // direction, and a copy in a test is the copy nobody updates — the picture
    // being asserted was lit from somewhere the game was not.
    scene.add(
      LightNode(
        color: hour.sunColor,
        intensity: hour.sunIntensity,
        name: 'sun',
      )..lookAt(hour.sunDirection),
    );
    scene.ambientIntensity = hour.ambientIntensity;

    // The shipped assembly, not this file's own. What is left here is the half
    // that needs a device.
    final staged = stage(document, world, cars: cars);
    final vehicles = staged.cars;
    final nodes = <MeshNode>[
      for (var i = 0; i < cars; i++)
        carBox(device, Looks.rival(i), name: 'car-$i'),
    ];
    for (final node in nodes) {
      scene.add(node);
    }

    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.05,
        near: 0.3,
        far: 1600.0,
      ),
    );
    scene.add(camera);

    return _Shown._(
      device,
      renderer,
      track,
      scene,
      world,
      vehicles,
      nodes,
      staged.sim,
      staged.race,
      staged.chase,
      camera,
      hour,
    );
  }

  final CpuDevice device;
  final Renderer renderer;
  final TrackSpline track;
  final Scene scene;
  final CollisionWorld world;
  final List<SphereVehicle> cars;
  final List<MeshNode> carNodes;
  final RacingSimulation simulation;
  final RaceState race;
  final ChaseCamera chase;
  final CameraNode camera;
  final SkyPreset sky;

  /// The preset as the renderer's own sky, exactly as `main.dart` builds it.
  SkySettings get skySettings => SkySettings(
        enabled: true,
        zenith: sky.zenith,
        horizon: sky.horizon,
        nadir: sky.belowHorizon,
        directionToSun: sky.directionToSun,
        sunColor: sky.sunColor,
        glowExponent: sky.glowWide,
        glowStrength: sky.glowStrength,
        sunIntensity: sky.sunDisc,
      );

  /// Which way the camera is looking, kept because the sky and the haze both
  /// depend on it — exactly as `main.dart` keeps it.
  final Vector3 gaze = Vector3(0.0, 0.0, 1.0);

  /// Points the camera by hand, for the tests that are about the air rather
  /// than about the driving.
  void aim({required Vector3 from, required Vector3 towards}) {
    camera
      ..setPositionFrom(from)
      ..lookAt(towards);
    gaze
      ..setFrom(towards)
      ..sub(from);
  }

  /// Drives everyone forwards for [seconds], the way the application does.
  void run(double seconds, {double throttle = 0.8}) {
    final steps = (seconds / _dt).round();
    final aim = Vector3.zero();
    final toAim = Vector3.zero();
    for (var step = 0; step < steps; step++) {
      for (var i = 0; i < cars.length; i++) {
        final car = cars[i];
        track.centreAt(car.trackDistance + math.max(14.0, car.speed * 0.6), aim);
        toAim
          ..setFrom(aim)
          ..sub(car.position);
        var turn = math.atan2(toAim.x, toAim.z) - car.headingYaw;
        while (turn > math.pi) {
          turn -= 2 * math.pi;
        }
        while (turn < -math.pi) {
          turn += 2 * math.pi;
        }
        simulation.inputs[i]
          ..throttle = throttle
          // Negated, as in the playthrough: see `SphereVehicle._steer`.
          ..steer = (-turn * 2.2).clamp(-1.0, 1.0);
      }
      simulation.step(_dt);
    }
    _place();
  }

  void _place() {
    for (var i = 0; i < cars.length; i++) {
      carNodes[i]
        ..setPositionFrom(cars[i].position)
        ..setRotation(Quaternion.fromRotation(cars[i].visualBasis));
    }
    chase.follow(cars[0], _dt);
    camera
      ..setPositionFrom(chase.eye)
      ..lookAt(chase.target);
    gaze
      ..setFrom(chase.target)
      ..sub(chase.eye);
  }

  /// [hazeAlong] overrides the direction the haze is worked out for, leaving
  /// the camera where it is — the one way to see what the fog colour alone is
  /// doing, since moving the camera changes the sky, the geometry and the
  /// lighting all at once.
  Future<Uint8List> draw({
    String? hiding,
    Vector3? hazeAlong,
    SkySettings? withSky,
  }) async {
    if (hiding != null) {
      for (final MeshNode piece in scene.meshes) {
        if (piece.name == hiding) piece.visible = false;
      }
    }
    // The sky and the haze the application draws with, worked out the same way:
    // from the preset, along the direction the camera is looking. Without any
    // fog at all the background is black, and so is a tarmac road under a low
    // sun — the first draft of this file counted eighty percent of the frame as
    // road and was counting the empty sky.
    final background = sky.colourAt(gaze);
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(
          camera: camera,
          clearColor: Vector4(background.x, background.y, background.z, 1.0),
        ),
      ],
      settings: RenderSettings(
        sky: withSky ?? skySettings,
        fog: FogSettings(
          color: sky.inScatterAlong(hazeAlong ?? gaze),
          density: sky.fogDensity,
        ),
        exposure: sky.exposure,
      ),
    );
    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    return pixels!.buffer.asUint8List();
  }
}


/// The average colour of whatever reads as tarmac, for the ambient above.
Vector3 _averageRoad(Uint8List rgba) {
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final rr = rgba[i], gg = rgba[i + 1], bb = rgba[i + 2];
    if (rr > 12 && rr < 150 && (gg - rr).abs() < 16 && (bb - gg).abs() < 26) {
      r += rr;
      g += gg;
      b += bb;
      n++;
    }
  }
  expect(n, greaterThan(200), reason: 'there is no road in this frame to read');
  return Vector3(r / n, g / n, b / n);
}

/// How many pixels read as tarmac: mid-dark, and grey rather than green.
///
/// The road is (0.17, 0.175, 0.185) — nearly neutral — the verge is
/// (0.14, 0.24, 0.11), clearly green, and the sky is bright. The first draft of
/// this asked only for "dark and neutral", which is also what the renderer
/// clears to, so it counted the empty sky as eighty percent road and passed
/// whether or not a road was drawn at all.
int _roadPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (r > 12 && r < 150 && (g - r).abs() < 16 && (b - g).abs() < 26) count++;
  }
  return count;
}

int _greenPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (g > r + 12 && g > b + 12) count++;
  }
  return count;
}

/// How many pixels read as the player's car, which is the first colour in the
/// palette: strongly red.
int _playerPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (r > 90 && r > g * 1.8 && r > b * 1.8) count++;
  }
  return count;
}

int _differences(Uint8List a, Uint8List b, {int threshold = 12}) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > threshold ||
        (a[i + 1] - b[i + 1]).abs() > threshold ||
        (a[i + 2] - b[i + 2]).abs() > threshold) {
      count++;
    }
  }
  return count;
}

void main() {
  test('the circuit is drawn at all', () async {
    final shown = await _Shown.build();
    shown.run(3.0);

    final frame = await shown.draw();

    expect(_roadPixels(frame), greaterThan(400),
        reason: 'the camera is behind a car on a road and should see one');
    expect(_greenPixels(frame), greaterThan(200),
        reason: 'and the ground either side of it');
  });

  test('the road is what the car is on, not something beside it', () async {
    // The claim the generated road exists to make: the mesh and the driving
    // surface come from one description. Hiding the road leaves a car-shaped
    // hole over green — if the two disagreed, the car would already be over
    // green with the road drawn.
    final shown = await _Shown.build();
    shown.run(3.0);

    final withRoad = await shown.draw();
    final withoutRoad = await shown.draw(hiding: 'road');

    expect(_roadPixels(withRoad), greaterThan(2000));
    expect(_roadPixels(withoutRoad), lessThan(200),
        reason: 'with the road hidden there is nothing else that colour');
  });

  test('the player is on screen, and is drawn', () async {
    // Mutation: never move the car's node. It would sit at the origin, which on
    // this circuit is the middle of the infield — visible, and nowhere near the
    // camera.
    final shown = await _Shown.build();
    shown.run(3.0);

    final frame = await shown.draw();
    final hidden = await shown.draw(hiding: 'car-0');

    expect(_playerPixels(frame), greaterThan(30));
    expect(_playerPixels(hidden), lessThan(_playerPixels(frame) ~/ 2));
  });

  test('the picture changes as the car goes round', () async {
    // Mutation: leave the camera at the origin. Every frame would be identical
    // and every test above would still pass, because the road and the cars
    // would still be somewhere in shot.
    final shown = await _Shown.build();
    shown.run(3.0);
    final early = await shown.draw();

    shown.run(6.0);
    final later = await shown.draw();

    expect(_differences(early, later), greaterThan(_width * _height ~/ 10));
  });

  test('the car is drawn where the simulation put it', () async {
    final shown = await _Shown.build();
    shown.run(4.0);

    expect(
      shown.carNodes[0].readPosition().distanceTo(shown.cars[0].position),
      lessThan(1e-6),
    );
  });

  test('the camera is behind the car and looking at it', () async {
    final shown = await _Shown.build();
    shown.run(4.0);

    final toCar = shown.cars[0].position - shown.chase.eye;
    final look = shown.chase.target - shown.chase.eye;

    expect(toCar.length, lessThan(14.0));
    expect(toCar.normalized().dot(look.normalized()), greaterThan(0.7));
  });

  group('the sky', () {
    test('the hour changes the picture', () async {
      // Two presets, one pose, one circuit. Everything the sky decides — the
      // background, the haze, the sun's colour and angle, the exposure — is in
      // this difference, and none of it is in the geometry.
      //
      // A difference rather than an absolute, because an absolute would be a
      // golden by another name and would fail the next time anybody moves a
      // control point.
      final golden = await _Shown.build(sky: SkyPresets.golden);
      golden.run(3.0);
      final atGolden = await golden.draw();

      final noon = await _Shown.build(sky: SkyPresets.noon);
      noon.run(3.0);
      final atNoon = await noon.draw();

      // Measured as colour rather than as brightness. Both skies are bright —
      // the tone curve sees to that, and the first draft of this assertion
      // found only ten levels between them and was really measuring the
      // exposure. What separates an evening from a midday is not how much light
      // there is but what colour it is, and that difference is enormous.
      expect(_skyWarmth(atGolden) - _skyWarmth(atNoon), greaterThan(40.0),
          reason: 'a low evening sun is warm and a high one is blue');
    });

    test('turning into the sun is a different place from turning away',
        () async {
      // Two ends of one axis, from one spot. Everything the direction of the
      // view decides is in this difference: the background, the haze, and which
      // side of every surface the sun is on.
      final shown = await _Shown.build(sky: SkyPresets.golden);
      shown.run(3.0);

      final toSun = shown.sky.directionToSun;
      final flat = Vector3(toSun.x, 0.0, toSun.z).normalized();
      final from = shown.cars[0].position + Vector3(0.0, 4.0, 0.0);

      shown.aim(from: from, towards: from + flat * 100.0);
      final into = await shown.draw();

      shown.aim(from: from, towards: from - flat * 100.0);
      final away = await shown.draw();

      expect(_brightnessOf(into) - _brightnessOf(away), greaterThan(15.0));
    });

    test('and the road is lit by this circuit\'s own sky, not by a grey', () async {
      // **The claim the preset's doc comment used to say was impossible.** It
      // said the renderer wrote one number for ambient and the shader read it
      // as a scalar, so a coloured sky could not reach a surface. That stopped
      // being true when the shader learned to blend an upper and a lower
      // ambient from the sky's own gradient — and nothing here had ever checked
      // it, which is how the comment survived being wrong.
      final it = await _Shown.build(sky: SkyPresets.golden);
      it.run(2.0);

      final lit = _averageRoad(await it.draw());
      final grey =
          _averageRoad(await it.draw(withSky: const SkySettings(enabled: false)));

      // A golden-hour gradient is nowhere near white, so its ambient is both
      // dimmer and warmer than the default. Five per cent is well above the
      // frame-to-frame noise of two renders of the same scene, which is none.
      expect((lit.x - grey.x).abs() / grey.x, greaterThan(0.05),
          reason: 'the sky the circuit is raced under does not light it');
      expect(lit.x, lessThan(grey.x),
          reason: 'a coloured sky lit the road more brightly than white did');
    });

    test('the haze itself carries the direction, not just the background',
        () async {
      // The test above would pass on the strength of the background alone, and
      // the background is the easy half. This one holds the camera still and
      // changes only which way the *air* is lit, so the difference can come
      // from nowhere but `FogSettings.color` reaching the frame.
      //
      // Mutation: return `horizonFogColour` from `inScatterAlong` and ignore
      // the view direction — which is what the engine's own fog does, and what
      // makes distance the same grey whichever way a car is pointing. Nothing
      // else in the repository notices; the frames here go identical.
      final shown = await _Shown.build(sky: SkyPresets.golden);
      shown.run(3.0);

      final toSun = shown.sky.directionToSun;
      final away = Vector3(-toSun.x, -toSun.y, -toSun.z);

      final lit = await shown.draw(hazeAlong: toSun);
      final unlit = await shown.draw(hazeAlong: away);

      expect(_brightnessOf(lit) - _brightnessOf(unlit), greaterThan(2.0),
          reason: 'the fog colour never reached the renderer');
    });
  });

  group('the track file', () {
    test('its sky block is the preset it names', () async {
      // Mutation: change a number in `SKY_PRESETS` in `make_track.py` and not
      // in `sky.dart`. The generated circuit and the fallback every fixture
      // uses would then be two different afternoons, and nothing else in the
      // repository compares them.
      final document = jsonDecode(
        File('assets/tracks/ring.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final block = document['sky'];
      expect(block, isA<Map<String, Object?>>(),
          reason: 'run tool/make_track.py');

      final written = SkyPreset.fromJson(block! as Map<String, Object?>);
      final named = SkyPresets.byName(written.name);
      expect(named, isNotNull,
          reason: '"${written.name}" is not a preset sky.dart knows');

      expect(written.fogDensity, closeTo(named!.fogDensity, 1e-9));
      expect(written.sunElevationDeg, closeTo(named.sunElevationDeg, 1e-9));
      expect(written.sunAzimuthDeg, closeTo(named.sunAzimuthDeg, 1e-9));
      expect(written.exposure, closeTo(named.exposure, 1e-9));
      expect(written.sunDisc, closeTo(named.sunDisc, 1e-9));
      expect(written.ambientIntensity, closeTo(named.ambientIntensity, 1e-9));
      expect((written.horizon - named.horizon).length, lessThan(1e-6));
      expect((written.zenith - named.zenith).length, lessThan(1e-6));
      expect((written.sunColor - named.sunColor).length, lessThan(1e-6));
    });

    test('the sun in the level is the sun in the sky', () async {
      // The level's one directional light is derived from the preset by the
      // generator. If it ever stops being, shadows fall one way and the glow in
      // the sky sits the other, which is the sort of wrongness a person sees
      // without being able to name.
      final document = jsonDecode(
        File('assets/tracks/ring.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final level = document['level']! as Map<String, Object?>;
      final light = (level['lights']! as List<Object?>).first!
          as Map<String, Object?>;
      final written = (light['direction']! as List<Object?>)
          .map((Object? v) => (v! as num).toDouble())
          .toList();

      final sky = SkyPreset.fromJson(document['sky']! as Map<String, Object?>);
      final expected = sky.sunDirection;
      expect(Vector3(written[0], written[1], written[2]).normalized()
          .dot(expected.normalized()), closeTo(1.0, 1e-3));
    });

    test('the ground reaches past where the haze hides its edge', () async {
      // The ground is a square and past its edge there is nothing at all. What
      // stops that showing is the haze, so the two are one decision: the
      // generator sizes the ground from the density, and this is the assertion
      // that it actually did.
      //
      // Mutation: put the reach back to a literal. A preset with clearer air
      // would then end in a visible line halfway to the horizon, and every
      // other test in this file would pass.
      final document = jsonDecode(
        File('assets/tracks/ring.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final level = document['level']! as Map<String, Object?>;
      final brushes = level['brushes']! as List<Object?>;
      final ground = brushes.first! as Map<String, Object?>;
      final size = (ground['size']! as List<Object?>)
          .map((Object? v) => (v! as num).toDouble())
          .toList();

      final sky = SkyPreset.fromJson(document['sky']! as Map<String, Object?>);
      final reach = size[0] / 2;
      expect(math.exp(-sky.fogDensity * reach), lessThan(0.15),
          reason: 'the edge of the ground is still visible through the air');
    });
  });
}

/// Mean luminance of the whole frame, 0 to 255.
double _brightnessOf(Uint8List rgba, {int fromRow = 0, int toRow = _height}) {
  var total = 0.0;
  var count = 0;
  for (var y = fromRow; y < toRow; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      total += 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
      count++;
    }
  }
  return total / count;
}

/// How warm the top eighth of the frame is: mean red minus mean blue.
///
/// The top eighth behind a chase camera is sky and haze and nothing else, and
/// red-minus-blue is what "what time is it" looks like in bytes.
double _skyWarmth(Uint8List rgba) {
  var total = 0.0;
  var count = 0;
  for (var y = 0; y < _height ~/ 8; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      total += rgba[i] - rgba[i + 2];
      count++;
    }
  }
  return total / count;
}
