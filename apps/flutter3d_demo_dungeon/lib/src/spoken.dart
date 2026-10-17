import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_ui/access.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// What the crypt says to a screen reader, and when (B6.23).
///
/// **The moments the screen says nothing about.** A hurt is a red flash and
/// a shake, a secret is a chime, and a death is the screen going dark: all
/// three are told to the eyes and the ears, and none to a player who reads
/// the game through VoiceOver or TalkBack. The rest — a locked door, a key —
/// is already a sentence on the screen, and a reader already reads that.
///
/// The shooter forwards these to the bus; [SpokenEvents] says them on the
/// frame channel and touches nothing, so the game is the same for a player
/// with no reader on.
final List<Spoken<BusEvent>> cryptSpoken = <Spoken<BusEvent>>[
  Spoken<PlayerHurt>((_) => 'Hurt.'),
  Spoken<SecretFound>((_) => 'You found a secret.'),
  Spoken<PlayerDied>((_) => 'You died.'),
];
