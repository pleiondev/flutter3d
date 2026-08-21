/// The collision bits this genre gives its own bodies.
///
/// Declared here rather than in the engine for the same reason a platformer
/// declares "you may pass upwards through this" for itself: `CollisionLayers`
/// names `world`, `player`, `monster`, `pickup` and `trigger`, which are facts
/// about any game with bodies in it, and "this is a car" is not one of them.
abstract final class RacingLayers {
  /// A car: to other cars, and to the volumes lying on the road.
  ///
  /// Bit seven. The engine uses nought to five and the platformer took six —
  /// not because a racing game and a platformer will ever share a world, but
  /// because two packages quietly holding different opinions about what bit six
  /// means is the kind of thing that is found by a car falling through a floor
  /// in the one build where both are linked.
  static const int vehicle = 1 << 7;

  /// Volumes that sit on the road surface and report being driven through:
  /// boost pads, item boxes, the plane across the finish line.
  ///
  /// Separate from the engine's `trigger` bit so that a car can be made to
  /// notice the track's own furniture without also noticing every door plate
  /// inherited from a level.
  static const int roadTrigger = 1 << 8;
}
