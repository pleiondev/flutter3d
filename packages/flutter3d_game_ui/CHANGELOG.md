## 1.0.0-rc.1

- **Every widget around a game is here.** The touch controls, the settings
  panel and its sections, the privacy questions, the automap, the credits,
  the loss screen, `GameUiTheme` and `Flutter3dGameLocalizations` come from
  `flutter3d_game`. Two new libraries hold what had no home here:
  `settings.dart` (the panel) and `theme.dart` (the colours and the words);
  the rest joined `touch.dart`, `hud.dart` and `screens.dart`.
- **Breaking: one widget per job.** `TouchCluster` is `TouchControls`, which
  gained its numbered slots and its corner switch (`toggle:` is `corner:`);
  a game that hands neither gets the stick and row it had. `Pedal` is
  `TouchButton.pedal`, the same held button in the shape of a pedal. The
  credits are one file: `Credit`, `CreditsSection`, `CreditLedger` and
  `LicenseRecord` together. `MiniMap` and `AutomapView` stay two widgets,
  because a course's outline and the cells a player has walked are two
  different maps.

- **`Portable` comes from `flutter3d_foundation`**, so the lens no longer
  needs the physics package.

- **Breaking: `ReelShot.film(clearColor:)` is `clearColorSrgb:`**, the same
  sRGB `Vector4`, named as `RenderView.clearColorSrgb` is.
- **Breaking: `RoleRings` reads the settings through a function**,
  `RoleRings(roles, () => controller.settings)`, since `GameSettings` is a
  value and a change makes a new one; `RolesApart.apply` returns the
  settings with the moved roles written in rather than editing them.
- **Breaking: an ending's number is `EndingTally`**, not `Tally`, which is
  the simulation's counter in `flutter3d_sim`; a game importing both no
  longer hides one.
- **`MiniMap`, `Pedal` and `SteeringBand` read `GameUiTheme`.**
  `MiniMap.playerColor` and `othersColor` are nullable and default to the
  theme's `miniMapPlayer` and `miniMapOthers`; its line and box are
  `miniMapTrack` and `miniMapBackdrop`, and `MiniMapPainter.trackColor`
  is new. The pedals and the steering band take the `touch*` roles.
- **New: one package for what was six.** `flutter3d_addon_hud`,
  `flutter3d_addon_touch`, `flutter3d_addon_access`, `flutter3d_addon_screens`,
  `flutter3d_addon_photo_mode`, `flutter3d_addon_capture` are libraries of this
  package now: `hud.dart`, `touch.dart`, `access.dart`, `screens.dart`,
  `photo_mode.dart`, `capture.dart`, each with the API its package had, and
  `flutter3d_game_ui.dart` exports them all. `dart run flutter3d_build:migrate`
  moves a project's dependencies and imports; the packages' own histories are in
  `doc/changelogs/`.

### `hud.dart`, from `flutter3d_addon_hud` 1.0.0-rc.1

- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kBeaconGlow` is `beaconGlow`. The values are
  the same; `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `accentColour` is `accentColor`, `colour` is `color`,
  `metresPerSecond` is `metersPerSecond`, `othersColour` is `othersColor`,
  `playerColour` is `playerColor`. Only the Dart names changed: a file
  keeps the keys it was written with, and `dart fix` carries the renames.
- **Breaking: the HUD's colours are the theme's.** `HudLine.defaultAccent`
  and `HudLine.labelWidth` are gone; `GameUiTheme` (a `ThemeExtension` in
  `flutter3d_game`) holds the accent, the label colour, the label column's
  width and the panel's background, with the old values as its fallback.
  `HudLine.accentColor` is nullable and overrides the theme's accent.
  `Speedometer` says its unit in the player's language.

- **The HUD pieces the demos each drew for themselves.** `HudPanel` and
  `HudLine` from racing, `HudTally` and `HudBanner` from the platformer and
  strategy (one widget each now, with a `HudTallyStyle` for the ink and the
  sizes that differed), and the `Speedometer`, which takes metres a second
  rather than a race's readout.

- **The minimap draws any course.** `MiniMap` takes an outline and a list of
  markers, the first the player's, and fits the course to its box.
  `MiniMapPainter.place` says where a point lands, for a HUD that lays out
  its own frame.

- **A hint is a rule.** `MomentHint` is a sentence and the moment it is
  true; `MomentHints` says each of several once, one a step, until
  `forget`. The dungeon's first-shot hint is one.

- **An objective that can be found in the dark.** `lightBeacon` raises what
  already glows on an object to `beaconGlow`, normalised so a second call
  changes nothing.

- **The stereo HUD panel is part of this package.** `StereoHudPanel` builds
  a HUD once and redraws it from a `ValueListenable`, for a surface in front
  of a stereo camera. Too small for a package of its own.

### `touch.dart`, from `flutter3d_addon_touch` 1.0.0-rc.1

- **Breaking: `TouchDrive`'s labels come from the player's language.**
  `throttleLabel`, `brakeLabel` and `handbrakeLabel` are nullable, null for
  `Flutter3dGameLocalizations`'s words; a game's own still override.

- **The controls bind to actions of every kind.** `SteeringBand.axis` and
  `TouchDrive.steer` write the wheel as one `AxisAction` beside the two
  magnitudes, and `TouchCluster.stickAction` puts the stick on any
  `DualAxisAction`.

- **Breaking: `SteeringBand`, `TouchCluster`, `TouchDrive`** as the snapshot
  counts it: a new optional field on each. No caller changes.

- **An analogue axis under a thumb.** `SteeringBand` writes how far left or
  right of centre the thumb is as two actions' magnitudes, sets the idle side
  to nought so a key held on the same machine cannot steer against it, and
  withdraws both on release so the keyboard has them back.

