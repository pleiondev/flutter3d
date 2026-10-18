# 31. Tools, MCP and build configuration before 1.0 (2026-10-15)

This audit reads the working tree of branch `1.0.0` at `da3b09a6e`. The tag `v1.0.0-rc.1` already exists (2026-10-14, 24 commits back), so every "since the last release" rule now measures against it. The audit covers the surfaces a user or a script depends on that are not Dart signatures:

- the `flutter3d` command, its `dart run flutter3d_build:<command>` aliases, and every other `bin/` entry point in a published package;
- the MCP servers in `flutter3d_mcp`, `flutter3d_sim_mcp` and `flutter3d_build` (`plugin_mcp`), with a glance at the VM extensions that share their rule;
- build configuration: `flutter3d_assets.yaml`, the hook's `user_defines`, the `flutter3d_plugins:` pubspec block, directory conventions and generated files;
- `flutter3d_lints`: rule names, the analyzer plugin config, and its `migrate` CLI;
- the third-party test surface: `flutter3d_testing`, `flutter3d_conformance`, `flutter3d_conformance_render`, the badge and golden layout;
- the `create` templates' output.

It measures them against `docs/CONTRACTS.md:385-395` ("Tools and the command line") and refers to decided items 66, 80, 118, 121 and 122 (`tasks/1.0-readiness-review.md` §6, wave 4.3 of `tasks/1.0-rc1-plan.md`) without re-arguing them.

Nothing was changed. Two things were run: `dart tool/cli_surface.dart` (its output matches `api/flutter3d_build.cli` byte for byte) and `dart run flutter3d_build:doctor --help` (it fails, see finding 4). A claim marked "read" was checked in the code. Counts come from `rg`/`fd`, and the ones marked "heuristic" come from a pattern, not a parser.

Severity, as asked:
- **BLOCKER**: only a major can fix it once 1.0.0 ships.
- **BEFORE RC.1**: cheap now. Later it costs a behaviour change, a false promise in the docs, or a hole in the rule that guards the 1.0 shape.
- **ADDITIVE 1.x**: a minor can do it.

## Verdict

The agent surface is the most carefully held part of the tooling. Each MCP server announces a schema version and offers `flutter3d.schema`. Every tool is snapshotted with its input schema and hints, renames keep aliases, and `tool/structure/schema.dart` sorts each change into major or minor in the right direction for inputs and outputs. The `flutter3d` command has a written exit-code table, a `--json` envelope with its own version, and a committed help surface with a release-break rule. `flutter3d_assets.yaml` is a real `FormatSpec` with a fixture.

The holes are at the edges of that structure:

1. **The CLI rule guards help text, not the command.** The snapshot is built from string constants. Only subcommand names and long flags count as "words" a release can lose. `--json` keys, exit codes, defaults, value sets and short flags can change after a regenerate without a `**Breaking:**` label, and no test compares a parser with its usage text.
2. **There are two badge authorities and they disagree.** `flutter3d_build`'s `plugin.report` gives out `conformant@1.0` from 5 checks. `flutter3d_conformance` defines suite 1.0 as 7 checks.
3. **`flutter3d_testing` records missing goldens on CI.** It decides "is this CI" from a compile-time define that no CI job passes.
4. **Two shape decisions only make sense now.** One: 224 pre-1.0 MCP aliases would be promised until 2.0 and listed in every `tools/list`. Two: render conformance check names contain spaces, and decision 121 is about to put them into badges and reports.

Decision 66 (`flutter3d_lints` stays 0.x) is not in the tree yet. When it lands it has to move four other places with it (finding 9).

**Two blockers** (findings 1 and 2), **twelve BEFORE RC.1**, **six ADDITIVE 1.x**. **12 questions.**

## 1. The surface

