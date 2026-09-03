# flutter3d

An **independent implementation** of a 3D engine on Flutter GPU, a game engine
on top of it, and **three games of different genres** built from both — which is
the only honest test that the engine is one. It is not a fork, a binding or a
wrapper around another engine, and it is not affiliated with the Flutter team.

[![CI](https://github.com/pleiondev/flutter3d/actions/workflows/ci.yml/badge.svg)](https://github.com/pleiondev/flutter3d/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

On pub.dev: all twenty-four packages, published by
[pleion.dev](https://pub.dev/publishers/pleion.dev/packages) — start with
[`flutter3d`](https://pub.dev/packages/flutter3d) and a backend. The newest is
[`flutter3d_sim`](https://pub.dev/packages/flutter3d_sim): the simulation, as
plain Dart, so a server can replay a run without a Flutter SDK.
Or build it
from this repository — see [Running](#running),
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

Documentation: <https://flutter3d.pleion.dev> — guides, tutorials for all three
genres, and the generated API reference.

## What is here

| Package | What it is |
|---|---|
| [`packages/flutter3d`](packages/flutter3d) | The renderer: scene graph, glTF/OBJ/`.f3d` loading, six lighting models, shadows, bloom, skinning, BVH culling, picking. [README](packages/flutter3d/README.md) |
| [`packages/flutter3d_game`](packages/flutter3d_game) | The game layer: a fixed timestep, interpolation, input that has forgotten which device it came from, levels and mechanisms. [README](packages/flutter3d_game/README.md) |
| [`packages/flutter3d_physics`](packages/flutter3d_physics) | Collision shapes, a broadphase, queries and a character controller. Plain Dart — no Flutter, no renderer |
| [`packages/flutter3d_game_shooter`](packages/flutter3d_game_shooter) | One genre: monsters, weapons, an inventory, the step order that ties them together, and the weapon held in the hands |
| [`packages/flutter3d_game_platformer`](packages/flutter3d_game_platformer) | A second genre, and the instrument that tests the first: a runner who jumps twice, coins, hazards and checkpoints |
| [`packages/flutter3d_bridge`](packages/flutter3d_bridge) | Where the two meet: level geometry to mesh nodes, an actor to its visual, a fixture to the light it drives |
| [`packages/flutter3d_audio`](packages/flutter3d_audio) | Positional audio: attenuation, panning and voice limiting, with a pluggable backend |
| [`packages/pad_input`](packages/pad_input) | A gamepad, read as a snapshot once per frame. Button names are physical positions, because they end up in a player's config file; the web backend is pure Dart. [README](packages/pad_input/README.md) |
| [`packages/flutter3d_screens`](packages/flutter3d_screens) | The screens that are not the game: settings, volumes, rebinding, credits. Shared by both games |
| [`packages/pointer_lock`](packages/pointer_lock) | Relative mouse deltas: a method channel on macOS, the browser's own Pointer Lock API on the web. Flutter surfaces neither |
| [`packages/flutter3d_samples`](packages/flutter3d_samples) | The Khronos test models, as fixtures rather than as the engine's own assets — so a game built on it carries the decoders and not the 4.1 MB they were checked against |
| [`packages/flutter3d_hardware`](packages/flutter3d_hardware) | The abstraction over graphics APIs: a device, an encoder, a pass. Its vocabulary is its own — it names no API, so a fourth backend changes no user code |
| [`packages/flutter3d_impeller`](packages/flutter3d_impeller) | The desktop backend, over `flutter_gpu`. Also where the shader build lives |
| [`packages/flutter3d_webgl`](packages/flutter3d_webgl) | The web backend, over WebGL2 |
| [`packages/flutter3d_cpu`](packages/flutter3d_cpu) | A software rasteriser. Not a teaching exercise: it gives a second, independent set of reference images and lets the renderer be tested in CI with no GPU |
| [`packages/flutter3d_testing`](packages/flutter3d_testing) | Pixel regression tests for a game built on this engine, with no GPU: draw a frame through the software backend and hold it to a reference image. Nothing else on this platform can do it without a real device |
| [`packages/flutter3d_conformance`](packages/flutter3d_conformance) | The contract every backend must pass, as runnable checks rather than a document |
| [`packages/flutter3d_backend`](packages/flutter3d_backend) | Picks one of the three by conditional import, so an application says `openDevice()` and not which |
| [`packages/flutter3d_shaders`](packages/flutter3d_shaders) | The GLSL, and the headers an extension package includes |
| [`packages/flutter3d_particles`](packages/flutter3d_particles) | One pool, one draw call, whatever is in it |
| [`packages/flutter3d_session`](packages/flutter3d_session) | A run that can be started, saved, resumed and ended, with no widget in it |
| [`packages/flutter3d_app`](packages/flutter3d_app) | What every application repeats: storage, settings, the frame clock, the screens |
| [`packages/flutter3d_game_racing`](packages/flutter3d_game_racing) | A third genre: a car simulated as a sphere, a circuit read from a spline, lap timing and a ghost |
| [`apps/flutter3d_demo_dungeon`](apps/flutter3d_demo_dungeon) | The shooter, and a headless test that plays it to the exit. Desktop, web, Android and iOS |
| [`apps/flutter3d_demo_platformer`](apps/flutter3d_demo_platformer) | The second game: third person, two jumps and a dash, and no line of the engine changed to allow it. Desktop, web, Android and iOS |
| [`apps/flutter3d_demo_racing`](apps/flutter3d_demo_racing) | The third game: a circuit, three rivals and the lap you drove before, drawn beside the one you are driving |
| [`apps/flutter3d_editor`](apps/flutter3d_editor) | A level editor that reads the same documents the games do, and writes projects from templates |
| [`apps/flutter3d_template_app`](apps/flutter3d_template_app) | The application a new project starts as, and the source the editor's templates are generated from |
| [`packages/flutter3d/example`](packages/flutter3d/example) | The engine's own demo: a model browser with every feature switchable |

The split is not filing. `flutter3d_game` does not depend on `flutter3d`, and
most of it does not depend on Flutter at all — simulation, input and collision
have nothing to say about how a frame is drawn. The same cut runs the other
way: **a genre is a package too.** `flutter3d_game_shooter` holds what only a shooter
wants, so a platformer or a racing game inherits none of this one's vocabulary
— and three of the scans in `tool/structure.dart` keep that a fact rather than
a habit. That is what lets the parts
which fail quietly (a collision that passes through a wall once in a thousand
steps, a jump that is a different height on a faster monitor, a press swallowed
at a low frame rate) be reached from a plain unit test. `flutter3d_bridge` is
the one package allowed to depend on both, and it is where the renderer and the
simulation meet; an application supplies only what its own game looks like.

## Running

A [pub workspace](https://dart.dev/tools/pub/workspaces), so one resolve covers
everything:

```bash
flutter pub get

# Required before the first run, after every Flutter SDK change, and after every
# edit to a shader. The bundle format is tied to the SDK version, the built
# bundle is gitignored so a fresh checkout has none, and a `.frag` edited without
# rebuilding changes nothing an application loads.
(cd packages/flutter3d_impeller && ./tool/build_shaders.sh)

# The shooter
(cd apps/flutter3d_demo_dungeon && flutter run -d macos)

# The platformer
(cd apps/flutter3d_demo_platformer && flutter run -d macos)

# The racing game
(cd apps/flutter3d_demo_racing && flutter run -d macos)

# The engine demo
(cd packages/flutter3d/example && flutter run -d macos)
```

In a browser it is the same command with a different device, and no shader
bundle: the WebGL backend translates the same GLSL and the browser compiles it.

```bash
(cd apps/flutter3d_demo_dungeon && flutter run -d chrome)

# What the demos are published as. --wasm builds the JavaScript output beside
# the WebAssembly one and the loader picks; the games are the one thing here
# that spends its frame budget in Dart rather than in a driver.
(cd apps/flutter3d_demo_dungeon && flutter build web --wasm --release)
```

Flutter GPU and Impeller are enabled **per application** through `Info.plist`,
so every app in this repository sets `FLTEnableFlutterGPU` and
`FLTEnableImpeller` for itself. A new one that skips them fails to initialise
the shader library and renders nothing. Neither setting means anything to a
browser build, which reaches WebGL2 through `flutter3d_backend` instead.

## Tests

```bash
tool/ci.sh          # everything a machine can check: shaders, analyze, all tests
```

Or one package at a time:

```bash
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test)   # plain Dart, no Flutter needed
```

3225 tests across twenty-four packages and five applications, and the only
ones that need a GPU are the
Impeller half of the golden set. The other half is rendered by the software
backend, which is what makes 35 scenes checkable in a headless run.

Two of the steps are browser steps — `flutter test --platform chrome` for the
WebGL backend and for the browser half of `pointer_lock` — and one of them
compiles a game to WebAssembly, because a build nobody runs is a platform nobody
supports.

How they are written down — two independent golden sets rather than one, and
why every new test is written by breaking the thing it covers — is in
[ARCHITECTURE.md](ARCHITECTURE.md), section 13.

## Channel

Flutter 3.47.0 stable, and the list of what that costs got shorter in August
2026. Mip levels and instancing both arrived, and both are now used: a mip
chain is built on the CPU and uploaded level by level because `flutter_gpu` has
no `generateMipmap`, and instanced draws carry mesh particles. What is still
absent is compressed texture formats, compute passes, and rendering into a mip
level — recorded in [ARCHITECTURE.md](ARCHITECTURE.md), section 2, and still
the reason several things are built the way they are rather than the obvious way.

The upgrade is worth one sentence of its own: `setDepthWrite(false)` did
nothing until 3.47, so additive particles occluded each other on two backends
out of three, and the software backend mirrored the bug on purpose so the two
would stay comparable. `ARCHITECTURE.md` §7 keeps that story
because the lesson outlives it.

### Editing a shader

**A stale bundle does not fail as a shader behaving oddly.** It fails as
`failed to bind texture`, because the renderer binds a slot the new GLSL
declares and the compiled binary has not got — and binding a slot a compiled
shader does not have takes the frame down. The message names nothing that leads
back to the file that was edited.

So `dart run tool/structure.dart` checks it: one of its twenty-three rules compares
the bundle against the sources it was built from and says which of them are
newer. The rule skips when there is no bundle at all, which is every fresh
checkout and every CI run — `impellerc` is not there to build one, and a rule
demanding it would be red on the machines least able to do anything about it.

The WebGL backend has the opposite arrangement and needs no such rule: its
translation is checked in, and CI regenerates it and fails on the diff.

## Contributing

The conventions here are not the usual ones — tests are written by breaking the
thing they cover, architecture is held by scans rather than by review, and
levels, models and templates are generated rather than edited. All of it is in
[CONTRIBUTING.md](CONTRIBUTING.md), and `bash tool/ci.sh` is the contract.

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to build, test and send a change
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — Contributor Covenant 2.1
- [SECURITY.md](SECURITY.md) — report privately, not in an issue
- [ARCHITECTURE.md](ARCHITECTURE.md) — how the system is put together, and why

## Licence

MIT — see [LICENSE](LICENSE).

Third-party assets keep their own terms, recorded beside them in `LICENSES.md`
with author, source, licence and what was changed. Everything shipped today is
CC0 or generated in this repository.
