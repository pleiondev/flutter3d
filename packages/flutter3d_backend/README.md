# flutter3d_backend

Which graphics backend a build draws through, chosen at compile time.

```dart
import 'package:flutter3d_backend/flutter3d_backend.dart';

final device = await openDevice(width: 1280, height: 720);
```

`openDevice` returns a `GraphicsDevice` from `flutter3d_hardware`. No backend
appears in any signature: on a desktop or a phone the device is
`flutter3d_impeller`'s, in a browser it is `flutter3d_webgl`'s, and web-or-native
is a conditional export rather than a runtime branch — `flutter_gpu` does not
compile for the web and `dart:js_interop` does not compile for macOS, so a file
importing both could target neither.

Two backends are reached at run time instead, because what decides them is not
visible to a compiler. On the native half, `flutter3d_cpu`'s software rasteriser
is where a build lands when Impeller will not start. On the browser half:

```sh
flutter build web --dart-define=FLUTTER3D_WEBGPU=true
```

asks for `flutter3d_webgpu` first and falls back to WebGL2 where the browser has
no `navigator.gpu` or hands out no adapter. **Off unless a build asks**, and that
is about size rather than about WebGPU: the probe has to be able to call both
openers, so a build that has it carries both backends and one that has not folds
the branch away. On `apps/flutter3d_demo_strategy` that is 372,686 bytes of
`main.dart.js` — 2,517,985 off against 2,890,671 on. Whether a particular game
pays it is the game's call, the same way its resolution and shadow budget are.

## What it does not decide

Resolution and shadow budget stay in the application. `kFixedResolution` tells a
caller whether the backend renders to a fixed internal target — true in a
browser, where a WebGL canvas resets its drawing buffer when it is resized —
and *what size* is the game's own trade against its own scene. The three games
in this repository answer it differently and each says why where the number is.

## Why it is a package

The conditional import and `openDevice` were three files in each of three games,
byte-identical in two of them down to the paragraph explaining the conditional.

`flutter3d_session` was the obvious home and is the wrong one: it would have to
depend on both backends, and then `apps/flutter3d_editor` — which opens a file, changes it
and writes it back, and has no browser build to choose for — would pull WebGL
through it. Session stays backend-neutral, which is what lets it be mounted over
a `CpuDevice` in its own tests.

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
