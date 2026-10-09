/// An engine as a widget: what it does when its device goes, and what it
/// moves when the origin does.
///
///     flutter test test/flutter3d_view_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

Widget _view(
  FakeBackend device, {
  void Function(Flutter3dEngine engine)? onCreated,
  void Function(Flutter3dEngine engine, DeviceLoss loss)? onDeviceLost,
  void Function(Flutter3dEngine engine)? onDeviceRestored,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 32,
    height: 24,
    child: Flutter3dView(
      device: device,
      continuous: false,
      presenter: _noPresenter,
      onCreated: onCreated,
      onDeviceLost: onDeviceLost,
      onDeviceRestored: onDeviceRestored,
    ),
  ),
);

void main() {
  testWidgets('a lost context that comes back gets a renderer of its own', (
    tester,
  ) async {
    // Mutation: leave `_recover` out of the restored branch. The view then
    // waits for ever on a loss that is over, and draws nothing again.
    final device = FakeBackend();
    Flutter3dEngine? engine;
    final lost = <DeviceLoss>[];
    var restored = 0;
    await tester.pumpWidget(
      _view(
        device,
        onCreated: (e) => engine = e,
        onDeviceLost: (_, loss) => lost.add(loss),
        onDeviceRestored: (_) => restored++,
      ),
    );
    await tester.pump();
    final before = engine!.renderer;

    device.lose(
      const DeviceLoss(reason: DeviceLossReason.unknown, isRecoverable: true),
    );
    await tester.pump();
    expect(lost, hasLength(1));
    expect(engine!.loss, isNotNull);
    expect(restored, 0);

    device.lose(
      const DeviceLoss(
        reason: DeviceLossReason.unknown,
        isRecoverable: true,
        restored: true,
      ),
    );
    await tester.pump();
    expect(restored, 1);
    expect(engine!.loss, isNull);
    expect(engine!.renderer, isNot(same(before)));
    // The steps the plugins were handed are the ones the new renderer reads.
    expect(engine!.renderer.renderSteps, same(before.renderSteps));
  });

  testWidgets('a borrowed device lost for good is shown as a failure', (
    tester,
  ) async {
    // Mutation: open a device again whether or not the view owned the first.
    // A borrowed device is its owner's, and so is what replaces it.
    final device = FakeBackend();
    await tester.pumpWidget(_view(device));
    await tester.pump();
    device.lose(const DeviceLoss(reason: DeviceLossReason.unknown));
    await tester.pump();
    expect(find.textContaining('could not start'), findsOneWidget);
  });

  testWidgets('particles that follow the origin move with a shift', (
    tester,
  ) async {
    // Mutation: drop the particles from `_shiftOrigin`. They then stay where
    // they were in the scene's space, which is a jump in the world.
    final device = FakeBackend();
    Flutter3dEngine? engine;
    await tester.pumpWidget(_view(device, onCreated: (e) => engine = e));
    await tester.pump();
    final effect = ParticleEffect(
      count: 1,
      emitter: const SphereEmitter(speed: Range.exact(0.0)),
      lifetime: const Range.exact(5.0),
      size: const Range.exact(1.0),
      color: Vector4(1.0, 1.0, 1.0, 1.0),
    );
    final particles = ParticleSystem(capacity: 2)
      ..burst(effect, Vector3(1.0, 0.0, 0.0));
    double firstX() {
      final out = Float32List(2 * ParticleSystem.floatsPerInstance);
      particles.writeInstances(out);
      return out[0];
    }

    final registration = engine!.followOrigin(particles);
    // Ten metres along X: what stood at x = 1 stands at x = -9 now.
    engine!.loop.shiftOrigin(const WorldPosition(10.0, 0.0, 0.0));
    expect(firstX(), closeTo(-9.0, 1e-4));
    registration.cancel();
    engine!.loop.shiftOrigin(WorldPosition.origin);
    expect(firstX(), closeTo(-9.0, 1e-4));
  });
}
