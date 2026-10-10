/// The GPU splat sort held to the CPU's, splat for splat and pixel for pixel
/// — `H11`.
///
///     flutter test --platform chrome test/splat_sort_gpu_test.dart
///
/// **The CPU sort is the reference, and the claim is equality, not
/// closeness.** Both orders are stable sorts of the same sixteen-bit keys,
/// so there is exactly one right answer and it includes the ties: two
/// splats at one quantised distance in index order. A cloud of a hundred
/// thousand splats has far more splats than keys, so the ties are most of
/// what is checked, and it spans hundreds of tiles and many of the scan's
/// chunks, which is where a radix sort that is right for one tile goes
/// wrong.
///
/// **Then the picture.** The same overlapping, translucent, differently
/// coloured cloud drawn through the renderer both ways must come back the
/// same to the byte: the order is all that differs between the two draws,
/// and a translucent stack shows its order in every overlapping pixel.
///
/// **Chrome only**, for the reason every renderer test in this package is:
/// there is no WebGPU on the Dart VM.
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

/// The device, or null where this browser has no WebGPU — see
/// `reflection_probe_test.dart` for why null and not a `setUp`.
Future<WebGpuDevice?> _open() async {
  try {
    return await WebGpuDevice.open(
      width: _width,
      height: _height,
      stages: webGpuEngineShaders,
    );
  } on DeviceUnavailableException {
    markTestSkipped('no WebGPU in this browser');
    return null;
  }
}

/// [count] splats in a box around the origin, a fifth of them copies of
/// earlier ones — the same distance from any eye, so a tie whatever the
/// quantisation — and half-transparent in a colour that depends on the
/// index, so an order shows in a picture.
SplatCloud _cloud(int count, {double extent = 2.0, double size = 0.05}) {
  final random = math.Random(11);
  final centers = Float32List(count * 3);
  for (var i = 0; i < count; i++) {
    final copy = i % 5 == 4 && i > 0;
    for (var k = 0; k < 3; k++) {
      centers[i * 3 + k] = copy
          ? centers[(i ~/ 2) * 3 + k]
          : (random.nextDouble() * 2.0 - 1.0) * extent;
    }
  }
  return SplatCloud(
    centers: centers,
    colors: Float32List.fromList(<double>[
      for (var i = 0; i < count; i++) ...<double>[
        (i % 3) / 2.0,
        ((i ~/ 3) % 3) / 2.0,
        ((i ~/ 9) % 3) / 2.0,
        0.5,
      ],
    ]),
    scales: Float32List.fromList(<double>[
      for (var i = 0; i < count; i++) ...<double>[size, size, size],
    ]),
    rotations: Float32List.fromList(<double>[
      for (var i = 0; i < count; i++) ...<double>[0.0, 0.0, 0.0, 1.0],
    ]),
  );
}

/// The GPU sort's index buffer, read back, against the CPU's order: six
/// indices a splat, `6s … 6s + 5` for the splat `s` the CPU put there.
Future<void> _expectSameOrder(
  WebGpuDevice device,
  SplatCloud cloud,
  Vector3 eye, {
  Matrix4? model,
  Vector3? axis,
}) async {
  final reference = SplatSorter()..sort(cloud, eye, model: model, axis: axis);
  final keys = SplatSorter()..quantize(cloud, eye, model: model, axis: axis);
  final gpu = SplatGpuSort(device, readable: true)
    ..sort(keys.keys, cloud.count, frameIndex: 0);
  final indices = await gpu.readIndices();
  gpu.release();
  expect(await device.debugDrainErrors(), isNull);

  expect(indices.length, cloud.count * 6);
  for (var n = 0; n < cloud.count; n++) {
    final want = reference.order[n];
    for (var k = 0; k < 6; k++) {
      final got = indices[n * 6 + k];
      if (got != want * 6 + k) {
        fail(
          'place $n holds index $got where ${want * 6 + k} belongs '
          '(splat $want, key ${reference.keys[n]}; the GPU put splat '
          '${got ~/ 6} there, key ${keys.keys[got ~/ 6]})',
        );
      }
    }
  }
}

