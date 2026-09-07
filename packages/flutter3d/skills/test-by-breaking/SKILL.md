---
name: test-by-breaking
description: Use when writing or reviewing a test in this repository — every test has to be shown to fail, the mutation has to be named in a comment beside it, and the test count lives in documents a scan checks.
---

# A test that has never failed has not been shown to test anything

The rule, from `CONTRIBUTING.md`: after writing a test, break the code it covers
and watch it go red. Then put the code back and name the mutation in a comment
beside the test.

```dart
test('and a dead one holds its final pose', () {
  // Mutation: return `AnimationWrap.loop` unconditionally, which is what the
  // default did and what the bug was — fails here and nowhere else.
  ...
});
```

The comment is the point twice over. It tells the next reader what this test is
for, in a way the assertion cannot; and it tells a reviewer that the check was
actually made, which is otherwise unfalsifiable. `ARCHITECTURE.md` §13 has the
longer version.

"Fails here and nowhere else" is worth aiming at. A mutation that turns forty
tests red has told you the suite is alive and nothing about this test.

## What the failure to break usually looks like

Not an assertion that is wrong — an assertion that cannot be reached. Five of
six lighting goldens once recorded byte-identical images because the scene's
lighting model reached the UI field and never the materials: every reference was
PBR, every comparison passed, and the suite was believed. A golden set that
cannot fail is worse than none.

The same shape appears in shell steps. A `git diff --exit-code` step in
`tool/ci.sh` used a pathspec with a `*` in the middle of a path, which in git
matches nothing here, so it passed whatever the generators wrote. It was found
by breaking a generator and watching the step stay green — which is this rule
applied to a script rather than to a `test(...)`.

## The count moves when you add a test, and three documents say what it is

`dart run tool/structure.dart` counts `test(` and `testWidgets(` declarations
across every package and application, and holds the number against:

- `ARCHITECTURE.md` §13, which states it as `**N tests** across M packages`;
- the repository `README.md`, which says it in prose with the package count as
  a word;
- the pages under `site/content`, whose testing page also carries a per-package
  table — a row is held to its directory, a directory with tests is held to
  having a row, and the sentence that reconciles the two totals is held to both.

A package's own `README.md` is a fourth, and a different question: if it states
a count at all it is held to its own `test/` directory, not to the workspace,
because that is the number a stranger meets on pub.dev. Only a README that
states a count is held to one.

So a change that adds tests updates those numbers. `dart run tool/structure.dart`
says what each should be.
