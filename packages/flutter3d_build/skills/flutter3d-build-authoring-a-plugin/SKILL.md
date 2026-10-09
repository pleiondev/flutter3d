---
name: flutter3d-build-authoring-a-plugin
description: Use when writing a flutter3d plugin — choosing its kind, creating the package from a template, running the conformance suite through the plugin author's MCP tools, reading the report, and what the badge needs.
---

# create, edit, conformance, report

```
plugin.create       directory, name, kind   a package from a template
dart pub get        (in the directory)      before anything runs
… edit lib/<name>.dart …
plugin.conformance  directory               the suite, test by test
plugin.report       directory               each check, and the badge
```

The server is `dart run flutter3d_build:plugin_mcp`. A person does the same
from a terminal with `dart run flutter3d_build:create plugin --kind <kind>
--name <name>` and `dart test test/conformance_test.dart`.

## Choose the kind first

The kind decides what the plugin may touch, and the host holds it to that.

- **render-step** — a full-screen pass at a render anchor, switched like a
  built-in step. A view plugin.
- **effect** — something seen when an event arrives, aged once a frame. A
  view plugin.
- **genre** — a step phase of its own between `physics` and `elements`, with
  rules that publish events. Touches the simulation.
- **element** — a field of the world stepped in `elements`. Touches the
  simulation.
- **tool** — an MCP tool published as `<plugin id>.<tool>`. A view plugin.

**A view plugin is refused anything in the step**: a step phase, a system in
one, a subscription to the step channel. If what you are writing changes
what the simulation computes, it is a genre or an element, and its switch is
written into every run so a replay makes it at the same step.

## What each check means

- **manifest** — the id is well formed, the API version is one this engine
  provides, the permissions are ones it knows.
- **switch** — switched off and on again at a step boundary, the plugin
  takes out everything it registered and puts it back.
- **determinism** — each step is run twice from a snapshot of the world the
  conformance test gave, and the two runs must agree after every system. A
  failure names the system and the plugin. With no world given it is
  declined, not passed: give `capture`, `restore` and `digest` in the
  harness, covering the plugin's own state.
- **backends** — the plugin installs on every backend its manifest names,
  and is switched off with a reason on one it does not.
- **budget** — the manifest's `extra: {'budget': {...}}` is declared and
  kept: step time and events per step.

## The badge

Earned when every check ran and passed on every declared backend, with a
world given to determinism and a budget declared and kept. A declined check
is a check not made, so it is no badge. `plugin.report` says which check
stands in the way.

## Code that runs in a step

Genre and element templates enable the `flutter3d_lints` analyzer plugin in
`analysis_options.yaml`. It flags what makes a step unrepeatable: a wall clock
(`DateTime.now`, `Stopwatch`), an unseeded `Random`, and a `dart:math`
transcendental where `Portable` gives the same bits on every platform. Fix
what it says rather than silencing it: the determinism check will find the
same thing later and less kindly.

## Publishing

Keep the `flutter3d-plugin` topic in the pubspec. The plugin catalogue on the
flutter3d site is read from pub.dev by that topic, and lists the package
after its next build.
