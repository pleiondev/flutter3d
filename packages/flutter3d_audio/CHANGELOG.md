## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* Mix buses opened like `GameAction`, spent when a voice is issued rather than
  when it is chosen.
* One list of sounds shared by the games that had each written their own.

## 0.1.0

* Positional audio: attenuation, panning and voice limiting.
* A pluggable backend, so a build with no audio device plays the game in
  silence rather than refusing to start.
