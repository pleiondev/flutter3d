/// What `NativeGpu.open` throws when there is no GPU to open.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException;

/// There is no GPU the visual passes can run on: no adapter, a driver
/// wgpu-native cannot use, no GPU library in this build, or the browser.
///
/// **A capability missing, not a failure** — the passes have a CPU path,
/// and a game that asked for the GPU falls back to it, saying [message]
/// where a player reporting a slow frame will see it.
final class GpuUnavailable extends CapabilityException {
  const GpuUnavailable(this.message);

  @override
  final String message;

  @override
  String toString() => 'GpuUnavailable: $message';
}