| Surface | Where | Documented | Versioned | Fixture of its 1.0 shape | A rename after 1.0 breaks |
|---|---|---|---|---|---|
| `flutter3d` and 10 subcommands (`convert create init plugins shaders migrate lights lightmap doctor help`) | `flutter3d_build/lib/src/cli_contract.dart:90`, dispatch `commands.dart:34-74` | help text; `CONTRACTS.md:385`; README "The command is a contract" | with the package (strict semver, `cli_contract.dart:1-11`) | `api/flutter3d_build.cli` (227 lines), current; rule `rules.dart:5891` | CI scripts, the cloud service, docs |
| Exit codes 0/1/2/3/4 | `cli_contract.dart:18-47` | yes | no number of its own | inside the `.cli` text, but not a "word" the release rule compares (finding 3) | `$? -eq 3` checks |
| `--json` on 4 subcommands (`convert doctor plugins shaders`) | `cli_contract.dart:55-87`; emitted `convert/command.dart:411`, `commands.dart:216,318`, `doctor.dart:628` | yes, keys only | `f3d.cli` v1 (`cliJsonVersion`) | `== --json ==` section is hand-written strings; no test reads real output against it | `jq` scripts |
| `--version` | `commands.dart:66` | no | — | no | scripts that probe the version |
| `dart run flutter3d_build:<cmd>` aliases (8) and `plugin_mcp` | `flutter3d_build/bin/*.dart`; `cli_aliases_test.dart:22-34` | "Every command also runs as …" (`cli_contract.dart:135`) | — | test fixes the list of files | `doctor` has no alias (finding 4) |
| Other `bin/` entry points (10): `flutter3d:skills`, `flutter3d_core:decode_worker`, `flutter3d_sim:{headless_run,f3drun_info,bake_visibility}`, `flutter3d_impeller:{build_shaders,build_shader_bundle}`, `flutter3d_model_core:export`, `flutter3d_net:relay`, `flutter3d_lints:migrate` | each `bin/` | doc comments; `decode_worker` in `web_decode_worker.dart:13` | none | none | web builds (`decode_worker`), level pipelines (`bake_visibility`), relay hosts |
| MCP `flutter3d.editor` | `flutter3d_mcp/lib/src/editor/editor_server.dart:31` | README, site index | schema 1.2.0 | `api/flutter3d_mcp.mcp`: 65 tools, 56 aliases, `out` on all | host configs, prompts |
| MCP `flutter3d.model` | `model/model_server.dart:34` | README | 1.1.0 | 154 tools, 153 aliases, `out` on all | same |
| MCP `flutter3d.project` | `kit/project_server.dart:22` | README | 1.0.0 | 1 tool (`flutter3d.schema`); plugins add theirs | same |
| MCP `flutter3d.sim`, `flutter3d.diagnostics` | `flutter3d_sim_mcp/lib/src/sim_server.dart:25`, `diagnostic_server.dart:24` | README (stale, finding 14) | 1.0.0 each | `api/flutter3d_sim_mcp.mcp`: 17 tools, 15 aliases, **`out` on 2** | same |
| MCP `flutter3d.plugins` (`plugin.create/conformance/report`) | `flutter3d_build/lib/src/plugin_author_server.dart:39` | `site/content/reference/plugins.md` | 1.0.0 | `api/flutter3d_build.mcp`: 4 tools, **`out` on 1** | plugin authors' agents |
| MCP hints | `ToolName` default `writes` (`kit/tool_table.dart:79`) | CONTRIBUTING:339 | a hint change counts as minor (`schema.dart:484-494`) | across the 3 snapshots (241 tools): 181 writes, 42 readOnly, 6 readOnly idempotent, 2 readOnly openWorld, 1 openWorld, 9 destructive | host permission prompts |
| VM extensions | `api/flutter3d_{app,game,plugin_api}.vm` | CONTRIBUTING:359 | with the package | same rule as `.mcp` | attached editors |
| `flutter3d_assets.yaml` | `flutter3d_build/lib/src/manifest.dart:103,164` | `site/content/reference/asset-pipeline.md` | `f3d.assets` format 1, `FormatSpec` | fixture rule | every project with rules |
| Hook `user_defines` (`textures`, `deviceClasses`, `fullShaders`) | `build_assets.dart:432,442,459` | `asset-pipeline.md:153-198,273` | none | none; unknown keys and bad values are ignored silently | pubspecs |
| Directory and file conventions: `assets_src/`, `flutter3d_generated/`, `flutter3d_generated/shaders/flutter3d.f3dshaders`, `<rel>.f3dmat → <rel>.f3dshaders`, `hook/build.dart` text, `/flutter3d_generated/` gitignore line, `lib/plugins.g.dart` with `installedPlugins` | `layout.dart:31,36,108-112`; `shader_build.dart:342`; `init.dart:44,57,70`; `plugin_discovery.dart:683` | yes | `init` keeps one past hook text as current (`init.dart:57,113-116`) | `layout_test`, `init_test`, `plugin_discovery_test` | every generated project |
| `flutter3d_plugins:` pubspec block | `plugin_discovery.dart:128` (`plugin`, `shaders`; app `with/without/set` at :346); catalogue keys `api backends touches demo conformance` in `site/tool/plugins.mjs:248-261` | `plugins.md:13-24` | legacy `flutter3d:` read until 2.0 | discovery tests; catalogue untested | every plugin package |
| `flutter3d_lints` rule names: `step_reads_no_clock`, `step_takes_seeded_random`, `step_uses_portable_math`, `step_prefixes_dart_math`; `flutter3d_migrate`, `flutter3d_migrate_by_hand` | `lib/src/simulation_scan.dart:63-72`, `migration/migration_rules.dart:47,79` | README | package at `1.0.0-rc.1` (decision 66 says 0.x) | the four step rules are consts in `api/flutter3d_lints.api`; the migration codes are not | `// ignore: flutter3d_lints/<rule>`, `diagnostics:` maps |
| `flutter3d_lints:migrate --json` (JSON Lines, no envelope) | `flutter3d_lints/bin/migrate.dart:143` | its usage | none | none | `flutter3d_build:migrate` parses it (`migrate/command.dart:237,265`) |
| `flutter3d_testing` | `expectMatchesGolden` defaults `tolerance 0, channel 8` (`golden.dart:43-52`); `test/goldens/<tape>-<step>.png` (`test_replay.dart:144,415`) | README | with the package | API snapshot | every game's goldens |
| `flutter3d_conformance` | `runDeviceConformance`, `checkPluginConformance`, `runPluginConformance`; `pluginCheckNames` (7) `plugins.dart:85`; suites `'1.0'` :122; `conformant@1.0`; `f3d.conformance` v1 report :172 | site `plugins.md:28-32` | suite id; report format 1 | API snapshot; report fixture | badge holders, catalogue |
| `flutter3d_conformance_render` | 7 `render.*` checks with spaces in their names (`render_checks.dart:57-65`) | API.md | — | API snapshot | report readers once 121 lands |
| `create` templates | project kinds `scene viewer arcade` (`project_template.dart:30-55`); plugin kinds ×6 (`plugin_template.dart:37-78`) | help, `plugins.md:34-40` | none | project kinds compiled when `flutter` is present (`create_project_kinds_test.dart:26`); plugin kinds text only (decision 122 covers this) | users who generated from 1.0 (finding 12) |

