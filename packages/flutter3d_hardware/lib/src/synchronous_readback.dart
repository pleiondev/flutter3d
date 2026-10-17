/// The synchronous buffer read, for a test or a tool and never a frame.
///
/// Exported by `package:flutter3d_hardware/testing.dart`, for the caller that
/// asks for it, and by `backend.dart`, for the backend that mixes it in; not
/// by the main library (E.12 of the API review: no synchronous readback on
/// the main API).
library;

import 'dart:typed_data';

import 'compute.dart';
import 'graphics_device.dart';
import 'resources.dart';

/// A device that reads a buffer back in the calling turn —
/// `DeviceFeature.synchronousReadback`.
///
/// **A capability a device opts into, not a member every device carries**,
/// since 1.0: WebGPU has no such call by design, and a member every device
/// had to answer was a member three of four answered with a refusal. Asked
/// with `device is SynchronousBufferReadback`; a device that is one lists
/// `DeviceFeature.synchronousReadback` in its features. The software
/// rasteriser and WebGL2 are.
///
/// **Out of the main library, since 1.0**, because a stall is a test's or a
/// tool's tradeoff and never a frame's: a caller that asks for it imports it
/// from `package:flutter3d_hardware/testing.dart`, and a backend mixes it in
/// from `backend.dart`.
base mixin SynchronousBufferReadback on GraphicsDevice {
  /// The bytes of [buffer] (a range of them), read back in the calling turn.
  ///
  /// **A stall, on purpose.** The call waits for every pass submitted before
  /// it, which is the price WebGL2's `getBufferSubData` charges and the
  /// reason WebGPU has no such call. For a tool or a test that would rather
  /// block than restructure; a frame loop wants
  /// [GraphicsDevice.readBuffer] or [GraphicsDevice.mapBuffer]. [buffer]
  /// must be [BufferUsage.hostReadable].
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  });
}
