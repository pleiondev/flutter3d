/// What this game ships that somebody else made.
///
/// The class and the screen are `flutter3d_game`'s — see `Credit` there. What
/// is here is the list, which is this game's alone.
///
/// **This game has no credits screen wired up**, unlike the shooter, the
/// platformer and the racing game — it has no settings screen at all yet for
/// one to sit in. Every model and texture here is CC0, so nothing is currently
/// owed on a screen the game does not have; this file and its test exist
/// anyway, for the reason the dungeon's own credits file gives: the next model
/// dropped into `assets/models` is one somebody found somewhere, and the check
/// that matters reads the directory, not a list written beside it.
///
/// The textures are recorded in `assets/CREDITS.md` with the models; the list
/// here is the models alone, because that is the directory the test reads.
library;

import 'package:flutter3d_game/flutter3d_game.dart'; // Credit

/// Everything the game ships that somebody else made.
///
/// The fog tiles, the water and every colour in `bridge.dart`'s materials are
/// this repository's own; the castles, the crowd, the trees and the rocks are
/// Kenney's, taken apart and put back together in `kit.dart`.
abstract final class Credits {
  static final List<Credit> models = <Credit>[
    for (final String piece in _castle)
      _kenney('castle-$piece.glb', 'Castle Kit, $piece', 'castle-kit'),
    _kenney('arena-soldier.glb', 'Mini Arena, character-soldier', 'mini-arena'),
    _kenney('arena-spear.glb', 'Mini Arena, weapon-spear', 'mini-arena'),
    _kenney('blocky-p.glb', 'Blocky Characters, character P', _blocky),
    _kenney('blocky-k.glb', 'Blocky Characters, character K', _blocky),
    for (final String piece in _nature)
      _kenney('nature-$piece.glb', 'Nature Kit, $piece', 'nature-kit'),
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

const String _blocky = 'blocky-characters';

const List<String> _castle = <String>[
  'tower-hexagon-base',
  'tower-hexagon-mid',
  'tower-hexagon-roof',
  'tower-square-base',
  'tower-square-mid-windows',
  'tower-square-top-roof-high',
  'wall',
  'flag',
  'flag-banner-long',
  'siege-ram',
];

const List<String> _nature = <String>[
  'tree_pineTallA_detailed',
  'tree_pineRoundC',
  'tree_oak',
  'tree_default',
  'tree_detailed',
  'stone_tallA',
  'stone_largeA',
  'stone_smallA',
];

/// A Kenney model, CC0, changed by `tool/prepare_models.py`: every one has
/// its texture reference taken out, and the characters lose their clips.
Credit _kenney(String file, String work, String pack) => Credit(
  file: 'models/$file',
  work: work,
  author: 'Kenney',
  source: 'https://kenney.nl/assets/$pack',
  licence: 'CC0 1.0',
  licenceUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
  modified: true,
);
