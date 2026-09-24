/// Every draw the renderer makes binds exactly what its stages keep.
///
///     flutter test test/binding_contract_test.dart
///
/// **The class of bug three releases shipped, caught on the VM.** 0.7.0 bound
/// the light list to Unlit, which keeps none, and Metal crashed at the first
/// frame; 0.7.0 to 0.7.2 bound a morph texture to `PolylineVertex`, which
/// declares none, and Impeller threw; 0.7.2 left a `MeshVertex`-based stage
/// without the morph block it declares. Each drew every golden on the other
/// backends. Here the renderer draws through a `FakeBackend` that knows, from
/// the compiled bundle's own reflection (`stageBindings`), what each stage
/// keeps, answers false to a bind a stage does not have, and records every
/// declared slot a draw leaves unbound.
///
/// Mutation: bind the light list for every lighting model again, or leave
/// the morph bind out of a stage that declares it.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The declared slots [draw] left unbound, one line each.
List<String> _unbound(
  void Function(FakeBackend device, Renderer renderer) draw,
) {
  final device = FakeBackend(stageBindings: stageBindings);
  final renderer = Renderer.create(device: device);
  draw(device, renderer);
  return device.bindingViolations.toSet().toList()..sort();
}

void main() {
  for (final which in ParityScene.values) {
    test('the ${which.name} fixture leaves nothing a stage keeps unbound', () {
      final unbound = _unbound((FakeBackend device, Renderer renderer) {
        final built = buildParityScene(device, which: which);
        renderer.render(
          width: kParityWidth,
          height: kParityHeight,
          scene: built.scene,
          views: <RenderView>[RenderView(camera: built.camera)],
          settings: paritySettingsFor(which),
        );
      });
      expect(unbound, isEmpty, reason: unbound.join('\n'));
    });
  }

  test('nor does an unlit mesh, a polyline or a lit one beside them', () {
    final unbound = _unbound((FakeBackend device, Renderer renderer) {
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(device, SphereShape(radius: 0.5).build()),
            Material(name: 'unlit', lighting: LightingModel.unlit),
          )..setPosition(-1.0, 0.0, 0.0),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              buildPolyline(<Vector3>[
                Vector3(-1.0, -0.8, 0.0),
                Vector3(1.0, -0.8, 0.0),
              ], width: 4.0),
            ),
            Material.polyline(viewportWidth: 64.0, viewportHeight: 64.0),
          ),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(0.6)).build(),
            ),
            Material(name: 'lit'),
          )..setPosition(1.0, 0.0, 0.0),
        )
        ..add(
          LightNode(intensity: 3.0)
            ..setPosition(2.0, 3.0, 4.0)
            ..lookAt(Vector3.zero()),
        )
        ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));
      renderer.render(
        width: 64,
        height: 64,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
      );
    });
    expect(unbound, isEmpty, reason: unbound.join('\n'));
  });

  test('nor does an impostor card, lit by a shadowed sun', () {
    // `C4`: the card brings its own vertex stage and a lit fragment stage
    // that reads two atlases through the albedo and normal slots, and nothing
    // else a lit model binds.
    final unbound = _unbound((FakeBackend device, Renderer renderer) {
      TextureHandle atlas() => device.createTextureFromPixels(
        width: 8,
        height: 8,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData(8 * 8 * 4),
      )!;
      final scene = Scene()
        ..add(
          ImpostorNode(
            device,
            albedo: atlas(),
            normalDepth: atlas(),
            centre: Vector3.zero(),
            radius: 0.8,
          ),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(0.6)).build(),
            ),
            Material(name: 'lit'),
          )..setPosition(1.0, 0.0, 0.0),
        )
        ..add(
          LightNode(intensity: 3.0)
            ..setPosition(2.0, 3.0, 4.0)
            ..lookAt(Vector3.zero()),
        )
        ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));
      renderer.render(
        width: 64,
        height: 64,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
      );
    });
    expect(unbound, isEmpty, reason: unbound.join('\n'));
  });
}
