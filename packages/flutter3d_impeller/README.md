# flutter3d_impeller

`flutter3d_hardware` over `flutter_gpu`: the backend a desktop or mobile build
draws through.

```dart
final device = await GpuRenderBackend.create();
final renderer = Renderer.create(device: device);
```

Nothing else in the stack names `flutter_gpu`. Swapping this for another backend
changes one line of application wiring. That property is what the split exists
for, and there are two more backends to prove it with.

## The shader bundle

`flutter_gpu` wants shaders compiled ahead of time, so this package builds a
bundle:

    ./tool/build_shaders.sh

The bundle is gitignored and its format is tied to the SDK version, so a fresh
checkout has none until that runs. A test asserts it was built. It fails instead
of skipping on purpose, because "CI built only one bundle" is the trap that test
exists to catch.

**Run it again after every shader edit.** The sources live in
`flutter3d_shaders`, and editing one changes nothing an application loads until
this rebuilds. Forgetting shows up as `failed to bind texture`, not as a shader
behaving oddly: the renderer binds a slot the new GLSL declares and the compiled
binary does not have. The message names neither the shader nor the edit.

`dart run tool/structure.dart` compares the bundle against its sources and says
which are newer, so the mistake is a red rule instead of a lost afternoon. It
skips when there is no bundle, which is every checkout without `impellerc`.

The entry point lives here and not in `flutter3d`, and it has to. The script
calls `impellerc`, which is this backend's compiler and not the engine's
concern, and a scan holds the engine to naming no backend at all. An extension
package outside this repository runs the same build against its own shaders:

    dart run flutter3d_impeller:build_shaders

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
