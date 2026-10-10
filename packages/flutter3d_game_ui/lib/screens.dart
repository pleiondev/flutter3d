/// The screens a game shows around its play: the title, the credits, the
/// ending and its scoreboard, the loss screen, a cutscene's overlay, and the
/// lens the play is seen through.
///
/// * [TitleSheet], the card a game opens on: its name, the controls, the
///   credits owed and how to begin.
/// * [Credit], [CreditsSection], [CreditLedger] and [LicenseRecord]: what a
///   game ships that somebody else made, shown where the licence asks and
///   held to the `LICENSES.md` beside its models.
/// * [EndingSheet], [EndingTally] and [TallyView]: how a game ends, and
///   [TapToRestart] for when it ends badly.
/// * [CutsceneOverlay]: a sequence's fade, subtitle and skip.
/// * [Lens]: one base projection, widened for speed and opened for a
///   narrow screen.
///
/// What each game says on these screens stays the game's: the lines about its
/// keys, the tallies it is played for. This package draws them.
library;

export 'src/screens/credits.dart';
export 'src/screens/cutscene_overlay.dart';
export 'src/screens/ending_sheet.dart';
export 'src/screens/lens.dart';
export 'src/screens/tap_to_restart.dart';
export 'src/screens/title_sheet.dart';
