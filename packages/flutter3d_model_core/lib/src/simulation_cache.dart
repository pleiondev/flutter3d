/// Baked simulation frames for one object — `pro-sim-03`'s own row.
///
/// **A cache, not a live simulation.** `pro-sim-01`'s XPBD solver (or
/// whatever else `pro-sim-02` eventually bakes) is expensive enough per
/// frame that scrubbing a viewport's own timeline cannot afford to re-run it
/// every time the playhead moves; [SimulationCache] is the frame-by-frame
/// answer captured once, ahead of time, so scrubbing becomes an array
/// lookup.
library;

import 'dart:convert';
import 'dart:typed_data';

/// One bake that fills a [SimulationCache] for one object — what
/// `ApplySimulationCache` needs to know about whatever produced the frames.
///
/// **The contract a new solver meets, so the modeller does not learn it.**
/// Cloth, a rigid body and a particle system each bake differently; what a
/// cache strip, a job runner and the apply command need is the same five
/// answers, and a soft body or a fluid arriving later is one more class that
/// gives them rather than one more branch wherever a bake is shown or applied.
abstract interface class SimulationBakeRequest {
  /// Which object the finished cache answers for.
  int get objectId;

  /// `ModelObject.version` when this was built; `ApplySimulationCache` refuses
  /// a cache whose object has moved past it.
  int get baseVersion;

  /// How many frames the bake aims for.
  int get frameCount;

  /// How many vertices each frame holds.
  int get vertexCount;

  /// Runs the whole bake and answers with the cache.
  Future<SimulationCache> bake();
}

/// [vertexCount] vertices, snapshotted once per frame in [frames].
///
/// **Every frame the same length, `3 * vertexCount`** — x/y/z per vertex,
/// flat, the same layout `ClothMesh.positions` already uses in
/// `flutter3d_cloth`, so a frame can be set straight into a mesh upload
/// without walking it into vectors first. [BakeClothJobRequest] is what
/// fills one of these in, one frame — one chunk — at a time.
final class SimulationCache {
  /// [frames] is copied into an unmodifiable list; mutating the [List] handed
  /// in afterwards does not reach back into this cache. Throws
  /// [ArgumentError] for a frame whose own length is not `vertexCount * 3` —
  /// a cache that quietly held frames of mismatched vertex counts would be a
  /// cache nothing downstream could trust the shape of.
  SimulationCache({required this.vertexCount, required List<Float32List> frames})
    : frames = List<Float32List>.unmodifiable(frames) {
    final expected = vertexCount * 3;
    for (var i = 0; i < this.frames.length; i++) {
      if (this.frames[i].length != expected) {
        throw ArgumentError(
          'frame $i has ${this.frames[i].length} values, expected $expected '
          '(vertexCount $vertexCount × 3)',
        );
      }
    }
  }

  /// How many vertices one frame covers. Constant across every frame in
  /// [frames] — a simulation that changes topology mid-bake is out of this
  /// cache's own scope.
  final int vertexCount;

  /// One snapshot per baked frame, in order, each `vertexCount * 3` values
  /// long (x/y/z per vertex). Unmodifiable — see the constructor.
  final List<Float32List> frames;

  /// How many frames are actually in [frames] — not to be confused with
  /// whatever frame count a bake was aiming for, which this type never
  /// knows on its own. See [coverage] for that comparison.
  int get frameCount => frames.length;

  bool get isEmpty => frames.isEmpty;

  /// Frame [index]'s own vertex positions.
  Float32List frame(int index) => frames[index];

  /// How much of a [targetFrameCount]-frame bake this cache actually holds,
  /// from `0.0` (nothing baked yet) to `1.0` (every frame baked) — the pure
  /// number a cache-status strip paints, without this type knowing what a
  /// strip even is. Clamped, so a cache that somehow holds more frames than
  /// [targetFrameCount] still reads as fully covered rather than overflowing
  /// past it.
  double coverage(int targetFrameCount) {
    if (targetFrameCount <= 0) return frames.isEmpty ? 0.0 : 1.0;
    return (frameCount / targetFrameCount).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'vertexCount': vertexCount,
    'frames': <String>[for (final Float32List f in frames) _encodeFrame(f)],
  };

  /// A [SimulationCache] from its own [toJson], or null when a field is
  /// missing, of the wrong type, or a frame's own length does not match
  /// `vertexCount` — the same "skip rather than fail the whole file"
  /// contract [JobRequest.fromJson] already keeps.
  static SimulationCache? fromJson(Map<String, Object?> json) {
    if (json case {
      'vertexCount': final int vertexCount,
      'frames': final List<Object?> framesJson,
    }) {
      final frames = <Float32List>[];
      for (final Object? each in framesJson) {
        if (each is! String) return null;
        final Float32List? frame = _decodeFrame(each);
        if (frame == null) return null;
        frames.add(frame);
      }
      try {
        return SimulationCache(vertexCount: vertexCount, frames: frames);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }
}

String _encodeFrame(Float32List frame) =>
    base64Encode(Uint8List.sublistView(frame));

Float32List? _decodeFrame(String encoded) {
  final Uint8List bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    return null;
  }
  if (bytes.lengthInBytes % 4 != 0) return null;
  // Copied into a fresh buffer rather than viewed in place: `base64Decode`
  // makes no promise its own result starts at a 4-byte-aligned offset, and
  // `ByteBuffer.asFloat32List` throws if it does not.
  return Uint8List.fromList(bytes).buffer.asFloat32List();
}