## 2. Findings

### BLOCKER

1. **224 pre-1.0 MCP aliases would be promised until 2.0 and listed in every `tools/list`.** `tool_table.dart:220-228` says an alias "is listed by `tools/list` with the current tool's schema and a description that opens by saying it is deprecated". `CONTRACTS.md:388` keeps an alias "until the next major". The snapshots hold 209 aliases in `flutter3d_mcp.mcp` (editor 56, model 153), 15 in `flutter3d_sim_mcp.mcp` and none in `flutter3d_build.mcp`. Every one of them names a pre-1.0 spelling (`render`, `addBrush`, `capture_draw`, `expect`). The rc.1 tag already carries them: `git show v1.0.0-rc.1:…/flutter3d_mcp.mcp` has the same 429 tool and alias entries. So 1.0.0 would promise names that no 1.x release ever published as current, and it would roughly double the model server's listing (154 tools, 307 entries) in the context of every agent. Hiding them from the listing would probably count as a minor after 1.0. Dropping them would not. **Question 1.**

2. **Render check names have spaces, and decision 121 is about to make them part of the badge and the report.** `pluginRenderCheckNames` = `render.nodes`, `render.lit model`, `render.lit model defaults`, `render.light type`, `render.decal`, `render.velocity`, `render.shadows` (`flutter3d_conformance_render/lib/src/render_checks.dart:57-65`). Three things then carry the name as data: the report's `check` field (`flutter3d_conformance/lib/plugins.dart:181-186`), a suite list in `conformanceSuites`, and `flutter3d_build`'s classifier, which assigns a test to a check "by the word each test's name carries" (`plugin_author_server.dart:55-56`). After 1.0 a rename breaks every report reader and changes what a suite id means. No other name in the engine has a space in it (`ToolName.pattern`, `tool_table.dart:92-94`). **Question 2.**

### BEFORE RC.1

