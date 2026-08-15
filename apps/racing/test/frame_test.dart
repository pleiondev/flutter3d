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
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing/src/looks.dart';
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
  );

  static Future<_Shown> build({int cars = 2}) async {
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

    final world = CollisionWorld();
    document.level?.addTo(world);

    final scene = Scene();
    // The real road, from the real bridge.
    addTrackTo(scene, track, device: device);

    // A sun, or every surface is the colour of nothing. Aimed rather than
    // given a vector: a light points along its node's local -Z, the same
    // forward axis a camera uses.
    scene.add(
      LightNode(
        color: Vector3(1.0, 0.97, 0.9),
        intensity: 3.0,
        name: 'sun',
      )..lookAt(Vector3(-0.4, -0.8, 0.45)),
    );

    final field = TrackField(track: track, world: world);
    final race = RaceState(
      mode: RaceMode.race,
      track: track,
      racers: cars,
      laps: 3,
    );

    final vehicles = <SphereVehicle>[];
    final nodes = <MeshNode>[];
    final position = Vector3.zero();
    final forward = Vector3.zero();
    for (var i = 0; i < cars; i++) {
      track.startSlot(i, position, forward);
      final car = SphereVehicle(
        world: world,
        ground: field,
        position: position.clone()..y += 0.6,
        headingYaw: math.atan2(forward.x, forward.z),
      );
      car.placeAt(
        car.position,
        car.headingYaw,
        trackDistance: track.centre.wrap(track.grid.s),
      );
      vehicles.add(car);

      final node = carBox(device, Looks.rival(i), name: 'car-$i');
      scene.add(node);
      nodes.add(node);
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
      RacingSimulation(collision: world, vehicles: vehicles, race: race),
      race,
      ChaseCamera(world: world, track: track),
      camera,
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
  }

  Future<Uint8List> draw({String? hiding}) async {
    if (hiding != null) {
      for (final MeshNode piece in scene.meshes) {
        if (piece.name == hiding) piece.visible = false;
      }
    }
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.62, 0.71, 0.82, 1.0)),
      ],
      // The same fog the application draws with. Without it the background is
      // black, and so is a tarmac road under a low sun — the first draft of
      // this file counted eighty percent of the frame as road and was counting
      // the empty sky.
      settings: RenderSettings(
        fog: FogSettings(
          color: Vector3(0.62, 0.71, 0.82),
          density: 0.0016,
        ),
      ),
    );
    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    return pixels!.buffer.asUint8List();
  }
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
}
