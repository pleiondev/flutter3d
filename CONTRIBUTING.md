# Contributing

Thank you for looking. This repository has a few conventions that are not the
usual ones, and every one of them exists because something went wrong without
it. Reading this first will save you a review round.

## Before you start

```bash
flutter pub get          # one lock file for the whole workspace
bash tool/ci.sh          # everything CI runs, in the order it runs it
```

`tool/ci.sh` is the contract for the ubuntu job, and only for that one: it is
what that job runs, so if it is red the first line of the failure names the step
and you can fix it without waiting for a runner. It is not a promise that green
here is green there. The macOS job asks a question this script never puts —
whether the platform-specific half compiles, whether both shader bundles build
with `impellerc`, whether the analyser is clean on a machine that sees the Swift
and the macOS branches — and a repository whose golden scenes can only be
re-recorded on macOS has to ask it somewhere.

Your machine is an input to the answer as much as your diff is. `math.sin` is
libm, and libm is the operating system's, so a generator that does not quantise
its coordinates writes different bytes here from the ones CI regenerates and
diffs; the Python that runs the generators is an input the same way, since a
version that reorders a dict or resamples an image differently produces output
that no longer matches what is committed. When a step fails only for you, or
only for CI, that is the first place to look.

The workspace needs Flutter stable: CI runs Flutter 3.47.0 with its Dart
3.13.0, and the pubspecs ask for Dart `>=3.12.0 <4.0.0` and Flutter
`>=3.44.0` ([SUPPORT.md](SUPPORT.md)). Impeller and Flutter GPU
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

`dart run tool/structure.dart` holds 73 rules about how the repository is
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

### Words the genre scan takes for a genre

The scan reads identifiers, not imports, and it splits them into words — so
`currentLap` fires and `overlaps` does not. A handful of perfectly ordinary
words for a tool are also words of a genre's repertoire, and the fix is a
different word rather than an exemption: an exemption spends the rule to keep a
synonym.

| Instead of | Write | Because |
|---|---|---|
| `dashed`, `dashedLine` | `dotted`, `dottedLine` | `dash` is a platformer's move |
| `reload` | `reopen`, `reread` | `reload` is a weapon's |
| `spike` (an experiment) | `peak`, `probe`, `trial` | `spike` is a hazard |
| `boss` (a supervisor) | `owner`, `parent` | `boss` is a monster |
| `magazine` | `store`, `buffer` | `magazine` holds rounds |
| `lap` (an overlap) | `overlap` is fine; `currentLap` is not | the scan reads words |

`bevel`, `loop`, `face`, `brush`, `bone` and `manifold` all pass, which is what
a modeller is mostly made of. The examples above are checked in
`proveDetectorsWork`, so this table cannot drift from the detector.

## Generated files are generated

Levels, models, icons, templates and the WebGL shader translation are written by
scripts and compared with `git diff --exit-code` in CI. Editing the output by
hand passes review and fails the next regeneration.

```bash
python3 tool/make_models.py                              # the editor's marks
(cd packages/flutter3d_editor_core && dart run tool/regenerate_levels.dart)
                                                         # every level, track and template
```

The level generators are Dart, in `packages/flutter3d_editor_core/tool/levels/`;
a document's `generatedBy` still names the script that first wrote it, and
`tool/levels/shipped.dart` maps that name to the function that writes it now.

If you change one of the applications the templates are copied from, re-run the
generator in the same commit.

The shader bundle is the exception to "compared with `git diff`": it is a binary
build artefact, gitignored, and needs `impellerc` to make. So it is checked by
freshness instead — `tool/structure.dart` compares it against the GLSL it was
built from. **Edit a shader and rebuild it in the same sitting:**

```bash
(cd packages/flutter3d_impeller && ./tool/build_shaders.sh)    # the engine's bundle
(cd packages/flutter3d/example && ./tool/build_shaders.sh)     # the example's, over the same GLSL
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
                                                               # the WebGL translation, compared by git diff
```

A stale bundle does not fail as a shader behaving oddly. It fails as `failed to
bind texture`, because the renderer binds a slot the new source declares and the
old binary has not got, and the message names neither the shader nor the edit.

## The API is a snapshot

Every published package is under strict semver from 1.0.0. Its whole public
surface is written down in `packages/<package>/api/<package>.api`: every
library under `lib/` outside `lib/src/`, every name it exports, each
declaration with its class modifiers and its members' signatures, the
annotations that change what a caller may do (`@Deprecated` with its message,
`@visibleForTesting`, `@protected`, `@internal`, `@experimental` and the
subclass ones), and every re-export of another package with the names it
admits. A re-export of another package of this repository names what it
admits with `show`, so a name added below does not become API above by
arriving there; a whole-library one would be visible as `(whole library)`.
Doc comments, bodies and formatting are not, so rewording or reformatting
moves nothing.

