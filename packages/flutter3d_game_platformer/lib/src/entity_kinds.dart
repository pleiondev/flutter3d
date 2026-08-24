import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'crate.dart';
import 'kinds/block_kinds.dart';
import 'kinds/checkpoint_kind.dart';
import 'kinds/collectible_kind.dart';
import 'kinds/enemy_kind.dart';
import 'kinds/hazard_kind.dart';
import 'kinds/key_kind.dart';
import 'kinds/spring_kind.dart';
import 'kinds/surface_kinds.dart';
import 'platformer_entities.dart';

export 'kinds/block_kinds.dart';
export 'kinds/checkpoint_kind.dart';
export 'kinds/collectible_kind.dart';
export 'kinds/enemy_kind.dart';
export 'kinds/hazard_kind.dart';
export 'kinds/key_kind.dart';
export 'kinds/spring_kind.dart';
export 'kinds/surface_kinds.dart';
export 'platformer_entities.dart';

/// Everything a platformer's level may contain, format and genre together.
///
/// A game composes this itself — there is no default registry and that is the
/// point — but the eight the format ships are wanted verbatim, so listing them
/// here is the honest version of "and the usual".
EntityRegistry platformerRegistry({Dynamics? dynamics}) =>
    EntityRegistry(<EntityKind>[
      const PlayerSpawnKind(),
      const DoorKind(),
      const LiftKind(),
      const PlatformKind(),
      const ButtonKind(),
      const TriggerKind(),
      const ExitKind(),
      const CollectibleKind(),
      const HazardKind(),
      const CheckpointKind(),
      const KeyKind(),
      CrateKind(dynamics: dynamics),
      const SpringKind(),
      const OneWayKind(),
      const ConveyorKind(),
      const CrumblingKind(),
      const BreakableKind(),
      const ClimbableKind(),
      // The engine's own kind, named by this game. `LightFixtureKind` stopped
      // being abstract precisely so a genre could say `lamp` without the engine
      // knowing the word.
      const EnemyKind(),
      LightFixtureKind(
        PlatformerEntities.lamp,
        defaultBehaviour: const FlameFlicker(),
        defaultSize: Vector3(0.4, 1.6, 0.4),
      ),
    ]);

/// What is true of a platformer's level whatever it contains.
///
/// One spawn to start at, one exit to reach. The shooter says the same two and
/// they are still not the format's, which is why [LevelRule] takes them as an
/// argument: a hub level with three exits is a perfectly good level and this
/// list is a game's opinion, not a law.
List<LevelRule> platformerRules() => const <LevelRule>[
      ExactlyOne(EntityTypes.playerSpawn),
      AtLeastOne(EntityTypes.exit),
    ];
