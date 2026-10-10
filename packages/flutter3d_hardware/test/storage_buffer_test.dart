/// A storage buffer is `createBuffer`'s, since `createStorageBuffer` folded
/// into it, and a trace still carries one as it always did.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

FakeBackend _device() => FakeBackend(
  extraFeatures: const <DeviceFeature>[
    DeviceFeature.buffers,
    DeviceFeature.renderStageStorage,
  ],
);

void main() {
  test('a storage buffer made with createBuffer is traced as one', () async {
    // Mutation: `RecordingDevice.createBuffer` left noting every buffer as
    // unrecorded, as it did before the fold — the trace loses the compute
    // input it used to carry, and its replay has no buffer to bind.
    final device = RecordingDevice(_device());
    final bytes = ByteData(16)..setUint32(4, 7, Endian.little);
    final buffer = device.createBuffer(
      BufferDescriptor(
        lengthInBytes: 16,
        usage: BufferUsage.standardStorage | BufferUsage.index,
      ),
      contents: bytes,
    );
    expect(buffer.asIndices, isNotNull);
    expect(device.unrecorded, isNot(contains('createBuffer')));
    final event = device.events.whereType<TraceCreateStorageBuffer>().single;
    expect(event.bytes.getUint32(4, Endian.little), 7);
    expect(event.hostReadable, isFalse);
    expect(event.indices, isNotNull);

    final again = RecordingDevice(_device());
    await replayTrace(Trace.decode(Trace(device.events).encode()), again);
    final replayed = again.events.whereType<TraceCreateStorageBuffer>().single;
    expect(replayed.bytes.getUint32(4, Endian.little), 7);
    expect(replayed.indices, isNotNull);
  });

  test('any other buffer is passed on and listed as unrecorded', () {
    final device = RecordingDevice(_device())
      ..createBuffer(
        const BufferDescriptor(lengthInBytes: 16, usage: BufferUsage.uniform),
      );
    expect(device.unrecorded, contains('createBuffer'));
    expect(device.events.whereType<TraceCreateStorageBuffer>(), isEmpty);
  });
}
