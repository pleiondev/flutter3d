# release_dashboard

A live page over the state of a release. It answers one question while the work
is going on: what is still between this tree and the day the shelf goes out.

    dart run tool/release_dashboard/bin/release_dashboard.dart

Open the address it prints (`http://127.0.0.1:8765/` by default). The page
updates itself; nothing needs reloading.

    --port <n>         where to listen (default 8765)
    --root <path>      the repository (default: found from the current directory)
    --release <x.y.z>  the version the shelf should carry (default 0.7.0)
    --no-auto          do not run the quick checks when the tree changes

## What the page shows

- **Five stages**, in the order the work goes: stabilise the branch, finish
  what was started, prepare the shelf, publish the modeller, publish the
  packages. Each row is green, red, running, waiting or unknown, with one
  sentence of what was found.
- **Checks**: the repository's own scripts (`dart format`, `tool/structure.dart`,
  `tool/verify_plan.dart`, `flutter analyze`, `tool/publish_check.sh`, the web
  build, `tool/ci.sh`). The fast ones run by themselves once the tree has been
  still for four seconds. The slow ones run when you press the button. They
  run one at a time, because each takes the pub lock or the whole CPU.
- **Packages**: version, top CHANGELOG heading and pub.dev's version for every
  package, with the reasons one would not publish (wrong number, a sibling
  constraint that does not admit it, a CHANGELOG that stops at an older
  heading).
- **Remote**: whether the branch is pushed and CI's verdict per job (through
  `gh`), whether models.pleion.dev answers and how many tutorial cases it lists.
- **Worktrees** other sessions are working in, and a log of what turned since
  the page was opened.

## Where each row comes from

Nothing here is a second implementation of a rule. A gate runs the script CI
runs and reads its output, so a rule changed in `tool/structure/` changes the
page without an edit here. The rest is read from files (`pubspec.yaml`,
`CHANGELOG.md`, `doc/plan-status.json`), from `git`, and, when they can be
reached, from GitHub, pub.dev and the modeller's server.

**Unknown is not pending.** *Pending* means the thing cannot have happened yet,
such as a tag for a release that is not published. *Unknown* means the
dashboard has not measured it, or the source did not answer. A page that drew
both in grey would say "nothing to worry about" about a network that was down.

The checklist itself is one pure function of the snapshots
(`lib/src/checklist.dart`). To follow a different release, change
`ReleaseConfig` and the probes in `lib/src/probes.dart`.

## Safety

It listens on `127.0.0.1` only. A page open in the same browser can still send
requests to it, so a POST is refused without an `x-dashboard: 1` header (a
cross-site request cannot add it without a preflight this server never
answers) and without this server's own `Host`. It writes nothing to disk.

## Tests

    dart test

They use fake sources, so no repository, network or `gh` is needed.
