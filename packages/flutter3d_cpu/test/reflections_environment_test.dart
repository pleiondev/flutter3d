/// Screen-space reflections under an environment: a hit takes the place of
/// the sky's reflection rather than adding to it.
///
///     dart test test/reflections_environment_test.dart
///
/// A polished metal-rough floor already reflects the environment in the lit
/// pass. Where the march finds an object, the floor should show the object
/// instead of the sky, not the object laid over the sky: the reflection of a
/// red cube under a white sky loses green and blue, which an added
/// reflection can never do.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// Copies the lit scene out as floats after the composite: the colour the
/// reflections pass wrote, before the composite dithers it.
final class _Probe extends RenderNode {
  _Probe(this._device);

  final CpuDevice _device;
  Float32List? last;

  @override
  String get name => 'probe hdr';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.frame,
    FrameResourceIds.hdrColour,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    last = _device.readHdrPixels(
      frame.resources.texture(FrameResourceIds.hdrColour),
    );
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

/// The lit frame of a polished floor with a red cube standing on it, under a
/// white environment when [sky] says so, with reflections [on].
Float32List _render({required bool on, required bool sky}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  // Metal-rough, and polished well inside the pass's window, so the lit pass
  // reflects the environment and the march is trusted in full.
  final floor = MeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(12.0, 0.4, 12.0)).build(),
    ),
    Material(baseColor: Vector4(0.05, 0.05, 0.06, 1.0), roughness: 0.02),
  )..setPosition(0.0, -0.2, 0.0);
  // Unlit, so it is red whatever the light and writes a rough surface that
  // reflects nothing itself.
  final cube = MeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
    ),
    Material(
      lighting: LightingModel.unlit,
      baseColor: Vector4(1.0, 0.0, 0.0, 1.0),
    ),
  )..setPosition(0.0, 0.5, 0.0);
  final camera = CameraNode()
    ..setPosition(0.0, 1.1, -3.6)
    ..lookAt(Vector3(0.0, 0.35, 0.0));
  final scene = Scene()
    ..add(floor)
    ..add(cube)
    ..add(camera)
    ..ambientIntensity = 1.0;
  if (sky) {
    const size = 8;
    const levels = 3;
    final faces = <ByteData>[
      for (var face = 0; face < 6; face++)
        ByteData.sublistView(
          Uint8List.fromList(<int>[
            for (var i = 0; i < size * size; i++) ...<int>[200, 200, 200, 255],
          ]),
        ),
    ];
    scene
      ..environment = device.createCubeTextureFromPixels(
        size: size,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: faces,
        mipLevels: EnvironmentMap.prefilter(faces, size: size, levels: levels),
      )
      ..environmentLevels = levels;
  }
  final probe = _Probe(device);
  Renderer.create(device: device)
    ..addNode(probe)
    ..render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: RenderSettings(
        tonemap: false,
        bloom: const BloomSettings(enabled: false),
        shadows: const ShadowSettings(enabled: false),
        reflections: ReflectionSettings(
          enabled: on,
          steps: 48,
          stride: 0.1,
          thickness: 0.15,
          intensity: 1.0,
        ),
      ),
    );
  return probe.last!;
}

/// The pixels where reflections put red on the floor: the march's hits.
List<int> _hits(Float32List on, Float32List off) => <int>[
  for (var i = 0; i < on.length; i += 4)
    if (on[i] - off[i] > 0.01) i,
];

void main() {
  test('a hit replaces the sky in the floor instead of adding to it', () {
    // Mutation: drop `replaced` from the sum in `ReflectionsShader` (the
    // additive composite this replaced). No hit pixel then loses any green:
    // the count of darker ones goes to zero.
    final on = _render(on: true, sky: true);
    final off = _render(on: false, sky: true);
    final hits = _hits(on, off);
    expect(hits.length, greaterThan(100), reason: 'the march found nothing');
    // The cube has no green, the sky does: where the cube's reflection took
    // the sky's place, the floor is less green than it was.
    final darker = hits.where((i) => on[i + 1] < off[i + 1] - 1e-3).length;
    expect(darker, greaterThan(hits.length * 0.8));
    // Nothing is taken below nought.
    expect(on.reduce(math.min), greaterThanOrEqualTo(0.0));
  });

  test('without an environment a hit only adds, as it always did', () {
    // There is no sky's reflection to take away, so every channel of every
    // pixel is at least what it was with reflections off.
    final on = _render(on: true, sky: false);
    final off = _render(on: false, sky: false);
    expect(_hits(on, off).length, greaterThan(100));
    var lowest = 0.0;
    for (var i = 0; i < on.length; i++) {
      lowest = math.min(lowest, on[i] - off[i]);
    }
    // Within the rounding of the half-float target the pass writes into.
    expect(lowest, greaterThan(-1e-4));
  });

  test('the environment slot is bound when the scene has no environment', () {
    // The pass declares a cube now, and a declared sampler left unbound is a
    // crash on Metal: the one-texel stand-in goes in its place.
    //
    // Mutation: leave `environment_texture` out of the pass's textures in
    // `_encodeReflections`. The fake device reports the slot.
    final device = FakeBackend(stageBindings: stageBindings);
    final camera = CameraNode()..setPosition(0.0, 1.0, 3.0);
    final scene = Scene()
      ..add(camera)
      ..add(
        MeshNode(
          DeviceMesh.upload(device, const PlaneShape().build()),
          Material(roughness: 0.02),
        ),
      );
    final result = Renderer.create(device: device).render(
      width: 32,
      height: 32,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(
        reflections: ReflectionSettings(enabled: true),
      ),
    );
    expect(result.passes.map((p) => p.name), contains('reflections'));
    expect(device.bindingViolations, isEmpty);
  });
}
