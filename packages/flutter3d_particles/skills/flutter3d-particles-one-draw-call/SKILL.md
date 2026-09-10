---
name: flutter3d-particles-one-draw-call
description: Use when adding particles to a flutter3d scene — the fixed pool, the emitters, advancing with the frame the simulation accepted, and per-particle randomness.
---

# A pool, an emitter, and one draw call

```dart
final particles = ParticleSystem(seed: 7);
renderer.addContributor(ParticleContributor(particles));

particles.burst(effect, at, direction: normal);
particles.advance(loop.lastFrame);
```

Every live particle is drawn in a single instanced call on any backend;
`MeshParticleContributor` is the same for particles that are meshes.

**The pool is fixed and reused.** A system that allocated per particle would
spend a frame's budget in the collector at exactly the moment something
exploded. When it is full, new particles are dropped and counted rather than
growing the pool — read the drop count if a burst looks thin, and raise the size
deliberately.

**Advance with `loop.lastFrame`**, the frame the simulation accepted, not the
raw delta from the widget. On a machine that drops a frame, advancing by wall
time drifts the smoke away from the world it is attached to.

## Emitters and shaping

`SphereEmitter`, `ConeEmitter`, `BoxEmitter` and `DriftEmitter` are the shapes.
`ParticleAffector` changes a particle after birth, `ParticleCurve` is a value
over its lifetime, `Flipbook` walks a sprite sheet, and `LightEmitter` is what
makes a muzzle flash light the wall.

`emit`, `emitTimed`, `emitFor` and `stopEmitting(key)` are the continuous forms;
`burst` is the one-shot. A continuous emitter is addressed by a key, so whatever
started it can stop it without holding a handle across a save.

## Randomness a particle owns

Each particle's values come from **its own stream**, keyed on the system's seed
and the particle's emission ordinal, rather than every birth taking a turn at
one generator. Both are deterministic; only this one survives editing, because
adding a sampled field to a `ParticleEffect` otherwise shifts every draw after
it and moves every golden with particles in it.

`ParticleRandom` implements `math.Random`, so an emitter a game wrote keeps its
signature. It is xorshift rather than a multiplying mixer because this engine
runs on the web, where an `int` is a double and a 32-by-32 multiply silently
loses the top bits.
