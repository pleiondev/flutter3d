## 0.6.0

* **The scaffold, and nothing else.** `ap-02` in `doc/asset-pipeline-plan.md`:
  a plain Dart package, `flutter3d_formats` and `flutter3d_geometry` for the
  decoders a hook will convert through, `package:hooks` for the contract
  `ap-00`'s spike proved works on macOS, web, Android and iOS without
  `package:data_assets`, which stays experimental on stable. No exports yet —
  those arrive with `ap-03` through `ap-05`.
* **A project stops carrying its own converter.** `dart run
  flutter3d_build:convert` (`ap-03`) turns a glTF/OBJ/STL source into the
  engine's `.f3d`, with `--textures auto|bc|etc2|none` and `--target`
  resolving it to the family a platform actually wants (`ap-09`); a
  `flutter3d_assets.yaml` manifest overrides a rule per glob, last match wins
  (`ap-04`); `buildAssets` runs the same conversion as a build hook, cached
  by content hash so a second build with nothing changed converts nothing
  (`ap-05`); and `dart run flutter3d_build:init` (`ap-10`) writes the four
  things a project needs to wire the hook in — `hook/build.dart`, the
  `pubspec.yaml` entries, `.gitignore` — idempotently, honouring a hook a
  person has edited unless told `--force`.
* **Round-tripped against the real Khronos sample set, not a synthetic
  document.** `ap-13`: eleven files `flutter3d_samples` ships credited to
  `KhronosGroup/glTF-Sample-Assets` — animation, skinning and morph targets
  included — decode, convert and decode back byte-identical, per
  `compareModelDocuments`.
* **Honestly not yet automatic:** the build hook itself cannot pass
  `--target` (`package:hooks` has no way to name a platform without
  `package:code_assets`, rejected as experimental), so a hook-driven build
  ships uncompressed textures with `ap-08`'s mip chain on top — a real
  weight, not a saving, until a build-driven build knows its own target.
  See [the asset pipeline](https://flutter3d.pleion.dev/reference/asset-pipeline/)
  for the current shape end to end.