`tool/api` writes the files and checks them:

```bash
cd tool/api
dart run api_snapshot                    # check every published package
dart run api_snapshot flutter3d_core     # check one, each change classified
dart run api_snapshot --update flutter3d_core
dart run api_snapshot --diff old.api new.api
```

A failing snapshot is not a stale golden to refresh: it is a version
decision. The classifier in `tool/structure/api.dart` says which one:

- **A break** (a major release; a minor one before 1.0): a declaration,
  member, library or re-exported name gone; a signature changed; a class
  that can no longer be implemented, extended, mixed in or constructed; a
  new member on a type outside code may `implement`, whatever its body here,
  or a new bodiless member on one it may only extend; an enum value added or
  removed; a new subtype of a `sealed` class; a member made
  `@visibleForTesting`, `@protected`, `@internal` or `@experimental`.
- **An addition** (a minor release): a new declaration, a new member on a
  type nobody outside may implement, a static or a constructor anywhere, an
  optional parameter added where nobody outside overrides, a type opened up,
  a new deprecation.
- **Nothing**: a reworded deprecation, `@immutable` on a `final` class, a
  constant too long to list (`= …`, a generated table).

Three structure rules hold it:

- `every published API is the snapshot its package commits`: the committed
  file is what the source makes.
- `a break in a published API is labelled and versioned`: against the
  snapshot and the pubspec at the newest `vX.Y.Z` tag, a break needs a major
  bump and an entry in the top section of that package's `CHANGELOG.md`
  whose bold thesis begins **`**Breaking:`**, naming each broken name as
  code:

  ```markdown
  - **Breaking: `GraphicsDevice.draw` takes a count.** Every backend passes
    the number of vertices it was asked for; …
  ```

  An addition needs a minor bump. A package with no snapshot at that tag
  has made no promise yet.
- `every deprecation names its versions and its replacement`: below.

Before a release, `tool/publish_check.sh` also runs
`tool/api_against_pub.sh`, which hands each package to `dart_apitool` against
its latest version on pub.dev. It resolves types where the snapshot reads
text, so the two catch different mistakes. It is not installed by anything
here (`dart pub global activate dart_apitool`) and skips, saying so, without
it or offline.

### A break comes with its migration

A break is also work for everybody whose code it breaks, and the release
carries that work out for them where it can. Every break since the last
published release (0.8.5 for 1.0) has an entry in a migration table,
`packages/flutter3d_build/lib/migrations/<from>_to_<to>.yaml`, named by the
minor lines it spans (`0.8_to_1.0.yaml`), and one table
drives three tools:

- `dart fix`, through a `lib/fix_data.yaml` generated into each package for
  the entries the Dart tooling can carry out by itself: `rename`, `moved` (a
  name another library now holds; the fix imports it) and `parameters`.
  The editor offers the same fixes one at a time.
- The `flutter3d_lints` analyzer plugin, for what needs the resolved code:
  `rewrite` (`device.supportsWireframe` becomes
  `device.features.has(DeviceFeature.wireframe)`, but only on a
  `GraphicsDevice`), `implementsToWith`, and `manual`, a diagnostic and a
  TODO with the guide's link. `dart run flutter3d_lints:migrate` applies its
  fixes across a project, because `dart fix` does not apply a plugin's.
- `dart run flutter3d_build:migrate`, which does what neither can, the
  pubspec constraints and imports of libraries that moved between packages,
  then runs the other two and prints the report.

When you break something:

1. Make the change, regenerate the snapshot (`dart run api_snapshot --update
   <package>` in `tool/api`), and label it in the CHANGELOG, as above.
2. `dart run api_snapshot:migration_seed --append` in `tool/api` drafts an
   entry for each break no entry covers yet. It writes what the classifier's
   wording settles (a name that moved, a new case of a sealed type, members
   an implementer now owes) and `TODO` for the rest.
