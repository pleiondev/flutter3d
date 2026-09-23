/// `LightNode.castsShadow` on a directional light.
///
///     flutter test test/sun_casts_shadow_test.dart
///
/// **Until 0.7.1 the renderer cast the sun whatever the flag said.** Only the
/// cube shadows read it, so clearing it on a directional light did nothing,
/// and "this sun does not cast" could only be said by turning shadows off for
/// the whole frame or mesh by mesh. The default follows the type, so every
/// scene that never set the flag draws what it drew.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

/// The directional-shadow fixture drawn once, with its sun's flag set to
/// [sunCasts], answering how many draw calls the frame took.
int _drawCalls({required bool sunCasts}) {
  final device = CpuDevice(
    width: kParityWidth,
    height: kParityHeight,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final built = buildParityScene(device, which: ParityScene.directionalShadow);
  for (final LightNode light in built.scene.lights) {
    if (light.type == LightType.directional) light.castsShadow = sunCasts;
  }
  return renderer
      .render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(ParityScene.directionalShadow),
      )
      .drawCalls;
}

void main() {
  test('the default follows the type', () {
    expect(LightNode().castsShadow, isTrue, reason: 'directional');
    expect(LightNode(type: LightType.point).castsShadow, isFalse);
    expect(LightNode(type: LightType.spot).castsShadow, isFalse);
    expect(LightNode(type: LightType.area).castsShadow, isFalse);
    expect(
      LightNode(type: LightType.point, castsShadow: true).castsShadow,
      isTrue,
    );
  });

  test('a sun that is told not to cast draws no shadow map', () {
    // Mutation: drop the `castsShadow` check from `_directionalIndexIn`, and
    // the two frames cost the same.
    final casting = _drawCalls(sunCasts: true);
    final notCasting = _drawCalls(sunCasts: false);
    expect(
      notCasting,
      lessThan(casting),
      reason: 'clearing castsShadow on the sun left its shadow pass in place',
    );
  });
}
