# flutter3d_impeller

`flutter3d_hardware` over `flutter_gpu`: the backend a desktop or mobile build
draws through.

```dart
final device = await GpuRenderBackend.create();
final renderer = Renderer.create(device: device);
```

Nothing else in the stack names `flutter_gpu`. Swapping this for another backend
is a change to one line of application wiring — which is the property the split
exists for, and the reason there are two more backends to prove it with.

## The shader bundle

`flutter_gpu` wants shaders compiled ahead of time, so this package builds one:

    ./tool/build_shaders.sh

The bundle is gitignored and its format is tied to the SDK version, so a fresh
checkout has none until that runs. A test asserts it was built — deliberately a
failure rather than a skip, because "CI built only one bundle" is exactly the
trap that test exists to catch.

**Run it again after every shader edit.** The sources live in
`flutter3d_shaders`, and editing one changes nothing an application loads until
this rebuilds. The failure that follows is the reason this paragraph exists: not
a shader behaving oddly, but `failed to bind texture`, because the renderer
binds a slot the new GLSL declares and the compiled binary has not got. The
message names neither the shader nor the edit.

`dart run tool/structure.dart` compares the bundle against its sources and says
which are newer, so the mistake is a red rule rather than an afternoon. It skips
when there is no bundle, which is every checkout without `impellerc`.

The entry point is here rather than in `flutter3d` and has to be: the script
calls `impellerc`, which is this backend's compiler and not the engine's
business, and a scan holds the engine to naming no backend at all. An extension
package outside this repository runs the same build against its own shaders:

    dart run flutter3d_impeller:build_shaders

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
