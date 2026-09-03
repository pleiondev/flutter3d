/// The x-ray stage drawn through this backend, pixel by pixel.
///
/// The fake device pins the *sequence* the stage emits; this pins what the
/// sequence does to a picture when every call is honoured, on the one
/// backend where a picture can be drawn in a test. Two frames, one question
/// each: a cube nothing hides keeps its own colour everywhere, and a cube a
/// wall hides comes back as the silhouette colour where the wall is.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;
const int _layer = 1 << 2;

/// The silhouette colour, chosen so no lit surface here can reach it: pure
/// green, against an unlit white cube and an unlit grey wall.
final Vector3 _silhouette = Vector3(0.0, 1.0, 0.0);

bool _isSilhouette(int r, int g, int b) => g > 200 && r < 60 && b < 60;
bool _isWhite(int r, int g, int b) => r > 200 && g > 200 && b > 200;

Future<Uint8List> _frame({required bool wall, required bool xray}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();
  scene.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build(),
        ),
        Material(
          name: 'cube',
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'cube',
      )
      ..layerMask = 1 | _layer
      ..setPosition(0.0, 0.0, -8.0),
  );
  if (wall) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(6.0, 6.0, 0.2)).build(),
        ),
        Material(
          name: 'wall',
          baseColor: Vector4(0.3, 0.3, 0.3, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'wall',
      )..setPosition(0.0, 0.0, -5.0),
    );
  }
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 50.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -8.0));
  scene.add(camera);

  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      shadows: const ShadowSettings(enabled: false),
      tonemap: false,
      exposure: 1.0,
      xray: XraySettings(color: _silhouette, layerMask: xray ? _layer : 0),
    ),
  );
  final bytes = await device.readPixels(result.frame);
  return bytes!.buffer.asUint8List();
}

int _count(Uint8List rgba, bool Function(int, int, int) wanted) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (wanted(rgba[i], rgba[i + 1], rgba[i + 2])) count++;
  }
  return count;
}

void main() {
  test('a cube nothing hides keeps its own colour everywhere', () async {
    // The mark has to land on every visible pixel of the cube, or the paint
    // that follows lands there instead: a visible surface painted flat is
    // the stage getting its two depth tests the wrong way round, or the
    // mark and the paint disagreeing about where the surface is.
    final plain = await _frame(wall: false, xray: false);
    final marked = await _frame(wall: false, xray: true);
    expect(_count(marked, _isSilhouette), 0);
    expect(
      _count(marked, _isWhite),
      _count(plain, _isWhite),
      reason: 'the cube is the same size with the stage on and off',
    );
  });

  test('a cube a wall hides comes back as the silhouette colour', () async {
    final hidden = await _frame(wall: true, xray: false);
    final seen = await _frame(wall: true, xray: true);
    expect(_count(hidden, _isSilhouette), 0, reason: 'off is off');
    expect(_count(hidden, _isWhite), 0, reason: 'the wall hides the cube');
    // Every pixel of the cube's footprint, since the wall hides all of it —
    // which is the same number of pixels the cube has without the wall.
    final footprint = _count(await _frame(wall: false, xray: false), _isWhite);
    expect(_count(seen, _isSilhouette), footprint);
  });
}
