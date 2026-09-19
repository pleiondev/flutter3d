# flutter3d_build

The build hook behind a [flutter3d](https://flutter3d.pleion.dev) project's
assets: converts model and texture sources into what the engine loads, on
every build rather than as a step somebody remembers to run.

```sh
dart pub add dev:flutter3d_build
dart run flutter3d_build:init          # hook/build.dart, pubspec, .gitignore
dart run flutter3d_build:init --check  # say what a run would change, change nothing
```

After that, anything under `assets_src/` is converted into
`flutter3d_generated/` at the same relative path whenever the project builds,
and a second build with nothing changed converts nothing. A
`flutter3d_assets.yaml` beside the pubspec excludes files by glob.

**The hook compresses textures for the platform it is building for** — BC for
a desktop target, ETC2 for Android and iOS — because a block format is a fact
about the platform rather than a guess about a device. A web build names no
target and is left alone; `textures:` under the project's own name in its
`hooks: user_defines:` overrides either, and `universal` there is the one
family every device can load, turned into BC, ASTC, ETC2 or RGBA8 when the
texture is uploaded.

The same converter runs by hand:

```sh
dart run flutter3d_build:convert assets_src/chair.glb --textures universal
```

**Plain Dart.** `hook/build.dart` is started by the Flutter tool as a
separate process with no window and no Flutter SDK to resolve inside
it — nothing this package depends on (`flutter3d_core`, `package:hooks`,
`package:code_assets` and a few plain-Dart libraries) names Flutter, because a
hook that needed the SDK would not start on any machine that has not got it.
