## 1.0.0-rc.1

- **Breaking: a field of view is `fovY`**, in radians, wherever this package
  names one (docs/CONTRACTS.md).
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `colour` is `color`, `licence` is `license`, `LicenceEntry` is
  `LicenseEntry`, `LicenceRecord` is `LicenseRecord`, `licenceUrl` is
  `licenseUrl`. Only the Dart names changed: a file keeps the keys it was
  written with, and `dart fix` carries the renames.
- **Breaking: one home for `Credit`.** The barrel re-exported `Credit` and
  `CreditsSection` from `flutter3d_game`, so the type had two libraries to be
  imported from; it no longer does. Import `flutter3d_game`.

- **Breaking: `EndingSheet.creditsHeading` comes from the player's
  language.** It is nullable, null for
  `Flutter3dGameLocalizations.artInThisGame`. `creditsFootnote` on
  `EndingSheet` and `TitleSheet` is the game's own line under the credits,
  since `CreditsSection` no longer has a default one.

- **The screens around play, out of the games.** `TitleSheet`, `EndingSheet`
  with `Tally` and `TallyView`, and `CutsceneOverlay` were laid out by hand in
  the platformer, the dungeon and racing, the same way each time. A game now
  hands them its words and its numbers and keeps nothing of the layout.

- **Credits held to the licence record.** `CreditLedger` is the list a game
  ships with `owed` and `untraced`, which five games wrote out identically.
  `LicenseRecord` reads the `LICENSES.md` beside the models, in both shapes
  the games keep it in, and `disagreementsWith` names every file the record
  does not mention and every licence or author the two state differently.
  The games' tests used to search the record's text for a file name.

- **A lens that keeps the view on a narrow screen.** `Lens` is the
  platformer's single base projection with `widened`, and adds `at`: below
  its `designAspect` the vertical field of view opens so the horizontal one
  stays what it was designed to be.
