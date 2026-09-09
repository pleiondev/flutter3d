/// What stands beside the road, checked by drawing it.
///
/// The signs were invisible twice for two different reasons — a board facing
/// away from the road, and before that a whole roadside five metres in the air
/// — and both times a screenshot through the circuit's own haze was too weak to
/// say which. This renders a sign at arm's length on the software backend and
/// reads the pixels, which is the same oracle the goldens use.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_racing/src/roadside.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// A wide ring, the shape the tests in this directory already use.
TrackSpline _ring() => TrackSpline(
  centre: CatmullRom(<Vector3>[
    Vector3(60.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 60.0),
    Vector3(-60.0, 0.0, 0.0),
    Vector3(0.0, 0.0, -60.0),
  ]),
  widths: List<double>.filled(4, 12.0),
  banks: List<double>.filled(4, 0.0),
  surfaces: const <SurfaceBand>[],
  checkpoints: const <double>[],
  grid: const StartGrid(s: 0.0, columns: 2),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sign shows its widget rather than its edge', () async {
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

    // Two halves rather than one colour: a flat board proves the texture
    // arrived and says nothing about which way round it arrived, and a
    // mirrored sign is exactly what a driver reported.
    final face = device.createTextureFromPixels(
      width: 2,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[220, 30, 30, 255, 30, 200, 60, 255]),
      ),
    )!;

    final scene = Scene();
    final track = _ring();
    final added = addRoadsideTo(
      scene,
      track,
      device: device,
      signs: <TextureHandle>[face],
    );
    final board = added.firstWhere((SceneNode n) => n.name == 'sign-0');
    final at = board.readPosition();

    scene.add(
      LightNode(color: Vector3(1.0, 1.0, 1.0), intensity: 3.0, name: 'sun')
        ..lookAt(Vector3(0.2, -1.0, 0.3)),
    );
    scene.ambientIntensity = 0.6;

    // Where the board is looking. A plane's face is its +Y before anything is
    // rotated, so the world normal is that vector through the node's rotation.
    final zero = board.worldMatrix.transformed3(Vector3.zero());
    final facing = board.worldMatrix.transformed3(Vector3(0.0, 1.0, 0.0))
      ..sub(zero)
      ..normalize();

    // Upright: a board still lying down has a vertical normal, which is the
    // canopy-on-posts this looked like before the pitch was believed.
    expect(facing.y.abs(), lessThan(0.2), reason: 'the board is lying down');

    // And looking across the road rather than along it. The sign stands beside
    // the centre line, so its face has to point back towards it.
    final towardsRoad = Vector3(-at.x, 0.0, -at.z)..normalize();
    expect(
      facing.dot(towardsRoad),
      greaterThan(0.7),
      reason:
          'the board faces ${facing.storage}, which is across the driver '
          'rather than at them',
    );

    // Stand in front of the face and look at it, so what is measured is the
    // face rather than where the camera happened to be.
    final eye = at + facing * 14.0;
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.05,
        near: 0.3,
        far: 400.0,
      ),
    )..setPosition(eye.x, eye.y, eye.z);
    camera.lookAt(at);
    scene.add(camera);

    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.3, 1.0)),
      ],
    );
    final pixels = (await device.readPixels(
      result.frame,
    ))!.buffer.asUint8List();

    // How much of the frame came out red, against a blue background. A board
    // edge-on covers a line of pixels; a board facing the camera covers a
    // patch of them.
    var red = 0, green = 0, redOnLeft = 0, redOnRight = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final i = (y * _width + x) * 4;
        final isRed = pixels[i] > 90 && pixels[i + 1] < 90;
        final isGreen = pixels[i + 1] > 90 && pixels[i] < 90;
        if (isRed) {
          red++;
          if (x < _width / 2) {
            redOnLeft++;
          } else {
            redOnRight++;
          }
        }
        if (isGreen) green++;
      }
    }
    final share = (red + green) / (_width * _height);

    expect(
      share,
      greaterThan(0.05),
      reason:
          'the sign covers ${(share * 100).toStringAsFixed(1)}% of the '
          'frame, which is what a board seen edge-on or facing away looks like',
    );

    // The texture's first texel is its left one, and a viewer in front of the
    // board sees it on the left. Finding it on the right is a sign read in a
    // mirror, which is what the back of a double-sided board shows.
    expect(
      redOnLeft,
      greaterThan(redOnRight),
      reason:
          'the left half of the texture came out on the right of the '
          'board, so the sign reads backwards',
    );
  });
}
