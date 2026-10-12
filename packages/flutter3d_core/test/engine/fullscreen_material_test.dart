// A full-screen stage written in the material language draws with every
// block and texture it declares bound: its uniforms at the source's
// defaults, the surface buffer when it reads `sceneDepth`, and each texture
// of its own refused when nothing names it.
import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart' show runtimeMaterialBundle;
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/backend.dart' show wrapShader, wrapTexture;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const String _vignette = '''
f3dmat 3
fullscreen Vignette {
  uniform float strength = 0.5;
  texture lut = lut_texture;
  fragment {
    let fade = 1.0 - strength * length(uv - vec2(0.5));
    let far = clamp(sceneDepth * 0.01, 0.0, 1.0);
    return vec4(sample(scene, uv).rgb * fade * sample(lut, uv).r + vec3(far * 0.0), 1.0);
  }
}
''';

BundledMaterials _materials() => BundledMaterials.read(
  runtimeMaterialBundle(
    _vignette,
    backend: 'cpu',
    from: 'vignette.f3dmat',
  ).encode(),
);

TextureHandle _texture() => wrapTexture(
  backend: 'test',
  width: 4,
  height: 4,
  format: TextureFormat.r8g8b8a8UNormInt,
);

final class _Source with FrameTextureSource {
  @override
  TextureHandle acquire(RenderTargetDescriptor spec) => wrapTexture(
    backend: 'frame',
    width: spec.width,
    height: spec.height,
    format: spec.format,
  );

  @override
  void release(TextureHandle texture) {}
}

final class _Services with RenderServices {
  final List<FullscreenDraw> draws = <FullscreenDraw>[];

  @override
  void drawFullscreen(FullscreenDraw draw) => draws.add(draw);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('a full-screen effect draws nothing else');
}

void main() {
  final shader = wrapShader(backend: Object(), name: 'Vignette');

  test('every block it declares is bound at its default, and the surface '
      'buffer when it reads the depth', () {
    final effect = FullscreenEffect.material(
      _materials(),
      'Vignette',
      name: 'vignette',
      shader: shader,
      textures: <String, TextureHandle>{'lut_texture': _texture()},
    );
    // Mutation: leave `readsSurface` at the plain constructor's false and
    // `surface_texture` is unbound on every backend.
    expect(effect.readsSurface, isTrue);
    expect(effect.reads, contains(FrameResourceIds.surfaceBuffer));

    final graph =
        (FrameGraph()
              ..addExternal(FrameResourceIds.hdrColor)
              ..addExternal(FrameResourceIds.surfaceBuffer)
              ..addNode(effect))
            .compile(outputs: const <ResourceId>[FrameResourceIds.hdrColor]);
    final resources =
        FrameResources(
            source: _Source(),
            graph: graph,
            frameWidth: 8,
            frameHeight: 8,
          )
          ..provide(FrameResourceIds.hdrColor, _texture())
          ..provide(FrameResourceIds.surfaceBuffer, _texture());
    final services = _Services();
    final frame = RenderFrame(
      device: FakeBackend(),
      resources: resources,
      services: services,
      settings: const RenderSettings(),
      width: 8,
      height: 8,
    );
    effect.parameters!['strength']![0] = 0.8;
    resources.beginNode(0);
    effect.execute(frame);
    resources.endNode(0);
    final draw = services.draws.single;
    // Mutation: drop `parameters` from `execute` and `MaterialParams` is
    // never bound.
    expect(
      draw.uniforms[materialParametersBlock]!['strength'],
      Float32List.fromList(<double>[0.8]),
    );
    expect(
      draw.textures.keys,
      containsAll(<String>['scene_texture', 'surface_texture', 'lut_texture']),
    );
  });

  test('a texture of its own that nothing names is refused, by name', () {
    expect(
      () => FullscreenEffect.material(
        _materials(),
        'Vignette',
        name: 'vignette',
        shader: shader,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}',
          'message',
          contains('lut_texture'),
        ),
      ),
    );
    expect(
      () => FullscreenEffect.material(
        _materials(),
        'Nothing',
        name: 'n',
        shader: shader,
      ),
      throwsArgumentError,
    );
  });
}
