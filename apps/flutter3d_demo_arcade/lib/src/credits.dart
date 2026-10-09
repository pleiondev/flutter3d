/// What this game ships that somebody else made.
///
/// The class is `flutter3d_game`'s — see `Credit` there — and the ledger that
/// asks what is owed is `flutter3d_game_ui/screens.dart`'. What is here is the list,
/// which is this game's alone. This game has no credits screen; every model
/// is CC0, so nothing is owed on one. The list exists anyway because
/// `credits_test.dart` reads `assets/models`, and the next model dropped in
/// there is one somebody found somewhere.
library;

import 'package:flutter3d_game_ui/screens.dart';

/// Everything the game ships that somebody else made: three craft from
/// Kenney's Space Kit. The yard, its props and every colour are this
/// repository's own. Nothing is owed: CC0 owes nobody a line on a screen.
const CreditLedger credits = CreditLedger(<Credit>[
  Credit(
    file: 'models/craft_speederD.glb',
    work: 'Space Kit, craft_speederD',
    author: 'Kenney',
    source: 'https://kenney.nl/assets/space-kit',
    license: 'CC0 1.0',
    licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
  ),
  Credit(
    file: 'models/craft_miner.glb',
    work: 'Space Kit, craft_miner',
    author: 'Kenney',
    source: 'https://kenney.nl/assets/space-kit',
    license: 'CC0 1.0',
    licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
  ),
  Credit(
    file: 'models/craft_racer.glb',
    work: 'Space Kit, craft_racer',
    author: 'Kenney',
    source: 'https://kenney.nl/assets/space-kit',
    license: 'CC0 1.0',
    licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
  ),
]);
