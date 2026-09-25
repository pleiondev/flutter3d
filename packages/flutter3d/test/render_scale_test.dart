/// `gfx-35n`: drawing the frame at less than the asked-for resolution.
///
///     flutter test test/render_scale_test.dart
///
/// **The one missing capability class that is not an effect.** Every other
/// setting trades a look for time; this trades resolution for it, which is
/// what an application reaches for when a frame will not fit its budget and
/// everything else is already off.
///
/// What a test can hold here is arithmetic and allocation: the frame comes
/// back at the size it was drawn at, both axes shrink, and the targets the
/// device was asked for shrink with them. Whether it *looks* acceptable at
/// 0.75 is a judgement, and a golden would only record one person's.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

({int width, int height}) _drawn(double scale, {int asked = 64}) {
  final device = FakeBackend();
  final renderer = Renderer.create(device: device);
  final scene = Scene()..add(CameraNode());

  final frame = renderer.render(
    width: asked,
    height: asked,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: RenderSettings(renderScale: scale),
  );
  return (width: frame.frame.width, height: frame.frame.height);
}

void main() {
  test('one is the whole resolution, and is the default', () {
    // Seventy-eight goldens are recorded at the size they asked for. A default
    // that shrank anything would move every one of them.
    expect(const RenderSettings().renderScale, 1.0);
    expect(_drawn(1.0), (width: 64, height: 64));
  });

  test('both axes shrink, so the cost is the square', () {
    // The number people misread: 0.5 is a quarter of the pixels, not half.
    expect(_drawn(0.5), (width: 32, height: 32));
    expect(_drawn(0.75, asked: 128), (width: 96, height: 96));
  });

  test('a frame never collapses to nothing', () {
    // A viewport animating open is a real state, and a target with no pixels
    // in it is not — `RenderPassDescriptor` would refuse one, which is a
    // crash rather than a small frame.
    expect(_drawn(0.1, asked: 4).width, greaterThanOrEqualTo(1));
  });

  test('a scale outside the range is clamped rather than obeyed', () {
    // Above one is a supersample, which is `RenderPreset.ssaa`'s job and not
    // this one; below a tenth is a frame nobody can read.
    expect(_drawn(4.0), (width: 64, height: 64));
    expect(_drawn(0.0, asked: 64).width, 6);
  });

  test('every pass runs at the smaller size, not just the scene', () async {
    // The whole value of the row is that the cost goes down, and it only does
    // if the post chain shrinks too. Checked on the software rasteriser,
    // where a texture that was allocated is a texture that was paid for.
    final device = CpuDevice(
      width: 64,
      height: 64,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1, 1, 1)).build(),
          ),
          Material(name: 'box', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
        ),
      )
      ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));

    final frame = renderer.render(
      width: 64,
      height: 64,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.single)],
      settings: const RenderSettings(
        renderScale: 0.5,
        bloom: BloomSettings(enabled: true),
      ),
    );

    // The composite writes the frame, and it is the last pass in the chain —
    // so if it came back at half size, everything feeding it did too.
    expect(frame.frame.width, 32);
    expect(frame.frame.height, 32);

    final bytes = await device.readPixels(frame.frame);
    expect(
      bytes!.lengthInBytes,
      32 * 32 * 4,
      reason:
          'the texture handed back is the one that was drawn, not an '
          'upscale of it — a presenter already stretches, and a pass to do '
          'that again would be a full-screen draw for nothing',
    );
  });
}
