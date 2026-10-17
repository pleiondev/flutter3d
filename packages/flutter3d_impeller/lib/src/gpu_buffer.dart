/// `GraphicsDevice.createBuffer` on flutter_gpu: a host-visible
/// `DeviceBuffer`, and the host's copy of what it holds.
///
/// **The host copy is not a cache, it is the buffer's contents.** On this
/// backend nothing but the host ever writes a buffer: there is no compute
/// pass, no storage binding, no copy into a buffer anyone can read and no
/// query resolve — every one of those is refused by name. So every byte the
/// `DeviceBuffer` holds arrived through [GpuBuffer.write], which writes both,
/// and `readBuffer` answering from the copy is answering what the buffer
/// holds. The day flutter_gpu gives the GPU a way to write a buffer, this
/// stops being true, and `readBuffer` has to go through a real read path —
/// which is the same upstream API that would unblock `mappedBuffers`.
library;

import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;

/// What `StorageBuffer.backend` carries for a buffer this backend made.
final class GpuBuffer {
  GpuBuffer(int lengthInBytes)
    : host = Uint8List(lengthInBytes),
      // flutter_gpu refuses an empty allocation; a zero-length buffer is a
      // legitimate contract value, so it gets four bytes nobody can reach.
      device = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        lengthInBytes == 0 ? 4 : lengthInBytes,
      );

  /// What a draw binds.
  final gpu.DeviceBuffer device;

  /// The bytes [device] holds, written alongside it — see the library doc.
  final Uint8List host;

  /// Writes [bytes] at [offsetInBytes] into both, flushing the device side:
  /// on unified memory a no-op, on a discrete GPU what moves the bytes across.
  void write(int offsetInBytes, ByteData bytes) {
    if (bytes.lengthInBytes == 0) return;
    host.setRange(
      offsetInBytes,
      offsetInBytes + bytes.lengthInBytes,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final ok = device.overwrite(bytes, destinationOffsetInBytes: offsetInBytes);
    if (!ok) {
      throw StateError(
        'DeviceBuffer.overwrite refused ${bytes.lengthInBytes} bytes at '
        '$offsetInBytes',
      );
    }
    device.flush(
      offsetInBytes: offsetInBytes,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  /// A copy of [length] bytes from [offset].
  ByteData read(int offset, int length) => ByteData.sublistView(
    Uint8List.fromList(host.sublist(offset, offset + length)),
  );
}
