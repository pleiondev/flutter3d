part of 'arcade_game.dart';

/// One level of the yard: its drones, how they behave, and how many hits
/// the ship may take before the level is lost.
///
/// The difficulty climbs along every axis a drone has. More of them, faster,
/// and from the second level on some hunt the ship instead of keeping to
/// their beat. From the third they also sidestep a ship flying straight at
/// them, which a ram needs, so the player has to cut them off rather than
/// chase them. The ship stays faster than any drone, at
/// [ArcadeGame.shipSpeed], or a hunter could never be rammed at all.
final class ArcadeLevel {
  const ArcadeLevel({
    required this.drones,
    required this.droneSpeed,
    required this.maxHits,
    this.hunters = 0,
    this.chaseRadius = 0.0,
    this.dodgeRadius = 0.0,
  });

  /// How many drones the level starts with, one to a lane.
  final int drones;

  /// Metres per second a drone walks at.
  final double droneSpeed;

  /// Hits the ship can take before the level is lost.
  final int maxHits;

  /// How many of the drones hunt the ship when it comes within
  /// [chaseRadius]. The rest keep to their beat.
  final int hunters;

  /// How near the ship has to come for a hunter to give chase, in metres.
  final double chaseRadius;

  /// How near a ship flying at a drone has to be for the drone to sidestep,
  /// in metres. Zero on the levels where drones do not dodge.
  final double dodgeRadius;
}

/// Every level, in the order they are played.
const List<ArcadeLevel> arcadeLevels = <ArcadeLevel>[
  ArcadeLevel(drones: 3, droneSpeed: 2.6, maxHits: 3),
  ArcadeLevel(
    drones: 5,
    droneSpeed: 3.2,
    maxHits: 3,
    hunters: 1,
    chaseRadius: 5.0,
  ),
  ArcadeLevel(
    drones: 6,
    droneSpeed: 3.6,
    maxHits: 2,
    hunters: 2,
    chaseRadius: 6.0,
    dodgeRadius: 3.0,
  ),
  ArcadeLevel(
    drones: 8,
    droneSpeed: 4.2,
    maxHits: 2,
    hunters: 4,
    chaseRadius: 7.0,
    dodgeRadius: 3.5,
  ),
];
