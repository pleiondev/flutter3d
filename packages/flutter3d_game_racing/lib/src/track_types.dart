import 'package:vector_math/vector_math.dart';

/// Where the road is at some distance along the track, and which way is
/// forward, sideways and up there.
///
/// Filled in by [TrackSpline.frameAt] rather than returned by it: a car asks
/// for this several times a step, and a fresh set of four vectors each time is
/// four allocations on the hottest path the simulation has.
final class TrackFrame {
  /// The point on the centre line.
  final Vector3 position = Vector3.zero();

  /// The direction of travel — the way a car is meant to be going.
  final Vector3 forward = Vector3.zero();

  /// The direction `lateral` increases in, tilted by the camber.
  ///
  /// For a road running along +z this points along +x. Which side of the track
  /// that is has no natural name, so the track file calls the other one "left"
  /// and this one "right", and they mean nothing more than the sign of
  /// `lateral`.
  final Vector3 right = Vector3.zero();

  /// The road's own up: the normal of the surface, tilted by the camber.
  final Vector3 up = Vector3.zero();
}

/// What the road is made of over a stretch of it.
///
/// The name is a word and nothing more, exactly as [Brush.surface] is: this
/// package does not know what "gravel" does, and the table that turns it into
/// grip lives with the car.
final class SurfaceBand {
  const SurfaceBand({
    required this.fromS,
    required this.toS,
    this.centre,
    this.shoulder,
  });

  final double fromS;
  final double toS;

  /// The name for the road itself.
  final String? centre;

  /// The name for the ground either side of it, which is usually what makes
  /// leaving the road cost something.
  final String? shoulder;

  /// Whether [s] falls in this band, including a band that runs across the
  /// start line and so ends before it begins.
  bool covers(double s) =>
      fromS <= toS ? s >= fromS && s < toS : s >= fromS || s < toS;
}

/// A stretch of track with a wall down one side or both.
///
/// A barrier is a property of the track and not a piece of geometry, which is
/// the same decision the road surface takes and for the same reason — see
/// [TrackSpline].
final class BarrierBand {
  const BarrierBand({
    required this.fromS,
    required this.toS,
    this.left = false,
    this.right = false,
  });

  final double fromS;
  final double toS;

  /// A wall on the negative-`lateral` side.
  final bool left;

  /// A wall on the positive-`lateral` side.
  final bool right;

  bool covers(double s) =>
      fromS <= toS ? s >= fromS && s < toS : s >= fromS || s < toS;
}

/// Where the cars line up before the lights go out.
final class StartGrid {
  const StartGrid({
    this.s = -12.0,
    this.columns = 2,
    this.rowGap = 6.0,
    this.columnGap = 3.5,
  });

  /// The distance along the track of the front row. Usually negative — behind
  /// the finish line, so that the first lap is a whole one.
  final double s;

  final int columns;

  /// How far back each row sits from the one in front.
  final double rowGap;

  /// How far apart the cars in a row sit.
  final double columnGap;

  /// Which car takes which slot, given what each of them qualified in.
  ///
  /// **The half of a grid that was missing.** [TrackSpline.startSlot] answers
  /// where slot three is, and every game placed car three there — so a
  /// qualifying session had nowhere to put its result and every race started
  /// in the order the cars happened to be listed in.
  ///
  /// Returns car indices, fastest first: the value at nought takes pole.
  ///
  /// **A car with no time starts behind every car with one**, in the order it
  /// was listed. That is what a session does with somebody who did not set a
  /// lap, and it is also what happens on the first race of a season, where
  /// nobody has — in which case this returns the order it was given and a game
  /// that always calls it gets the old behaviour for free.
  static List<int> orderBy(List<double?> qualifying) {
    final timed = <int>[];
    final untimed = <int>[];
    for (var i = 0; i < qualifying.length; i++) {
      (qualifying[i] == null ? untimed : timed).add(i);
    }
    timed.sort((int a, int b) => qualifying[a]!.compareTo(qualifying[b]!));
    return <int>[...timed, ...untimed];
  }
}
