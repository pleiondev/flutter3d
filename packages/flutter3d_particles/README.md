# flutter3d_particles

A pool, an emitter, and one draw call.

```dart
final particles = ParticleSystem();
renderer.addContributor(ParticleContributor(particles));

particles.burst(effect, at, direction: normal);
particles.advance(loop.lastFrame);
```

Every live particle in a scene is drawn in a single instanced call, on any
backend the engine has. The pool is fixed and reused: a system that allocated
per particle would spend a frame's budget in the garbage collector at exactly
the moment something exploded.

**Advanced with the frame the simulation accepted**, not with the raw delta —
`GameLoop.lastFrame` — or the smoke drifts away from the world it is attached
to on any machine that drops a frame.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
