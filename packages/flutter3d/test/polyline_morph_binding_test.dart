/// A material with its own vertex stage is not handed the morph texture it
/// never declared.
///
///     flutter test test/polyline_morph_binding_test.dart
///
/// **Every `Material.polyline` threw on Impeller at its first draw**, in
/// 0.7.0 and 0.7.1 alike: the renderer bound the morph block and texture to
/// whichever vertex stage drew, and `PolylineVertex` declares neither. A
/// missing block is skipped, but flutter_gpu refuses a texture bound to a slot
/// the stage does not have, with "Failed to bind texture". WebGL and the
/// software backend let the extra bind pass, so only a run on Metal saw it.
///
/// Mutation: bind the morph state for every stage again, as before.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// How many times the frame bound `morph_texture`, drawing [mesh].
int _morphBinds(MeshNode Function(FakeBackend device) mesh) {
  final device = FakeBackend();
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(mesh(device))
    ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));
  renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    // No shadow map, whose caster pass draws through the engine's own stage.
    settings: const RenderSettings(shadows: ShadowSettings(enabled: false)),
  );
  return device.passes
      .expand((FakePass pass) => pass.commands)
      .whereType<RecordedTexture>()
      .where((RecordedTexture bind) => bind.slot == 'morph_texture')
      .length;
}

void main() {
  test('a polyline binds no morph texture', () {
    final binds = _morphBinds(
      (FakeBackend device) => MeshNode(
        DeviceMesh.upload(
          device,
          buildPolyline(<Vector3>[
            Vector3(-1.0, 0.0, 0.0),
            Vector3(1.0, 0.0, 0.0),
          ], width: 4.0),
        ),
        Material.polyline(viewportWidth: 64.0, viewportHeight: 64.0),
      ),
    );
    expect(binds, 0);
  });

  test('and a mesh through the engine stage still binds it', () {
    // Otherwise the test above would pass for a renderer that never bound it.
    final binds = _morphBinds(
      (FakeBackend device) => MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.5).build()),
        Material(name: 'ball', lighting: LightingModel.unlit),
      ),
    );
    expect(binds, greaterThan(0));
  });

  test('and so does a stage of its own written from MeshVertex', () {
    // **0.7.2 got this one wrong.** It keyed the bind on whether the node
    // morphed, so a stage built on `mesh.vert`, which declares the morph block
    // and texture whether or not anything morphs, drew a plain mesh without
    // them: another draw's weights on the software backend, garbage on WebGL,
    // a native failure on Metal. The stage says what it declares.
    //
    // Mutation: bind for a material's own stage only when the node morphs.
    final binds = _morphBinds(
      (FakeBackend device) => MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.5).build()),
        Material(
          name: 'displaced',
          lighting: const LightingModel(
            'Displaced',
            'Unlit',
            vertexShaderName: 'MeshVertex',
            usesMaterialMaps: false,
            usesMetallicRoughnessMap: false,
          ),
        ),
      ),
    );
    expect(binds, greaterThan(0));
  });
}