3. **The CLI release rule sees command names and long flags, nothing else.** `cliSurfaceWords` (`tool/structure/detectors.dart:1283-1300`) collects `== <command> ==` headings and `--flag` tokens. `_cliSurfaceCurrent` (`rules.dart:5934-5982`) asks for a `**Breaking:**` entry only when one of those disappears. Measured against the promise in `cli_contract.dart:6-8` ("a subcommand, a flag or an exit code is not removed or renamed within a major, and the `--json` output only grows"), it does not see:
   - **`--json` keys.** The `== --json ==` section (`flutter3d_build.cli:222-227`) has no `--` tokens, so removing `reports[].mapped` only fails the "is current" check. A regenerate then passes with no label.
   - **The exit-code table.** Renumbering `3` and `4` is the same case.
   - **Short flags** (`-o`), **value sets** (`--textures auto|bc|…`, `--target native|web|any`, `--kind`), and **defaults** (`lightmap --density 4 --bounces 2 --samples 64`, `lights -o` default "over the input").
   - **The parsers themselves.** The snapshot prints string constants (`tool/cli_surface.dart` imports only `cli_contract.dart`). A flag a parser stops reading, or starts reading, with the usage text left unchanged passes every check. Nothing compares `cliJsonBodies` with real output either: the only `--json` test call is `convert_support.dart:68`, and it does not assert the key list. A heuristic scan of the flags each command parses shows that today the usage texts and the parsers agree. Nothing keeps them that way.
   **Question 6.**

4. **`dart run flutter3d_build:doctor` does not exist, though the surface says every command runs that way.** `flutter3d_build.cli:30` says "Every command also runs as `dart run flutter3d_build:<command>`". `bin/` has no `doctor.dart` (`cli_aliases_test.dart:22-34` fixes the list without it), and running it answers "Could not find `bin/doctor.dart`". The test checks one direction only: each alias appears in the usage (:55). It never checks the reverse. Also, `--version` (`commands.dart:66`) works and appears in no help text, so the snapshot does not hold it.

5. **Exit codes and streams disagree between subcommands for the same situation.** Read:
   - **`--help`.** `convert`, `migrate`, `lightmap`, `plugins` and `shaders` print to stdout and exit 0. `init --help` exits 2 on stderr (`init.dart:407-415`, deliberately). `lights --help` exits 2 on stderr (`lights.dart:24-26`). `flutter3d help init` and `help lights` call those parsers, so their text goes to stderr while `_help` answers 0 (`commands.dart:84-95`).
   - **Unknown options are ignored silently** by `create project` (`commands.dart:172`: any `-x` that is not `--kind`/`--name` is dropped, so `--kind=viwer` fails but `--knd=viewer` makes a `scene`), by `create plugin` (`commands.dart:125-136` reads named options and ignores the rest, so `--targte dir` writes into `./<name>`) and by `migrate` (`migrate/command.dart:71-77`). `CliExit.usage`'s own doc says an unknown option is 2 (`cli_contract.dart:26-28`).
   - **Misfiled errors.** `migrate` on a directory without `pubspec.yaml` exits 2, not 1 (`migrate/command.dart:91-92`), and a broken migration table also exits 2 (:110-112). `init --check` exits 1 when the hook was hand-edited (`init.dart:444`), and its help documents only 0 and 3.
   Once 1.0 ships, each of these is either frozen or fixed through a behaviour change. **Question 5.**

6. **Two badge authorities, and they disagree.** `flutter3d_conformance` defines suite `1.0` as `pluginCheckNames`: `manifest switch names determinism backends budget materials` (`plugins.dart:85-93,122-124`). `flutter3d_build` keeps its own copy, `pluginConformanceChecks` = `manifest switch determinism backends budget` (`plugin_author_server.dart:61-67`), with a comment claiming "The names are the suite's `pluginCheckNames`" (:59). `ConformanceRun.earnsBadge` (:257) counts only those five, so `plugin.report` can answer `badge: conformant@1.0` for a plugin whose `names` or `materials` check failed. The copy exists for a reason (the suite is a test library and the build must not depend on `test`, :57-59). No rule holds the two lists equal, and decision 121 is about to add render checks to one of them. **Question 3.**

7. **`flutter3d_testing` records missing goldens on CI and passes.** `golden.dart:62` decides "recording is allowed" with `!const bool.fromEnvironment('CI')`. That is a Dart compile-time define, not the `CI` environment variable "every runner sets" (the comment at :57-61). `rg` finds no `--dart-define=CI` or `-DCI` in `tool/*.sh` or `.github/workflows/*.yml`. So on GitHub Actions a mistyped or gitignored golden is written fresh and agrees with itself, which is exactly what the comment says it prevents. `testReplay` and `expectReplayMatches` inherit the same behaviour (`test_replay.dart:154,175,243,310`). The fix (also read `Platform.environment['CI']`) is a behaviour change for third-party suites that pass today by accident, so it is cheapest before the tag.

