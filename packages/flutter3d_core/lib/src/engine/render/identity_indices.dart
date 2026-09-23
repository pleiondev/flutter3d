import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The index sequence 0, 1, 2, … that a draw of unindexed vertices is made
/// through.
///
/// **`CommandEncoder.draw` in this engine is always indexed, and there is no
/// non-indexed path.** A draw with a vertex buffer and no index buffer bound
/// is a draw of nothing, silently. The renderer's debug overlay, `MeshOverlay`
/// and `SplatContributor` all draw vertex lists that way, and each keeps one
/// of these rather than its own copy of the growth arithmetic.
///
/// The buffer only grows. A grown buffer does not release the one before it,
/// because a draw encoded earlier in the same frame may still be reading a
/// slice of it; [release] gives back the current one when its owner is done.
final class IdentityIndices {
  GeometryBuffer? _buffer;
  int _capacity = 0;

  /// A view over the sequence long enough for [count] vertices, uploaded to
  /// [device] the first time [count] outgrows what is already there.
  GeometryBuffer view(GraphicsDevice device, int count) {
    if (count > _capacity) {
      var capacity = math.max(_capacity * 2, 1024);
      while (capacity < count) {
        capacity *= 2;
      }
      final indices = Uint32List(capacity);
      for (var i = 0; i < capacity; i++) {
        indices[i] = i;
      }
      _buffer = device.uploadGeometry(
        indices.buffer.asByteData(),
        GeometryUsage.indices,
      );
      _capacity = capacity;
    }
    return _buffer!.slice(length: count * 4);
  }

  /// Gives the current buffer back to [device]; the next [view] uploads a
  /// fresh one.
  void release(GraphicsDevice device) {
    final buffer = _buffer;
    if (buffer != null) device.releaseGeometry(buffer);
    _buffer = null;
    _capacity = 0;
  }
}
