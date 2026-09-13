import 'package:flutter3d_game/flutter3d_game.dart';

/// `rp-04`'s game-side half: the last few seconds [rewind] has kept, as the
/// state and the tape a [Demo] needs — everything except the checkpoints and
/// the free-text fields, which only the caller can supply.
///
/// **Not a [Demo] itself.** A digest trace over the window this reports
/// costs a replay this function has no simulation to run — the caller
/// already has one, running, and is who should take it. Handing back the
/// two pieces that only [rewind] can give keeps this from asking for a
/// callback it would use exactly once.
///
/// Null when [rewind] holds nothing yet — the very first moments of a level,
/// before its first keyframe — the same as [RewindBuffer.rewindBy] itself.
BugReportTape? bugReportTape(RewindBuffer rewind) {
  final point = rewind.rewindBy(rewind.available);
  if (point == null) return null;
  return (
    start: point.snapshot,
    tape: InputTape(seed: point.seed, frames: point.frames),
  );
}

/// The state a bug report's tape starts from, and everything since.
typedef BugReportTape = ({Snapshot start, InputTape tape});
