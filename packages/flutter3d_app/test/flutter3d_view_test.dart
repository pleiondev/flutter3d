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
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show OriginShifted;
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

/// A view that counts the frames it draws into [frames], on a ticker held to
/// [cap] frames a second while [continuous].
Widget _capped(
  FakeBackend device, {
  required bool continuous,
  required double? cap,
  required List<FrameInfo> frames,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 32,
    height: 24,
    child: Flutter3dView(
      device: device,
      continuous: continuous,
      frameRateCap: cap,
      presenter: _noPresenter,
      onFrame: (_, frame) => frames.add(frame),
    ),
  ),
);

/// Pumps [count] refreshes of a 60 Hz display.
Future<void> _refreshes(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

void main() {
  testWidgets('a capped view draws again as soon as its ticker restarts', (
    tester,
  ) async {
    // Mutation: leave `FrameCadence.reset()` out of `_startTicker`. The
    // restarted ticker counts from nought again, the cadence still holds the
    // last frame drawn at two seconds, and the view draws nothing until the
    // new ticker has caught up with the old one — ten minutes for a ten
    // minute pause.
    final device = FakeBackend();
    final frames = <FrameInfo>[];
    await tester.pumpWidget(
      _capped(device, continuous: true, cap: 30.0, frames: frames),
    );
    await tester.pump();
    await _refreshes(tester, 120);
    expect(frames, isNotEmpty);
    await tester.pumpWidget(
      _capped(device, continuous: false, cap: 30.0, frames: frames),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(
      _capped(device, continuous: true, cap: 30.0, frames: frames),
    );
    final before = frames.length;
    await _refreshes(tester, 12);
    expect(frames.length - before, greaterThanOrEqualTo(5));
  });

  testWidgets('a cap of nought or less is no cap', (tester) async {
    // Mutation: hand the cadence the cap as it is. A cap of nought divides
    // the refresh rate by it and the view throws on its first refresh.
    final device = FakeBackend();
    final frames = <FrameInfo>[];
    await tester.pumpWidget(
      _capped(device, continuous: true, cap: 0.0, frames: frames),
    );
    await tester.pump();
    await _refreshes(tester, 30);
    expect(tester.takeException(), isNull);
    expect(frames.length, greaterThanOrEqualTo(29));
  });

  testWidgets('a display that says nought hertz has a rate to measure', (
    tester,
  ) async {
    // Mutation: hand the cadence the display's rate as it is. Nought hertz
    // taken as known is under every cap, so the cap is off and a view held to
    // thirty draws sixty.
    tester.view.display.refreshRate = 0.0;
    addTearDown(tester.view.display.resetRefreshRate);
    final device = FakeBackend();
    final frames = <FrameInfo>[];
    await tester.pumpWidget(
      _capped(device, continuous: true, cap: 30.0, frames: frames),
    );
    await tester.pump();
    await _refreshes(tester, 60);
    expect(frames.length, inInclusiveRange(28, 33));
  });

  testWidgets('a camera five kilometres out takes the origin with it', (
    tester,
  ) async {
    // Mutation: leave the origin where it is (no `_followCamera`). The
    // camera then stands 5 km from it, where float32 has half a millimetre
    // between neighbours, and the crate a quarter of a metre away is drawn
    // from a difference of two big numbers.
    final device = FakeBackend();
    Flutter3dEngine? engine;
    final shifts = <OriginShifted>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 32,
          height: 24,
          child: Flutter3dView(
            device: device,
            presenter: _noPresenter,
            onCreated: (e) {
              engine = e;
              e.loop.onOriginShift(shifts.add);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final crate = SceneNode(name: 'crate');
    engine!.scene.add(crate);
    crate.setPosition(5000.25, 0.0, 0.0);
    engine!.camera.setPosition(5000.0, 1.0, 5.0);
    await _refreshes(tester, 2);

    final scene = engine!.scene;
    expect(scene.origin, const WorldPosition(5000.0, 1.0, 5.0));
    expect(engine!.loop.origin, scene.origin, reason: 'one origin for both');
    expect(shifts, hasLength(1));
    // Nothing moved in the world; near the camera, float32 has its
    // precision back.
    final eye = engine!.camera.worldPosition;
    expect(eye.distanceTo(const WorldPosition(5000.0, 1.0, 5.0)), 0.0);
    final local = crate.worldMatrix.getTranslation();
    expect(local.x, 0.25);
    expect(local.y, -1.0);
    expect(local.z, -5.0);

    // A camera a few metres on is still near: no shift for every step.
    engine!.camera.setPosition(3.0, 0.0, 0.0);
    await _refreshes(tester, 2);
    expect(shifts, hasLength(1));
  });

  testWidgets('a view told not to shift the origin leaves it alone', (
    tester,
  ) async {
    // Mutation: shift whatever `originShift` says.
    final device = FakeBackend();
    Flutter3dEngine? engine;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 32,
          height: 24,
          child: Flutter3dView(
            device: device,
            presenter: _noPresenter,
            originShift: null,
            onCreated: (e) => engine = e,
          ),
        ),
      ),
    );
    await tester.pump();
    engine!.camera.setPosition(5000.0, 1.0, 5.0);
    await _refreshes(tester, 2);
    expect(engine!.scene.origin, WorldPosition.origin);
  });

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
    // The loss arrives on a stream, after the frame the first pump draws;
    // the failure is built on the next.
    await tester.pump();
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

  testWidgets('particles followed twice move once with a shift', (
    tester,
  ) async {
    // Mutation: move the engine's followers from `_shiftOrigin` beside the
    // scene's own handlers, as it did. A system the declarative `Particles3D`
    // draws and the game also hands `followOrigin` then moves twice: 20 m
    // for a 10 m shift, a jump in the world.
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

    final mount = SceneWidgets.mount(
      scene: engine!.scene,
      renderer: engine!.renderer,
      device: engine!.device,
      children: <Widget>[Particles3D(effect: effect, system: particles)],
    );
    final followed = engine!.followOrigin(particles);
    engine!.loop.shiftOrigin(const WorldPosition(10.0, 0.0, 0.0));
    expect(firstX(), closeTo(-9.0, 1e-4));
    // Either way of following keeps it following while the other goes.
    followed.cancel();
    engine!.loop.shiftOrigin(WorldPosition.origin);
    expect(firstX(), closeTo(1.0, 1e-4));
    mount.dispose();
  });
}
