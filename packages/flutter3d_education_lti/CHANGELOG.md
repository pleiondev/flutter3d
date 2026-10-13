## 1.0.0-rc.1

- **New: a package of its own.** The LTI 1.3 launch, the AGS and xAPI
  clients and `CheckReporter` were the `lti.dart` library of
  `flutter3d_education`, and `flutter3d_lti` before that (its history is in
  `doc/changelogs/flutter3d_lti.md`). Every name is the one it had; import
  `package:flutter3d_education_lti/flutter3d_education_lti.dart`, and
  `dart run flutter3d_build:migrate` moves the dependency and the imports
  of a project written against `flutter3d_lti` 0.8. What reads an
  experiment no longer resolves `pointycastle`, `dart_jsonwebtoken` and
  `http`.

### From `flutter3d_lti` 1.0.0-rc.1

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
