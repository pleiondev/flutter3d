# flutter3d_build

The build hook behind a [flutter3d](https://flutter3d.pleion.dev) project's
assets. It converts model and texture sources into what the engine loads, and
it does so on every build, so nobody has to remember to run a separate step.

```sh
dart pub add dev:flutter3d_build
dart run flutter3d_build:init          # hook/build.dart, pubspec, .gitignore
dart run flutter3d_build:init --check  # say what a run would change, change nothing
```

After that, anything under `assets_src/` is converted into
`flutter3d_generated/` at the same relative path whenever the project builds,
and a second build with nothing changed converts nothing. A
`flutter3d_assets.yaml` beside the pubspec excludes files by glob.

The hook compresses textures for the platform it is building for: BC for a
desktop target, ETC2 for Android and iOS. A block format is a property of the
platform, so the hook does not have to guess about the device. A web build
names no target and is left alone. Setting `textures:` under the project's own
name in its `hooks: user_defines:` overrides either choice. The value
`universal` there is the one family every device can load; it is turned into
BC, ASTC, ETC2 or RGBA8 when the texture is uploaded.

## Materials

A material written in the material language goes under `assets_src/` with the
extension `.f3dmat`, next to the models that wear it. The hook compiles
`assets_src/fx/rim.f3dmat` into `flutter3d_generated/fx/rim.f3dshaders`: one
shader bundle with a fragment stage named after the material, carrying an
Impeller section, a WebGL2 section and, when `glslangValidator` and `naga` are
on `PATH`, a WebGPU section. Load it with `GraphicsDevice.loadShaders`.
Compiling happens only here, at build time. A mistake fails the build with the
material's file, line and column. A manifest rule's `glob` and `exclude` apply
to materials as well.

The same converter can be run by hand:

```sh
dart run flutter3d_build:convert assets_src/chair.glb --textures universal
```

## Plain Dart

The Flutter tool starts `hook/build.dart` as a separate process, with no window
and no Flutter SDK to resolve inside it. None of this package's dependencies
(`flutter3d_core`, `package:hooks`, `package:code_assets` and a few plain-Dart
libraries) names Flutter, because a hook that needed the SDK would not start on
a machine that does not have it.
