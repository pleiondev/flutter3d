# flutter3d

An independent implementation of a 3D engine on Flutter GPU, a game engine on
top of it, and four games of different genres built from both. The games are
there because building them is the only honest test that the engine is one.
flutter3d is not a fork, a binding or a wrapper around another engine, and it is
not affiliated with the Flutter team.

[![CI](https://github.com/pleiondev/flutter3d/actions/workflows/ci.yml/badge.svg)](https://github.com/pleiondev/flutter3d/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

On pub.dev: thirty-eight packages, published by
[pleion.dev](https://pub.dev/publishers/pleion.dev/packages). Start with
[`flutter3d`](https://pub.dev/packages/flutter3d) and a backend. Thirty-six of
them are the 0.8.0 set, one number for all, so any `^0.8.0` resolves against
every other; [`pad_input`](https://pub.dev/packages/pad_input) and
[`pointer_lock`](https://pub.dev/packages/pointer_lock) keep a line of their own
at 0.4.2, since neither names a sibling. Coming from 0.6.0, several packages were
folded into others, and [`doc/boundary-0.7.0.md`](doc/boundary-0.7.0.md) lists
which import lines move. To work on the engine itself, see
[Running](#running), [CONTRIBUTING.md](CONTRIBUTING.md) and
[SECURITY.md](SECURITY.md).

The documentation at <https://flutter3d.pleion.dev> has guides, tutorials for
three of the four genres, and the generated API reference. The model editor runs in a
browser at <https://models.pleion.dev>, with its own
[tutorial](https://models.pleion.dev/learn/modeler/).

## What is here

| Package | What it is |
|---|---|
| [`packages/flutter3d`](packages/flutter3d) | The renderer: scene graph, glTF/OBJ/`.f3d` loading, six lighting models, shadows, bloom, skinning, BVH culling, picking. [README](packages/flutter3d/README.md) |
| [`packages/flutter3d_game`](packages/flutter3d_game) | What a game adds to an application: input that has forgotten which device it came from, the run being played, the settings and save screens, and actors and fixtures drawn. [README](packages/flutter3d_game/README.md) |
| [`packages/flutter3d_physics`](packages/flutter3d_physics) | Collision shapes, a broadphase, queries, a character controller and an XPBD cloth solver. Plain Dart, with neither Flutter nor the renderer behind it |
| [`packages/flutter3d_game_shooter`](packages/flutter3d_game_shooter) | One genre: monsters, weapons, an inventory, the step order that ties them together, and the weapon held in the hands |
| [`packages/flutter3d_game_platformer`](packages/flutter3d_game_platformer) | A second genre, and the instrument that tests the first: a runner who jumps twice, coins, hazards and checkpoints |
| [`packages/flutter3d_audio`](packages/flutter3d_audio) | Positional audio: attenuation, panning and voice limiting, with a pluggable backend |
| [`packages/pad_input`](packages/pad_input) | A gamepad, read as a snapshot once per frame. Button names are physical positions, because they end up in a player's config file; the web backend is pure Dart. [README](packages/pad_input/README.md) |
| [`packages/pointer_lock`](packages/pointer_lock) | Relative mouse deltas: a method channel on macOS, the browser's own Pointer Lock API on the web. Flutter surfaces neither |
| [`packages/flutter3d_samples`](packages/flutter3d_samples) | The Khronos test models, as fixtures rather than as the engine's own assets, so a game built on it carries the decoders and not the 4.1 MB they were checked against |
| [`packages/flutter3d_core`](packages/flutter3d_core) | The renderer with no Flutter SDK behind it, and two libraries it draws from that import on their own: `geometry.dart` (vertex layouts, mesh data, shape generators, tangents, morph targets, ray intersections) and `formats.dart` (`ModelDocument` and its materials, glTF/GLB, OBJ, STL, USDZ, `.f3d`, `.fmat`, and an FBX decoder that refuses with a reason). Plain Dart, so a modeller's document layer or a tool an agent starts can read a mesh or a `.glb` without a window |
| [`packages/flutter3d_hardware`](packages/flutter3d_hardware) | The abstraction over graphics APIs: a device, an encoder, a pass. Its vocabulary is its own and names no API, so a fourth backend changes no user code. Plain Dart |
| [`packages/flutter3d_impeller`](packages/flutter3d_impeller) | The desktop backend, over `flutter_gpu`. Also where the shader build lives |
| [`packages/flutter3d_webgl`](packages/flutter3d_webgl) | The web backend, over WebGL2. What an ordinary browser build draws through |
| [`packages/flutter3d_webgpu`](packages/flutter3d_webgpu) | The second web backend, over WebGPU. The only one whose shaders are not the same text the others read: its WGSL is translated from the same GLSL through `glslangValidator` and `naga`. A browser build reaches it by asking: `--dart-define=FLUTTER3D_WEBGPU=true`. [README](packages/flutter3d_webgpu/README.md) |
| [`packages/flutter3d_cpu`](packages/flutter3d_cpu) | A software rasteriser, built for testing rather than teaching. It gives a second, independent set of reference images and lets the renderer be tested in CI with no GPU |
| [`packages/flutter3d_testing`](packages/flutter3d_testing) | Pixel regression tests for a game built on this engine, with no GPU: draw a frame through the software backend and hold it to a reference image. Nothing else on this platform can do it without a real device |
| [`packages/flutter3d_conformance`](packages/flutter3d_conformance) | The contract every backend must pass, as runnable checks rather than a document |
| [`packages/flutter3d_shaders`](packages/flutter3d_shaders) | The GLSL, and the headers an extension package includes |
| [`packages/flutter3d_particles`](packages/flutter3d_particles) | One pool, one draw call, whatever is in it. Plain Dart, so a model can bake a particle system with no window |
| [`packages/flutter3d_stereo`](packages/flutter3d_stereo) | Two eyes and a head: the rig, the widget that draws a pair into one frame, and the settings a pair can have. A phone in a holder today, a headset when there is one |
| [`packages/flutter3d_app`](packages/flutter3d_app) | What every application repeats: which of the four backends `openDevice()` opens, the frame surface and clock, widgets in the scene, a level loaded into a scene, and storage |
| [`packages/flutter3d_game_racing`](packages/flutter3d_game_racing) | A third genre: a car simulated as a sphere, a circuit read from a spline, lap timing and a ghost |
| [`packages/flutter3d_game_strategy`](packages/flutter3d_game_strategy) | A fourth genre, and the first without a protagonist: ground made of samples, a crowd that takes orders and shoves itself apart, flow fields shared by destination, an economy, a fight, fog a side has to walk into, and a policy that plays a side without a mouse |
| [`packages/flutter3d_editor_core`](packages/flutter3d_editor_core) | The level editor with the editor taken out: the document being selected in, nudged, undone and written back, the handles a pointer hits, the palette a level builds out of itself, and the project a template becomes. Plain Dart, so a linter or a service can depend on it |
| [`packages/flutter3d_editor_mcp`](packages/flutter3d_editor_mcp) | The same editor offered to an agent: an MCP server over stdio whose tools are the editor's own commands, one document per process |
| [`packages/flutter3d_editor_widgets`](packages/flutter3d_editor_widgets) | The controls the modeller and the level editor share instead of each keeping a copy: number, colour, range, enum and texture fields and the row they assemble into, over one theme |
| [`packages/flutter3d_mcp_kit`](packages/flutter3d_mcp_kit) | What every MCP server here shares: a tool paired with its handler, a server that is a list of them over one session, answers that refuse without failing, and a loopback HTTP transport. Plain Dart |
| [`packages/flutter3d_mesh`](packages/flutter3d_mesh) | The mesh a modeller edits, with the topology still in it: faces of any valency, half-edges that know their twin, and the operations that change them. Plain Dart. [README](packages/flutter3d_mesh/README.md) |
| [`packages/flutter3d_model_core`](packages/flutter3d_model_core) | The headless half of the model editor: the project of objects, the sealed command every edit is one of, the history that takes them back, what it refuses to export, and the rig algorithms it runs: bone-name mapping, retargeting with a foot lock, automatic skin weights |
| [`packages/flutter3d_model_mcp`](packages/flutter3d_model_mcp) | The same modeller offered to an agent, over MCP on stdio: 147 editing tools, each one of the editor's own commands, and `render`, which hands the agent a picture of what it did |
| [`packages/flutter3d_sim_mcp`](packages/flutter3d_sim_mcp) | A level an agent can play without seeing it, and a second server that says why a frame is wrong: one pixel's HDR value, the passes that ran, a scan for NaN |
| [`packages/flutter3d_sim`](packages/flutter3d_sim) | The simulation with no Flutter in it: the fixed step, the level format, entities, navigation, saves, replays and the portable arithmetic that makes a run reproduce on another machine |
| [`packages/flutter3d_net`](packages/flutter3d_net), [`flutter3d_net_webrtc`](packages/flutter3d_net_webrtc) | Rollback netcode for two peers over `flutter3d_sim`, with the network behind one interface, and that interface over a WebRTC data channel |
| [`packages/flutter3d_build`](packages/flutter3d_build) | The build hook: model and texture sources converted into what the engine loads, on every build, with a content-hash cache |
| [`packages/flutter3d_lab`](packages/flutter3d_lab) | Virtual laboratory simulations a server can replay with no Flutter SDK. The pendulum is the first |
| [`apps/flutter3d_demo_dungeon`](apps/flutter3d_demo_dungeon) | The shooter, and a headless test that plays it to the exit. Desktop, web, Android and iOS |
| [`apps/flutter3d_demo_platformer`](apps/flutter3d_demo_platformer) | The second game: third person, two jumps and a dash, and no line of the engine changed to allow it. Desktop, web, Android and iOS |
| [`apps/flutter3d_demo_racing`](apps/flutter3d_demo_racing) | The third game: a circuit, three rivals and the lap you drove before, drawn beside the one you are driving |
| [`apps/flutter3d_demo_strategy`](apps/flutter3d_demo_strategy) | A map, two sides and a match played to a finish, with a headless test that plays the recording back. Desktop, web, Android and iOS |
| [`apps/flutter3d_editor`](apps/flutter3d_editor) | A level editor that reads the same documents the games do, and writes projects from templates |
| [`apps/flutter3d_modeler`](apps/flutter3d_modeler) | The model editor: mesh editing, materials and a texture graph, UV, sculpting, retopology, texture painting, rigging and animation, simulation and LOD over one project document, with undo that records who made each change. On macOS and in a browser, where it is <https://models.pleion.dev> |
| [`apps/flutter3d_lesson_viewer`](apps/flutter3d_lesson_viewer), [`flutter3d_stereo_lesson_viewer`](apps/flutter3d_stereo_lesson_viewer), [`flutter3d_lab_pendulum`](apps/flutter3d_lab_pendulum) | The lessons: a level document with steps in it, played flat or as a stereo pair, and the pendulum laboratory a student runs |
| [`packages/flutter3d_app/example`](packages/flutter3d_app/example) | The smallest application on the engine: a lit cube you can turn. What a project that is not a game starts from |
| [`packages/flutter3d_game/example`](packages/flutter3d_game/example) | A level you can walk around, with no genre in it: what a new game starts as, and the source the editor's templates are generated from |
| [`packages/flutter3d/example`](packages/flutter3d/example) | The engine's own demo: a model browser with every feature switchable |

The package boundaries carry weight. `flutter3d_sim` depends on neither
`flutter3d` nor Flutter, because simulation, input and collision have nothing to
say about how a frame is drawn. The same cut runs the other way, and a genre is
a package too. `flutter3d_game_shooter` holds what only a shooter wants, so a
platformer or a racing game inherits none of its vocabulary, and three of the
scans in `tool/structure.dart` enforce that rather than leaving it to habit.
This split is what lets a plain unit test reach the parts that fail quietly: a
collision that passes through a wall once in a thousand steps, a jump that is a
different height on a faster monitor, a press swallowed at a low frame rate.
`flutter3d_app` is where a level meets the renderer for any application, and
`flutter3d_game` is where a game's simulation does; an application supplies only
what its own game looks like.

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

# The second bundle: the one the engine demo loads at runtime rather than links.
# The demo's pubspec declares it as an asset, so without this the demo and the
# golden set stop at "No file or variants found for asset" before anything runs.
(cd packages/flutter3d/example && ./tool/build_shaders.sh)

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
A build that wants WebGPU instead asks for it with
`--dart-define=FLUTTER3D_WEBGPU=true`, and the probe falls back to WebGL2 where
the browser has no adapter to give. WebGPU is off by default for two reasons. A
build that can try both backends ships both, which costs 376,649 bytes of
`main.dart.js` measured on the strategy demo. And WebGL2 is the browser backend
three shipped games have been looked at on.

```bash
(cd apps/flutter3d_demo_dungeon && flutter run -d chrome)

# What the demos are published as. --wasm builds the JavaScript output beside
# the WebAssembly one and the loader picks; the games are the one thing here
# that spends its frame budget in Dart rather than in a driver.
(cd apps/flutter3d_demo_dungeon && flutter build web --wasm --release)
```

Flutter GPU and Impeller are enabled per application through `Info.plist`,
so every app in this repository sets `FLTEnableFlutterGPU` and
`FLTEnableImpeller` for itself. A new one that skips them fails to initialise
the shader library and renders nothing. Neither setting means anything to a
browser build, which reaches WebGL2 through `flutter3d_app` instead.

## Tests

```bash
tool/ci.sh          # everything a machine can check: shaders, analyze, all tests
```

Or one package at a time:

```bash
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test)   # plain Dart, no Flutter needed
```

There are 10533 tests across thirty-eight packages and nine applications. The
only ones that need a GPU are the Impeller half of the golden set. The other
half is rendered by the software backend, which is what makes 78 scenes
checkable in a headless run.

Several steps run in a browser. `flutter test --platform chrome` covers the two
web backends, `flutter3d_app`'s browser half and the browser half of
`pointer_lock`, and one step compiles a game to WebAssembly, since a platform
counts as supported here only if its build actually runs. The WebGPU backend
gets something from this that no other backend does: Chrome has a real WebGPU
device inside `flutter test`, so the WebGPU conformance run is a test rather
than an application somebody watches.

[ARCHITECTURE.md](ARCHITECTURE.md), section 13, describes how the tests are
written: three complete independent golden sets rather than one, a fourth
part-recorded for WebGPU, and why every new test is written by breaking the
thing it covers.

## Channel

The repository builds on Flutter 3.47.0 stable, and the list of what that
channel costs has kept getting shorter. Mip levels and instancing both arrived,
and both are now used: a mip chain is built on the CPU and uploaded level by
level because `flutter_gpu` has no `generateMipmap`, and instanced draws carry
mesh particles. Rendering into a mip level came with them. `ColorTarget.mipLevel`
names a face and a level, and the environment map is prefiltered through it.
Compressed pixel formats are here too: the BC, ETC2 and ASTC families are in
`TextureFormat`, every backend answers `supportsTextureFormat` for itself, and
a KTX2 that arrives is read. No asset in this repository ships a compressed
texture, though, because `dart run flutter3d_build:convert` has no encoder to
make one. That gap is upstream of the engine, not in it.

One entry is left on the list: compute passes, and with them GPU particles,
GPU skinning, GPU culling and indirect draw. It is recorded in
[ARCHITECTURE.md](ARCHITECTURE.md), section 2, and it is still the reason
several things are built the way they are rather than the obvious way.

The upgrade also fixed `setDepthWrite(false)`, which did nothing until 3.47.
Before that, additive particles occluded each other on two backends out of
three, and the software backend mirrored the bug on purpose so the two would
stay comparable. `ARCHITECTURE.md` §7 keeps that story because the lesson still
applies.

### Editing a shader

A stale bundle fails with `failed to bind texture`, not with a shader behaving
oddly. The renderer binds a slot that the new GLSL declares and the compiled
binary has not got, and binding a slot a compiled shader does not have takes
the frame down. The message names nothing that leads back to the file that was
edited.

So `dart run tool/structure.dart` checks it: one of its thirty-five rules compares
the bundle against the sources it was built from and says which of them are
newer. The rule skips when there is no bundle at all, which is every fresh
checkout and every CI run. `impellerc` is not there to build one, and a rule
demanding it would be red on the machines least able to do anything about it.

Both web backends work the other way and need no such rule: their translations
are checked in, and CI regenerates each and fails on the diff. The WebGPU
translation takes a longer route, from the same GLSL through `glslangValidator`
and then `naga` into WGSL, so the diff also catches a different compiler on the
machine.

## Skills for whatever is writing the code

Every package here ships agent skills: what its API is for, the mistakes it has
already paid for, and the boundaries a scan holds it to. A project that depends
on any of them installs the ones it wants:

```bash
dart run skills@ get          # reads the skills/ of every dependency
```

They travel in the published archive, so an agent working in your game reads
them where it looks rather than out of a version-stamped pub cache directory it
has no way to name. Each skill directory is named for the package it comes from,
which the [`skills`](https://pub.dev/packages/skills) CLI requires and a
structure rule here checks. A skill directory named otherwise is installed for
nobody, and nothing reports it.

## Contributing

The conventions here differ from the usual ones. Tests are written by breaking
the thing they cover, architecture is held by scans rather than by review, and
levels, models and templates are generated rather than edited. All of it is in
[CONTRIBUTING.md](CONTRIBUTING.md), and `bash tool/ci.sh` is the contract.

- [CONTRIBUTING.md](CONTRIBUTING.md): how to build, test and send a change
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): Contributor Covenant 2.1
- [SECURITY.md](SECURITY.md): report privately, not in an issue
- [ARCHITECTURE.md](ARCHITECTURE.md): how the system is put together, and why

## Licence

MIT. See [LICENSE](LICENSE).

Third-party assets keep their own terms, recorded beside them in `LICENSES.md`
with author, source, licence and what was changed. Everything shipped today is
CC0 or generated in this repository.
