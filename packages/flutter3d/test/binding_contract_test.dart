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
// The parity fixtures are the engine's own test scene, not its API.
// ignore: implementation_imports
import 'package:flutter3d_core/src/engine/render/parity_scene.dart';
import 'package:flutter3d_hardware/testing.dart';
// The generated uniform tables are shared by the engine and its backends,
// released together, and are nobody else's API since 1.0.
// ignore: implementation_imports
import 'package:flutter3d_shaders/internal.dart';
import 'package:flutter_test/flutter_test.dart';

/// The declared slots [draw] left unbound, one line each.
List<String> _unbound(
  void Function(FakeBackend device, Renderer renderer) draw, {
  int attachments = 2,
}) {
  final device = FakeBackend(
    stageBindings: stageBindings,
    maxColorAttachments: attachments,
  );
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
            RenderMaterial(name: 'unlit', lighting: LightingModel.unlit),
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
            RenderMaterial.polyline(viewportWidth: 64.0, viewportHeight: 64.0),
          ),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(0.6)).build(),
            ),
            RenderMaterial(name: 'lit'),
          )..setPosition(1.0, 0.0, 0.0),
        )
        ..add(
          LightNode(intensity: 3.0 * Photometric.legacyUnit)
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
      );
      final scene = Scene()
        ..add(
          ImpostorNode(
            device,
            albedo: atlas(),
            normalDepth: atlas(),
            center: Vector3.zero(),
            radius: 0.8,
          ),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(0.6)).build(),
            ),
            RenderMaterial(name: 'lit'),
          )..setPosition(1.0, 0.0, 0.0),
        )
        ..add(
          LightNode(intensity: 3.0 * Photometric.legacyUnit)
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

  test('nor does the decal pass, with pictures and without', () {
    // `P3`: four picture slots a draw binds whether or not a decal names
    // them, and two buffers out of the scene pass. Three attachments, or the
    // pass is refused before it binds anything.
    //
    // Mutation: binding only the slots a batch fills leaves three of the four
    // pictures unbound, which is a crash on Metal.
    final ran = <String>[];
    final unbound = _unbound((FakeBackend device, Renderer renderer) {
      final picture = device.createTextureFromPixels(
        width: 4,
        height: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData(4 * 4 * 4),
      );
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(4.0, 0.2, 4.0)).build(),
            ),
            RenderMaterial(name: 'floor'),
          )..setPosition(0.0, -0.1, 0.0),
        )
        ..add(DecalNode(texture: picture)..setScale(2.0, 1.0, 2.0))
        ..add(DecalNode()..setScale(1.0, 1.0, 1.0))
        ..add(
          CameraNode()
            ..setPosition(0.0, 4.0, 2.0)
            ..lookAt(Vector3.zero()),
        );
      final result = renderer.render(
        width: 64,
        height: 64,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: const RenderSettings(decals: DecalSettings(enabled: true)),
      );
      ran.addAll(result.passes.map((p) => p.name));
    }, attachments: 3);
    expect(ran, contains('decals'));
    expect(unbound, isEmpty, reason: unbound.join('\n'));
  });

  test('nor does a planar reflection, or a camera into a texture', () {
    // `P4`: the mirrored camera draws the lit scene, the reflection is laid
    // over a floor through its own stage with its picture and its block, and
    // a render texture's light is encoded through a full-screen stage. All
    // three under a shadowed sun, which is what a lit capture binds most of.
    //
    // Mutation: binding the reflection without its block, or the floor's
    // albedo slot to a stage that dropped it, is a violation here and a
    // crash on Metal.
    final ran = <String>[];
    final unbound = _unbound((FakeBackend device, Renderer renderer) {
      final floor = MeshNode(
        DeviceMesh.upload(device, const PlaneShape(width: 6, depth: 6).build()),
        RenderMaterial(name: 'floor'),
      );
      final camera = CameraNode()
        ..setPosition(0.0, 3.0, 4.0)
        ..lookAt(Vector3.zero());
      final scene = Scene()
        ..add(floor)
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(0.6)).build(),
            ),
            RenderMaterial(name: 'box'),
          )..setPosition(0.0, 0.8, 0.0),
        )
        ..add(PlanarReflectorNode(surfaces: <MeshNode>[floor]))
        ..add(
          LightNode(intensity: 3.0 * Photometric.legacyUnit)
            ..setPosition(2.0, 3.0, 4.0)
            ..lookAt(Vector3.zero()),
        )
        ..add(camera)
        ..addTextureView(
          RenderView.texture(device, camera: camera, width: 16, height: 16),
        );
      final result = renderer.render(
        width: 64,
        height: 64,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: const RenderSettings(
          planarReflections: PlanarReflectionSettings(enabled: true),
        ),
      );
      ran.addAll(result.passes.map((p) => p.name));
    });
    expect(ran, containsAll(<String>['planar reflections', 'render textures']));
    expect(unbound, isEmpty, reason: unbound.join('\n'));
  });
}
