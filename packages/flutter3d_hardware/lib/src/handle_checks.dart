/// The debug check every backend makes before it uses a handle: that the
/// handle has not been disposed. Exported by
/// `package:flutter3d_hardware/backend.dart`.
library;

import 'compute.dart';
import 'geometry_buffer.dart';
import 'resources.dart';
import 'shader.dart';
import 'texture.dart';

/// Asserts that [handle] — a [TextureHandle], [GeometryBuffer],
/// [StorageBuffer], [PipelineHandle], [ComputePipelineHandle], [QuerySet] or
/// [RenderBundle] — has not been disposed, naming [operation] when it has.
///
/// **For a backend, at the point it hands the handle to its API**: a bind, a
/// draw, a copy, a readback. A disposed handle reaching a driver is a WebGL
/// error the browser logs, a WebGPU validation error a frame later, and on
/// Impeller (whose handles the collector frees) a picture that still draws,
/// so the one place all four can say the same thing is here, before the
/// call. An assertion: a release build pays nothing.
///
/// Anything else, a [ShaderHandle] among it, passes: a stage is handed out by
/// its library, and a pipeline linked from it keeps drawing after it is
/// disposed (see `ShaderHandle.dispose`).
void debugCheckLive(Object handle, String operation) {
  assert(() {
    final disposed = switch (handle) {
      TextureHandle(:final isDisposed) ||
      GeometryBuffer(:final isDisposed) ||
      StorageBuffer(:final isDisposed) ||
      PipelineHandle(:final isDisposed) ||
      ComputePipelineHandle(:final isDisposed) ||
      QuerySet(:final isDisposed) ||
      RenderBundle(:final isDisposed) => isDisposed,
      _ => false,
    };
    if (disposed) {
      throw StateError(
        '$operation: $handle was disposed. A handle may not be used once '
        'its owner has given it back; make another.',
      );
    }
    return true;
  }());
}
