# flutter3d_audio

Positional audio: attenuation, panning, occlusion and voice limiting, with a
pluggable backend. A sibling of `flutter3d_game` rather than a `RenderPlugin` —
it draws nothing, so the renderer's plugin seam does not apply to it.

Depends on neither `flutter3d` nor `flutter_gpu`. It is handed a listener pose
and emitter positions; where those come from is the application's business.

## Why the geometry is computed here

SoLoud has a 3D layer, and it cannot be used for anything that moves.
Applying a moved source or a turned listener requires `update3dAudio()`, and
`flutter_soloud` 4.1.7 exposes neither that call nor anything that makes it:
its `set3dSourcePosition` passes straight through to a SoLoud method that only
marks the source dirty. A source set once at `play3d` never moves again, and in
a first-person game the listener turns constantly.

So `AudioScene` computes gain and pan, and the backend is asked only for a flat
voice with a volume and a pan — which every backend can do and which takes
effect immediately. If a later `flutter_soloud` exposes the call, the right
change is a second backend, not an edit to this one.

## Shape

```dart
final scene = AudioScene(
  backend: SoLoudBackend()..open(),
  maxVoices: 24,
  // The walls belong to the physics; this package must not learn about them.
  occlusion: (from, to) => world.raycast(from, to) ? 0.3 : 1.0,
);

await scene.preload(<SoundDef>[Sounds.pistol, Sounds.door]);

scene.play(Sounds.pistol, muzzlePosition);          // one-shot
final hum = scene.play(Sounds.torch, torchPosition); // holds a looping emitter

// Once a frame, after everything has moved.
listener.aimAt(eyePosition, yaw);
scene.update(listener);
```

An emitter is returned so whatever owns a moving source can move it; the mixer
updates that voice rather than restarting it.

## What the mixer decides

- **Attenuation** — `InverseRolloff` by default, the only one of the three that
  sounds right when the player walks *past* something. `LinearRolloff` and
  `ExponentialRolloff` are there because designers ask for them, and
  `NoAttenuation` for music.
- **Panning** — the left-right component of the direction, and nothing else.
  Yaw only: tilting your head back does not swap left and right.
- **Voice limiting** — priority first, loudness second. A door closing outranks
  the ninth footstep even when the footstep is nearer.
- **Instance limiting** — ten identical grunts on one frame are a click, not
  ten times as loud.

## Testing

`SilentBackend` records every call and makes no sound, so the whole mix is
testable without an audio device — and it is what a headless build or a player
who has turned sound off should use, rather than a branch at every call site.
