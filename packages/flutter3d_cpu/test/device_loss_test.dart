/// `GraphicsDevice.lost` on the software device.
///
///     dart test test/device_loss_test.dart
///
/// Nothing outside this process can take a software device away, so the one
/// loss it has is its own [CpuDevice.dispose], reported as
/// `DeviceLossReason.destroyed` the way every backend reports it. A caller
/// that listens on whatever device it opened then learns the same thing here
/// as on WebGPU, rather than an empty stream that reads as "never lost".
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

CpuDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('a device that is disposed says so, once, and is lost', () async {
    // Mutation: leave `lost` and `isLost` to the inherited defaults, and the
    // stream ends with no event while `isLost` stays false.
    final device = _device();
    expect(device.isLost, isFalse);
    final events = device.lost.toList();
    device
      ..dispose()
      // A second dispose is a teardown run twice, not a second loss.
      ..dispose();
    final losses = await events;
    expect(losses, hasLength(1));
    expect(losses.single.reason, DeviceLossReason.destroyed);
    expect(losses.single.isRecoverable, isFalse);
    expect(device.isLost, isTrue);
  });

  test('a listener that arrives after the loss can still ask', () async {
    // Mutation: set `isLost` only inside a listener, and a caller that
    // subscribed late reads a live device.
    final device = _device()..dispose();
    expect(device.isLost, isTrue);
    expect(await device.lost.toList(), isEmpty);
  });
}
