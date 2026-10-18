## 1.0.0-rc.1

- **`ghostOfRun` takes the `physics` the ghost is replayed on.**
- **Breaking: `ghostOfRun` answers a `GhostNote`, not an English
  sentence.** The record's `says` is `note`, an open set of ids with what
  each carries; `GhostNote.say(languageCode)` words it in English or Russian
  at the screen.

- **Breaking: `BestRun.load` is asynchronous**, because `Storage` is.
  `BestRun.saved` is the write `finished` started.

- **One ghost for every game.** `Ghost` puts a node where a `Tape` was at a
  moment of it and hides it outside the track. It stands on a model's floor,
  turns by its facing and lifts along the track's own up, so the same class
  draws a runner on its feet and a car leaning into a banked corner.

- **A ghost is a look, not a livery.** `Ghost.look` is translucent, unlit and
  writes no depth; `Ghost.haunt` puts it on every part of a model, replacing
  the materials rather than editing them; `Ghost.build` makes a ghost of the
  game's own model, or of a fallback while that loads.

- **A shared run is raced from its tape or its poses.** `ghostOfRun` plays the
  tape again through the game's own staging when the run can be replayed, and
  reads the body's track off the run's pose record when it cannot: other
  physics, another simulation version, a level edited as it went. A run in
  another version of the level is refused, with the reason.

- **The best run, kept.** `BestRun` samples every run, keeps one only when it
  beats the record on disk (not the session's), refuses a run with almost no
  samples in it, and never throws on a document that will not read. The
  game may name its own document format.

- **Out of the demos.** The platformer's runner ghost and the racing demo's
  ghost car and lap keeper moved here; each demo keeps its own staging, its
  own model and its own file.
