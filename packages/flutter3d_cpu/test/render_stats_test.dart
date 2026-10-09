/// What a frame says it cost — `P6`: the draws and triangles it made and the
/// memory its targets hold, without a capture asked for.
///
///     dart test test/render_stats_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

const int _width = 64;
const int _height = 48;

/// One frame of [cubes] cubes, through [settings].
FrameResult _render(RenderSettings settings, {int cubes = 1}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final mesh = DeviceMesh.upload(device, CuboidShape().build());
  final scene = Scene();
  for (var i = 0; i < cubes; i++) {
    scene.add(
      MeshNode(
        mesh,
        RenderMaterial(baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.5, 1.0)),
      )..setPosition(i * 1.5 - (cubes - 1) * 0.75, 0.0, -6.0),
    );
  }
  final camera = CameraNode();
  scene.add(camera);
  return Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings,
  );
}

void main() {
  test('a texture is counted as its texels, every slice and sample', () {
    // Mutation: leave out the slices, and a cube target is a sixth of itself.
    TextureHandle handle(TextureFormat format, {TextureType? type}) =>
        wrapTexture(
          backend: Object(),
          width: 8,
          height: 4,
          format: format,
          sampleCount: 2,
          type: type ?? TextureType.texture2D,
        );
    expect(textureBytes(handle(TextureFormat.r8UNormInt)), 8 * 4 * 2);
    expect(
      textureBytes(handle(TextureFormat.r16g16b16a16Float)),
      8 * 4 * 2 * 8,
    );
    expect(
      textureBytes(
        handle(TextureFormat.r8g8b8a8UNormInt, type: TextureType.textureCube),
      ),
      8 * 4 * 6 * 2 * 4,
    );
  });

  test('a frame says what its targets hold', () {
    // Mutation: count only the pooled scratch, and the scene's own colour —
    // provided, not pooled — drops out, taking the frame below what one
    // half-float target of its size holds.
    final frame = _render(const RenderSettings());
    expect(frame.targetBytes, greaterThanOrEqualTo(_width * _height * 8));
  });

  test('a glow is paid for in targets, and a smaller scene in fewer bytes', () {
    // Mutation: count a texture each time a version names it, and the glow's
    // chain, read and written in place, is counted twice over.
    final plain = _render(
      const RenderSettings(bloom: BloomSettings(enabled: false)),
    );
    final glowing = _render(
      const RenderSettings(bloom: BloomSettings(enabled: true)),
    );
    expect(glowing.targetBytes, greaterThan(plain.targetBytes));
    expect(
      glowing.targetBytes,
      lessThan(plain.targetBytes * 3),
      reason: 'a chain of halvings is about a third of its first level',
    );
  });

  test('more cubes are more draws and more triangles', () {
    final one = _render(const RenderSettings(), cubes: 1);
    final three = _render(const RenderSettings(), cubes: 3);
    expect(three.drawCalls, greaterThan(one.drawCalls));
    expect(three.triangles, greaterThanOrEqualTo(one.triangles + 24));
  });
}
