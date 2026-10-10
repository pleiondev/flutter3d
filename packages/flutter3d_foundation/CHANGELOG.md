## 1.0.0-rc.1

- **`Unit` and `Quantity`: a unit is a vector of dimension exponents and
  a scale.** SI's seven bases and the angle, so a lumen is not a candela
  and rad/s is not a hertz. Two units are equal when they measure the same
  dimension at the same size, whatever their symbols, so `N·m` is a joule.
  `Unit.parse` reads products, quotients, powers and SI prefixes (`kPa`,
  `J/(kg·K)`, `m/s²`, `s^-1`), and `toJson`/`fromJson` write the symbol
  where it reads back and the whole unit where it does not, so a base this
  build does not name survives. `Quantity` converts between units of one
  dimension (offsets included, so 20 °C is 293.15 K) and throws
  `UnitMismatchException` across dimensions; text that is not a unit is a
  `UnitFormatException`. The parameter schemas, the expression language,
  the probes and the property laws all take this one type.
- **`ShaderCompileException` says where.** It gains `stage`, `target` (the
  bundle section, `webgl` or `webgpu`), `line`, `column` and `excerpt`, or a
  list of `ShaderDiagnostic`s, each with its own place, and `toJson` for a
  tool. `ShaderDiagnostic.parseLog` reads GLSL's `ERROR: 0:12:` and the
  `file:14:7: error:` of glslang, Tint and Naga. The constructor of before
  still works.
- **`UnsupportedCapability` and `Capability` are here**, so the core and
  the platforms refuse what they lack the way a device does. The refusal
  came from `flutter3d_hardware`; its `feature` is now a `Capability`, which
  `DeviceFeature` extends, and the sentence's "ask first" comes from
  `Capability.askedBy`.

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
