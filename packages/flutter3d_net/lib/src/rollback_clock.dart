/// The clock a rollback's cost is read off, outside every step.
library;

final Stopwatch _clock = Stopwatch()..start();

/// The time since the first session asked, on a monotonic stopwatch: what
/// `RollbackSession.stats` times a step run again by. Nothing a step runs
/// reads it; the times go into the stats and nowhere else.
Duration rollbackClock() => _clock.elapsed;
