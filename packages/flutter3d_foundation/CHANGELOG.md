## 1.0.0-rc.1

- **`internal.dart` is outside semver, and the engine's packages ask for
  each other within one minor** (`'>=1.0.0-rc.1 <1.1.0'`), so a minor that
  changes the parser never resolves under a core built before it.
- **`ExpressionType.measuring` takes `components:` and
  `ExpressionParser.fail` `where:` by name**, so either can gain an option
  beside it.
- **Breaking: a crash reporter takes one `CrashContext`.** A
  `CrashReporter` is handed a `CrashContext` (new) with the `error`, its
  `stackTrace` and the `record` the log kept, so a minor can tell a
  reporter more without breaking one written against 1.0.
- **One severity, one kind of light and one pose for every package.**
  `Severity` (`note`, `warning`, `error`) is what a mesh check, an export,
  a level's validation and an `Issue` (new `severity:`, a warning unless
  said) report in. `LightType` moved here from the core, so a level, a
  modeller project and a model file hold the scene's kinds, `area` and a
  plugin's own among them. `RigidPose` (a position and an orientation,
  immutable, with `components` and `fromComponents`) is a tracked head,
  an XR pose, a ragdoll's bone and an element's body.
- **`ExpressionToken` takes `number:` by name**, so a token can carry more
  than its number in a minor.
- **`internal.dart` names the expression bytecode** (`ExpressionBytecode`
  and its version) for `flutter3d_physics_native`, whose C core runs it:
  still internal, not covered by semver for applications, its format
  versioned in its header.
- **The engine's expression language.** `parseExpression` reads text such
  as `1.8e-6 [Pa·s] * exp(1850 [K] / T)` or `T > 100 [°C] && p < 2 [bar]`
  into a typed `Expression` tree whose every node carries an
  `ExpressionType`: its components and the `Dimension` it measures, so a
  sum of a length and a time is refused where it is written. Numbers in a
  unit are kept in the coherent SI unit. `CompiledExpression` turns the
  tree into Dart closures once and runs it on `Portable` maths, the same
  bits on every platform, with values taken as `Quantity`s by name;
  `ExpressionCodec` writes the canonical text a document stores;
  `ExpressionVisitor` (with `visitUnknown`) is how a translator reads the
  tree. `ExpressionBuiltin` lists the functions, each with its unit rule;
  `Unit.coherent` names the coherent unit of a dimension.
- **`package:flutter3d_foundation/internal.dart`: what a host language
  stands on, outside the API.** `ExpressionParser`, the `base class` the
  material language extends, its `ExpressionToken`s and
  `tokenizeExpression`, and the operator arithmetic every evaluator shares
  (`applyExpressionOperator`, `broadcastExpressionArguments`). For the
  engine's own packages, as `flutter3d_shaders`' `internal.dart` is: a
  minor that grows the grammar may change them, so an application reads
  expressions through `parseExpression` and the types the main library
  names.
- **A refusal of bad bytes is still a `FormatException`.**
  `Flutter3dFormatException` implements it, so code that catches
  `on FormatException`, as 0.8 code does, keeps catching the engine's
  format refusals; `source` and `offset` are null unless a refusal knows
  them.
- **`UnsupportedCapabilityException`**, renamed from `UnsupportedCapability`
  so that what is thrown says so in its name, as every other exception of
  the engine does.

- **`PlacedEvent` is a `base mixin class`**: an event mixes it in beside
  the `BusEvent` it extends (`extends BusEvent with PlacedEvent`), and
  `direction` is null unless the event says otherwise.
- **`LinearColor.toSrgb()` returns an `SrgbColor`**, a final class with
  `r`, `g`, `b`, `a`, value equality and `toLinear()`, where it returned a
  record: the fields read as before, and a destructuring pattern names the
  class (`final SrgbColor(:r, :g, :b, :a) = color.toSrgb()`).
  `Portable.sinCos` and `WorldPosition.relativeTo` keep their records: a
  sine and a cosine, an offset's three components, maths that never grows.

- **`EngineLog`: what an engine says about itself, one log per engine.**
  Records at a `LogLevel` (`trace`, `debug`, `info`, `warning`, `error`, an
  open set with wire names) reach the listeners `listen` registers, and an
  error nothing caught goes through `reportCrash` to every `onCrash`
  reporter whatever the level, which is where a crash reporter is wired.
  No log is global, and none reads a clock unless it is handed one.
- **`FormatSpecs`, the formats one program knows.** A registry the
  packages that own formats add their `FormatSpec`s to, found by id, alias
  or the longest suffix of a path; a second format under a taken id or
  alias is refused. `flutter3d migrate --data` and `doctor` walk a project
  with it.
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
- **`UnsupportedCapabilityException` and `Capability` are here**, so the core and
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
