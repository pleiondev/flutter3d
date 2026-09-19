# Working in this repository

For an agent — or a person — with commit access and no history here. The
conventions below are not style preferences; each one is a check that will fail
or a review comment you will get.

## What this is

A 3D engine for Flutter and the tools around it: 36 packages and 8 applications
in one pub workspace. `packages/flutter3d` is the renderer; `packages/flutter3d_
mesh` and `packages/flutter3d_model_core` are the modeller's own topology and
document; `apps/flutter3d_modeler` is the modeller. `ARCHITECTURE.md` is the map
and `doc/model-editor-plan.md` is the work.

## Before you change anything

Read the plan row. Every piece of work in the modeller has an id — `ux-19`,
`mesh-42`, `rel-20d` — a row in `doc/model-editor-plan.md` saying what it is and
an acceptance line saying when it is done. Work a row at a time and say which
row a change belongs to.

## Before you commit

```sh
dart analyze                      # in the packages you touched
dart run tool/structure.dart      # 35 rules about how the tree is arranged
dart run tool/verify_plan.dart    # every finished row names something real
```

All three have to be clean. `tool/structure.dart` will tell you, among other
things, that the test counts in `ARCHITECTURE.md`, `README.md`,
`site/content/quickstart.md` and `site/content/reference/testing.md` no longer
match the tree — update all of them, including the per-package row and the
"rows sum to X rather than Y" sentence.

Then update `doc/plan-status.json` and write what you built into the row itself.

## One row, one commit

The first line of a commit message is one short sentence saying what changed.
Then a blank line, then prose explaining what and why — what was wrong before,
what the alternative was, what it costs. Do not compare the project to other
projects in a commit message.

## How the code is written

**A doc comment says why, not what.** The signature says what. A comment that
restates it is noise; a comment that says what was tried and rejected, or what
breaks without this, is the thing a reader cannot get anywhere else. The
convention here is a bold first sentence for the decision and the reasoning
after it.

**`final` by default, and no mutable variable without a reason.** Accumulate
with `switch` expressions, records, patterns, collection `if`/`for`, `fold`,
`where`, `map`. Mutable state belongs where it is state — a hot loop's buffer,
a step counter.

**A refusal is an answer.** Commands and tools return "did it, and what to say"
rather than throwing; a refusal names what was asked for, why it cannot be, and
what to do instead. There is no exception for a case somebody thinks is
obvious.

**Tests state a claim, and say what breaks without it.** The convention is a
`// Mutation:` comment naming the change that would make the test pass while
the behaviour is wrong. A test with no such comment is usually a test that is
not checking anything.

## Running things

```sh
flutter test test                          # one package's suite
dart test test/some_test.dart              # one file, in a flat Dart package
cd apps/flutter3d_modeler && flutter run -d macos
```

The modeller's suite is long. Run the file you are working on while you work,
and the whole suite before you commit.

## Driving the modeller as an agent

`packages/flutter3d_model_mcp` offers the whole editor over MCP:

```sh
dart run flutter3d_model_mcp:model_mcp my-model.f3dproj
```

Ask for the `modelling_strategy` prompt first — it is the order to do things in.
The short version: `list` and `describe` before you edit, name what you act on
rather than leaning on the selection, `render` before and after a change you
cannot predict, `batch` what belongs together, `check` before you export.

With the application open, `flutter run -d macos --dart-define=mcpPort=8080`
serves the same tools over HTTP plus the `ui.*` ones, which drive the window
itself — including `ui.screenshot`, which is what the person sees rather than
what the model looks like.

## What not to do

Do not add a dependency to a flat Dart package that drags the Flutter SDK in;
`tool/structure.dart` checks, and a server that will not start under `dart run`
is a server nobody can use. Do not silence a print, weaken a test to make it
pass, or add a rule to an allow-list without saying why in the same commit. Do
not write a Cyrillic string literal into `lib/` — the interface goes through
`AppLocalizations`.
