## 1.0.0-rc.1

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
