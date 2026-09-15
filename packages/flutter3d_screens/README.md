# flutter3d_screens

**Compatibility shim.** The settings, volumes, rebinding, credits and save
storage this package used to hold moved to
[`flutter3d_session`](../flutter3d_session) by the package-merge plan, once it
turned out nothing anywhere depended on this package without also depending
on that one. `lib/flutter3d_screens.dart` is one `export` of that package's
own barrel, so an existing import keeps resolving to the exact same
declarations, unchanged.

```dart
import 'package:flutter3d_session/flutter3d_session.dart'; // new code
```

`native.dart` and `testing.dart` moved the same way and are not re-exported
here — reach them through `flutter3d_session` directly.

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
