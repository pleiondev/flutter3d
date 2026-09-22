## 0.7.0

* **The first publication.** The 0.6.0 below was a number carried inside the
  workspace and never reached pub.dev, and it describes a scaffold with no
  exports. 0.7.0 is the number the whole shelf goes out on, so one number names
  one tree and `^0.7.0` on any `flutter3d_*` package resolves against every
  other; `doc/boundary-0.7.0.md` lists the thirteen packages that begin here.
  What follows is what the scaffold was filled in with. The package is plain
  Dart: it depends on `flutter3d_core` for the decoders and encoders, on
  `hooks` and `code_assets` for the build-hook contract, and on `glob`, `yaml`,
  `crypto` and `image`.
* **`dart run flutter3d_build:convert <model-or-directory>`.** Converts a glTF,
  GLB, OBJ or STL model into the engine's `.f3d` container, and a directory
  converts every recognised model under it. `-o` names the output file or
  directory, and `--textures` takes `auto`, `bc`, `etc2`, `universal` or
  `none`. `bc` writes BC1 for an opaque image and BC3 for one with alpha.
  `etc2` writes ETC2 RGB8 and leaves an image with alpha as it arrived, saying
  so, because the EAC alpha block is not encoded. An image whose sides are not
  multiples of four is left as it arrived too. `runConvert`, `convertOne`,
  `ConvertOptions`, `TextureFamily` and `encodeDocumentTextures` are the same
  from Dart. `TextureFamily` is a final class with static constants and not an
  enum, so a `switch` over one needs a default.
* **`buildAssets(input, output)` is the build hook.** A project's
  `hook/build.dart` calls it. With no configuration everything under
  `assets_src/` is converted into `flutter3d_generated/` at the same relative
  path with the extension `.f3d`, which is `AssetLayout.plan`. A
  `flutter3d_assets.yaml` overrides that per glob through `AssetManifest`: the
  texture family, `mips`, how an OBJ without normals gets them, or `exclude`,
  with the last matching rule winning, and a `ManifestFormatException` names
  the line. The glob `**/*.obj` does not match a file directly under
  `assets_src/`; `**.obj` matches both.
* **A source is converted again when its content changed, and not when its
  date did.** `runAssetBuild` keeps a cache of a content hash per source with
  the texture family that wrote the output and two version stamps,
  `kAssetPipelineVersion` and the `.f3d` format's own, and any of the four
  moving converts the file again. A cache that cannot be read converts
  everything. `AssetBuildReport` lists what was `converted`, what was `skipped`
  and the `dependencies` the hook declares, so the next build is asked for when
  one of them changes.
* **The hook picks the texture family from the platform it builds for.**
  `familyForTargetOS` answers `bc` for macOS, Windows and Linux, `etc2` for
  Android and iOS, and `auto`, which converts no texture, for anything else,
  the web included. A `textures:` value under this package's key in the
  project's `hook_user_defines` comes first. The target is read only when the
  build input carries a code configuration.
* **A compressed texture carries a mip chain.** Each level is a box filter of
  the one above in the channel's stored values, down to the last level that is
  whole 4x4 blocks: a 64-pixel image gets five levels and a 12-pixel one gets
  one.
* **`--textures universal` cooks one texture for every device.** It writes a
  4x4 block intermediate of `kUniversalBlockBytes`, twenty, bytes a block that
  is not a GPU format, and `flutter3d_core`'s upload turns it into BC1, BC3,
  ASTC 4x4, ETC2 or RGBA8 against what the device says it samples. A project
  that ships to desktop and phone from one build sets it in
  `hook_user_defines`.
* **`--no-mips` skips something.** It was accepted and answered with a note,
  because nothing generated a chain to skip; every compressed family has since
  learned to write one. `convertOne` and `encodeDocumentTextures` take
  `mips:`, and with it false a texture keeps its base level alone — `bc`,
  `etc2` and `universal` alike. The note `--textures auto` prints, and the
  usage text, stop promising a per-target choice the converter was never going
  to make: a build hook is told its target and resolves `auto`, a command line
  names a family, and `universal` is the one that needs no target at all.
* **A project stops needing a person to wire up its own build hook.**
  `dart run flutter3d_build:init` (`ap-10`) writes the four things the hook
  needs — `hook/build.dart`, a `dev_dependencies:` line on this package, the
  `flutter: assets:` entries for the generated directory, and a `.gitignore`
  line for it — each idempotent on its own, so a second run is an empty diff.
  `--check` reports what a run would change and changes nothing; a
  `hook/build.dart` somebody edited is reported and left alone without
  `--force`. **One `assets:` entry per generated subdirectory, not one for the
  root:** Flutter bundles a declared directory without recursing, so a single
  `flutter3d_generated/` line ships the hook's own cache file and silently
  drops every model converted under `models/`.

## 0.6.0

* **The scaffold, and nothing else.** `ap-02` in `doc/asset-pipeline-plan.md`:
  a plain Dart package, `flutter3d_formats` and `flutter3d_geometry` for the
  decoders a hook will convert through, `package:hooks` for the contract
  `ap-00`'s spike proved works on macOS, web, Android and iOS without
  `package:data_assets`, which stays experimental on stable. No exports yet —
  those arrive with `ap-03` through `ap-05`.
