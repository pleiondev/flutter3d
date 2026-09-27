part of 'arcade_game.dart';

/// One level of the yard: its bots, how they behave, and how many hits
/// the ship may take before the level is lost.
///
/// The difficulty climbs along every axis a bot has. More of them, faster,
/// and from the second level on some hunt the ship instead of keeping to
/// their beat. From the third they also sidestep a ship flying straight at
/// them, which a ram needs, so the player has to cut them off rather than
/// chase them. The ship stays faster than any bot, at
/// [ArcadeGame.shipSpeed], or a hunter could never be rammed at all.
final class ArcadeLevel {
  const ArcadeLevel({
    required this.bots,
    required this.botSpeed,
    required this.maxHits,
    this.hunters = 0,
    this.chaseRadius = 0.0,
    this.dodgeRadius = 0.0,
  });

  /// How many bots the level starts with, one to a lane.
  final int bots;

  /// Metres per second a bot walks at.
  final double botSpeed;

  /// Hits the ship can take before the level is lost.
  final int maxHits;

  /// How many of the bots hunt the ship when it comes within
  /// [chaseRadius]. The rest keep to their beat.
  final int hunters;

  /// How near the ship has to come for a hunter to give chase, in metres.
  final double chaseRadius;

  /// How near a ship flying at a bot has to be for the bot to sidestep,
  /// in metres. Zero on the levels where bots do not dodge.
  final double dodgeRadius;
}

/// Every level, in the order they are played.
const List<ArcadeLevel> arcadeLevels = <ArcadeLevel>[
  ArcadeLevel(bots: 3, botSpeed: 2.6, maxHits: 3),
  ArcadeLevel(bots: 5, botSpeed: 3.2, maxHits: 3, hunters: 1, chaseRadius: 5.0),
  ArcadeLevel(
    bots: 6,
    botSpeed: 3.6,
    maxHits: 2,
    hunters: 2,
    chaseRadius: 6.0,
    dodgeRadius: 3.0,
  ),
  ArcadeLevel(
    bots: 8,
    botSpeed: 4.2,
    maxHits: 2,
    hunters: 4,
    chaseRadius: 7.0,
    dodgeRadius: 3.5,
  ),
];
