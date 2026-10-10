/// `GraphicsDevice.lost` on Impeller, through the state `GpuRenderBackend`
/// keeps it in.
///
///     flutter test test/device_loss_test.dart
///
/// flutter_gpu gives no signal when the context goes, so the one loss this
/// backend can see is its own `dispose`, reported as
/// `DeviceLossReason.destroyed` the way every backend reports it. The device
/// itself needs Impeller to open, which `flutter test` does not run, so this
/// holds the piece the device delegates to; `gpu_device.dart` forwards
/// `lost`, `isLost` and `dispose` to it and nothing else.
library;

import 'dart:io';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/src/gpu_device_loss.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a disposed device says so, once, and is lost', () async {
    // Mutation: drop the `add` in `GpuDeviceLoss.dispose`, and the stream
    // closes with no event while `isLost` reads true; return before it, and
    // the stream never closes and this times out.
    final loss = GpuDeviceLoss();
    expect(loss.isLost, isFalse);
    final events = loss.lost.toList();
    loss
      ..dispose()
      // A second dispose is a teardown run twice, not a second loss.
      ..dispose();
    final losses = await events;
    expect(losses, hasLength(1));
    expect(losses.single.reason, DeviceLossReason.destroyed);
    expect(losses.single.isRecoverable, isFalse);
    expect(loss.isLost, isTrue);
  });

  test('a listener that arrives after the loss can still ask', () async {
    // Mutation: drop the `close`, and a late listener waits forever on a
    // stream that will never say anything again.
    final loss = GpuDeviceLoss()..dispose();
    expect(loss.isLost, isTrue);
    expect(await loss.lost.toList(), isEmpty);
  });

  test('the device hands its loss to this and to nothing else', () {
    // The device cannot be opened here, so the forwarding is held by reading
    // its source: an override that drifted back to the inherited empty
    // stream would leave every test above green and the backend silent.
    //
    // Mutation: delete the `lost` override in `gpu_device.dart`, and this
    // fails naming it.
    final source = File('lib/src/gpu_device.dart').readAsStringSync();
    for (final forwarded in <String>[
      'Stream<DeviceLoss> get lost => _loss.lost;',
      'bool get isLost => _loss.isLost;',
      '_loss.dispose();',
    ]) {
      expect(source, contains(forwarded), reason: forwarded);
    }
  });
}
