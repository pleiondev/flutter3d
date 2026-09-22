/// What a metal reflects when the scene gives it something to reflect.
///
///     flutter test test/image_based_lighting_test.dart
///
/// **This is the defect the feature exists for, written down as a test.** A
/// metal has no diffuse response at all. With no environment it was lit by
/// direct light alone and came out very nearly black, which is why both games
/// reached for dark dielectrics wherever they wanted gunmetal — the comment
/// above `_metal` in the dungeon's weapon models says so in its own words.
///
/// Rendered through the software backend, which is the one that can be asked
/// for a picture without a GPU. The GLSL side is the same operations in the
/// same order; that the two agree is what the golden pairs are for.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 48;
const int _cube = 8;

/// Six faces of one bright colour, so anything reflecting them is unmistakable.
List<ByteData> _brightFaces() => <ByteData>[
  for (var face = 0; face < 6; face++)
    () {
      final data = ByteData(_cube * _cube * 4);
      for (var i = 0; i < _cube * _cube; i++) {
        data.setUint8(i * 4, 230);
        data.setUint8(i * 4 + 1, 230);
        data.setUint8(i * 4 + 2, 230);
        data.setUint8(i * 4 + 3, 255);
      }
      return data;
    }(),
];

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera})
_ball() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  final scene = Scene();
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        SphereShape(radius: 1.4, segments: 24, rings: 16).build(),
      ),
      Material(
        name: 'metal',
        baseColor: Vector4(0.9, 0.9, 0.92, 1.0),
        metallic: 1.0,
        roughness: 0.25,
        lighting: LightingModel.pbr,
      ),
      name: 'metal',
    )..setPosition(0.0, 0.0, -4.0),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 60.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  scene.add(camera);

  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it,
) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// Red at the middle of the frame, which is the middle of the sphere.
///
/// A named point rather than the frame's maximum: the maximum picks up whatever
/// is behind the ball as readily as the ball, and the first version of this file
/// measured the background and called it a metal.
int _onTheBall(Uint8List pixels) =>
    pixels[((_height ~/ 2) * _width + _width ~/ 2) * 4];

/// Gives [scene] a bright prefiltered environment, and says how many levels.
void _light(CpuDevice device, Scene scene, {int levels = 4}) {
  final faces = _brightFaces();
  final chain = EnvironmentMap.prefilter(faces, size: _cube, levels: levels);
  expect(chain, isNotNull, reason: 'the environment could not be prefiltered');

  final texture = device.createCubeTextureFromPixels(
    size: _cube,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces,
    mipLevels: chain,
  );
  expect(texture, isNotNull, reason: 'the environment could not be uploaded');

  scene
    ..environment = texture
    ..environmentLevels = levels
    // Turned up from the default so the indirect term is the thing being
    // measured rather than a rounding of it. This scales both the flat ambient
    // and the environment, which is the point of them sharing the knob.
    ..ambientIntensity = 1.0;
}

void main() {
  test('a metal in an empty scene is very nearly black', () async {
    // The state of the world before this feature, kept as a test so the claim
    // is measured rather than remembered.
    final it = _ball();
    it.scene.ambientIntensity = 1.0;

    expect(
      _onTheBall(await _draw(it)),
      lessThan(60),
      reason: 'with nothing to reflect, a metal has almost nothing to show',
    );
  });

  test('and the same metal given an environment reflects it', () async {
    // **The whole feature in one assertion.** Mutation: bind the fallback cube
    // instead of the scene's, or leave `frame_params.w` at zero — the sphere
    // goes back to nearly black and this fails.
    final it = _ball();
    _light(it.device, it.scene);

    final lit = _onTheBall(await _draw(it));
    expect(
      lit,
      greaterThan(120),
      reason: 'a mirror-ish ball in a bright room is a bright ball',
    );
  });

  test('and a rough metal is dimmer than a polished one', () async {
    // Roughness picks the level, so a rough surface gathers a wider, dimmer
    // lobe. Mutation: drop the `* levels` and always sample level zero — both
    // spheres come out identical and this fails, which is the failure that
    // would otherwise read as "roughness does nothing".
    final polished = _ball();
    _light(polished.device, polished.scene);
    final rough = _ball();
    _light(rough.device, rough.scene);
    (rough.scene.root.children.first as MeshNode).material.roughness = 1.0;

    expect(
      _onTheBall(await _draw(rough)),
      lessThanOrEqualTo(_onTheBall(await _draw(polished))),
      reason: 'a rough metal cannot be brighter than a polished one',
    );
  });

  test('and a scene without one is not touched by any of this', () async {
    // The promise the goldens rest on: an environment nobody set changes
    // nothing. Mutation: bind the fallback cube *and* report a level count —
    // every existing reference image moves and this fails first.
    final it = _ball();
    it.scene.ambientIntensity = 1.0;
    final before = await _draw(it);

    final again = _ball();
    again.scene.ambientIntensity = 1.0;
    expect(await _draw(again), equals(before));
  });
}
