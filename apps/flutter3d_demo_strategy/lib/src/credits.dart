/// What this game ships that somebody else made.
///
/// The class and the screen are `flutter3d_game`'s — see `Credit` there. What
/// is here is the list, which is this game's alone.
///
/// **This game has no credits screen wired up**, unlike the shooter, the
/// platformer and the racing game — it has no settings screen at all yet for
/// one to sit in. Both models here are CC0, so nothing is currently owed on
/// a screen the game does not have; this file and its test exist anyway, for
/// the reason the dungeon's own credits file gives: the next model dropped
/// into `assets/models` is one somebody found somewhere, and the check that
/// matters reads the directory, not a list written beside it.
library;

import 'package:flutter3d_game/flutter3d_game.dart'; // Credit

/// Everything the game ships that somebody else made.
///
/// The ground, the fog tiles and every colour in `bridge.dart`'s materials
/// are this repository's own; only the crowd and the halls are somebody
/// else's work.
abstract final class Credits {
  static const List<Credit> models = <Credit>[
    Credit(
      file: 'models/worker.glb',
      work: 'Blocky Characters, character A',
      author: 'Kenney',
      source: 'https://kenney.nl/assets/blocky-characters',
      licence: 'CC0 1.0',
      licenceUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
      modified: true,
    ),
    Credit(
      file: 'models/hall.glb',
      work: 'Castle Kit, tower-square',
      author: 'Kenney',
      source: 'https://kenney.nl/assets/castle-kit',
      licence: 'CC0 1.0',
      licenceUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
      modified: true,
    ),
  ];

  /// The ones whose licence makes naming the author a condition.
  ///
  /// **Empty here**, unlike the shooter, the platformer and the racing game:
  /// CC0 owes nobody a line on a screen. Kept for the same reason a genre
  /// with no CC BY asset still keeps this getter — a model added later that
  /// does owe one should not need a second place taught to look for it.
  static List<Credit> get owed =>
      models.where((Credit c) => c.owesAttribution).toList();

  /// The ones that cannot be credited because nobody knows who made them.
  ///
  /// While this has anything in it the game cannot be released, whatever the
  /// screen says. `credits_test.dart` reads the asset directory rather than
  /// this list, so an untraced file arriving is a red test rather than an
  /// entry somebody forgets to add.
  static List<Credit> get untraced =>
      models.where((Credit c) => !c.traced).toList();
}
