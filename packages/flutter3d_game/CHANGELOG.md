## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.2

**Two triggers on one action answer with the harder press.** The value was
whichever trigger `PadInput` read last, so 1.0 on the left and 0.2 on the right
gave a throttle of 0.2. Letting one go also withdrew the value the other had
just written, and for that frame the action fell back to its held 1.0. The
action now takes the largest magnitude among the controls pressing it, and is
withdrawn only when none is.

## 0.7.1

**A restart chosen while the next level was loading stays a restart.**
`RunSession.advance` loaded the next level on top of it and saved that.
`TouchButton` releases the action it pressed, not whatever it holds at
pointer-up, so a relaid-out button list no longer leaves an action held for
good. `PadInput` tracks analogue state per control, so two triggers bound to
one action stop cancelling each other.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3, `vm_service` ^15.3.0.

## 0.7.0

**Breaking.** Everything a game adds to an application is here, and
`flutter3d_sim` is no longer re-exported. `flutter3d_session`,
`flutter3d_screens` and `flutter3d_bridge` are marked `discontinued` on pub.dev
the day this is published, the last two with this package as their
replacement; `doc/boundary-0.7.0.md` has the whole list.

* From `flutter3d_session`: `RunSession`, `RunTimeline` and its service
  extensions, the demo timeline and the bug-report tape, the settings overlay
  and panel, rebinding, `SaveFile`/`SettingsFile`/`DemoFile`, volumes, credits,
  `AutomapView`, `DragLook`, `TapToRestart`, `clockText` and
  `configureForTouch`. `package:flutter3d_game/testing.dart` holds
  `creditGaps`. At 0.6.0 everything in that list after the bug-report tape was
  `flutter3d_screens`, which was folded into the session first and followed it
  here.
* From `flutter3d_bridge`: `ActorVisuals`, `FixtureVisuals` and
  `SoundOcclusion`. Loading a level into a scene, `LevelLoader` and what it
  stands on, went to `flutter3d_app`.
* To `flutter3d_app`: `Issue`, `IssueSink` and `IssueLog`, which storage
  reports through. This package depends on `flutter3d_app`, and a file that
  used one of the three imports it.
* **Breaking. A file that steps a simulation imports `flutter3d_sim` by
  name.** The line `export 'package:flutter3d_sim/flutter3d_sim.dart'` is gone
  from this library, so `Level`, `GameLoop`, `InputState` and every other
  simulation type stop arriving through it. `flutter3d_sim` is still a
  dependency here at `^0.7.0`; a package that uses its types adds it to its own
  pubspec.
* **`RunTimeline`: a running game paused, stepped and rewound from outside.**
  New since 0.6.0. `pause`, `resume`, `stepOnce`, `preview(secondsAgo)`,
  `releaseAt` and `releaseAtStep(step)` over a `RewindBuffer`, with each action
  kept as a sealed `TimelineCommand`: `TimelinePaused`, `TimelineResumed`,
  `TimelineStepped` or `TimelineBranched`. `registerTimelineExtensions` puts a
  timeline on the VM service as `ext.flutter3d.timeline.pause`, `resume`,
  `stepOnce`, `preview`, `releaseAtStep`, `history` and `status`, with
  `frameTimes` and `bugReport` when the caller supplies them. That is the
  channel a tool attached to a running game already has.
  `rewindBufferFromDemo` replays a whole `Demo` once into a buffer that reaches
  every step of it, and `bugReportTape` answers the state and the tape of the
  last seconds a `RewindBuffer` kept, or null before its first keyframe.
* **`LevelWalk`, `OpenKind` and `openRegistryFor`**, out of the game example's
  `main.dart`: a body that walks a level, turns where it is dragged and carries
  a camera at eye height, and a registry that accepts every type a level names
  before a game has taught it any.
* **A level names a model by either kind of path.** `FixtureVisuals` and
  `ActorVisuals` load through the engine's `loadModelByPath`: a model a level
  names under `assets_src/` is read from the `.f3d` the build hook converted
  it into, and any other path from the bundle exactly as before, so a project
  that has run `dart run flutter3d_build:init` and one that has not both load
  through the same two classes.
* **What it depends on.** `flutter3d_app`, `flutter3d`, `flutter3d_sim`,
  `flutter3d_audio` and `flutter3d_particles` at `^0.7.0`, `flutter_bloc` for
  the settings cubit, and `pad_input` and `pointer_lock` at `^0.4.0`. None of
  them is re-exported. The input devices, the bindings, the touch controls and
  `GameConfig` are what 0.6.0 had.

