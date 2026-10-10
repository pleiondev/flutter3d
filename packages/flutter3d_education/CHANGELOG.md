## 1.0.0-rc.1

- **Depends on `flutter3d_foundation` instead of the plugin API**, for the
  exception families its refusals belong to.

- **The pendulum lab steps by a fixed step** (`LabClock`, `labFixedDt`), a
  length changed mid-swing keeps its angular momentum (ω scales by
  (L/L′)²), and the damping is documented in 1/s with the large-swing
  period.
- **The chemistry bench is right about its solutions.** Hydrochloric acid
  is colourless; permanganate is labelled 0.2 mmol/L, the strength its
  purple is (at 0.02 mol/L three centimetres of it are black); Beer and
  Lambert run on linear transmittance, decoded from the picked sRGB, so a
  mixture is the colour light through it is; and the bench says it mixes
  colours and nothing reacts. The glass is half a millimetre, as drawn.
- **New: one package for what was two.** `flutter3d_lab`, `flutter3d_lti` are
  libraries of this package now: `lab.dart`, `lti.dart`, each with the API its
  package had, and `flutter3d_education.dart` exports them all. `dart run
  flutter3d_build:migrate` moves a project's dependencies and imports; the
  packages' own histories are in `doc/changelogs/`.
- **The chemistry bench is the example.** `chemlab` moved from
  `packages/education/` to `example/`: it draws, so it stays an application, and
  the package stays plain Dart for the services that use it.

### `lab.dart`, from `flutter3d_lab` 1.0.0-rc.1

- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`.

**A pendulum with no world swings by the engine's one standard gravity.**
`PendulumSimulation` and `PendulumLabRun` default to `standardGravity`
from `flutter3d_physics` instead of a 9.81 of their own: the same number,
so every recorded lab replays to the bit, but now the one every world in
the engine starts with. A lab teaching the Moon still passes its own.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

### `lti.dart`, from `flutter3d_lti` 1.0.0-rc.1

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `LtiPlatformConfig` is `LtiPlatformSettings`, `XapiLrsConfig` is
  `XapiLrsSettings`. Every settings class is `final` with a `const`
  constructor and a `copyWith` over every field; a nullable field is reset
  with `copyWith(clearX: true)`. `dart fix` carries the renames.
- **Breaking:** `AgsException`, `LtiLaunchException`, `XapiException` extend
  `ResourceException` instead of implementing `Exception` directly. The names
  and members are unchanged and every `on` clause that caught them still does;
  every exception the engine throws now hangs from `Flutter3dException` in
  `flutter3d_plugin_api`, in one of four families: format, capability, plugin
  and resource. A caller who reports anything the engine refused catches the
  root; one who acts on a kind catches its family. The migration table marks
  them as nothing to do. `LtiLaunchException` is still sealed over the same
  five cases.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^1.0.0`.