8. **Template version constraints are hard-coded, and only one of them is tied to a version.** A heuristic count: `rg` finds 24 occurrences of `1.0.0-rc.1` in `flutter3d_build/lib/src/*.dart`. Project templates write `flutter3d: ^1.0.0-rc.1` and `flutter3d_app: ^1.0.0-rc.1` (`project_template.dart:120-121`, `project_kinds.dart:133-134,360-361`). Plugin templates do the same for six packages (`plugin_template.dart:239-251,1006-1012`) and `flutter3d_lints: ^1.0.0-rc.1` (:296). Only `flutter3dBuildVersionConstraint` (`init.dart:33`) is held to the pubspec, by `init_test.dart:256-275`, and `plugin_template_test.dart:346` hard-codes the same string. After 1.0, a 1.3 template that uses a 1.3 API still writes `^1.0.0-rc.1`, and a `pub get` that resolves 1.0 fails to compile.

9. **Decision 66 has to move five places together.** `flutter3d_lints` is still `version: 1.0.0-rc.1` (`flutter3d_lints/pubspec.yaml:3`). When it goes to 0.x:
   - **The plugin template breaks.** It writes `plugins: flutter3d_lints: ^1.0.0-rc.1` into `analysis_options.yaml` (`plugin_template.dart:296`), which no 0.x release satisfies, so the analysis server cannot load the plugin in every generated simulation plugin.
   - **The README** tells users the same (`flutter3d_lints/README.md:38,48`).
   - **A 1.x tool parses a 0.x CLI.** `flutter3d_build:migrate` (1.x) runs `dart run flutter3d_lints:migrate --json [--automatic]` in the user's project and parses its JSON Lines with `!` casts (`migrate/command.dart:211-222,237-247,265-287`). Those lines have no envelope and no version (`flutter3d_lints/bin/migrate.dart:131-145`), and the `f3d.cli` rule does not cover them. A 0.x minor of lints that renames `applied` breaks a 1.x tool.
   - **Decision 80** (`avoid_engine_internal_imports`) cannot reach applications. The project template enables no lints plugin at all (`project_kinds.dart:32-44`), so the rule would reach only simulation plugin kinds. **Question 8.**

10. **A material source can overwrite the engine's shader bundle.** `materialPlan` maps `assets_src/<rel>.f3dmat` to `flutter3d_generated/<rel>.f3dshaders` (`layout.dart:69-88`), and `shaders` writes `flutter3d_generated/shaders/flutter3d.f3dshaders` (`shader_build.dart:342`). An author's `assets_src/shaders/flutter3d.f3dmat` lands on the engine bundle. This was read, not run. Reserving `flutter3d_generated/shaders/` (refusing a source under `assets_src/shaders/`, or moving the material outputs) is a layout decision. After 1.0, any such change moves a path that a project's `flutter: assets:` may name.

11. **The hook's `user_defines` ignore mistakes silently.** `textures: bx` falls back to the platform's family (`build_assets.dart:432-435`). `deviceClasses` goes through `parseDeviceClasses`. A misspelt key (`fullShader: true`) is never read. `flutter3d_assets.yaml` refuses an unknown key with its line number (`manifest.dart:210-217`), and the pubspec half of the same configuration says nothing. **Question 11.**

12. **There is no statement of what a project generated from 1.0 may rely on.** The files that keep mattering after generation:
    - **`hook/build.dart`.** `init --check` and `doctor` compare it exactly, and `init` accepts exactly one older text as current (`_hookBuildContentBefore`, `init.dart:57-64,113-116`). A 1.x hook text that forgets to add 1.0's text to that set turns every 1.0 project "pending" (exit 3) and "edited" (refused without `--force`).
    - **`lib/plugins.g.dart`** exposes `installedPlugins` (`plugin_discovery.dart:683`), and application code imports it.
    - **The `flutter3d_plugins:` marker.**
    - **`assets_src/` and `flutter3d_generated/`.**
    The rest (`main.dart`, README, tests) is the user's once written. Nothing snapshots the template output, and decision 122 adds five plugin kinds to it. **Question 7.**

