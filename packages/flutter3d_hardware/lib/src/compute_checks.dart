/// The checks every compute encoder makes the same way — since
/// 1.0.0-rc.1, from `package:flutter3d_hardware/backend.dart`.
///
/// **Refused on the VM as WebGPU refuses it in the browser.** A storage
/// range at an offset the device cannot bind, or a dispatch past
/// `maxComputeWorkgroupsPerDimension`, is a validation error a WebGPU
/// device drains long after the call, while the CPU would simply have run
/// it. Every encoder calls these two before it records the binding or the
/// dispatch, so the mistake is a [RangeError] at the call that made it, on
/// every backend, and a test on the CPU finds what the browser would.
library;

import 'capabilities.dart';
import 'compute.dart';

/// Checks a storage binding of [buffer] from [offsetInBytes], [sizeInBytes]
/// long (to the end when null), against [limits]: the range lies inside
/// the buffer and starts at a multiple of
/// `DeviceLimits.minStorageBufferOffsetAlignment`. Answers the size bound.
///
/// Throws a [RangeError] naming the call that is wrong.
int checkStorageBinding(
  StorageBuffer buffer,
  DeviceLimits limits, {
  int offsetInBytes = 0,
  int? sizeInBytes,
}) {
  final size = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
  if (offsetInBytes < 0 ||
      size < 0 ||
      offsetInBytes + size > buffer.lengthInBytes) {
    throw RangeError(
      'bindStorageBuffer: $size bytes from $offsetInBytes leave a buffer of '
      '${buffer.lengthInBytes}',
    );
  }
  final alignment = limits.minStorageBufferOffsetAlignment;
  if (alignment > 0 && offsetInBytes % alignment != 0) {
    throw RangeError(
      'bindStorageBuffer: offset $offsetInBytes is not a multiple of '
      'minStorageBufferOffsetAlignment ($alignment) on this device',
    );
  }
  return size;
}

/// Checks a dispatch of `x × y × z` workgroups against [limits]: each
/// count at least zero and at most
/// `DeviceLimits.maxComputeWorkgroupsPerDimension`.
///
/// Throws a [RangeError] naming the count that is wrong.
void checkDispatch(DeviceLimits limits, int x, int y, int z) {
  final most = limits.maxComputeWorkgroupsPerDimension;
  for (final (axis, n) in <(String, int)>[('x', x), ('y', y), ('z', z)]) {
    if (n < 0 || n > most) {
      throw RangeError(
        'dispatch: $n workgroups along $axis, and this device takes 0 to '
        '$most (maxComputeWorkgroupsPerDimension)',
      );
    }
  }
}
