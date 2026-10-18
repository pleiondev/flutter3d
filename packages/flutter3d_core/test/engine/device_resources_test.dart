/// The registry a restored device is answered from: each resource made
/// again by its recipe, ids kept, and a renderer that draws again on the
/// device that came back without being made anew.
///
///     dart test test/engine/device_resources_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceResources', () {
    test('recreate makes every resource again, in order, ids kept', () {
      // Mutation: skip `_remake` for adopted resources. The fallback an
      // application handed in stays the spent handle.
      final device = FakeBackend();
      final resources = DeviceResources();
      final made = <String>[];
      final white = resources.add('white', device, (GraphicsDevice on) {
        made.add('white');
        return SolidColorTexture.white.upload(on);
      });
      final handed = SolidColorTexture.flatNormal.upload(device);
      final normal = resources.adopt('normal', handed, (GraphicsDevice on) {
        made.add('normal');
        return SolidColorTexture.flatNormal.upload(on);
      });
      final before = white.value;
      expect(made, <String>['white']);

      final report = resources.recreate(device);
      expect(report.recreated, 2);
      expect(report.isComplete, isTrue);
      expect(made, <String>['white', 'white', 'normal']);
      expect(identical(white.value, before), isFalse);
      expect(identical(normal.value, handed), isFalse);
      expect(white.generation, 1);
      expect(<int>[white.id, normal.id], <int>[0, 1]);
    });

    test('onMade hears the first value and every one after', () {
      final device = FakeBackend();
      final heard = <TextureHandle>[];
      final resources = DeviceResources();
      final entry = resources.add(
        'white',
        device,
        SolidColorTexture.white.upload,
        onMade: heard.add,
      );
      resources.recreate(device);
      expect(heard, hasLength(2));
      expect(identical(heard.last, entry.value), isTrue);
    });

    test('a released resource is not made again and its id stays spent', () {
      final device = FakeBackend();
      final resources = DeviceResources();
      final first = resources.add('a', device, SolidColorTexture.white.upload);
      resources.release(first);
      final second = resources.add('b', device, SolidColorTexture.white.upload);
      expect(first.isReleased, isTrue);
      expect(second.id, 1);
      expect(resources.recreate(device).recreated, 1);
      expect(first.generation, 0);
    });

    test('a recipe that throws is reported and the rest are made', () {
      // Mutation: let the throw escape `recreate`. One missing stage leaves
      // every resource after it spent.
      final device = FakeBackend();
      final resources = DeviceResources();
      var fail = false;
      final broken = resources.add('broken', device, (GraphicsDevice on) {
        if (fail) throw StateError('gone');
        return SolidColorTexture.white.upload(on);
      });
      final after = resources.add(
        'after',
        device,
        SolidColorTexture.white.upload,
      );
      fail = true;
      final report = resources.recreate(device);
      expect(report.recreated, 1);
      expect(report.failed.single.resource, same(broken));
      expect(report.failed.single.error, isA<StateError>());
      expect(after.generation, 1);
      expect(broken.generation, 0);
    });
  });

  group('Renderer.recoverFromLoss', () {
    ({FakeBackend device, Renderer renderer, Scene scene, CameraNode camera})
    stage() {
      final device = FakeBackend();
      final camera = CameraNode();
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(device, CuboidShape().build()),
            RenderMaterial(),
          )..setPosition(0.0, 0.0, -5.0),
        )
        ..add(camera);
      return (
        device: device,
        renderer: Renderer.create(device: device),
        scene: scene,
        camera: camera,
      );
    }

    FrameResult draw(
      ({FakeBackend device, Renderer renderer, Scene scene, CameraNode camera})
      it,
    ) => it.renderer.render(
      width: 64,
      height: 48,
      scene: it.scene,
      views: <CameraView>[CameraView(camera: it.camera)],
    );

    test('the same renderer draws again with nothing it held before', () {
      // Mutation: drop `_forgetDeviceObjects` from `recoverFromLoss`. The
      // frame after the restore draws into targets the lost device spent.
      final it = stage();
      draw(it);
      final spent = Set<Object>.identity()..addAll(it.device.liveHandles);
      final albedo = it.renderer.fallbackAlbedo;
      final steps = it.renderer.renderSteps;

      it.device
        ..lose(
          const DeviceLoss(
            reason: DeviceLossReason.unknown,
            isRecoverable: true,
          ),
        )
        ..lose(
          const DeviceLoss(
            reason: DeviceLossReason.unknown,
            isRecoverable: true,
            restored: true,
          ),
        );
      final report = it.renderer.recoverFromLoss();
      expect(report.isComplete, isTrue);
      // Every stage and the three fallbacks.
      expect(report.recreated, it.renderer.deviceResources.length);
      expect(identical(it.renderer.fallbackAlbedo, albedo), isFalse);
      expect(it.renderer.renderSteps, same(steps));

      // The scene's own mesh is the scene's to load again.
      it.scene.meshes.first.mesh = DeviceMesh.upload(
        it.device,
        CuboidShape().build(),
      );
      final attachments = <Object>[];
      it.device.onBeginRenderPass = (RenderPassDescriptor pass) {
        attachments.addAll(
          <Object?>[
            for (final color in pass.colors) ...<Object?>[
              color.texture,
              color.resolveTexture,
            ],
            pass.depth?.texture,
          ].whereType<Object>(),
        );
      };
      final result = draw(it);
      expect(result.passes, isNotEmpty);
      expect(attachments, isNotEmpty);
      expect(attachments.where(spent.contains), isEmpty);
    });

    test('a fallback handed in is replaced by the one handed to recover', () {
      final it = stage();
      final mine = SolidColorTexture.white.upload(it.device);
      it.renderer.recoverFromLoss(fallbackAlbedo: mine);
      expect(it.renderer.fallbackAlbedo, same(mine));
    });

    test('a plugin\'s resource registered with the renderer comes back', () {
      final it = stage();
      final table = it.renderer.deviceResources.add(
        'acme.table',
        it.device,
        SolidColorTexture.white.upload,
      );
      final before = table.value;
      it.renderer.recoverFromLoss();
      expect(identical(table.value, before), isFalse);
    });
  });
}
