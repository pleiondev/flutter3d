## Unreleased

* **`--no-mips` skips something.** It was accepted and answered with a note,
  because nothing generated a chain to skip; every compressed family has since
  learned to write one. `convertOne` and `encodeDocumentTextures` take
  `mips:`, and with it false a texture keeps its base level alone — `bc`,
  `etc2` and `universal` alike. The note `--textures auto` prints, and the
  usage text, stop promising a per-target choice the converter was never going
  to make: a build hook is told its target and resolves `auto`, a command line
  names a family, and `universal` is the one that needs no target at all.

## 0.6.0

* **The scaffold, and nothing else.** `ap-02` in `doc/asset-pipeline-plan.md`:
  a plain Dart package, `flutter3d_formats` and `flutter3d_geometry` for the
  decoders a hook will convert through, `package:hooks` for the contract
  `ap-00`'s spike proved works on macOS, web, Android and iOS without
  `package:data_assets`, which stays experimental on stable. No exports yet —
  those arrive with `ap-03` through `ap-05`.