## 0.6.0

* **A floor, and no code — the same shape as 0.5.1 and for the same reason.**
  The input devices, the fixed step and the interpolation are byte for byte
  0.5.1's. What moved is the promise about the package this one re-exports
  whole: `flutter3d_sim` is required at `^0.6.0`, so a caller reaching a
  simulation type through this name reaches a version that has it rather than
  whatever the resolver picked.
* `pad_input` and `pointer_lock` stay at `^0.4.0`. They are on a line of their
  own, their 0.4.1 is a documentation patch, and a floor that demanded it would
  be claiming this package needs something it does not.

## 0.5.1

* **A floor, and no code.** Nothing in this package changed; what changed is
  what it promises about the package it re-exports. `flutter3d_sim` is now
  required at 0.5.2 or above, because that is where `Heightfield` arrived and,
  through it, `flutter3d_physics` 0.5.1 with the collision shape a body stands
  on. A caller reaching those names through this one was reaching whatever the
  resolver happened to pick, which for a `^0.5.0` floor could be a version
  without either — and the symptom is a compile error in somebody else's
  package.

## 0.5.0

**Breaking.** A stick use carries what it does, and an issue is an object.

* **`PadStickUse` is open, and its interpreter opened with it.** It was an enum
  switched over in one method, so a game could not say its stick leans the
  ship. A use now *is* what it does with a deflection — `route` against a
  narrow `PadStickTarget`, `letGo` for whatever it writes — and the three built
  in are instances rather than cases. There is no switch left to break.
* **`IssueSink` takes an `Issue`.** A bare string could not grow a severity or
  a source without breaking every sink anybody had written.

## 0.4.1

* **The simulation moved out, and nothing that imports this package changes a
  line.** The fixed step, the entity store, the level format, saves, demos, the
  rewind buffer, actors, navigation and the maths are `flutter3d_sim` now — a
  plain Dart package with no Flutter in it, so a server can replay a run
  through the same simulation the player ran. This package keeps the eight
  files that reached Flutter — the touch stick and button, keyboard and mouse,
  the gamepad route, the `MediaQuery` read and the diagnostics sink — and
  re-exports `flutter3d_sim` and `flutter3d_physics` whole.

## 0.4.0

* **A touch control lets go when it leaves.** The button and the stick press
  into a shared `InputState`, and unmounting while pressed is a normal path —
  settings opening over the control, a level transition. Each now releases its
  held action or zeroes its axis in `dispose` instead of leaving the runner
  jumping into the next screen.

## 0.3.0

* **`Playing` no longer asks `kIsWeb`,** and both answers it used to give about a
  browser were wrong. Capture is asked of `pointer_lock`, which can now hold a
  pointer in a desktop browser and says so — and which says no on Windows and
  Linux, where the old platform list claimed a capture that does not exist and
  then turned off drag-look, leaving a camera that could not move at all. Touch
  is asked of `defaultTargetPlatform`, which reports a mobile browser as
  `android` or `iOS`, so a phone opening a web build finally gets the on-screen
  controls it has always had natively.
* `InputTape` records a run as transitions plus axes, one entry per fixed step,
  and replays it exactly. A tape of intents, not of poses.
* `StepSystems`: a game adds a rule to a genre's step without forking it.
  Phases are named by the genre, announced unconditionally, and run in a
  defined order — never in whatever order a hash map returns.
* `InputState` exposes this step's presses, releases and analogue readings,
  which is what a recorder needs and cannot ask for by name.

## 0.2.0

* An ECS whose every component serialises, and one snapshot mechanism serving
  the save, the network packet and the determinism test.
* Actors with a flow field to walk it, mechanisms composed through signals, and
  movers that carry what stands on them.
* A pad and a touch layer that arrive as the same actions a key does, and
  `GameAction` opened from an enum to a value class so a genre can invent its
  own.
* `WorldStep`: the order the world is stepped in, as named phases the game
  calls, because two genres want their actors on different sides of the index.

## 0.1.0

* A fixed timestep with an accumulator that reports the steps it had to drop,
  and interpolation at draw time.
* Device-independent input: actions, bindings, and a keyboard — all arriving as
  the same thing.
* Levels as documents — brushes, entities, lights, materials — with a validator
  that reports a coordinate rather than "the file is broken".
