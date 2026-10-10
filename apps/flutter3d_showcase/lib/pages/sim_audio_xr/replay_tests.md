# Replays as tests

A replay that is checked against digests already tells you when two runs of
one tape part. `testReplay` in `flutter3d_testing` turns that into a test a
game keeps in its own repository. You record a run once and keep the
`.f3drun` next to the tests. From then on, every change to the simulation is
played against it on the software backend, so CI needs no GPU. A change that
moves the game fails at the first checkpoint where it shows.

In the platformer's tests it is one call:

```dart
testReplay(
  'test/tapes/ascent.f3drun',
  start: _Ascent.open,
  goldensAt: <int>[120, 600],
);
```

`start` builds the game as a `ReplaySubject`: the `EngineLoop` it is
stepped in, the genre whose run the tape recorded, `frame` and the level's
hash. The tape's start goes back through `loop.rewindTo`, each step is a
`loop.runSteps(1)`, and a checkpoint is the digest of the genre's part of
`loop.capture()`. `digestAt` is
left out there, so every checkpoint the tape holds is checked: 24 of them
over 600 steps, in about five seconds. `goldensAt` draws the frame
at those steps and compares it with `test/goldens/<tape>-<step>.png`.

This page runs in an app, where there is no `flutter_test` and no tape on
disk, so it carries over the loop `testReplay` is built from. That loop is a
dozen lines over `Demo`, `InputTapePlayback` and `StateDigest`, all from
`flutter3d_sim`. The page leaves out the goldens and keeps the digests. The
two balls play the same tape. The lower one runs a build whose bounce is a
little softer, and the lamps in front are that build's checkpoints.

## Step 1: A game the tape can be played into

The game is a ball pushed along a track between two walls. It has the
three things a replay needs, which a game with a rewind buffer already has:
`restore` from a snapshot, `step` with the input, and `save`. `levelHash` is
the fourth. It is a digest of the level the run was played on, so a tape is
refused against an edited level instead of reported as a bug.

`restitution` is the number the planted change will touch. Until the ball
first reaches a wall, two builds that differ only there make the same run.

{{code game}}

## Step 2: Record a tape

A recording is what a play session leaves behind: the starting state, the
tape of input, and a `DigestTrace` that takes the digest of the snapshot
every twenty steps. Together they are a `Demo`, the document a `.f3drun`
file holds. The page writes it to JSON and reads it back, which is what
`readTape` does with a file.

The digest is taken after the step runs and before `endStep`, with the
step's input still applied. The replay has to take it at the same moment, or
every checkpoint differs for a reason that has nothing to do with the game.

{{code record}}

## Step 3: Replay it with no screen

The checker first refuses what would make the replay meaningless. It refuses
a step the tape took no checkpoint at, a replay that checks nothing (which
would pass whatever the game does), and a level whose hash changed since the
recording. Each refusal comes back as a sentence that says what to do
instead.

After that it restores the start, plays the tape one step at a time and
compares the digest at each step it was asked about. The first mismatch ends
the replay and names its step, along with the last checkpoint that still
agreed, so the change is in the steps between them.

{{code replay}}

`testReplay` does the same and then calls `fail` with that sentence, and at a
step in `goldensAt` it draws the frame on the software device and compares it
with the golden file.

## Step 4: What the page holds itself to

Five replays of the one tape. This build agrees at all twelve checkpoints,
and at only 60 and 120 when those are the steps asked for. The softer bounce
fails at step 100 with step 80 still agreeing, and the check also confirms
that the first bounce falls between those two. A step with no checkpoint is
refused, and so is a level whose wall moved.

{{code check}}

Switch **Lower lane: a softer bounce** off and the lower ball runs this build
again. Every lamp turns green.

> **Note.** `testReplay` needs Flutter: the game is built on a software
> device and a level is read through the asset bundle. A digest-only replay
> under plain `dart test`, for a game whose simulation has no Flutter in it,
> is not written yet, and a server that verifies runs would need
> `HeadlessRun` to take a `restore`. The dungeon's own replay test and the
> racing demo have not moved onto `testReplay`, and the strategy demo's
> match is not a `Demo` at all. A tape the running game recorded still gets
> into `test/tapes/` through a script per game, not from the editor.
