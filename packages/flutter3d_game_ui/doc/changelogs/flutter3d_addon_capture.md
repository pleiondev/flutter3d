## 1.0.0-rc.1

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
