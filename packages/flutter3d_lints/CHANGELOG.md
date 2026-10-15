## 1.0.0-rc.1+1

- **The engine's number, outside the 1.0 promise.** Its signatures carry
  types of a package before 1.0 or of one that takes a major a year, so a
  release of that package may break this API in a minor, and the break is
  labelled here. SUPPORT.md names the four packages outside the promise;
  the number says which engine release this one goes with, and every pin
  the engine writes on it is the engine's own.

## 1.0.0-rc.1

- **Breaking: the rule classes are the package's own.**
  `StepReadsNoClock`, `StepTakesSeededRandom`, `StepUsesPortableMath`,
  `StepPrefixesDartMath`, `simulationRules()` and the plugin class
  `main.dart` registers them with are no longer exported: they extend
  classes of `analysis_server_plugin`, which is at 0.x, and a 1.x library
  naming them would break with its next minor. `flutter3d_lints.dart`
  exports `scanSimulationCode`, `SimulationFinding`, `SimulationRules` and
  `machineArithmetic`; the analyzer loads `main.dart`'s `plugin` as before.
- **A second pass changes nothing the first one wrote.** A callback a rule
  wraps, or a value it turns into a `Duration`, is left alone once it has
  the parameter's type; a hook's parameters rewritten whole win over a
  rename inside them, so the reads from the context are never written into
  a method that does not take it. A project named like one of the engine's
  packages (`flame_flutter3d_example`) has its own classes made `base`
  under a base class; a renamed class whose old name another engine
  package took since (`Unit`) is renamed as one `dart:core` shadows is; a
  record in a collection `for` or `if`, or a map's value, becomes the class
  it was typed as. A `rewrite` reaches a call of a field of a function type
  (`tool.run(session, arguments)`), and leaves a call with fewer arguments
  than its template reads, which is the new call already.
- **A hook that took nothing is migrated too.** A `hookContext` entry
  with no fields gives an override its new parameter and hands a call
  `const <Context>()`, which asks for nothing; `AssetSource.read` is the
  first.
- **The TODO stands where the error does.** A use further down a statement
  gets its TODO on the line above it; a gone function or class named as a
  value, each name of a gone library, each use of a name gone internal,
  each override of a type whose implementers have something to do, and
  each argument a changed call lost or now takes in another type, carry
  one. `--automatic` writes only what needs no person.
- **More is carried out with the resolved code.** A moved name is imported
  where a project reached it through its own re-export; a renamed member, a
  renamed named parameter, a class renamed under an import prefix, in a
  `show` or `hide`, or from a name the Dart SDK also has (`Match`); an
  implementer's declaration of a renamed member and its uses; a record built
  where the class it became goes (a return, a closure, a variable, an
  argument, a list); a renamed field of a record typedef; a call that
  became asynchronous, awaited in an `async` body (a test's callback, or a
  function that returns nothing, made `async` for it); a component read off
  a `LinearColor` the engine hands out (`.x` is `.r`).

- **A positional argument that became named is named for you.** `migrate`
  writes `settings: ` before the second argument of
  `AdaptiveQuality(table, s)`, and the same for each constructor whose
  optional positional arguments 1.0 made named (`AssetManifest`,
  `EnumHintValue`, `MaterialVariant`, `TraceDraw`, `ParticleGravity`).
  `dart fix` offers no fix for an extra positional argument, so this is
  where it happens. A call that passes the name as well keeps a TODO.
- **More of the move to 1.0 is written for you.** A colour passed as a
  `Vector3` or `Vector4` where 1.0 takes a `LinearColor` becomes one, as
  `LinearColor(r, g, b)` or `LinearColor.fromSrgb(r, g, b, a)` by how that
  colour was encoded, in an argument and in an assignment; a parameter
  that was renamed or changed its unit is rewritten (`arcDegrees: 100` to
  `arc: 100 * pi / 180`); a static member that is gone is rewritten through
  its class (`DesktopInput.defaultBindings()`); and a class renamed in a
  `const` creation, which `dart fix` cannot resolve, takes its new name. A
  value it cannot write once, and a read used as the old type, keep the
  TODO.
- **Code written against 0.8 is told what 1.0 changed, at each use.** Two
  more warnings come from the migration table:
  - `flutter3d_migrate` has a quick fix. It rewrites a deprecated capability
    getter on a `GraphicsDevice` into `features.has(...)` or `limits.…`,
    and turns `implements X` into `with X` on a `base` class, for the types
    1.0 made `base mixin class`es.
    It also moves named arguments that became an options object into it
    (`View3d(fov: 1)` to `View3d(view: ViewOptions(fov: 1))`), gives a
    `switch` over a type that stopped being an enum or sealed a wildcard
    that throws, reads `.$1` of a record that became a class through its
    getter, and turns a null check right beside a call that throws now into
    `try … on` the exception. The last two of those leave a TODO beside
    what they wrote, because a person decides what the new case or the
    caught exception does.
  - `flutter3d_migrate_by_hand` links the guide's line for a change a person
    has to make. A name 1.0 keeps to its package is reported once per
    import of that package, listing every such name the file uses, rather
    than at each use.

  Both use the resolved code, so a class of your own with a
  `supportsWireframe` is left alone. `dart fix` does not apply a plugin's
  fixes in bulk, so `dart run flutter3d_lints:migrate <project>` applies
  all of them across a project, puts a TODO above each use left for a
  person, and hides on a flutter3d import a name 1.0 started exporting
  that the project declares itself. `flutter3d_build:migrate` runs it.

- **A plugin's simulation code is held to the engine's rules.** Four
  analyzer rules, shipped as an analysis server plugin and enabled by
  listing the package under `plugins:` in `analysis_options.yaml`:
  `step_reads_no_clock`, `step_takes_seeded_random`,
  `step_uses_portable_math` and `step_prefixes_dart_math`. They are the
  rules `tool/structure.dart` holds this repository's packages to, put in
  the editor of anybody writing a step, because a replay is the same run
  only while every step computes the same thing on every machine.

- **Stronger than a text scan where a resolver can say more.** A
  transcendental is reported by what it resolves to, so a call through any
  prefix of `dart:math`, or through an unprefixed import, is found, and a
  class of the author's own named `Random` is not. A comment or a string
  that names a forbidden call is not reported.

- **Warnings, so enabling the plugin enables them.** Each can be turned off
  by name under `diagnostics:`, or silenced for a file that runs once a
  frame rather than in the step with
  `// ignore_for_file: flutter3d_lints/<rule>`.
