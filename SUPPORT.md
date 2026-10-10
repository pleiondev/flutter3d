# Support

What flutter3d runs on, how well each combination is looked after, and which
releases get fixes. From 1.0.0 the packages follow strict semver; the reasons
behind each promise here are in
[`tasks/1.0-stability.md`](tasks/1.0-stability.md), and the rules a change to
the API is held to are in [CONTRIBUTING.md](CONTRIBUTING.md#the-api-is-a-snapshot).

`dart run tool/structure.dart` checks this file against the tree: every
published pubspec declares `platforms:`, the table of packages below says the
same thing each pubspec says, and every package that implements
`GraphicsDevice` is named here as a backend.

## Platforms and backends

Four levels, and the difference between the first two is whether a machine
checks it on every push:

- **CI**: tested on every push by `.github/workflows/ci.yml` or `tool/ci.sh`.
  A regression fails the build.
- **Supported**: works and is fixed in a patch when it breaks, but what
  proves it is a person with a device, not CI. CI may still build it.
- **Best effort**: built, and expected to work, with nobody having played
  it yet. A report is welcome and a fix may wait for a minor.
- **No**: does not work, or does not exist on that platform.

| Platform | Impeller (Metal) | Impeller (Vulkan) | Impeller (OpenGL ES) | WebGL2 | WebGPU | CPU |
|---|---|---|---|---|---|---|
| macOS | Supported | No | No | | | Supported |
| iOS | Best effort | No | No | | | Best effort |
| Android | No | Supported | Best effort | | | Best effort |
| Windows | No | Best effort | Best effort | | | Best effort |
| Linux | No | No | No | | | CI |
| Web (Chrome) | | | | CI | Supported | Best effort |
| Web (Safari, Firefox) | | | | Best effort | Best effort | Best effort |

A blank cell is a backend that cannot exist there: Impeller is not in the
browser, and the browser APIs are not on a native platform.

**The backends are packages.** Impeller is `flutter3d_impeller`, WebGL2 is
`flutter3d_webgl`, WebGPU is `flutter3d_webgpu` and the software rasteriser is
`flutter3d_cpu`. The engine names none of them (a structure rule holds that),
and `flutter3d_conformance` runs one suite against each.

What sits behind each level:

- **macOS, Metal.** The golden sets are recorded and compared here through
  `packages/flutter3d/tool/golden.sh`, by hand, on a Mac with a GPU. CI's
  `macos` job resolves, analyses and runs the structure scan, and its `pacing`
  job plays a recorded run through Impeller and fails on a frame over 50 ms;
  that job reports and does not block yet, because no hosted runner has shown
  it can drive the GPU.
- **iOS, Metal.** CI builds four demos with `flutter build ios --no-codesign`.
  They run clean in the simulator; no physical device has run them.
- **Android, Vulkan.** CI builds four demos as APKs. The platformer has been
  played on a Galaxy A55, where Impeller chose Vulkan by itself. Impeller's
  OpenGL ES fallback has not run on a real device; on OpenGL ES 2 mipmaps and
  wireframe are missing, and the device says so through `features`.
- **Windows.** CI builds the five games and the editor, and runs the native
  physics core's tests under MSVC. Nobody has played a game on Windows yet.
- **Linux.** Every test suite in the repository runs here, and the `render`
  job draws every golden scene through the CPU backend under Xvfb. Impeller
  does not draw on Linux yet: the embedder keeps Flutter GPU off unless the
  runner passes `--enable-flutter-gpu`, and with it on, Impeller's OpenGL ES
  backend refuses the shaders that read `gl_VertexID`. A Linux game draws
  through the CPU backend until that is fixed.
- **Web, WebGL2.** `flutter test --platform chrome` runs the conformance suite
  and the parity comparison in headless Chrome, and CI builds the dungeon demo
  with `--wasm`.
- **Web, WebGPU.** The default backend of a browser build since 1.0.0, with
  WebGL2 as the fallback when no adapter is handed out. Its golden set is
  compared by hand in Chrome with a GPU. CI runs the same suite, but headless
  Chrome on the runner returns no adapter, so the suite declines there rather
  than drawing. That is why it is not marked CI.
- **CPU.** Plain Dart, so it runs wherever Dart does, and its output is the
  same bits on every machine: it uses only the arithmetic IEEE 754 rounds one
  way. It is marked CI only where CI runs it.

**The native physics core** (`flutter3d_physics_native`) is not a graphics
backend, but it is native code: CI tests it on Linux, on Windows under MSVC,
and in Chrome as WebAssembly under both dart2js and dart2wasm, with and
without threads.

## Packages and platforms

What each published package declares in its pubspec. Packages without `web`
run on Flutter's native platforms; most of the ones marked that way reach
`dart:io` or `dart:isolate` from a public library, and the comment above
`platforms:` in the pubspec says where.

| Package | Platforms |
|---|---|
| `flutter3d` | android, ios, linux, macos, web, windows |
| `flutter3d_app` | android, ios, linux, macos, web, windows |
| `flutter3d_audio` | android, ios, linux, macos, web, windows |
| `flutter3d_audio_core` | android, ios, linux, macos, web, windows |
| `flutter3d_build` | linux, macos, windows |
| `flutter3d_build_hooks` | linux, macos, windows |
| `flutter3d_camera` | android, ios, linux, macos, web, windows |
| `flutter3d_conformance` | android, ios, linux, macos, web, windows |
| `flutter3d_core` | android, ios, linux, macos, web, windows |
| `flutter3d_cpu` | android, ios, linux, macos, web, windows |
| `flutter3d_editor_core` | android, ios, linux, macos, web, windows |
| `flutter3d_editor_play` | linux, macos, windows |
| `flutter3d_editor_widgets` | android, ios, linux, macos, web, windows |
| `flutter3d_education` | android, ios, linux, macos, web, windows |
| `flutter3d_effects` | android, ios, linux, macos, web, windows |
| `flutter3d_elements` | android, ios, linux, macos, web, windows |
| `flutter3d_foundation` | android, ios, linux, macos, web, windows |
| `flutter3d_game` | android, ios, linux, macos, web, windows |
| `flutter3d_game_kit` | android, ios, linux, macos, web, windows |
| `flutter3d_game_physics` | android, ios, linux, macos, web, windows |
| `flutter3d_game_platformer` | android, ios, linux, macos, web, windows |
| `flutter3d_game_racing` | android, ios, linux, macos, web, windows |
| `flutter3d_game_shooter` | android, ios, linux, macos, web, windows |
| `flutter3d_game_strategy` | android, ios, linux, macos, web, windows |
| `flutter3d_game_ui` | android, ios, linux, macos, web, windows |
| `flutter3d_hardware` | android, ios, linux, macos, web, windows |
| `flutter3d_impeller` | android, ios, linux, macos, windows |
| `flutter3d_level_scene` | android, ios, linux, macos, web, windows |
| `flutter3d_lints` | linux, macos, windows |
| `flutter3d_matter` | android, ios, linux, macos, web, windows |
| `flutter3d_mcp` | android, ios, linux, macos, windows |
| `flutter3d_mesh` | android, ios, linux, macos, web, windows |
| `flutter3d_model_core` | android, ios, linux, macos, windows |
| `flutter3d_net` | android, ios, linux, macos, web, windows |
| `flutter3d_net_webrtc` | android, ios, linux, macos, web, windows |
| `flutter3d_particles` | android, ios, linux, macos, web, windows |
| `flutter3d_physics` | android, ios, linux, macos, web, windows |
| `flutter3d_physics_native` | android, ios, linux, macos, web, windows |
| `flutter3d_plugin_api` | android, ios, linux, macos, web, windows |
| `flutter3d_plugin_runtime` | android, ios, linux, macos, web, windows |
| `flutter3d_post` | android, ios, linux, macos, web, windows |
| `flutter3d_samples` | android, ios, linux, macos, web, windows |
| `flutter3d_shaders` | android, ios, linux, macos, windows |
| `flutter3d_sim` | android, ios, linux, macos, web, windows |
| `flutter3d_sim_mcp` | linux, macos, windows |
| `flutter3d_stereo` | android, ios, linux, macos, web, windows |
| `flutter3d_testing` | android, ios, linux, macos, windows |
| `flutter3d_voxel` | android, ios, linux, macos, web, windows |
| `flutter3d_webgl` | web |
| `flutter3d_webgpu` | web |
| `flame_flutter3d` | android, ios, linux, macos, web, windows |
| `flame_flutter3d_audio` | android, ios, linux, macos, web, windows |
| `flame_multiplayer` | android, ios, linux, macos, web, windows |
| `flame_multiplayer_dashwire` | android, ios, linux, macos, web, windows |
| `pad_input` | android, ios, linux, macos, web, windows |
| `pointer_lock` | linux, macos, web, windows |

The desktop-only packages are tools for the machine a game is made on: the
build hook, the MCP servers an agent starts over stdio, the editor's Play
button, and the lints the analysis server runs. A game for a phone still uses
them while it is built; they never ship inside it.

## Versions

**Strict semver from 1.0.0.** A patch fixes bugs and adds nothing that
breaks. A minor adds. A break comes only in a major, after a deprecation.
Every public name is covered, with no experimental exceptions, and the
snapshot in each package's `api/` is what a release is compared against.

**The engine ships under one number.** The 49 packages of the shelf
carry the same version, now the release candidate `1.0.0-rc.1`, and ask for
`^1.0.0-rc.1` of each other. Among them are the packages the candidate
brings: the game parts (`flutter3d_game_kit`, `flutter3d_game_physics`,
`flutter3d_game_ui`, `flutter3d_camera`), `flutter3d_build_hooks`, the post-processing families (`flutter3d_post`), the
foundation types every package shares (`flutter3d_foundation`), what a world
is made of (`flutter3d_matter`), the elements' simulation out of the effects
(`flutter3d_elements`), and
`flutter3d_mcp` and `flutter3d_education`, which took in five packages of
the 0.8 shelf. That constraint
admits the final 1.0.0 too, so it stays when 1.0.0 follows. The candidate
already keeps the promise above. The interface
packages keep lines of their own that break more rarely than the engine:
`flutter3d_plugin_api` (1.0.0-rc.1), `flutter3d_hardware` (on the shelf's number
for now) and the file format schemas. Wasm plugin ABI 1 (`wasmPluginAbi` in
`flutter3d_plugin_runtime`) is numbered on its own as well: a module states
the ABI it was written for, and only a change to what a module may import or
export moves it. `pad_input`, `pointer_lock`,
`flame_multiplayer` and `flame_multiplayer_dashwire` were never on the shelf
and keep their own lines below 1.0.

**Which releases get fixes:**

- The newest minor gets every fix, as a patch.
- The minor before it gets fixes for crashes, data loss and security
  problems for three months after its successor is released.
- One minor a year is a long-term support (LTS) release, and gets those same
  fixes for 18 months from its release. Its CHANGELOG says so when it ships,
  and this file lists it. None is named yet.
- A major before the current one gets nothing once its last LTS window
  closes.

**Deprecations.** A deprecated name stays until the next major, and at least
six months after the release that deprecated it: a major that comes sooner
keeps the name. Each `@Deprecated` names the version it came in, the major it
goes in, and its replacement, and a structure rule checks the wording.

## The Flutter and Dart SDKs

- **The floor** every pubspec declares is Dart `>=3.12.0 <4.0.0` and, where a
  package names Flutter, `flutter: '>=3.44.0'`. A structure rule keeps every
  package on the same floor.
- **What CI runs** is Flutter 3.47.0 on the stable channel, and Dart 3.13.0
  with no Flutter for the plain Dart packages (the `flat-dart` job). The
  workspace resolves against one lock file, so the declared floor itself is
  not exercised.
- **Supported** is the Flutter stable CI runs and every stable release after
  it within the same Flutter major. A new Flutter stable is taken into CI in
  the next minor at the latest.
- **Raising the floor** is a minor, never a patch, with the one exception
  below.

## Flutter GPU

`flutter_gpu` is reached only from `flutter3d_impeller`. The hardware layer
and the engine name no graphics API, and structure rules hold both. When a
Flutter release changes `flutter_gpu`, the repair is a patch of
`flutter3d_impeller`, and no other package's API changes. If that repair
cannot compile against the older Flutter, the patch raises
`flutter3d_impeller`'s own Flutter floor, which is the one exception to the
rule above, and its CHANGELOG says so.

A capability Impeller does not have yet is in the hardware interface anyway.
The Impeller device leaves it out of `features`, and a call to it throws
`UnsupportedCapability`. When Flutter GPU gains it, it is filled in without a
change to the API.
