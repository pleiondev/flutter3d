# Contributing

Thank you for looking. This repository has a few conventions that are not the
usual ones, and every one of them exists because something went wrong without
it. Reading this first will save you a review round.

## Before you start

```bash
flutter pub get          # one lock file for the whole workspace
bash tool/ci.sh          # everything CI runs, in the order it runs it
```

`tool/ci.sh` is the contract. If it is green locally it is green on CI, and if
it is red the first line of the failure names the step.

The workspace needs Flutter stable with Dart `^3.12.2`. Impeller and Flutter GPU
are switched on per application in `Info.plist`; a new application that forgets
`FLTEnableFlutterGPU` and `FLTEnableImpeller` draws nothing at all and says
nothing about why.

## Tests are written by breaking the thing they cover

**A test that has never failed has not been shown to test anything.** So the
rule here is: after writing a test, break the code it covers and watch it go
red. Then put the code back and name the mutation in a comment beside the test.

```dart
test('and a dead one holds its final pose', () {
  // Mutation: return `AnimationWrap.loop` unconditionally, which is what the
  // default did and what the bug was — fails here and nowhere else.
  ...
});
```

The comment is the point. It tells the next reader what this test is for, and it
tells a reviewer that the check was actually made. `ARCHITECTURE.md` §13 has the
longer version.

The test count in `ARCHITECTURE.md` §13 is checked by a scan, so a change that
adds tests updates that number too. `dart run tool/structure.dart` says what the
number should be.

## Architecture is checked by scans, not by review

`dart run tool/structure.dart` holds twenty-six rules about how the repository is
arranged — that a genre package names no other genre, that the hardware layer
names no graphics API, that the engine names no backend, that a simulation step
reaches for no clock and no loose dice. It runs first in CI and takes under a
second.

Two of them are worth knowing before you write anything:

- **A genre is a package.** What only a shooter wants lives in
  `flutter3d_game_shooter`, so a platformer inherits none of its vocabulary.
- **The engine chooses no backend.** An application picks Impeller, WebGL or the
  software rasteriser; `packages/flutter3d` must not know which exists.

If a rule is genuinely wrong for what you are doing, the exemption lists in
`tool/structure/repository.dart` take an entry with a reason. An exemption
without one is the thing the rule exists to catch.

## Generated files are generated

Levels, models, icons, templates and the WebGL shader translation are written by
scripts and compared with `git diff --exit-code` in CI. Editing the output by
hand passes review and fails the next regeneration.

```bash
python3 apps/flutter3d_demo_dungeon/tool/make_crypt.py   # the crypt's level document
python3 tool/make_models.py                              # the editor's marks
python3 tool/make_templates.py                           # the editor's project templates
```

If you change one of the applications the templates are copied from, re-run the
generator in the same commit.

The shader bundle is the exception to "compared with `git diff`": it is a binary
build artefact, gitignored, and needs `impellerc` to make. So it is checked by
freshness instead — `tool/structure.dart` compares it against the GLSL it was
built from. **Edit a shader and rebuild it in the same sitting:**

```bash
(cd packages/flutter3d_impeller && ./tool/build_shaders.sh)
```

A stale bundle does not fail as a shader behaving oddly. It fails as `failed to
bind texture`, because the renderer binds a slot the new source declares and the
old binary has not got, and the message names neither the shader nor the edit.

## Assets need provenance

Every model, texture and sound ships with an entry in the nearest
`LICENSES.md` — author, source, licence, and what was changed. This is not
paperwork: the repository once shipped a model from an archive with no licence
file and no author, and it could not be released until that was replaced.

Where a fetch can be scripted, script it, so that re-running reproduces the
asset exactly. `apps/flutter3d_demo_dungeon/tool/fetch_weapons.py` is the shape
to copy.

## Comments say why, not what

The house style is to explain a decision by naming the thing that forced it,
usually a bug:

```dart
// A capsule is a shape about its middle and sits on the body's centre; a model
// of somebody standing has its feet at its origin. Rooted at the centre, a
// monster's model hovers half its height off the floor.
```

A comment restating the line below it is noise. A comment recording why the line
is not the obvious one is the only place that knowledge lives.

## Code review

Open a pull request against `main`. In the description, say what broke or what
was missing — the same thing the comments do. A PR that says "refactor
`renderer.dart`" tells a reviewer nothing about what to look for.

Small, complete changes are easier to accept than large ones. A change that
touches one package, updates its tests and leaves `tool/ci.sh` green is the
easiest kind to merge.

## Licence

By contributing you agree that your contribution is licensed under the MIT
licence, the same as the rest of the repository. See [LICENSE](LICENSE).
