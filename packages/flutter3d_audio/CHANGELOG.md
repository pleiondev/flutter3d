## 0.5.0

**Breaking.** The issue sink is named apart and takes an object.

* **`IssueSink` is `AudioIssueSink`, taking an `AudioIssue`.** Two identical
  `typedef`s were interchangeable and cost nothing; two identical *classes* are
  not, and a program importing this package and `flutter3d_game` would have had
  to prefix one at every use. This package depends on nothing of ours so that a
  program can take the sound without the rest, and its own vocabulary is what
  that means.

## 0.4.0

* **`SoLoudBackend.open` waits out the web module.** flutter_soloud's wasm
  initialises after `main` is already running, and an `init` called in that
  gap throws — which, on the web, looked exactly like a game with no sound.
  `open` now retries for up to five seconds before rethrowing into the
  caller's fallback-to-silence. The other half of web audio is the
  application's: two script tags in `index.html` and cross-origin isolation
  headers, which the template app now carries.

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
