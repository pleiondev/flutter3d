/// A mirror ball between two coloured walls shows each wall on its own side.
///
///     flutter test --platform chrome test/reflection_probe_test.dart
///
/// **The check `supportsRenderToMip` is answered by.** That capability is not a
/// question about attachments; it is a promise that a reflection probe works
/// here, because `ReflectionProbeNode.supportedOn` reads it and a device that
/// says yes is handed a probe to fill. The conformance suite asks the device
/// half — a pass aimed at one face of one level lands there, and its viewport
/// covers that level — and neither of those would notice a probe that captured
/// six views and then convolved them into a chain nobody sampled. So the
/// promise is checked where it is made: through the engine's own renderer,
/// against a room whose reflection has a side to it.
///
/// Direction is what a picture can prove and what nothing else here can. A red
/// wall at +X has to appear on the ball's right and a blue wall at −X on its
/// left; a probe with a face mirrored, a face upside down, two faces
/// transposed, or a chain filtered from the wrong level puts a colour on the
/// wrong side, and every one of those draws a plausible reflection. The
/// software backend asks the same three questions of the same room in
/// `flutter3d_cpu/test/reflection_probe_test.dart`, deliberately: two
/// rasterisers that agree about which side is which agree about the whole face
/// table.
///
/// **Chrome only.** There is no WebGPU on the Dart VM, and a browser without
/// one reports rather than fails — a red line about the machine is not a
/// finding about the code.
@TestOn('browser')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _width = 96;
const int _height = 96;

/// How far either side of the centre the ball is sampled.
///
/// The ball's projected radius is about a third of the frame; at seventy per
/// cent of it the surface normal is far enough round for the reflection to have
/// turned towards a wall, and still well inside the silhouette.
const int _offset = 22;

/// A wall at [at], its plane turned by [roll] about z so it faces the ball.
///
/// Unlit, so the colour on it is the colour in it whatever the light does, and
/// both sides drawn, so which way the plane's normal ends up cannot cull it out
/// of a probe face.
MeshNode _wall(
  WebGpuDevice device,
  Vector3 at,
  double roll,
  Vector4 colour,
  String name,
) =>
    MeshNode(
        DeviceMesh.upload(device, const PlaneShape().build()),
        Material(
          name: name,
          baseColor: colour,
          lighting: LightingModel.unlit,
          doubleSided: true,
        ),
        name: name,
      )
      ..setPosition(at.x, at.y, at.z)
      ..setScale(6.0, 1.0, 6.0)
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), roll));

/// The renderer, with the two fallback texels every material needs bound.
Renderer _renderer(WebGpuDevice device) {
  TextureHandle texel(List<int> rgba) {
    final made = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
    );
    if (made == null) fail('the device would not make a 1x1 texture');
    return made;
  }

  return Renderer.create(
    device: device,
    fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
    fallbackNormal: texel(<int>[128, 128, 255, 255]),
  );
}

({
  WebGpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
  MeshNode ball,
})
_room(WebGpuDevice device) {
  final scene = Scene()..ambientIntensity = 1.0;

  final ball = MeshNode(
    DeviceMesh.upload(
      device,
      SphereShape(radius: 1.0, segments: 32, rings: 24).build(),
    ),
    Material(
      name: 'mirror',
      baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
      metallic: 1.0,
      roughness: 0.0,
      lighting: LightingModel.pbr,
    ),
    name: 'mirror',
  );

  scene
    ..add(ball)
    // A plane faces +Y; a quarter turn about z lays it flat against +X or −X.
    ..add(
      _wall(device, Vector3(4, 0, 0), math.pi / 2, Vector4(1, 0, 0, 1), 'red'),
    )
    ..add(
      _wall(
        device,
        Vector3(-4, 0, 0),
        -math.pi / 2,
        Vector4(0, 0, 1, 1),
        'blue',
      ),
    )
    ..add(
      LightNode(type: LightType.directional, intensity: 3.0)
        ..setLocalForward(Vector3(0.0, -1.0, -0.3)),
    )
    ..add(ReflectionProbeNode(faceSize: 32, levels: 2)..excluded.add(ball));

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 0.6,
      near: 0.1,
      far: 60.0,
    ),
  )..setPosition(0.0, 0.0, 6.0);
  camera.lookAt(Vector3.zero());
  scene.add(camera);

  return (
    device: device,
    renderer: _renderer(device),
    scene: scene,
    camera: camera,
    ball: ball,
  );
}

Future<Uint8List> _draw(
  ({
    WebGpuDevice device,
    Renderer renderer,
    Scene scene,
    CameraNode camera,
    MeshNode ball,
  })
  it,
) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(
      shadows: ShadowSettings(enabled: false),
      bloom: BloomSettings(enabled: false),
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  if (pixels == null) fail('the frame could not be read back');
  return pixels.buffer.asUint8List();
}

List<int> _at(Uint8List pixels, int x, int y) {
  final i = (y * _width + x) * 4;
  return <int>[pixels[i], pixels[i + 1], pixels[i + 2]];
}

void main() {
  late WebGpuDevice device;

  setUp(() async {
    final made = await WebGpuDevice.create(
      width: _width,
      height: _height,
      stages: engineShaders,
    );
    if (made == null) {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    device = made;
  });

  test('this device offers a probe both halves of what one needs', () {
    // The capability under test, asked directly. It is one line and it is the
    // line the two tests below give meaning to: answering true here without
    // them is how a backend hands `ReflectionProbeNode.supportedOn` a yes and
    // gets a black ball instead of a skip.
    expect(device.supportsCubeTextures, isTrue);
    expect(device.supportsRenderToMip, isTrue);
    expect(ReflectionProbeNode.supportedOn(device), isTrue);
    device.dispose();
  });

  test(
    'the ball shows the red wall on its right and the blue on its left',
    () async {
      final it = _room(device);
      final pixels = await _draw(it);

      final centre = _at(pixels, _width ~/ 2, _height ~/ 2);
      final right = _at(pixels, _width ~/ 2 + _offset, _height ~/ 2);
      final left = _at(pixels, _width ~/ 2 - _offset, _height ~/ 2);

      expect(
        right[0],
        greaterThan(right[2] + 40),
        reason: 'right is red $right',
      );
      expect(left[2], greaterThan(left[0] + 40), reason: 'left is blue $left');
      // Straight ahead the ball reflects the empty space behind the camera,
      // which is the clear colour: neither wall.
      expect(
        centre[0],
        lessThan(40),
        reason: 'centre reflects nothing: $centre',
      );
      expect(centre[2], lessThan(40));
      device.dispose();
    },
  );

  test('a ball with no probe reflects neither wall', () async {
    // The control, and what says the two colours above came out of the probe
    // rather than out of the room being red on one side. The same scene with
    // the probe taken out is a mirror metal in an empty environment, which is
    // nearly black everywhere.
    final it = _room(device);
    it.scene.remove(it.scene.probes.single);
    final pixels = await _draw(it);
    final right = _at(pixels, _width ~/ 2 + _offset, _height ~/ 2);
    final left = _at(pixels, _width ~/ 2 - _offset, _height ~/ 2);
    expect(right[0], lessThan(40), reason: 'no red without a probe: $right');
    expect(left[2], lessThan(40), reason: 'no blue without a probe: $left');
    device.dispose();
  });
}
