## 1.0.0-rc.1

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