void main() {
  test('only a device with compute and the stages is offered it', () async {
    final device = await _open();
    if (device == null) return;
    expect(SplatGpuSort.availableOn(device), isTrue);
    device.dispose();
  });

  test(
    'a hundred thousand splats come out in the CPU\'s order, ties and all',
    () async {
      final device = await _open();
      if (device == null) return;
      final cloud = _cloud(100003);
      await _expectSameOrder(device, cloud, Vector3(0.3, 4.0, 7.0));
      // From inside the cloud, where near and far are on every side.
      await _expectSameOrder(device, cloud, Vector3(0.1, -0.2, 0.05));
      device.dispose();
    },
  );

  test('placed by a model and seen along an axis, the same', () async {
    final device = await _open();
    if (device == null) return;
    final cloud = _cloud(5000);
    final model = Matrix4.compose(
      Vector3(1.0, -2.0, 3.0),
      Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7),
      Vector3.all(1.5),
    );
    await _expectSameOrder(device, cloud, Vector3(0.0, 1.0, 9.0), model: model);
    await _expectSameOrder(
      device,
      cloud,
      Vector3(0.0, 1.0, 9.0),
      model: model,
      axis: Vector3(0.2, -0.1, -1.0)..normalize(),
    );
    // One splat, and a cloud a key's worth of splats short of one tile.
    await _expectSameOrder(device, _cloud(1), Vector3(0.0, 0.0, 5.0));
    await _expectSameOrder(device, _cloud(255), Vector3(0.0, 0.0, 5.0));
    device.dispose();
  });

  test(
    'a second sort in one frame does not write the first one\'s buffer',
    () async {
      // Two views of one cloud in a frame: the first view's draw is encoded
      // and not yet submitted when the second sorts, so the second has to land
      // somewhere else. The next frame may take either back.
      final device = await _open();
      if (device == null) return;
      final cloud = _cloud(2000);
      final keys = SplatSorter()..quantize(cloud, Vector3(0.0, 0.0, 6.0));
      final gpu = SplatGpuSort(device)..sort(keys.keys, 2000, frameIndex: 1);
      final first = gpu.drawn(1)!.backend;
      gpu.sort(keys.keys, 2000, frameIndex: 1);
      final second = gpu.drawn(1)!.backend;
      expect(identical(first, second), isFalse);
      gpu.sort(keys.keys, 2000, frameIndex: 2);
      final third = gpu.drawn(2)!.backend;
      expect(identical(third, first) || identical(third, second), isTrue);
      gpu.release();
      device.dispose();
    },
  );

  test('the cloud drawn in the GPU\'s order is the CPU-sorted picture to the '
      'byte', () async {
    final device = await _open();
    if (device == null) return;

    TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
    );
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );
    // Big enough to overlap many deep: the order shows wherever they do.
    final splats = SplatContributor(_cloud(3000, extent: 1.5, size: 0.12));
    renderer.renderSteps.addContributor(splats);
    final camera = CameraNode(
      projection: const PerspectiveProjection(fovY: 0.9, near: 0.1, far: 60.0),
    );
    final scene = Scene()..add(camera);

    Future<Uint8List> draw(Vector3 eye, {required bool gpu}) async {
      splats.gpuSort = gpu;
      camera.setPosition(eye.x, eye.y, eye.z);
      camera.lookAt(Vector3.zero());
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[
          RenderView(
            camera: camera,
            clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0),
          ),
        ],
        settings: const RenderSettings(
          shadows: ShadowSettings(enabled: false),
          bloom: BloomSettings(enabled: false),
        ),
      );
      expect(splats.didDrawGpuOrder, gpu);
      final pixels = await device.readback(result.frame);
      return Uint8List.fromList(pixels.buffer.asUint8List());
    }

    for (final eye in <Vector3>[
      Vector3(0.0, 0.0, 4.5),
      Vector3(3.0, 2.0, -2.5),
      Vector3(-0.4, 3.5, 0.6),
    ]) {
      final cpu = await draw(eye, gpu: false);
      final gpu = await draw(eye, gpu: true);
      expect(await device.debugDrainErrors(), isNull);
      // Something was drawn, or two black frames would agree.
      expect(cpu.where((b) => b > 0).length, greaterThan(cpu.length ~/ 8));
      var differ = 0;
      for (var i = 0; i < cpu.length; i++) {
        if (cpu[i] != gpu[i]) differ++;
      }
      expect(differ, 0, reason: 'from $eye, $differ bytes differ');
    }
    device.dispose();
  });
}
