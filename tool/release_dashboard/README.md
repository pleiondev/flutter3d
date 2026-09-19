# release_dashboard

The state of a release in one look, and a page that shows it. It answers one
question while the work is going on: what is still between this tree and the day
the shelf goes out.

There are two halves, and neither is a server.

- **`bin/release_dashboard.dart`** takes one look and prints JSON. It reads the
  tree, asks git, GitHub, pub.dev and the modeller's own server, and runs the
  quick checks that have not judged this tree. Then it exits and opens no port.
- **`page.html`** is the page, published as an artifact. It subscribes to one
  document, `release/state`, in the artifact's database and redraws when that
  document changes. It cannot see this machine; it shows what was last written.

Whoever runs the tool writes its output into that document. In this repo that is
the Claude session doing the release, on a schedule, with `ArtifactData`.

    dart run tool/release_dashboard/bin/release_dashboard.dart --out state.json

    --out <file>       write the JSON there instead of printing it
    --run <id,id>      also run these checks, whatever they last said
                       (format, structure, plan, analyze, publish, web, ci)
    --root <path>      the repository (default: found from the current directory)
    --release <x.y.z>  the version the shelf should carry (default 0.7.0)
    --no-auto          do not run the quick checks that are out of date

## What the page shows

- **Five stages**, in the order the work goes: stabilise the branch, finish what
  was started, prepare the shelf, publish the modeller, publish the packages.
  Each row is done, broken, running, waiting or not measured, with one sentence
  of what was found.
- **Checks**: the repository's own scripts (`dart format`, `tool/structure.dart`,
  `tool/verify_plan.dart`, `flutter analyze`, `tool/publish_check.sh`, the web
  build, `tool/ci.sh`), with the last verdict, how long ago, and whether the tree
  has changed since.
- **Packages**: version, top CHANGELOG heading and pub.dev's version for every
  package, with the reasons one would not publish (wrong number, a sibling
  constraint that does not admit it, a CHANGELOG that stops at an older heading).
- **Remote**: whether the branch is pushed, CI's verdict per job (through `gh`),
  whether models.pleion.dev answers and how many tutorial cases it lists.
- **Worktrees** other sessions are working in, and what changed between the
  snapshots this page has seen.
- **How old the numbers are.** The page is only as fresh as the last write, so
  it says so, and warns when nobody has refreshed it for half an hour.

## Where each row comes from

Nothing here is a second implementation of a rule. A check runs the script CI
runs and reads its output, so a rule changed in `tool/structure/` changes the
page without an edit here. The rest is read from files (`pubspec.yaml`,
`CHANGELOG.md`, `doc/plan-status.json`), from `git`, and, when they can be
reached, from GitHub, pub.dev and the modeller's server.

**Not measured is not waiting.** *Waiting* means the thing cannot have happened
yet, such as a tag for a release that is not published. *Not measured* means
this tool has not looked, or the source did not answer. A page that drew both in
grey would say "nothing to worry about" about a network that was down.

**Results are kept.** Each check's verdict is written to
`.dart_tool/release_dashboard/results.json` with the state of the tree it
judged. A later look reruns a quick check only when the tree is different, so a
look at an unchanged tree runs no scripts. The slow checks (`publish`, `web`,
`ci`) run only when asked for with `--run`.

The checklist itself is one pure function of the snapshots
(`lib/src/checklist.dart`). To follow a different release, change
`ReleaseConfig` and the probes in `lib/src/probes.dart`.

## Tests

    dart test

They use fake sources, so no repository, network or `gh` is needed.
