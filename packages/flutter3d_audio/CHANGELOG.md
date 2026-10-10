## 1.0.0-rc.1

- **Breaking: `Issue` and `IssueSink` are not re-exported.** They are
  `flutter3d_foundation`'s, where they are declared; the plugin API is no
  longer a dependency. The audio model is still this package's, re-exported
  from `flutter3d_audio_core` by name.

- **A sound started under a pause waits for the resume.** `SoLoudBackend`
  starts a voice held while it is paused (`isPaused`), and `resume` lets it
  go with the rest; it used to play over the pause menu.
- **Breaking: `openSpeakers` throws instead of answering null.** No audio
  device is an `AudioDeviceException`, a `ResourceException`, and a game
  catches it and plays silent; nothing is printed for it any more. The
  `Future<Speakers?>` is a `Future<Speakers>`.
- **Breaking: `Speakers.backend` is an `AudioBackend`**, not the SoLoud
  class, so a test or a host with its own device hands one in the same
  shape. `Speakers` gains `pause`, `resume` and `dispose`.
- **Breaking: one issue type.** `AudioIssue` and `AudioIssueSink` are gone:
  the backend reports through `Issue` and `IssueSink`, the type
  `flutter3d_app` reports in, now from `flutter3d_plugin_api` and exported
  here. `dart fix` carries the renames.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **Breaking: `flutter3d_audio_core` is re-exported by name**, so a type added
  to it is not this package's API until it is listed.

- **The mix model is re-exported, and the speakers take a renderer.** This
  package now re-exports `AudioEmitter`, `AudioPlugin`, `MixSnapshot`,
  `DuckRule`, the bus effects, `SpatialRenderer` with `EqualPowerPanner`,
  the opt-in `MixingBackend` and `DirectionalBackend`, `PoseSource` and the
  units. `openSpeakers(spatial: ...)` hands the scene a renderer other than
  equal-power panning.

- **Breaking: `package:flutter3d_audio/testing.dart` is gone.**
  `soundTableIn` checked three demo games' sound banks against their
  source, which is repository hygiene rather than API; it lives in the
  repository's unpublished `flutter3d_demo_content` now.

- **`SoLoudBackend` pauses.** It extends `AudioBackend`, whose `open` and
  `dispose` its own now override, and `pause` and `resume` hold and release
  every voice it started.

- **Breaking: `SoundEmitter` is no longer exported**; it is `AudioEmitter`,
  the same type.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.2

**The positional half is `flutter3d_audio_core` now.** `AudioScene`, the
`Mixer` and its buses, `SoundDef`, `SoundBank`, `EngineSound`, the listener and
the attenuation curves moved there unchanged, and this package re-exports
them, so nothing a caller imports changes. What stays here is the SoLoud
backend and `Speakers`. The split lets a package that only names a bus, such
as `flutter3d_game`, leave SoLoud's native build out.

## 0.8.1

**A sound recorded below 32 kHz plays.** Every source had a low-pass open
at 16 kHz, so a wall could dull a voice by moving its cutoff. SoLoud runs a
voice's filters at the voice's own rate, the file's sample rate times its
speed, and 16 kHz is past the Nyquist frequency of a 22.05 kHz file: the
biquad's poles left the unit circle and the filter fed itself until it
overflowed. A 22.05 kHz engine loop came out as a scream and every one-shot
as silence. The backend now reads each file's sample rate from its WAV header
(taking 44.1 kHz for anything else) and holds each voice's cutoff below nine
tenths of its Nyquist frequency for the speed it is played at. A file at
44.1 kHz or above keeps its 16 kHz.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3, `flutter_soloud` ^5.1.2.

## 0.7.0

* **A number, and no code.** The one line under `lib/` that differs from 0.6.0
  is a doc comment in `soloud_backend.dart` that named `flutter3d_screens`,
  which is folded away, and names `flutter3d_app` now. This package still
  depends on no sibling, so there was no floor to move either.
* **The archive carries a skill.** `skills/flutter3d-audio-positional-mix/` is
  a `SKILL.md` for a coding agent, about `AudioScene`, moving emitters,
  attenuation, voice limiting and the silent backend for tests. A project that
  depends on this package installs it with `dart run skills@ get`. The README's
  links to the genre packages point at pub.dev where they were relative paths
  that did not resolve there.

## 0.6.0

* **No changes of its own.** Attenuation, panning, voice limiting and the
  pluggable backend are byte for byte 0.5.0's, and this package names no sibling
  in its pubspec, so nothing here had to follow anything. The workspace is
  released as a set, in the order `ARCHITECTURE.md` §16 gives, and the version
  moves with the rest so that one number names one tree.

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
