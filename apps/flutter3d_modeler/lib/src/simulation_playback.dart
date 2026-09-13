/// Playing a baked simulation cache back onto a device mesh — `pro-sim-04`.
///
/// **[SimulationFrameSource] is the real, shipped contract; [SimulationCache]
/// (`pro-sim-03`, `packages/flutter3d_model_core`) is reconciled onto it via
/// [SimulationCacheFrameSource] below** rather than this file being rewritten
/// against the landed class's own member names (`frame(index)`, not the
/// `frameAt(index)` this file was originally drafted against before
/// `SimulationCache` was visible here).
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' show SimulationCache;

/// What this file needs from `pro-sim-03`'s `SimulationCache`: a fixed vertex
/// count, a frame count, and each frame's baked positions.
///
/// [frameAt] returns `vertexCount * 3` floats — x, y, z per vertex, the same
/// convention `pro-sim-03`'s own row describes and the one a position-only
/// preview mesh's vertex buffer already is. No normals, no UVs: a baked cache
/// played back for scrubbing does not need them, and carrying them would mean
/// this function no longer overwrites "the whole buffer" in one call, since a
/// cache frame would then cover only part of each vertex's bytes.
abstract interface class SimulationFrameSource {
  /// Vertices per frame. Every frame answers exactly this many.
  int get vertexCount;

  /// How many frames this cache holds.
  int get frameCount;

  /// The baked positions of frame [index]: `vertexCount * 3` floats, x/y/z
  /// per vertex, in vertex order.
  Float32List frameAt(int index);
}

/// [SimulationCache] (`pro-sim-03`), read through [SimulationFrameSource] —
/// the one reconciliation this file needed once the real class landed:
/// [SimulationCache.frame] answers the same floats [frameAt] promises, under
/// a different name.
final class SimulationCacheFrameSource implements SimulationFrameSource {
  const SimulationCacheFrameSource(this.cache);

  final SimulationCache cache;

  @override
  int get vertexCount => cache.vertexCount;

  @override
  int get frameCount => cache.frameCount;

  @override
  Float32List frameAt(int index) => cache.frame(index);
}

/// Writes frame [frameIndex] of [cache] into [mesh]'s own vertex buffer, via
/// [DeviceMesh.overwriteVertices] — the whole buffer in one call ("целиком"),
/// not a partial region.
///
/// [mesh] must be a position-only mesh — [DeviceMesh.vertexCount] vertices of
/// exactly 12 bytes (`x`, `y`, `z` as `Float32`) each, [VertexLayout
/// .positionOnly]'s own stride — which is what makes a cache frame's raw
/// floats a legal whole-buffer overwrite with no attribute layout to thread
/// through. A mesh with normals or UVs baked in cannot be scrubbed this way
/// without either re-deriving those attributes per frame (no simulation row
/// in this plan asks for that) or overwriting position alone through a
/// partial-stride call, which `pro-sc-05` already owns for a different
/// reason (dirty sculpt chunks) and this row does not.
///
/// Throws an [ArgumentError] if [cache]'s vertex count does not match
/// [mesh]'s, or if [mesh] is not position-only sized.
void playSimulationFrame(
  DeviceMesh mesh,
  GraphicsDevice device,
  SimulationFrameSource cache,
  int frameIndex,
) {
  if (cache.vertexCount != mesh.vertexCount) {
    throw ArgumentError(
      'playSimulationFrame: cache has ${cache.vertexCount} vertices per '
      'frame, mesh has ${mesh.vertexCount}',
    );
  }
  const positionOnlyStride = 12; // x, y, z as Float32 — 4 bytes each.
  final meshStride = mesh.vertices.lengthInBytes ~/ mesh.vertexCount;
  if (meshStride != positionOnlyStride) {
    throw ArgumentError(
      'playSimulationFrame: mesh has a $meshStride-byte vertex stride; '
      'cache playback needs a position-only mesh ($positionOnlyStride bytes)',
    );
  }
  if (frameIndex < 0 || frameIndex >= cache.frameCount) {
    throw RangeError.index(frameIndex, cache, 'frameIndex', null, cache.frameCount);
  }

  final frame = cache.frameAt(frameIndex);
  if (frame.length != cache.vertexCount * 3) {
    throw ArgumentError(
      'playSimulationFrame: frame $frameIndex has ${frame.length} floats, '
      'expected ${cache.vertexCount * 3} (${cache.vertexCount} vertices x3)',
    );
  }

  final bytes = frame.buffer.asByteData(frame.offsetInBytes, frame.lengthInBytes);
  mesh.overwriteVertices(device, 0, bytes);
}
