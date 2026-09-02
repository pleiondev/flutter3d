/// A mirror ball between two coloured walls shows each wall on its own side.
///
///     flutter test test/reflection_probe_test.dart
///
/// The whole chain, through the software backend: a probe captures six views
/// into a cube face by face, the prefilter writes the chain level by level,
/// and the physical model reads the nearest probe. What a picture can prove
/// about it is direction — a red wall at +X has to appear on the ball's right
/// and a blue wall at −X on its left. A probe with a face mirrored, a face
/// upside down, or two faces transposed would put a colour on the wrong side,
/// and no other test here could see it.
///
/// The prefilter stage itself is held to two things the arithmetic promises:
/// one tap copies the capture, and a uniform capture stays uniform under any
/// roughness.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 96;

/// A wall at [at], its plane turned by [roll] about z so it faces the ball.
///
/// Unlit, so the colour on it is the colour in it whatever the light does,
/// and both sides drawn, so which way the plane's normal ends up cannot cull
/// it out of a face.
MeshNode _wall(
  CpuDevice device,
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

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera})
_room() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
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
      _wall(
        device,
        Vector3(4.0, 0.0, 0.0),
        math.pi / 2,
        Vector4(1, 0, 0, 1),
        'red',
      ),
    )
    ..add(
      _wall(
        device,
        Vector3(-4.0, 0.0, 0.0),
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
    settings: const RenderSettings(
      shadows: ShadowSettings(enabled: false),
      bloom: BloomSettings(enabled: false),
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  return pixels!.buffer.asUint8List();
}

List<int> _at(Uint8List pixels, int x, int y) {
  final i = (y * _width + x) * 4;
  return <int>[pixels[i], pixels[i + 1], pixels[i + 2]];
}

void main() {
  test(
    'the ball shows the red wall on its right and the blue on its left',
    () async {
      // The point on the ball whose normal is forty-five degrees to the right
      // reflects straight along +X, into the red wall; its mirror image on the
      // left reflects into the blue one. Mutation: drop the x mirror in
      // `probeFaceViewProjection`, or swap the +X and −X faces — the colours
      // change sides and both assertions fail.
      final it = _room();
      final pixels = await _draw(it);

      // The ball's projected radius is about a third of the frame; sample at
      // seventy percent of it either side of the centre, well inside the
      // silhouette and well past where the reflection turns towards the walls.
      final centre = _at(pixels, _width ~/ 2, _height ~/ 2);
      final right = _at(pixels, _width ~/ 2 + 22, _height ~/ 2);
      final left = _at(pixels, _width ~/ 2 - 22, _height ~/ 2);

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
    },
  );

  test('a ball with no probe reflects neither wall', () async {
    // The control: the same room without the probe is a metal in an empty
    // scene, which is nearly black everywhere. Mutation: bind the probe
    // whether or not one is in the scene — this fails first.
    final it = _room();
    it.scene.remove(it.scene.probes.single);
    final pixels = await _draw(it);
    final right = _at(pixels, _width ~/ 2 + 22, _height ~/ 2);
    final left = _at(pixels, _width ~/ 2 - 22, _height ~/ 2);
    expect(right[0], lessThan(40), reason: 'no red without a probe: $right');
    expect(left[2], lessThan(40), reason: 'no blue without a probe: $left');
  });

  group('the prefilter stage', () {
    late CpuDevice device;
    late BoundTexture capture;

    setUp(() {
      device = CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      // Six faces, six colours: red, green, blue, yellow, magenta, cyan.
      const colours = <List<int>>[
        <int>[255, 0, 0],
        <int>[0, 255, 0],
        <int>[0, 0, 255],
        <int>[255, 255, 0],
        <int>[255, 0, 255],
        <int>[0, 255, 255],
      ];
      final cube = device.createCubeTextureFromPixels(
        size: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: <ByteData>[
          for (final c in colours)
            ByteData.sublistView(
              Uint8List.fromList(<int>[
                for (var i = 0; i < 16; i++) ...<int>[c[0], c[1], c[2], 255],
              ]),
            ),
        ],
      )!;
      capture = BoundTexture(
        cube.backend as CpuTexture,
        SamplerOptions.linearClamp,
      );
    });

    Vector4 run(int face, double roughness, int samples, double s, double t) =>
        const ProbePrefilterShader().run(
          Float32List.fromList(<double>[s, t]),
          ShaderBindings(
            <String, Map<String, Float32List>>{
              'ProbeInfo': <String, Float32List>{
                'params': Float32List.fromList(<double>[
                  face.toDouble(),
                  roughness,
                  0.0,
                  samples.toDouble(),
                ]),
              },
            },
            <String, BoundTexture>{'capture_texture': capture},
          ),
          FragmentContext(),
        )!;

    test('one tap copies the face it is told to', () {
      // The mirror level, and the conformance check's readback. Mutation:
      // swap two cases of `probeFaceDirection` — a face comes back the colour
      // of its neighbour.
      expect(run(0, 0.0, 1, 0.5, 0.5).x, closeTo(1.0, 1e-6));
      expect(run(0, 0.0, 1, 0.5, 0.5).y, closeTo(0.0, 1e-6));
      expect(run(2, 0.0, 1, 0.5, 0.5).z, closeTo(1.0, 1e-6));
      expect(run(2, 0.0, 1, 0.5, 0.5).x, closeTo(0.0, 1e-6));
      expect(run(5, 0.0, 1, 0.5, 0.5).y, closeTo(1.0, 1e-6));
      expect(run(5, 0.0, 1, 0.5, 0.5).x, closeTo(0.0, 1e-6));
    });

    test('the corner of a face looks towards its neighbours', () {
      // Row zero of +X looks up: the top-left texel gathers +Y and +Z as well
      // as +X, so a wide lobe there is a mix of red, blue and magenta rather
      // than pure red. Mutation: use the same direction for every texel —
      // the whole face is one colour at every roughness.
      final corner = run(0, 1.0, 64, 0.0, 0.0);
      expect(corner.x, lessThan(0.95), reason: 'not pure red: $corner');
      expect(corner.z, greaterThan(0.05), reason: 'some blue: $corner');
    });

    test('a rough level of a uniform cube is that colour, not darker', () {
      // Weights normalise. Mutation: divide by the tap count instead of the
      // cosine sum — a rough metal comes out dim for no reason a person can
      // see in the capture.
      final uniform = device.createCubeTextureFromPixels(
        size: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: <ByteData>[
          for (var f = 0; f < 6; f++)
            ByteData.sublistView(
              Uint8List.fromList(<int>[
                for (var i = 0; i < 16; i++) ...<int>[128, 64, 32, 255],
              ]),
            ),
        ],
      )!;
      capture = BoundTexture(
        uniform.backend as CpuTexture,
        SamplerOptions.linearClamp,
      );
      final rough = run(3, 1.0, 64, 0.3, 0.7);
      expect(rough.x, closeTo(128 / 255, 0.01));
      expect(rough.y, closeTo(64 / 255, 0.01));
      expect(rough.z, closeTo(32 / 255, 0.01));
    });
  });
}