13. **The conformance report has a format and no writer, and the catalogue's badge is self-declared.** `conformanceReportFormat` (`f3d.conformance` v1, `plugins.dart:159-170`) and `conformanceReport(...)` (:172) exist. `rg` finds no caller in the repository. `runPluginConformance` writes nothing, and `plugin.report` keeps its run in memory (`plugin_author_server.dart:351,398`). The catalogue reads `conformance:` straight from the pubspec (`site/tool/plugins.mjs:254-261`, `true` read as `1.0`, or `conformant@<suite>`). The page shows only `conformance: true` (`plugins.md:23`). Once decision 121 changes what a badge takes, `true` no longer says which suite was passed. Two cheap changes: document the `conformant@1.0` spelling, and have `runPluginConformance` write the report. **Part of question 3.**

14. **Docs teach the alias names and describe a transport that is not there.**
    - `README.md:133` says the modeller has "147 editing tools and `render`". The tool is `view.render`, `render` is an alias (`flutter3d_mcp.mcp:593`), and the server has 154 tools.
    - `site/content/reference/what-1.0-is.md:39` repeats `render`.
    - `flutter3d_sim_mcp/README.md:9-12` names `expect` and `verify`, which are now `run.expect` and `run.verify`.
    - The same README says the server "speaks MCP over a socket rather than literal stdio" (:21-23). No `ServerSocket` or `bind` appears in its `lib/`, the package has no `bin/`, and it never says how a host starts it.
    - `flutter3d_mcp/bin/editor_mcp.dart:19-21` says "no package in this repository declares [an `executables:` entry]". `flutter3d_mcp/pubspec.yaml:36-39` and `flutter3d_build/pubspec.yaml:27-28` both do.
    - CONTRIBUTING:353 says every tool has "an `out` line". 17 of 21 tools outside `flutter3d_mcp` have none (finding 16).
    - `dart run flutter3d:skills` (`flutter3d/bin/skills.dart`) is a second skills installer that no document names. Every document says `dart run skills@ get` (`README.md:340`).

### ADDITIVE 1.x

15. **Ten `bin/` entry points sit outside any contract and use two exit-code dialects.** `decode_worker` and `f3drun_info` use sysexits (64, 65, 66, 69). `headless_run` and `bake_visibility` use `exit(2)`. The rest use 1. None has a snapshot. Two of them are part of a user's pipeline:
    - `decode_worker` writes `web/flutter3d_decode_worker.js`, which `WebDecodeWorker.use` loads by that name (`web_decode_worker.dart:13-16`).
    - `bake_visibility` writes `<level>.visibility.json` beside each level (`flutter3d_sim/bin/bake_visibility.dart:6,58`).
    `relay` prints `listening on <port>` for scripts to read and binds `anyIPv4` (`flutter3d_net/bin/relay.dart:137-141`). `flutter3d_impeller:build_shaders` and `:build_shader_bundle` are this repository's own tools, published under `bin/`. CONTRACTS says nothing about any of them. **Question 4.**

16. **Most of the sim and plugin servers' answers have no declared shape.** `out` is declared for 220 of 220 tools in `flutter3d_mcp`, 2 of 17 in `flutter3d_sim_mcp` and 1 of 4 in `flutter3d_build`, and the ones it has are all `flutter3d.schema`. `state.snapshot` answers "as JSON" in text (`flutter3d_sim_mcp.mcp:116-118`), so its keys are a de facto contract the rule cannot see. Declaring `out` later counts as minor (`schema.dart:499-505`). That is correct, and it means these shapes are unguarded until someone declares them.

17. **Refusals are prose only.** Every refusal is `ToolResult.text(says, isError: true)` (`tool_table.dart:588`, `kit/answers.dart:53-61`, `argument_check.dart:22-41`). The editor and model answers have `did` and `says` in `structuredContent`, but no reason code (`paused`, `badArgument`, `notFound`, `permission`). A machine reader has to match sentences, and a reworded sentence is not a change the classifier sees. Adding a `refusal` field later is minor. CONTRACTS should say now that the wording is not the contract. **Question 10.**

18. **`plugin.conformance` is hinted `readOnly` but runs the plugin's own tests** (`dart test`/`flutter test` in the directory, `plugin_author_server.dart:337-341`). That runs arbitrary code, and a test can write files. In the spirit of decision 118 it should not be `readOnly`, and probably should be `openWorld`. A hint change counts as minor.

19. **Every `flutter3d_assets.yaml` key added in 1.x must bump `format`.** A 1.0 reader refuses an unknown top-level key with "unknown key … the ones this reads are format, rules, classes, shaders" (`manifest.dart:210-217`). It gives the helpful "update flutter3d_build" message only when `format` is newer (:230-235). That is a rule for whoever writes 1.1, and nothing enforces it. **Question 9.**

