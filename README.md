# flutter3d

A 3D engine on Flutter GPU, a game engine on top of it, and a first-person game
built from both.

## What is here

| Package | What it is |
|---|---|
| [`packages/flutter3d`](packages/flutter3d) | The renderer: scene graph, glTF/OBJ/`.f3d` loading, six lighting models, shadows, bloom, skinning, BVH culling, picking. [README](packages/flutter3d/README.md), [RESEARCH](packages/flutter3d/RESEARCH.md) |
| [`packages/flutter3d_game`](packages/flutter3d_game) | The game layer: a fixed timestep, interpolation, input that has forgotten which device it came from, levels and mechanisms. [README](packages/flutter3d_game/README.md) |
| [`packages/flutter3d_physics`](packages/flutter3d_physics) | Collision shapes, a broadphase, queries and a character controller. Plain Dart — no Flutter, no renderer |
| [`packages/flutter3d_bridge`](packages/flutter3d_bridge) | Where the two meet: level geometry to mesh nodes, an actor to its visual, a weapon to a view model |
| [`packages/flutter3d_audio`](packages/flutter3d_audio) | Positional audio: attenuation, panning and voice limiting, with a pluggable backend |
| [`packages/mouse_capture`](packages/mouse_capture) | Relative mouse deltas, which Flutter offers on no desktop platform |
| [`apps/dungeon`](apps/dungeon) | The game, and a headless test that plays it to the exit |
| [`packages/flutter3d/example`](packages/flutter3d/example) | The engine's own demo: a model browser with every feature switchable |

The split is not filing. `flutter3d_game` does not depend on `flutter3d`, and
most of it does not depend on Flutter at all — simulation, input and collision
have nothing to say about how a frame is drawn. That is what lets the parts
which fail quietly (a collision that passes through a wall once in a thousand
steps, a jump that is a different height on a faster monitor, a press swallowed
at a low frame rate) be reached from a plain unit test. `flutter3d_bridge` is
the one package allowed to depend on both, and it is where the renderer and the
simulation meet; the application supplies only what a dungeon looks like.

## Running

A [pub workspace](https://dart.dev/tools/pub/workspaces), so one resolve covers
everything:

```bash
flutter pub get

# Required before the first run, and after every Flutter SDK change: the shader
# bundle format is tied to the SDK version.
(cd packages/flutter3d && ./tool/build_shaders.sh)

# The game
(cd apps/dungeon && flutter run -d macos)

# The engine demo
(cd packages/flutter3d/example && flutter run -d macos)
```

Flutter GPU and Impeller are enabled **per application** through `Info.plist`,
so every app in this repository sets `FLTEnableFlutterGPU` and
`FLTEnableImpeller` for itself. A new one that skips them fails to initialise
the shader library and renders nothing.

## Tests

```bash
for p in packages/*/; do (cd "$p" && flutter test); done
(cd packages/flutter3d_physics && dart test)   # plain Dart, no Flutter needed
```

1234 tests across thirteen packages, and the only ones that need a GPU are the
Impeller half of the golden set. The other half is rendered by the software
backend, which is what makes 30 scenes checkable in a headless run.

How they are written down — two independent golden sets rather than one, and
why every new test is written by breaking the thing it covers — is in
[docs/SPEC.md](docs/SPEC.md), section 6.

## Channel

Flutter 3.47.0 stable, and the list of what that costs got shorter in August
2026. Mip levels and instancing both arrived, and both are now used: a mip
chain is built on the CPU and uploaded level by level because `flutter_gpu` has
no `generateMipmap`, and instanced draws carry mesh particles. What is still
absent is compressed texture formats, compute passes, and rendering into a mip
level — recorded in [RESEARCH](packages/flutter3d/RESEARCH.md), and still the
reason several things are built the way they are rather than the obvious way.

The upgrade is worth one sentence of its own: `setDepthWrite(false)` did
nothing until 3.47, so additive particles occluded each other on two backends
out of three, and the software backend mirrored the bug on purpose so the two
would stay comparable. `flutter3d_graphics/COMPATIBILITY.md` keeps that story
because the lesson outlives it.
