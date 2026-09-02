import 'pose.dart';

/// A recording: where something was, over and over.
///
/// **Not a replay of the simulation, and that distinction is the whole design.**
/// Playing a run back by feeding recorded input through the physics would be
/// exact, and would break the moment anything about the body was tuned — which
/// is exactly when somebody most wants to compare against their old time.
/// Positions survive tuning, survive a changed surface, and cost nothing to
/// draw.
///
/// [seconds] is what the recorded thing took, and is the reason anybody keeps
/// the tape: a lap time, a run's clock, a personal best.
final class Tape {
  const Tape({required this.poses, required this.seconds});

  final List<Pose> poses;

  final double seconds;

  bool get isEmpty => poses.isEmpty;

  /// How long the recording runs for, which is not always [seconds]: the last
  /// sample lands before the finish rather than on it.
  double get duration => poses.isEmpty ? 0.0 : poses.last.time;

  /// **A tape does not write itself down, and that is not an omission.**
  ///
  /// The obvious `toJson` here would have to choose key names, and the names
  /// that matter are already on players' disks — written by the game that had
  /// this class first, under words this package is not allowed to say. The
  /// engine's own `no_genre_test.dart` caught the attempt, and it was right to:
  /// `lapTime` is a racing word, and a document's shape belongs to whoever
  /// keeps the document.
  ///
  /// [Pose] does serialise, because a place, a facing and a time are nobody's
  /// vocabulary in particular.
}
