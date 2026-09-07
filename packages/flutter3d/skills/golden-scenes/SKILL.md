---
name: golden-scenes
description: Use when a change could alter a rendered pixel, or when adding a scene to the golden set — the references are recorded per backend, compared across backends, and the count is written in prose a scan checks.
---

# Golden rendering, and the three sets

Golden rendering needs a real GPU, so it cannot run under `flutter test`, which
is headless. Each scene runs as the engine's example application instead, which
renders one fully-specified frame and exits with a code the script reads.

```bash
packages/flutter3d/tool/golden.sh                  # compare, through Impeller
packages/flutter3d/tool/golden.sh --update         # record instead
packages/flutter3d/tool/golden.sh shadow-teapot    # just that one
packages/flutter3d/tool/golden.sh --cpu            # the software rasteriser
packages/flutter3d_webgl/tool/golden_web.sh        # a real browser
```

Three reference sets, one per backend, each in that backend's own `test/goldens`.
Their own and not a shared one: the software rasteriser has no multisampling, so
it cannot reproduce Impeller's pictures byte for byte, and a shared set would
need a tolerance — which is a threshold that stops watching.

Held to zero against itself, a set answers "did this backend change". The
cross-backend question — do the two draw the same picture — is a plain test over
the two committed sets, `flutter3d_cpu/test/cross_backend_test.dart`, and needs
no device at all. That is the one CI runs, and it is the question that actually
matters.

The web set is one build for the whole suite: the scene is a query parameter
rather than a compile-time define, so it is one dart2js run and a navigation
each rather than a dart2js run each. That is the only reason it is minutes
rather than an hour.

## The count is in prose, and a scan holds it

The scene names come out of `example/lib/src/spike/golden_scenes.dart` — the
scripts grep them rather than keeping a second copy that can fall out of step.
The *number* of them is a different matter: it is written in `tool/ci.sh`, in
`golden_web.sh`, in `ARCHITECTURE.md`, on the site and in doc comments all over
the tree, and three of those carried three different answers at once before a
rule existed. `dart run tool/structure.dart` counts the PNGs and says what the
sentence should be.

A scene the site shows is checked too: `{{golden name}}` resolves at build time
against the sets, and the site is built on deploy rather than in CI, so the scan
asks the same question where every push sees it.

## After a Flutter upgrade

The shader bundle format is tied to the Flutter version, so references recorded
on one SDK will not match another. Re-record — and read the diff rather than
accepting it blindly. That difference is the entire thing these tests exist to
show.

## Adding a scene

Record it in every set the site draws from, or the site's build breaks on a
picture that is not there. Then swap one reference for another's and confirm the
comparison fails, for the reason `test-by-breaking` gives: a golden suite that
cannot fail is worse than none, because it is believed.
