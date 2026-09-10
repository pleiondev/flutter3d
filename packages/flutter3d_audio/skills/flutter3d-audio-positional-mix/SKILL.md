---
name: flutter3d-audio-positional-mix
description: Use when adding positional sound to a flutter3d game — AudioScene, moving emitters, attenuation and panning, voice limiting, and the silent backend for tests.
---

# The geometry is computed here; the backend plays flat voices

```dart
final scene = AudioScene(
  backend: SoLoudBackend()..open(),
  maxVoices: 24,
  // The walls belong to the physics; this package must not learn about them.
  occlusion: (from, to) => world.raycast(from, to) ? 0.3 : 1.0,
);

await scene.preload(<SoundDef>[Sounds.pistol, Sounds.door]);

scene.play(Sounds.pistol, muzzlePosition);            // one-shot
final hum = scene.play(Sounds.torch, torchPosition);  // a moving emitter

listener.aimAt(eyePosition, yaw);
scene.update(listener);                               // once a frame, after moving
```

`play` returns an emitter, so whatever owns a moving source can move it and the
mixer updates that voice rather than restarting it.

**Why gain and pan are computed here.** SoLoud's 3D layer cannot be used for
anything that moves: applying a moved source or a turned listener needs
`update3dAudio()`, which `flutter_soloud` 4.1.7 exposes no way to reach, so a
source set once at `play3d` never moves again — and in a first-person game the
listener turns constantly. If a later version exposes the call, the right change
is a second backend rather than an edit to this one.

## What the mixer decides

**Attenuation.** `InverseRolloff` by default, the only one of the three that
sounds right when the player walks past something. `LinearRolloff` and
`ExponentialRolloff` exist because designers ask for them, `NoAttenuation` for
music.

**Panning** is the left-right component of the direction and nothing else. Yaw
only: tilting your head back does not swap left and right.

**Voice limiting** is priority first, loudness second, so a door closing
outranks the ninth footstep even when the footstep is nearer. **Instance
limiting** is the other half: ten identical grunts on one frame are a click
rather than ten times as loud.

## Testing, and playing nothing

`SilentBackend` records every call and makes no sound, so the mix is testable
with no audio device — and it is what a headless build or a player who turned
sound off should use, as a backend rather than a branch at every call site.

Assert on what it recorded: which sound, at what gain and pan, how many voices
survived the limiter. None of those can be heard in CI.
