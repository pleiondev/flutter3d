/// A rival or a past run, drawn from a recorded track.
///
/// Three pieces, each usable alone:
///
/// * [Ghost] — a translucent, unlit, untouchable node put where a [Tape] was
///   at a moment of it, or hidden before it starts and after it ends;
/// * [ghostOfRun] — the track of one body through a shared run: the tape
///   played again when it can be, the run's pose record when it cannot, and
///   the reason when neither will do;
/// * [BestRun] — the best run made in one place, kept between launches.
///
/// None of them knows what is being raced. A game hands over its own model,
/// its own staging for a replay and its own name for the file.
library;

export 'src/ghost/best_run.dart';
export 'src/ghost/ghost.dart';
export 'src/ghost/ghost_of_run.dart';
