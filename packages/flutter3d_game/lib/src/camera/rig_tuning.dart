/// Where a chasing camera sits, and how fast it gets there.
///
/// **Two games had these six fields and two of the sentences explaining them.**
/// A platformer's `FollowTuning` and a racing game's `ChaseTuning` each declared
/// `distance`, `height`, `aimHeight`, `lag`, `nearClearance` and `minDistance` —
/// with the same meanings and, in two cases, the same paragraph rewritten around
/// a different noun: "how far up the runner the camera looks, its middle rather
/// than its feet, or the horizon sits in the wrong place the whole game", and
/// the same again about a car and a race.
///
/// So the six are here and the reasons are written once. What is **not** here is
/// how either camera decides where it wants to be — an orbit the player turns,
/// or a heading blended between the nose and the direction of travel. That is
/// the game, it is most of both classes, and it stays there. This is the part
/// that was the same answer to the same question.
///
/// Extended rather than held, so `tuning.distance` goes on meaning what it did
/// at every call site in both games.
base class RigTuning {
  const RigTuning({
    required this.distance,
    required this.height,
    required this.aimHeight,
    required this.lag,
    required this.nearClearance,
    required this.minDistance,
  });

  /// How far behind whatever it is watching the camera sits, in metres.
  final double distance;

  /// And how far above it.
  final double height;

  /// How far up the subject the camera looks.
  ///
  /// Its middle rather than its feet, or the horizon sits in the wrong place
  /// for the whole game.
  final double aimHeight;

  /// How much of the remaining gap is closed in a second.
  ///
  /// Exponential rather than a fixed speed, so it is frame-rate independent and
  /// so it never overshoots — a camera that oscillates around what it is
  /// watching is a camera that makes people ill.
  final double lag;

  /// How far in front of a wall the camera stops.
  final double nearClearance;

  /// How close to the subject it may be pulled before giving up.
  ///
  /// A camera pushed inside what it is watching shows the inside of it, which
  /// is worse than a camera in a wall.
  final double minDistance;
}
