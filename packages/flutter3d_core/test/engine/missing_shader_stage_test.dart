/// A bundle written for a project's needs (D15): the base draws a frame, and
/// a stage left out is refused by name when it is asked for.
///
///     dart test test/engine/missing_shader_stage_test.dart
///
/// Mutation: throw a `StateError` again from `_fragmentShaderFor` in
/// `renderer_resources.dart`.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:test/test.dart';

/// Every stage no engine need but [ShaderStageNeed.base] brings: what a
/// project that declared nothing carries.
final Set<String> _optional = <String>{
  for (final need in ShaderStageNeed.engine) ...need.stages,
};

FrameResult _draw(FakeBackend device, LightingModel lighting) {
  final mesh = DeviceMesh.upload(device, CuboidShape().build());
  final scene = Scene()
    ..add(
      MeshNode(mesh, RenderMaterial(lighting: lighting))
        ..setPosition(0.0, 0.0, -5.0),
    )
    ..add(CameraNode());
  return Renderer.create(device: device).render(
    width: 64,
    height: 48,
    scene: scene,
    views: <CameraView>[CameraView(camera: scene.cameras.single)],
  );
}

void main() {
  test('the base alone draws the default material', () {
    final result = _draw(
      FakeBackend(missingShaders: _optional),
      LightingModel.pbr,
    );
    expect(result.drawCalls, greaterThan(0));
  });

  test('a lighting model left out is refused with the need that brings it', () {
    expect(
      () => _draw(FakeBackend(missingShaders: _optional), LightingModel.toon),
      throwsA(
        isA<MissingShaderStageException>()
            .having((e) => e.stage, 'stage', 'Toon')
            .having((e) => e.need, 'need', 'toon')
            .having((e) => e.message, 'message', contains('Toon')),
      ),
    );
  });

  test('a base stage missing says the bundle is not this build\'s', () {
    expect(
      () => Renderer.create(
        device: FakeBackend(missingShaders: const <String>{'Composite'}),
      ),
      throwsA(
        isA<MissingShaderStageException>()
            .having((e) => e.stage, 'stage', 'Composite')
            .having((e) => e.need, 'need', 'base'),
      ),
    );
  });
}
