# flutter3d_conformance

What `flutter3d_hardware` requires of a backend, as a suite the backend runs
against itself.

```dart
void main() => runConformance(device);
```

An interface can only say that a call exists. This says that a clear covers the
whole attachment, that uploaded pixels keep their row order, that the HDR format
the backend names is really renderable, and that every stage pair the engine
links does link.

**The last one earns its place regularly.** A varying a fragment stage reads and
no vertex stage writes is a hard error in a browser and invisible on a backend
whose pipelines were linked ahead of time — so the check catches, on one
backend, a mistake that would ship on another.

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
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from
[`apps/flutter3d_template_app`](../../apps/flutter3d_template_app).
Documentation: <https://flutter3d.pleion.dev>.
