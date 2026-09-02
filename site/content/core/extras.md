---
description: A pooled particle system that draws in one call, lights measured from the particles that cast them, and positional audio computed in Dart.
---

# Particles & audio

Two packages that are extensions rather than parts of the engine. Nothing in `flutter3d` names a particle or a sound.

## Particles

`ParticleSystem` is **one pool for the whole application**, not one per effect. A system per effect is a draw call per effect, and on this engine a pipeline change is the most expensive state change there is.

```dart
final particles = ParticleSystem(capacity: 2000);
renderer.addContributor(ParticleContributor(particles));

// once a frame
particles.advance(dt);
```

That is the whole integration. `ParticleContributor` is a `PassContributor` — the seam that lets something draw inside an existing pass without the renderer learning what it is.

{{golden particles-burst | A seeded burst a little over half a second in: spread, drag and gravity bending the paths, colour and size changing over life.}}

### Effects are values

```dart
abstract final class Effects {
  static final ParticleEffect dust = ParticleEffect(
    count: 12,
    emitter: const ConeEmitter(speed: Range(0.6, 1.8), halfAngleDegrees: 55.0),
    lifetime: const Range(0.35, 0.7),
    size: const Range(0.08, 0.2),
    color: Vector4(0.8, 0.78, 0.7, 0.5),
    affectors: <ParticleAffector>[
      ParticleSizeCurve(...),
      ParticleColorGradient(...),
      ParticleSpin(...),
    ],
  );
}
```

| Emitter | Shape |
|---|---|
| `SphereEmitter` | Outward from a shell, `speed` and `radius` ranges |
| `ConeEmitter` | A cone about a direction, `halfAngleDegrees` |
| `BoxEmitter` | From inside a box, optionally along an axis |
| `DriftEmitter` | Slow and spread — smoke, motes |

### Two ways to emit

```dart
// One-shot: a footstep, an impact, a coin taken.
particles.burst(Effects.dash, at, direction: up);

// Continuous: restated every frame, keyed on who is emitting.
particles.emit(fire, Effects.flame, origin, perSecond: 34.0, direction: up);
```

<div class="note">
<p>A continuous rate that is <strong>not restated goes out</strong>. That is the design, not a leak: a torch that was destroyed stops smoking because nobody told it to keep going, and no code had to remember to stop it.</p>
</div>

`advance` sub-steps internally with a ceiling, because a debugger pause hands it a delta of several seconds and catching all of it up takes longer than the stall did.

### Lights measured from the particles

A fire *is* its particles, so the light it casts is measured from them rather than produced by a second wobble running alongside.

```dart
final class TorchFire with LightEmitter {
  // ParticleGlow accumulates every live particle's contribution during the
  // step and hands back a smoothed intensity.
}
```

<div class="why">
<p>Two generators of one quantity disagree eventually, and the disagreement looks like a flame burning brightly while the light it casts has gone out. <code>ParticleGlow</code> removes the second generator instead of trying to keep them in step.</p>
</div>

### Mesh particles and flipbooks

`MeshParticleContributor` draws instanced meshes rather than quads — debris, sparks with volume. `Flipbook` walks a sprite sheet over a particle's lifetime.

{{golden particles-mesh | Five spheres in a row, one instanced draw, sizes ascending so a backend that drew instance zero five times would be caught.}}

<div class="note">
<p>The particle shaders live in <code>flutter3d_shaders</code> rather than here. That package is already the shared GLSL every backend compiles from — Impeller into a bundle, WebGL by translation, the CPU backend as Dart transcriptions, so <code>particle.vert</code> living there while the simulation lives here is the arrangement that package exists for.</p>
</div>

## Audio

The spatialisation — attenuation, panning, occlusion and voice limiting — is computed in Dart. Making noise is a backend's job.

```dart
AudioScene audio = AudioScene(backend: SilentBackend());
final ears = AudioListener();

// SoLoud arrives asynchronously and must not hold up the first frame.
final backend = SoLoudBackend();
try {
  await backend.open();
  audio = AudioScene(backend: backend, mixer: audio.mixer);
  await audio.preload(Sounds.all);
} catch (error) {
  debugPrint('audio: could not start SoLoud: $error');   // keep playing, silently
}
```

<div class="why">
<p>Starting with <code>SilentBackend</code> and swapping is not defensive coding for its own sake. A machine with no audio device, or a CI runner, keeps the silent backend and plays the game, and the alternative, awaiting the device before the first frame, makes a missing sound card the difference between playing and staring at a spinner.</p>
</div>

### Sounds are definitions

```dart
abstract final class Sounds {
  static const SoundDef coin = SoundDef(
    name: 'coin',
    asset: 'assets/sounds/coin.ogg',
    gain: 0.8,
    bus: AudioBus.sfx,
    rate: 1.0,
    rateVariance: 0.08,   // so forty coins are not one coin forty times
    priority: 2,
    maxInstances: 4,
    attenuation: InverseRolloff(reference: 2.0, maximum: 40.0),
  );
}
```

`InverseRolloff`, `LinearRolloff`, `ExponentialRolloff` and `NoAttenuation` are the four curves; `reference` is the distance at which a sound is at full gain and `maximum` is where it stops being audible at all.

### Playing and updating

```dart
// Fire and forget, at a world position.
audio.play(Sounds.coin, where);

// Held for as long as it should sound, stopped when it should not.
final voice = audio.play(Sounds.stoneGrinding, door.origin);
// ...
voice.stop();

// Once a frame, after the camera has moved.
ears.aimAlong(camera.eye, camera.target - camera.eye);
audio.update(ears);
```

<div class="note">
<p><code>aimAt(position, yaw)</code> reads an angle the way a first-person camera does. A follow camera is not one, so it uses <code>aimAlong</code> with its own forward vector — passing a yaw would put the ears where the player is facing rather than where the camera is looking.</p>
</div>

### Voice limiting and occlusion

`maxVoices` caps how many sound at once. When more want to play, `priority`, distance and `maxInstances` decide, so forty coins in a heap do not drown a door opening behind you.

Occlusion is a callback, because what counts as blocking is a game's answer. The bridge's `SoundOcclusion` is the answer a brush level gives: it walks the ray from the source to the ear through the collision world and lets every obstacle it meets take half, down to a floor that keeps a distant torch from switching off as the player rounds a corner.

```dart
final occlusion = SoundOcclusion(collision, perObstacle: 0.5, maxObstacles: 4, floor: 0.06);
final audio = AudioScene(backend: backend, occlusion: occlusion.between);
```

**A wall makes a sound quieter and duller, and both come from that one number.** The share that got through is the gain; one minus it goes beside it to the backend as a *muffle*, which `SoLoudBackend` turns into a low-pass cutoff per voice, geometric between 16 kHz open and 600 Hz through a wall, because hearing is geometric. Thickness is not measured, so every wall counts once however thick, and the answer is pure, so a replay sounds the way the run did.

<div class="why">
<p>The dungeon had a wall test since its first commit and it was yes-or-no: a torch behind a door and a torch three rooms away were the same torch.</p>
</div>

### Buses

```dart
audio.mixer.setVolume(AudioBus.master, 0.9);
audio.mixer.setVolume(AudioBus.music, 0.4);
audio.mixer.setVolume(AudioBus.sfx, 1.0);
```

`Mixer.fromJson` / `toJson` is what a settings file stores.

## Next

- [Tutorial: first scene](/core/tutorial/): both of these wired into a real application
- [Platformer tutorial](/platformer/tutorial/), where every event on the page becomes a sound and a burst