20. **Third-party MCP and CLI snapshots.** `api/<package>.plugin.mcp` and the `.cli` rule run only inside this repository (`tool/api`). A plugin author whose plugin adds tools has no published way to snapshot them, although the plugin API's own `McpTools` promise is the same. A `dart run flutter3d_build:snapshot` (or a `plugin.snapshot` tool) can come in a minor.

## 3. What the structure rules claim and cannot see

`site/content/reference/testing.md:292` says the command-line rule holds "a subcommand or flag gone since the last release tag". That is exactly what it does. The rest of what `cli_contract.dart:6-11` promises (exit codes, `--json` only grows) is held by nobody once the snapshot is regenerated (finding 3). Specifically:

| Rule | Claims | Cannot see |
|---|---|---|
| `_cliSurfaceCurrent` (`rules.dart:5891`) | the committed `.cli` is what `help --surface` prints; a command or long flag gone since the tag needs `**Breaking:**` | parsers (the text is built from constants); `--json` keys; exit codes; short flags; values and defaults; `--version`; the missing `doctor` alias |
| `cli_aliases_test.dart` | each `bin/` file is one call to `runFlutter3d` and is named in the usage | a command in the usage with no alias |
| `_schemaSnapshotsCurrent` / `_schemaBreaksLabelled` (`rules.dart:5179,5318`) | every tool, argument, hint, alias and declared `out` is current; breaks need a major, a label and a schema bump | answers given as JSON text (finding 16); refusal wording; that aliases are listed (finding 1); third-party plugin tools (finding 20) |
| `_formatFixtures` | `f3d.assets`, `f3d.conformance`, `f3d.convertReport` have fixtures per version | that `f3d.conformance` has a writer (finding 13); the JSON Lines of `flutter3d_lints:migrate` |
| none | — | the build's copy of the badge checks against the suite's (finding 6); template constraints against package versions (finding 8); the hook texts `init` accepts against every hook a release wrote (finding 12) |

An aside on the same page: `testing.md:292` says "and a table is closed once its release is tagged" twice in a row, inside a sentence the counting rule reads.

## 4. What is good

- **The MCP kit is the right shape for a 1.0.**
  - A tool and its body are one object.
  - Arguments are checked for unknown keys before the schema, so a typo is refused, not ignored.
  - Every server announces a schema version in `initialize` and through `flutter3d.schema`.
  - Plugin namespaces carry their own versions.
  - No `dart_mcp` type appears in a signature, and `dart_mcp` is pinned to one 0.x minor.
- **The schema classifier is direction-aware.** A widened input enum is minor and a narrowed one major. An output field added is minor, and one removed or made optional is major (`schema.dart:520-560`). Few projects get this right.
- **The exit-code table and the `f3d.cli` envelope exist, are written down, and match the code.** The `convert` outcome and `doctor` status words come from explicit wire strings (`ConvertOutcome._('missing-tool', 3)`, `DoctorStatus._('[ok]', 'ok')`), not Dart `.name`.
- **`flutter3d_assets.yaml` is a versioned format with a fixture and a strict reader** that names the line it refuses.
- **`init` is idempotent, has `--check`, and refuses to overwrite a hand-edited hook.** It also already knows to accept an earlier hook text as current.
- **The golden helper explains its own semantics.** `channel: 8` versus byte-exact, and FLIP as a second question, are documented on the call itself. Only the CI switch is wrong (finding 7).

## Questions for Dmitrii

1. **The 224 pre-1.0 MCP aliases (finding 1).** *Recommended:* stop listing aliases in `tools/list` from 1.0.0, keep answering them until 2.0, and keep them in the snapshot as `alias` lines. Host configs and old prompts keep working, and agents stop paying for two copies of every tool. *Alternative:* drop them at 1.0.0 with a table in the migration guide, since no 1.x release named them as current. That is cleaner, but it breaks every host config written against 0.x or rc.1.

2. **Render check names (finding 2).** *Recommended:* rename them before decision 121 lands, to `render.nodes`, `render.litModel`, `render.litModelDefaults`, `render.lightType`, `render.decal`, `render.velocity`, `render.shadows`. Hold every check name to `ToolName.pattern` with a rule. *Alternative:* keep the spaces and freeze them as they are.

