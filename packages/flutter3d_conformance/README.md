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

The last check catches real mistakes regularly. A varying that a fragment stage reads and no
vertex stage writes is a hard error in a browser, and invisible on a backend
whose pipelines were linked ahead of time. The check catches on one backend a
mistake that would ship on another.

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