3. Edit the drafts. Prefer a kind a tool carries out: a rename is a `rename`,
   not a `manual` entry saying "use the new name". A break no call can see
   (a constant's value, a widened parameter) is `none`, with the `reason`.
   For a `manual` entry, narrow what it reports with `match: subtypes` (only
   `implements` and `extends` clauses) or `members: [name]`. Otherwise it
   puts a TODO on every use of the type.
4. `dart run tool/generate_migrations.dart` in `packages/flutter3d_build`
   writes the `fix_data.yaml` files, the plugin's `table.g.dart` and the
   table on the site's migration guide.

Entries are appended to the end of the table and never renumbered. Once a
release is tagged, the breaks after it go into a new table whose `from:` is
that tag's version, such as `1.0.0-rc.1`. The old table stays, because a
project can still be on that release, and the generator folds every table
into the fix data. The old table is also closed: the rule `a migration
table is closed once its release is tagged` holds it to its text at the
tag. Start the next table by hand with the old one's header, `from:` the
tagged version and `entries:` empty; `migration_seed` then writes there,
and `migrate` applies every table after the release a project's
`pubspec.lock` resolves. An entry's
`id` is the anchor its diagnostic links to. A deprecation can have an entry
too: it is not a break yet, but migrating it now spares a project the major.

The structure rule `every break since the last release has its migration`
holds this. It names each uncovered break, a table entry still saying
`TODO`, a generated file whose stamp is not the tables', and a published
package whose own version `packages: versions:` does not list. The proof is
the corpus: the 0.8.5 demos and examples, extracted with `git archive`,
migrated, and analysed against this tree must have no errors. See
`tasks/1.0-publish.md`.

### Deprecations say when

A deprecation lasts until the next major, and at least six months after the
release that deprecated it: a major that comes sooner keeps the name. It
names three things, in this order and these words, so a script can list
everything due in a release:

```dart
@Deprecated(
  'Use TonemapCurve.agx, which is now the full AgX transform. '
  'Deprecated in 0.7.4, removed in 2.0.0.',
)
```

The replacement is a sentence beginning `Use ` (or `No replacement`, with
why); the last sentence is `Deprecated in X.Y.Z, removed in N.0.0.`, where
the removal is a major after the deprecation. A bare `@deprecated` says none
of it and fails, and so does one still here at or past its removal version.

### The hardware interface

A capability a backend cannot provide yet is not a reason to leave it out of
the interface. It goes in, the backend leaves it out of `features`, and the
call throws `UnsupportedCapability` with a `TODO(<backend>)` saying what would
unblock it. `capabilityChecks` in `flutter3d_conformance` holds both halves.

## Tools for agents are a contract too

An MCP tool is called by name from somebody's host config, with arguments a
model read out of its schema, and a VM service extension is called by name
from an editor attached to a running game. Neither caller compiles against
anything here, so a rename passes every test in this repository and breaks
every one of them. Since 1.0.0 both follow the same semver as the Dart API
(decision 11 in `tasks/1.0-stability.md`), and both are written down:

- `packages/<package>/api/<package>.mcp`, for every published package with a
  `ToolTableServer` subclass: each server's announced name, its schema
  version and aliases, and for each tool its name, the first sentence of its
  description, its `hints` (read-only, destructive), one `arg` line per
  argument with `required` where it is and its JSON schema with keys sorted,
  and an `out` line with the schema of the `structuredContent` it answers.
  `description` and `title` are taken out, so rewording a hint moves nothing.
- `packages/<package>/api/<package>.plugin.mcp`, for a package whose plugin
  adds tools to a project: `--plugin package:<package>#<Plugin>` installs it
  into an empty `McpTools` and writes what it added, by namespace, with the
  schema version the namespace declared.
- `packages/<package>/api/<package>.vm`, for every published package that
  registers a VM service extension or posts a game event: each extension
  with the parameters its handler reads and the type it parses each as, a
  `->` line with the keys it answers, and each `postToolEvent` kind as
  `flutter3d.<kind>`. An engine extension registers through
  `registerFlutter3dExtension`, so `ext.flutter3d.version` lists it; a
  plugin's goes through `VmExtensions` and is `ext.flutter3d.<pluginId>.*`.

**Tools are named `area.verb`**: what is acted on, a dot, what is done to
it (`brush.add`, `run.step`). A server takes its tools' written names to
`ToolName`s in `names:`, and the written name stays an alias until the next
major. Every tool is a `ToolSpec` and every answer a `ToolResult`, from
`flutter3d_mcp`'s `kit.dart`; the MCP library's own types stay inside the library that
builds the schemas (its `mcpTool` builder is not exported).

```bash
cd tool/api
dart run api_snapshot:schema_snapshot                      # check them all
dart run api_snapshot:schema_snapshot flutter3d_mcp  # one, classified
dart run api_snapshot:schema_snapshot --update flutter3d_mcp
dart run api_snapshot:schema_snapshot --diff old.mcp new.mcp
```

A plain Dart server is built and its `tools` list read back, so whatever its
constructor does to the tools is in the snapshot. A server in a package that
needs Flutter cannot be built under `dart run`, so its tool list is read from
source: the list its constructor passes as `tools:` has to be a list of
`X(mcpTool(...), handler)` or of calls to a top-level function returning
one, either of them allowed under an `if` with no `else`, and the helpers
those `mcpTool(...)` expressions use have to be top-level functions or constants.
Anything else is refused by name rather than half read. A new plain Dart
server goes into `tool/api/lib/live_servers.dart`, and the tool says so if
it is missing.

**A tool offered to some hosts only** is in the snapshot with a `when` line
under its name: `sim_mcp`'s `order` says `when game is OrderedGame`, since
the session offers it only for a game played by orders. The list is built
for a probe game that is every kind the tools ask about, with placeholders
(`{game}`, `{order}`, `{argument}`) where a host's own game fills in names,
so a guarded tool is checked like any other and the `when` line says who
gets it.

The classifier in `tool/structure/schema.dart` says what a change is:

- **A break**: a tool, server, extension or event gone; a tool renamed
  without its old name kept as an alias; an alias dropped; a new required
  argument, or an optional one made required; an argument removed or its
  type changed; a schema narrowed (an `enum` value removed, a `minimum` raised
  or a `maximum` lowered, `additionalProperties` closed, a `pattern` or a
  `format` added or moved); an extension that stops reading a key; a tool
  that every host had made conditional, or its condition changed.
- **An addition**: a new tool, server, extension or event; a new optional
  argument; a schema widened; a tool renamed with its old name kept as an
  alias; a conditional tool offered to every host; an extension reading a
  new key. The VM service hands every
  parameter over as a string and cannot say which are required, so **a new
  key has to have a default**: an old caller does not send it.
- **Nothing**: a reworded description, anywhere.

**Renaming a tool.** Give the server an alias, old name to new, through
`ToolTableServer`'s `aliases`. The old name stays in `tools/list` with the
new tool's schema and a description that starts by saying it is deprecated
and what to call instead, and a call to it runs the new tool. It stays until
the next major release, like a deprecated Dart name.

**The schema version.** Each server announces one beside its version, in the
`initialize` result's `serverInfo` as `schemaVersion` — `editorMcpSchemaVersion`,
`modelMcpSchemaVersion`, `projectMcpSchemaVersion`, `simMcpSchemaVersion`,
`renderMcpSchemaVersion` and `pluginAuthorMcpSchemaVersion`; the VM service
extensions answer to `vmSchemaVersion`.
It moves only when that server's tools do: a minor for an addition, a major
for a break. A host can cache a tool list against it. Every server starts at
1.0.0 with the first stable release, whatever it counted before: nothing was
promised before it. A plugin's namespace versions its tools the same way,
with `McpTools.declareSchemaVersion`, which is honoured whenever it is
called and withdrawn with the plugin.

Every tool says what it does to the world (`ToolHints`: read-only,
destructive, idempotent, open-world), and every tool of the editor's and the
modeller's servers declares the `structuredContent` it answers with as its
`outputSchema`. The snapshot prints a tool's hints, and `hints writes` for
an ordinary edit, which the protocol would otherwise leave a host to guess.

Two structure rules hold this, the same way the API's two do:

- `every MCP tool and VM extension is the snapshot its package commits`.
- `a break in a tool or an extension is labelled and versioned`: against the
  snapshots and the pubspec at the newest `vX.Y.Z` tag, a break needs a
  major bump of the package and of the server's schema version, and a
  `**Breaking:` entry in the top CHANGELOG section naming each broken tool,
  extension or event as code — `` `play_swap` `` or
  `` `ext.flutter3d.level.apply` ``. An addition needs a minor of both.

## File formats read their past

A 1.x build opens every file a 1.x build wrote. Each reader accepts every
version up to the one it writes and refuses only a newer one, saying which
version to update to. A change that alters what an existing field means
bumps the format's version and adds the step that lifts the previous
version to the reader's migration list. A new field an older reader can
skip needs no bump. Unknown fields are kept wherever the format has a place
to keep them.

Every version a reader opens has a fixture under the package's
`test/fixtures/v<N>/`. A fixture is minted once, at the moment of the bump,
and never re-minted. When a fixture test goes red, re-minting it throws the
promise away; either the change was a mistake or it needs a migration.

`every versioned format has a fixture for each version it reads` holds this.
It reads the version each reader declares, counts the fixtures listed in
`versionedFormats` in `tool/structure/repository.dart`, and fails on a version
constant that is not listed there or in `notAVersionedFormat`. It also fails
on a `!=` against the current version, the gate that refuses every older
file. Shader bundles are handled differently because they are build
artifacts. The build stamp carries their versions, so an update rebuilds
them, and a bundle the runtime cannot read is refused as stale.

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
// A capsule is a shape about its middle and sits on the body's center; a model
// of somebody standing has its feet at its origin. Rooted at the center, a
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

**A red `main` blocks the merge.** Nothing lands on top of a broken build, even
a change that has nothing to do with what broke: the second commit makes the
first one's failure somebody else's to untangle, and by the third nobody can
tell which one to revert. Fix or revert what is red first, then merge. A pull
request whose own job is red is the same rule one step earlier — it does not go
in on the argument that the failure is unrelated.

## Licence

By contributing you agree that your contribution is licensed under the MIT
licence, the same as the rest of the repository. See [LICENSE](LICENSE).
