---
name: structure-scan
description: Use when a change moves a file, adds a package, renames a rule or touches a number written in prose — the structure scan is the first thing CI runs and the cheapest place to find out.
---

# The structure scan runs first, and it needs nothing

```bash
dart run tool/structure.dart            # every rule
dart run tool/structure.dart --list     # name them and stop
dart run tool/structure.dart --only 'engine names'
```

Thirty rules, all of them reading source text. No `pub get`, no shader bundle,
no device, under a second. That is why it is the first step in `tool/ci.sh`:
finding out after four minutes of building that a package imports a genre is
finding out late what could have been known before anything started.

## What kind of thing it holds

Two families, and they fail for different reasons.

**Arrangement.** A genre package names no other genre; the hardware layer names
no graphics API; the engine names no backend; a simulation step reaches for no
clock and no loose dice. These are the boundaries the repository is built on,
and a violation is a design decision made by accident. The `import-layers`
skill has the layer rules one by one.

**Numbers written in prose.** How many tests there are, how many golden scenes,
how many rules, how many checks the conformance suite runs, how many enums the
HAL promises. Every one of these was wrong in at least two documents at once
before a scan existed, and each time in a different direction — which is the
part that matters. A reader who finds two numbers in one repository disagreeing
has no way to tell which of the others to trust.

The number rules read Dart doc comments as well as documents. A sentence in a
comment is a number nobody recounts, exactly like a sentence in a README, and
there are far more of them.

## When a rule is genuinely wrong for what you are doing

The exemption lists live in `tool/structure/repository.dart`, and an entry takes
a reason as its value. That is not decoration: the table is as much the rule as
the regular expression is, and the next reader has to be able to tell a
considered exception from something somebody silenced to get a build green.

Deleting a rule because it fired is almost never right. A rule that fires on
correct code is a rule whose sentence is wrong, and the fix is the sentence.

## The trap this scan itself fell into

One rule — the one about the shader bundle being no older than its sources —
returned "nothing to compare" on every machine that ran the whole scan, because
the bundle is gitignored and a fresh checkout has none. It could not fail, for
as long as it had existed. `tool/ci.sh` now asks it a second time, after the
bundle is built, with `--only 'shader bundle'`.

So when you add a rule: make it fail on purpose once, in the place it will
actually run.
