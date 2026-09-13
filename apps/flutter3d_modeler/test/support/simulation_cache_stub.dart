/// A test-only stand-in for `pro-sim-03`'s `SimulationCache`.
///
/// **Not the real class — reconcile on sight.** At the time this file was
/// written, no `SimulationCache` existed anywhere in this worktree (grepped
/// directly: no `simulation_cache.dart` under `packages/flutter3d_model_core`
/// or anywhere else, and no `class SimulationCache` in the repo at all).
/// `pro-sim-03`'s own plan row gives its shape as `SimulationCache(frames,
/// vertexCount)`, and the driving task's own summary adds `frameCount`,
/// `frameAt(index)`, `toJson`/`fromJson` — this class is exactly that shape
/// and nothing more, kept here under `test/support/` rather than in
/// `lib/src/` so it cannot be mistaken for, or collide with, the real one
/// landing in `flutter3d_model_core`. It implements
/// `SimulationFrameSource` (`lib/src/simulation_playback.dart`) so the
/// production playback code depends on an interface, not on this stub or on
/// guessed internals of the real cache.
library;

import 'dart:typed_data';

import 'package:flutter3d_modeler/src/simulation_playback.dart';

final class SimulationCacheStub implements SimulationFrameSource {
  SimulationCacheStub({required this.vertexCount, required List<Float32List> frames})
    : _frames = List<Float32List>.unmodifiable(frames) {
    for (final frame in _frames) {
      if (frame.length != vertexCount * 3) {
        throw ArgumentError(
          'SimulationCacheStub: a frame has ${frame.length} floats, '
          'expected ${vertexCount * 3} for $vertexCount vertices',
        );
      }
    }
  }

  @override
  final int vertexCount;

  final List<Float32List> _frames;

  @override
  int get frameCount => _frames.length;

  @override
  Float32List frameAt(int index) => _frames[index];

  /// Named the same as the summarized real class, for whatever calls it —
  /// nothing in this row's own tests does, but a future caller reaching for
  /// `pro-sim-03`'s cache format should find the same two members here.
  Map<String, Object?> toJson() => <String, Object?>{
    'vertexCount': vertexCount,
    'frames': _frames.map((f) => f.toList()).toList(),
  };

  static SimulationCacheStub? fromJson(Map<String, Object?> json) {
    final vertexCount = json['vertexCount'];
    final frames = json['frames'];
    if (vertexCount is! int || frames is! List) return null;
    return SimulationCacheStub(
      vertexCount: vertexCount,
      frames: [
        for (final frame in frames)
          Float32List.fromList((frame as List).cast<num>().map((n) => n.toDouble()).toList()),
      ],
    );
  }
}
