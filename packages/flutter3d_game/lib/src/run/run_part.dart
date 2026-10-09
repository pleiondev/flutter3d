/// A run's own snapshot and the loop's, converted by the part the run is
/// registered under.
///
/// **Why both shapes exist.** A `.f3drun`'s start and its checkpoints are
/// the run's own `save()` — what every tape recorded since 0.6 holds, and
/// what its digests are taken of — while the loop restores and captures
/// every part at once. A run registered in the loop as one part (a genre
/// under its plugin id, a game's run under a `SnapshotPart` of its own)
/// converts between the two by that part's id, and nothing else is needed:
/// a tape's start goes in as that part alone, and a checkpoint comes out of
/// a loop capture as that part's data.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';

/// [runState] as a snapshot of [loop] holding the part [part] alone, for
/// `EngineLoop.rewindTo(step, state: …)`. The parts it does not hold are left
/// as they are.
///
/// Throws an [ArgumentError] naming the loop's parts when [part] is not one
/// of them: the run would otherwise be restored into nothing.
Snapshot loopStateWith(EngineLoop loop, String part, Snapshot runState) {
  final parts = loop.snapshots.parts;
  if (!parts.contains(part)) {
    throw ArgumentError.value(
      part,
      'part',
      'is not a part of the loop\'s snapshots (${parts.join(', ')}); '
          'register the run as one — a genre does under its plugin id',
    );
  }
  // Version 1: a run's own snapshot carries no version of its own, and the
  // first is the one every part reads.
  return Snapshot(<String, Object?>{
    part: <String, Object?>{'version': 1, 'data': runState.data},
  });
}

/// The data of [part] in [loopState], a loop's capture, as the run's own
/// snapshot; an empty one when [loopState] holds none of it.
Snapshot runStateIn(Snapshot loopState, String part) =>
    switch (loopState.data[part]) {
      {'data': final Map<Object?, Object?> data} => Snapshot(
        data.cast<String, Object?>(),
      ),
      _ => const Snapshot(<String, Object?>{}),
    };
