# Working in this repository

For an agent, or a person, with commit access and no history here. Each
convention below is a check that will fail or a review comment you will get.
CONTRIBUTING.md has the longer reasons; this page is where to start.

## What this is

A 3D engine on Flutter GPU, a game layer on top of it, the games, editors and
laboratories built from both, and the tools that hold them together: 61
packages and 17 applications in one pub workspace, published to pub.dev under
strict semver from 1.0.0.

| Where | What |
|---|---|
| `packages/flutter3d_hardware` | The hardware abstraction layer. Names no graphics API |
| `packages/flutter3d_impeller`, `_webgl`, `_webgpu`, `_cpu` | The four drawing backends; `flutter3d_wgpu` is a compute-only one |
| `packages/flutter3d_core`, `packages/flutter3d` | The renderer, scene and assets. Names no backend |
| `packages/flutter3d_sim`, `flutter3d_physics`, `flutter3d_physics_native` | The fixed step, levels and actors; the Dart physics and the C core. No Flutter |
| `packages/flutter3d_app`, `flutter3d_game` | Backend choice, the view, input, the run |
| `packages/flutter3d_game_shooter`, `_platformer`, `_racing`, `_strategy` | One package per genre |
| `packages/flutter3d_build` | The `flutter3d` command: `convert`, `create`, `init`, `migrate`, `doctor`, and the migration tables |
| `packages/flutter3d_mcp` | The level and model editors as MCP servers |
| `apps/` | Demos, the editor, the modeller, the showcase, the labs |
| `tool/` | `structure.dart`, `ci.sh`, `api/` (the snapshots), pacing and release scripts |
| `site/content/` | The site's pages |
| `tasks/` | Plans and reviews. Working notes, never cited in a commit |

The documents: `ARCHITECTURE.md` is the map, `docs/CONTRACTS.md` what the
engine promises, `SUPPORT.md` what runs where, `CONTRIBUTING.md` the rules
for changes.

## The structure rules

```sh
dart run tool/structure.dart           # every rule
dart run tool/structure.dart --list    # their names
dart run tool/structure.dart --only migration   # the rules whose name has it
```

The rules read source text: which package imports what (the layers are in
`tool/structure/layers.dart`), that the engine names no backend and a genre
no other genre, that every published API matches its snapshot, that every
break has a migration, and that the counts the documents state are the
tree's. A count it holds (tests, rules, packages) is one it will tell you
the right value of; update README, ARCHITECTURE.md and the site pages it
names in the same commit.

An exemption goes into a list in `tool/structure/repository.dart` with its
reason. A hook an outside author implements takes one context object; one
that cannot is listed in `hookParametersAllowed` with why.

## Tests

- **Written by breaking the code.** Write the test, break what it covers,
  watch it go red, put the code back, and name the change in a `// Mutation:`
  comment beside the test.
- **A minute at most** (`dart_test.yaml`). A slower test is listed in
  `slowTestsAllowed` with its reason and measured time, or it is a bug.
- **Run the suites you touched**, not the tree; CI runs the rest
  (`bash tool/ci.sh` is the ubuntu job, step by step).
- **No `flutter test` or `dart test` typed directly.** Agents here run behind
  a hook that refuses a command containing either. Write a small runner
  script outside the tree that `cd`s into the package and runs the files
  you name, and run it with `bash`.
- A new test moves the test count; `tool/structure.dart` says the new number.

## Breaks, snapshots and migrations

Every published package commits its surface in `packages/<p>/api/`:
`<p>.api` for Dart, `.mcp` for MCP tools, `.vm` for VM service extensions,
and `flutter3d_build.cli` for the command.

```sh
cd tool/api && dart run api_snapshot --update <package>      # after a Dart API change
cd tool/api && dart run api_snapshot:schema_snapshot --update <package>
cd packages/flutter3d_build && dart tool/cli_surface.dart > api/flutter3d_build.cli
```

- **An addition** needs a line in the package's CHANGELOG.
- **A break** needs a `**Breaking:` CHANGELOG entry naming each broken name,
  and an entry appended to the end of
  `packages/flutter3d_build/lib/migrations/0.8_to_1.0.yaml`. Prefer a kind a
  tool carries out (`rename`, `moved`, `parameters`, `rewrite`) over
  `manual`; the table has a ceiling on manual entries.
  `dart run api_snapshot:migration_seed --append` in `tool/api` drafts them,
  and `dart run tool/generate_migrations.dart` in `packages/flutter3d_build`
  writes `fix_data.yaml`, the lints' table and the site's guide
  (`--check` to verify).
- **A growing set is a class**, not an enum: `static const` members and a
  private constructor, as `DeviceFeature` is. A public `enum` or `sealed`
  type stays only when listed in `closedForGood` with a reason.

## Adding things

- **A package**: add it to the root `pubspec.yaml` workspace, place it in
  `packageLayers` in `tool/structure/layers.dart`, declare `platforms:` and
  add its row to SUPPORT's table if it is published, give it a README row,
  commit its snapshot, and update the package counts the rules name.
- **A file format**: write the envelope from `flutter3d_foundation`'s
  `formats.dart` (`{"format": "f3d.<name>", "version": 1, ...}`), list the
  reader in `versionedFormats` in `tool/structure/repository.dart`, and mint
  `test/fixtures/v1/` once. A change to what a field means bumps the version,
  at most once per release candidate, with a migration step and a new
  fixture; a fixture is never re-minted.
- **A shader**: rebuild the bundles in the same sitting
  (`packages/flutter3d_impeller/tool/build_shaders.sh`,
  `dart run tool/generate_shaders.dart` in `packages/flutter3d_webgl`).
- **An asset**: an entry in the nearest `LICENSES.md`.

## Commits

A short narrative first line ("A material keeps the version it was written
at"), a blank line, then what changed and why. Never mention plans, reviews
or other engines as a reference. Run before you commit:

```sh
dart analyze                        # or flutter analyze, in the packages you touched
dart run tool/structure.dart
```

## How the code is written

- **A doc comment says why.** A bold first sentence for the decision, then
  what forced it, usually a bug. A comment that restates the line is noise.
- **`final` by default.** Collection `if`/`for`, `switch` expressions,
  records and patterns over accumulators; mutable state where it is state.
- **A refusal is an answer.** Commands and tools return what they did or a
  sentence saying why not and what to do instead.
- **American spelling in code, digits for numbers in prose.**

## Driving the editors as an agent

```sh
dart run flutter3d_mcp:editor_mcp assets/levels/first.json   # a level
dart run flutter3d_mcp:model_mcp assets_src/crate.f3dproj    # a model
```

Ask the model editor for its `modelling_strategy` prompt first: `list` and
`describe` before you edit, `render` before and after a change you cannot
predict, `check` before you export. The modeller's own plan is
`doc/model-editor-plan.md`, checked by `dart run tool/verify_plan.dart`, and
its interface strings go through `AppLocalizations`, never a literal in
`lib/`.
