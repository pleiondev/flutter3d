import 'package:flutter3d/flutter3d.dart';

import 'accommodations.dart';
import 'game_config.dart';

/// Whether [config] asks for the high-contrast look, with [system]'s answer
/// as the fallback.
///
/// **The system answer is a default and never an override**, which is the
/// rule [Accommodations] is built on: a player who has asked their phone for
/// more contrast gets the look without finding a switch, and a player who
/// then turns the switch off in this game's panel gets it off, because the
/// switch is the more recent and the more specific thing they said.
bool wantsHighContrast(GameSettings config, Accommodations system) =>
    config.chosenValueOf(GameSettingKeys.highContrast) ?? system.highContrast;

/// The look a frame is drawn with for this player: [base] switched on or off
/// by [wantsHighContrast].
///
/// Only `enabled` is the player's. The rest of [base] is the game's — how
/// wide its rings are, how much colour it leaves in a world of its palette —
/// and the engine's defaults are a reasonable start for a game that has not
/// looked.
HighContrastSettings highContrastOf(
  GameSettings config,
  Accommodations system, [
  HighContrastSettings base = const HighContrastSettings(),
]) => base.copyWith(enabled: wantsHighContrast(config, system));
