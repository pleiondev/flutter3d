/// `H7`: targets whose lifetimes do not overlap share a texture, and no pass
/// can tell.
///
///     flutter test test/transient_aliasing_test.dart
///
/// **Reuse within a frame is safe for a reason the engine did not use.** A
/// pooled target goes back through a ring of frames in flight because the GPU
/// may still be reading it; but the passes of one frame reach the queue in the
/// order they were encoded, so a target whose last reader has been encoded can
/// be drawn over by any later pass of the same frame. `RenderSettings
/// .aliasTargets` takes that: a target retired by the graph waits in a free
/// list for the rest of the frame, and the next pass that wants its size and
/// format is handed it.
///
/// What that could break is a pass that reads a resource after its last
/// declared use, or loads a target instead of clearing it — both of which
/// worked before by accident, because the pixels were still there. So the
/// first test makes sure they are not: every target is filled with garbage the
/// moment its lifetime ends, and the frame has to come out the same to the
/// byte. The second counts what the pool had to allocate.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// Every effect with a pass of its own that the software rasteriser draws and
/// that does not feed back across frames, so ten passes run and the frame is
/// the same whichever frame of a sequence it is.
const RenderSettings _tenPasses = RenderSettings(
  bloom: BloomSettings(intensity: 0.8),
  ambientOcclusion: AmbientOcclusionSettings(
    enabled: true,
    radius: 0.9,
    blurTaps: 4,
  ),
  contactShadows: ContactShadowSettings(enabled: true),
  reflections: ReflectionSettings(enabled: true),
  lightShafts: LightShaftSettings(enabled: true),
  depthOfField: DepthOfFieldSettings(enabled: true),
  antiAlias: AntiAliasSettings(enabled: true),
  shadows: ShadowSettings(enabled: true),
);

/// Garbage no pass could mistake for a picture: large, and different in each
/// channel, so a read of it moves every channel of whatever it lands in.
void _poison(TextureHandle texture) {
  final cpu = texture.backend as CpuTexture;
  for (var i = 0; i < cpu.pixels.length; i += 4) {
    cpu.pixels
      ..[i] = 97.0
      ..[i + 1] = -13.0
      ..[i + 2] = 41.0
      ..[i + 3] = 0.5;
  }
  for (final level in cpu.levels ?? const <CpuTexture>[]) {
    level.pixels.fillRange(0, level.pixels.length, 97.0);
  }
}

typedef _Shot = ({
  Uint8List pixels,
  int created,
  int retired,
  List<String> ran,
});

/// A corner room with a block in it, under a sun that casts, drawn [frames]
/// times; the last frame's pixels and what the pool made over all of them.
Future<_Shot> _draw({
  required bool alias,
  required bool poison,
  int frames = 3,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  var retired = 0;
  final renderer = Renderer.create(device: device)
    ..debugOnTargetRetired = (TextureHandle texture) {
      retired++;
      if (poison) _poison(texture);
    };

  final scene = Scene()..ambientIntensity = 0.15;
  final wall = Material(name: 'wall', baseColor: Vector4(0.8, 0.8, 0.8, 1.0));
  final block = Material(
    name: 'block',
    baseColor: Vector4(0.9, 0.4, 0.2, 1.0),
    emissive: Vector3(1.5, 0.6, 0.2),
  );
  for (final (Vector3 size, Vector3 at, Material material)
      in <(Vector3, Vector3, Material)>[
        (Vector3(2.8, 0.1, 2.8), Vector3(0.0, -1.4, 0.0), wall),
        (Vector3(0.1, 2.8, 2.8), Vector3(-1.4, 0.0, 0.0), wall),
        (Vector3(2.8, 2.8, 0.1), Vector3(0.0, 0.0, -1.4), wall),
        (Vector3(0.6, 0.6, 0.6), Vector3(-0.3, -1.05, -0.2), block),
      ]) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: size).build()),
        material,
      )..setPosition(at.x, at.y, at.z),
    );
  }
  scene.add(
    LightNode(type: LightType.directional, intensity: 0.8, castsShadow: true)
      ..setLocalForward(Vector3(-0.4, -0.9, -0.3)),
  );
  final view = RenderView(
    camera: CameraNode()
      ..setPosition(1.8, 1.2, 1.8)
      ..lookAt(Vector3(-0.6, -0.8, -0.6)),
    clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
  );

  late FrameResult frame;
  for (var i = 0; i < frames; i++) {
    frame = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[view],
      settings: _tenPasses.copyWith(aliasTargets: alias),
    );
  }
  return (
    pixels: (await device.readPixels(frame.frame))!.buffer.asUint8List(),
    created: renderer.targetPool.createdCount,
    retired: retired,
    ran: <String>[
      for (final pass in frame.passes)
        if (pass.active) pass.name,
    ],
  );
}

void main() {
  test(
    'a target poisoned at the end of its lifetime changes no frame',
    () async {
      final plain = await _draw(alias: false, poison: false);
      final poisoned = await _draw(alias: false, poison: true);
      final aliased = await _draw(alias: true, poison: true);

      expect(
        plain.ran.length,
        greaterThanOrEqualTo(10),
        reason: 'the scene is meant to run ten passes: ${plain.ran}',
      );
      expect(
        poisoned.retired,
        greaterThan(0),
        reason: 'nothing was retired, so nothing was poisoned',
      );
      // Mutation: let `FrameResources.provide` leave a node's scratch in the
      // scratch list when the node hands it in as its output, which is how it
      // was — it is then retired when the node ends while the next pass still
      // reads it, the occlusion, the shafts and the finished frame all sample
      // the garbage, and the frame moves.
      expect(
        poisoned.pixels,
        plain.pixels,
        reason: 'a pass read a target after its lifetime in the frame ended',
      );
      expect(
        aliased.pixels,
        plain.pixels,
        reason: 'a pass read another pass\'s pixels through a shared target',
      );
    },
  );

  test('RenderTargetPool.createdCount falls on the ten-pass scene', () async {
    final separate = await _draw(alias: false, poison: false);
    final shared = await _draw(alias: true, poison: false);

    // Mutation: have `FrameResources` hand retired textures to the source as
    // it does with aliasing off, and the two counts are equal.
    expect(
      shared.created,
      lessThan(separate.created),
      reason:
          'aliasing made ${shared.created} targets against '
          '${separate.created} without it',
    );
    expect(shared.pixels, separate.pixels);
  });
}
