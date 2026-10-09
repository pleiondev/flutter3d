# flutter3d_particles

A pool, an emitter, and one draw call.

```dart
final particles = ParticleSystem();
renderer.addContributor(ParticleContributor(particles));

particles.burst(effect, at, direction: normal);
particles.advance(loop.lastFrame);
```

Every live particle in a scene is drawn in a single instanced call, on any
backend the engine has. The pool is fixed and reused. A system that allocated
per particle would spend a frame's budget in the garbage collector at exactly
the moment something exploded.

The system is advanced with the frame the simulation accepted,
`GameLoop.lastFrame`, and not with the raw delta. Otherwise the smoke drifts
away from the world it is attached to on any machine that drops a frame.

There is no Flutter in it. The contributors draw through `flutter3d_core`'s
`PassContributor`, so the package runs under `dart test`, and
`flutter3d_model_core` bakes a system into a `SimulationCache` on the Dart VM.
The same `seed` and the same sequence of `advance` calls give byte-identical
particles. The bake relies on that; it does not add it.

An effect can also be a file. A `.f3dfx` document says in JSON what the Dart
says: the emitter, the lifetime, size and colour, the affectors in order, how
it is drawn, and the bus events it goes off on.

```dart
final effects = ParticleEffects(particles);
effects.addDocument(EffectDocument.parse(text), events: loop.events);
effects.burst('explosionEmbers', at);
```

A document's effect and the same effect in Dart are one simulation, particle
for particle, and the dungeon demo's effects are tested both ways. A
`.f3dplugin` can carry these documents too.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