- **A pedal is a held button with a name.** `Pedal` presses its action while
  one finger is on it, lets go on lift, cancel or unmount, and says its label
  to a screen reader.

- **Two layouts, each for a kind of game.** `TouchDrive` is a band and pedals
  with one button in the far corner, never wanted mid-corner. `TouchCluster`
  is a stick, a cluster of buttons, numbered slots and a switch, placed by how
  often each is wanted and how bad it is to press by mistake.

- **Out of the demos.** The racing demo's band, pedals and layout, and the
  dungeon demo's cluster, moved here; each demo keeps only which of its
  actions go where.

### `access.dart`, from `flutter3d_addon_access` 1.0.0-rc.1

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `GameConfig` is `GameSettings`. Every settings class is `final`
  with a `const` constructor and a `copyWith` over every field; a nullable
  field is reset with `copyWith(clearX: true)`. `dart fix` carries the
  renames.
- **Breaking: `announceTo` and `announceToImplicitView` speak in the
  platform's direction.** Their `direction` defaulted to left to right, so a
  sentence in Arabic or Hebrew was read in the wrong order; null now asks
  the platform's language (`platformTextDirection`), and `announceIn(context)`
  speaks on the context's view in its ambient `Directionality`. A caller that
  passed a direction is unchanged.

- **Rings in the colour a player chose.** `RoleRings` gives the
  high-contrast look's ring colour for a role, read from the settings on
  every call, so a change in the panel is the ring's colour on the next
  frame. The dungeon's rings are built on it; which things are worth a ring
  stays the game's question.

- **Roles moved apart for the player's eyes.** `RolesApart.choicesFor` says
  which palette colour each colliding role should take for the deficiency
  the player named, and `apply` writes it into the settings. With none named
  it moves nothing.

- **What happens, said to a screen reader.** `SpokenEvents` is a view plugin
  on the bus's frame channel: a table of event types and sentences, said as
  announcements through Flutter's semantics. The same sentence waits a number
  of steps before it is said again; the limit is counted in steps, so it
  needs no clock. Nothing is written back, so the game is the same with it
  installed.

### `screens.dart`, from `flutter3d_addon_screens` 1.0.0-rc.1

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

### `photo_mode.dart`, from `flutter3d_addon_photo_mode` 1.0.0-rc.1

- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `PhotoMode.active` is `isActive`; `PhotoMode.manualExposure` is
  `usesManualExposure`; `PhotoMode.busy` is `isBusy`. `dart fix` carries the
  renames.
- **Breaking: the photo bar's words come from `Flutter3dGameLocalizations`.**
  `PhotoMode.walkingKeys` and `PhotoMode.exposureKeys` are gone, and
  `keysHint` is nullable: null shows the walking keys in the player's
  language, and a game with other keys still passes its own line. The
  package depends on `flutter3d_game` for them.

- **One photo mode for every game.** `PhotoMode` and `PhotoBar` hold the
  engine's `PhotoCamera` and `PhotoFilter` together and own the filter,
  tilt, zoom and capture keys while it is open. Four demos had their own
  copy; they build this one now.

- **The game says how its keys fly the camera.** `ActionPhotoControls` reads
  the game's own actions and mouse, `KeyPhotoControls` the keyboard as held,
  with the arrows turning it if the game asks. Either is read, never
  stepped: the loop is paused and nothing of the flying reaches the run.

- **Its lens, not a default one.** The picture is taken through the lens the
  game hands in, zoomed, so a far plane or a chase camera's widened view
  survives the moment photo mode opens.

- **A game whose keys would stick says so.** `takesEveryKey` keeps every key
  and its release while photo mode is open, so a throttle held when the
  picture was framed is not still held when the run comes back.

- **Aperture, shutter and ISO** (`B6.22`). `PhotoMode.exposure` is a
  `PhysicalCamera` the keys 1 to 6 move a third of a stop at a time, and 0
  hands the exposure back to the game; `enter(camera:)` starts the dials at
  the game's own. `PhotoMode.settings` applies it once a dial is turned —
  the physical camera on, auto exposure off — and, with the game's depth of
  field on, focuses at the camera's aperture. `PhotoBar` shows the setting
  and the keys.

### `capture.dart`, from `flutter3d_addon_capture` 1.0.0-rc.1

- **Breaking: `reelOut` is gone; `Reel.out` is the game's.** The folder was
  a constant read from `--dart-define=REEL_OUT`, so every game on the engine
  answered to one variable. `Reel.out` defaults to `reel`, and an entry point
  that wants the define reads it itself.

- **Breaking: `ShareStrip`'s words come from `Flutter3dGameLocalizations`.**
  `shareLabel`, `codeHint` and `openLabel` are nullable; null says them in
  the player's language (English and Russian ship), and a game's own words
  still override. The package depends on `flutter3d_game` for them.

- **A game filmed frame by frame.** `Reel` and `ReelShot` step nothing
  themselves: a game places its camera and steps its world `reelFrameStep`
  a frame, and `film` draws the frame at full size and writes it as
  `<out>/<shot>/frame_NNNN.png`. Five demos filmed the 0.9 reel with their
  own PNG writers and folder shelves; they film through this now.

- **One tile unless asked.** A frame is drawn whole by default, so a pass
  that reads its neighbours is not cut at a tile's edge; a reel that wants
  photo mode's tiles says so.

- **A hole stops the reel.** A frame that could not be written throws with
  the shelf's sentence, rather than leaving a numbered sequence with one
  missing for an encoder to stumble on.

- **Sharing in a sentence.** `ShareStrip` files the run just played and
  says its code, and opens a friend's; every answer is a sentence, because
  a share that failed silently is a code nobody can open. Its words are the
  game's.