3. **One badge authority (findings 6, 13).** *Recommended:* `runPluginConformance` writes `<package>.conformance.json` (`f3d.conformance`). `plugin.report` and the catalogue read that file, and `earnsBadge` in `flutter3d_conformance` stays the only judge. Until then, a structure rule holds `pluginConformanceChecks` equal to `pluginCheckNames`. Document `conformance: conformant@1.0` as the pubspec spelling. *Alternative:* keep the build's own classifier, generate its list from the suite's file with a rule, and leave the report unwritten.

4. **Which `dart run` entry points are the 1.0 contract (finding 15).** *Recommended:*
   - in the contract: the `flutter3d` command and its aliases, the four MCP server entry points (`editor_mcp`, `model_mcp`, `project_mcp`, `plugin_mcp`), and the `flutter3d_lints:migrate` flags `flutter3d_build` calls;
   - into the command, additively: `decode_worker` and `bake_visibility` become `flutter3d decode-worker` and `flutter3d visibility`, and the old entry points stay as one-line aliases;
   - out: CONTRACTS names the rest as tools outside the contract, and `flutter3d_impeller`'s two builders move to `tool/`.
   *Alternative:* snapshot every published `bin/`'s help in a per-package `.cli` and hold them all to the same rule.

5. **Uniform CLI behaviour before the tag (finding 5).** *Recommended:*
   - `--help` and `help <cmd>` print to stdout and exit 0 everywhere;
   - an unknown option is 2 everywhere, `create` and `migrate` included;
   - a missing file or pubspec is 1;
   - `init --check` documents 1 for a hand-edited hook.
   Add one table-driven test over all ten commands. *Alternative:* document each command's current behaviour in its help and freeze it.

6. **How deep the CLI rule reads (finding 3).** *Recommended:*
   - classify `--json` keys (a key gone is a break) and the exit-code lines (a code gone or renumbered is a break);
   - add a test that every option a parser accepts appears in its usage, and the reverse;
   - add one test per `--json` command that compares its real top-level keys with `cliJsonBodies`.
   *Alternative:* only the `--json` keys and exit codes, leaving parsers to review.

7. **What a project generated from 1.0 may rely on (finding 12).** *Recommended:*
   - the generated files belong to the user once written, and template text is not a contract;
   - four things are: `hook/build.dart` (every text any release wrote stays accepted as current, as a list held by `init_test`), the `flutter3d_plugins:` block, `lib/plugins.g.dart`'s `installedPlugins`, and the `assets_src/` and `flutter3d_generated/` layout;
   - template constraints are derived from each package's own version, held by one test, replacing the 24 literals.
   *Alternative:* snapshot the template output (`api/flutter3d_build.templates`) and classify changes the way the `.cli` is classified.

8. **Decision 66 and the lints plugin in templates (finding 9).** *Recommended:*
   - when lints goes to 0.x, the plugin template, the README and `flutter3d_build`'s parser move in the same commit;
   - `flutter3d_lints:migrate --json` gets the `f3d.cli` envelope (or `f3d.lintsMigrate`) with a version, and `flutter3d_build` refuses a newer version with a sentence;
   - the project template enables `flutter3d_lints` too, so decision 80 reaches applications.
   *Alternative:* plugin templates only, and leave `migrate`'s JSON as an internal pipe between two packages released together.

9. **How `flutter3d_assets.yaml` grows (finding 19).** *Recommended:* every new key bumps `format`, with a structure rule (the key set and `formatVersion` move together), so a 1.0 build says "update flutter3d_build". *Alternative:* accept unknown keys with a warning, in line with "unknown keys are kept" for files. That is friendlier to a team on mixed versions, but it lets typos pass.

10. **The MCP refusal shape (finding 17).** *Recommended:* say in CONTRACTS now that the refusal wording is not a contract. Add a `refusal` code to `structuredContent` (`badArgument`, `paused`, `notFound`, `permission`, `refused`) in 1.1. *Alternative:* add the code before rc.1 so 1.0 clients can rely on it from day one.

11. **Mistakes in the hook's `user_defines` (finding 11).** *Recommended:* fail the build on an unknown value of `textures` or `deviceClasses`, naming the choices, and warn on an unknown key under `flutter3d_build:`. *Alternative:* warn on both and keep building.

12. **How stable CPU goldens are across 1.x.** Every third-party golden is a picture from the software rasteriser (`flutter3d_testing/README.md:120-123`), and nothing says whether a minor may change it. *Recommended:* the CPU picture may change in a minor under a `**Picture:**` CHANGELOG label naming the cause. It never changes in a patch, and the `channel: 8` default is frozen. *Alternative:* the CPU output is byte-stable within 1.x, which freezes the rasteriser's rounding until 2.0.
