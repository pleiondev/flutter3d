## 1.0.0-rc.1

- **`FormatSpecs`, the formats one program knows.** A registry the
  packages that own formats add their `FormatSpec`s to, found by id, alias
  or the longest suffix of a path; a second format under a taken id or
  alias is refused. `flutter3d migrate --data` and `doctor` walk a project
  with it.
- **`ShaderCompileException` and `AssetNotFoundException`**, the two
  failures every backend and loader share. The first, a
  `Flutter3dFormatException`, names the `shader` (or the pair a linker
  refused), the `backend` and the compiler's `log`; the second, a
  `ResourceException`, names the asset's `key` with an optional `detail`,
  and keeps the platform's own failure as its `cause`.
- **`FormatSpec.open` refuses a version below 1**, saying `"version"
  counts from 1`; `versionOf` returns the 0 or negative number the document
  holds where it used to answer 1.

- **The first release: the types every package shares, in a package of
  their own.** `Flutter3dException` and its four families,
  `DocumentFormatException`, `WorldPosition`, `LinearColor`, `Issue` and
  `IssueSink`, `FormatSpec`, `FormatDocument`, `FormatMigration`,
  `FormatRefusal` and `Registration` come from `flutter3d_plugin_api`, which
  re-exports them, so nothing written against it changes. The crossings
  into `vector_math` (`WorldPositionVector`, `Vector3Foundation`,
  `Vector4Foundation`, `LinearColorVector`) and `Portable` come from
  `flutter3d_physics`, which no longer exports them; `flutter3d_sim` and
  `flutter3d_core` still do. It depends on `vector_math` only, so the hardware
  layer, the shaders and the backends no longer need the plugin API to throw
  or to read a file.
- **`PlacedEvent`**, the shape of an event that says where it happened,
  comes from `flutter3d_particles`, so the elements' simulation can
  publish a placed event without depending on what draws it.
