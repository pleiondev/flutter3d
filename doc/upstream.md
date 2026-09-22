# Upstream: what we have filed against flutter/flutter

*Verified 2026-09-18 with `gh pr list` and `gh issue list --author @me`. This
document exists because the work was invisible: five pull requests and seven
issues were open against the Flutter engine and no document in this
repository mentioned any of them. A survey looking for "our upstream patches"
found nothing in `doc/` and concluded there were none, which was wrong by
twelve filings.*

Numbers here are checked against GitHub, not recalled. Two filings an
earlier survey attributed to us — `#190871` and `#191829` — are **not** ours;
they do not appear under our authorship and must not be cited as our
evidence.

## Pull requests

| # | Title | State | Opened | Review |
|---|---|---|---|---|
| 192539 | [Impeller] Key the Vulkan framebuffer cache on the whole attachment set | open | 2026-09-10 | required |
| 192536 | [Impeller] Refuse a Vulkan render target with no color attachment | open | 2026-09-10 | required |
| 192475 | [Impeller] Let a render pass set the blend constant | open | 2026-09-09 | required |
| 192423 | [engine_tool] Allow a dot in GN target names | open | 2026-09-08 | **changes requested** |
| 192398 | [Flutter GPU] Reuse HostBuffer blocks after a block boundary, and view only the write | open | 2026-09-07 | required |

Four are awaiting a first reviewer. One has been reviewed and has changes
requested — which matters, because it is the only evidence that the path is
not simply dead, and an earlier summary of this table said "zero reviewers
assigned" across all five. That was wrong.

There is no `CODEOWNERS` entry for `engine/src/flutter/lib/gpu`, so nobody is
auto-assigned.

## Issues

| # | Title | State | Comments |
|---|---|---|---|
| 192538 | [Impeller/flutter_gpu] The Vulkan framebuffer cache is keyed on the color attachment alone | open | 4 |
| 192535 | [Impeller/flutter_gpu] A render target with only a depth attachment crashes | open | 1 |
| 192449 | [Flutter GPU] No way to sample a depth texture | open | 0 |
| 192422 | [engine_tool] `et` rejects every Dart test target because their names contain a dot | open | 1 |
| 192397 | [Flutter GPU] `BlendFactor.blendColor` and the three factors beside it silently do nothing | open | 3 |
| 192396 | [Flutter GPU] Uniform and texture bindings survive `bindPipeline` | open | 1 |
| 192392 | [Flutter GPU] `HostBuffer` never reuses a block after a boundary crossing | open | 1 |

## What this ledger is for, and the three rules that come out of it

**1. The deliverable is the filing, never the merge.** The shipping
arithmetic, measured on a change by the area owner himself
(render-to-mip-level: merged 2026-06-09, stable 2026-08-12): 64 days, best
case, and that is for someone with commit rights. Feature work is explicitly
excluded from the cherry-pick shortcut, so the path is master → ~2 weeks to
beta → up to a quarter of betas before promotion, with review as the
unbounded term. Nothing in this repository may depend on a filing landing.

**2. Do not file a sixth pull request on the theory that cheap correlates
with landing.** Chase the five that exist: rebase each onto master so the
diff is current, and ping once at the two-week mark. The class of filing that
*has* moved for us is the crash report — `#192397` drew three comments,
`#192538` drew four — while the capability request `#192449` has drawn none in
ten days. If something new is filed, file it as the crash it is, not as the
feature we want.

**3. Keep `#192449` open and forbid the dependency.** Sampled depth textures
is the most defensible of our filings on merit and it unlocks no
postprocessing step we want. Worse, if it lands it will tempt us to throw
away `surface.a`, which carries view-axis depth in metres and is exactly what
a thin-lens circle-of-confusion needs. Every post row keeps reading
`surface.a`. This is recorded as a row (`gfx-58n`) so the temptation has an
answer attached.

**`gfx-58n` landed 2026-09-18, as a rule rather than a paragraph.** "The
surface buffer keeps carrying depth in metres" is one of the thirty-five
checks `tool/structure.dart` runs: it fails if `lib/color.glsl` stops writing
`ViewDepth()` into the channel, and it fails if any shader declares a depth
sampler. A rule can be read by somebody who never opened this document, which
is the difference between an answer attached and an answer written down.

**`gfx-51n` landed with it, and the survey's version of the fact was wrong.**
The row was recorded as "`texelFetch` aborts impellerc at the default GLES
target and compiles only with `--gles-language-version=300`". The bundle
builds today with fragment stages that would have contradicted that, and
`lib/morph.glsl` carries the bisected account: impellerc crashes on
`texelFetch` in a *vertex* stage — SIGABRT, exit 134, no diagnostic — while a
fragment stage compiles it. The rule enforces the narrower claim, which is the
one with evidence behind it, and it ignores comments so that the file
documenting the constraint is not the file it flags.

## Why a runtime engine patch cannot be a feature of our packages

A `flutter_gpu` or Impeller runtime change compiles into
`libflutter`/`Flutter.framework`. Every developer and every CI job would need
`--local-engine` plus a matching per-ABI build, and a consumer running
`flutter build` against stock stable cannot get it at all. Our packages are
published to pub.dev; a pubspec constrains SDK versions and nothing else. So
a runtime patch is a demo, a benchmark, or a proof attached to a pull
request.

`impellerc` is the one exception, and it is why the only engine-shaped row
worth writing is a compiler row. It is a prebuilt **host-only** binary —
`shader_bundle_build.dart` resolves
`$SDK/bin/cache/artifacts/engine/<platform>/impellerc` — and a bundle it
produces loads on a stock engine while `ShaderBundleFormatVersion` stays 2.
We ship the built bundle as a package asset. A patch confined to
`impeller/compiler` changes our build machine and nothing a user runs.

The one such patch: `compiler.cc` reads a single `gles_language_version`
field for both the GLES and the desktop-GL target, so
`--gles-language-version=300` emits an illegal `#version 300` for desktop GL.
Worth writing only as the safety belt on passing that flag in our own build,
which is not an engine change at all.

## The advantage none of this buys

`flutter_gpu` and `flutter_scene` are written by the same person. Anything we
land upstream reaches the engine they consume at the same moment it reaches
ours, and their `render_pass_compat.dart` — a `try`/`NoSuchMethodError` shim
in a published 0.23.0 package — means adopting a new API costs them one
implementation and no SDK floor bump. It costs us four backends and up to 176
re-recorded golden frames, three sets of which cannot be recorded on this
machine.

So the lead time on a public patch is zero or negative for us. File upstream
because a bug should be fixed for everyone, which is a good enough reason.
Do not file upstream expecting an advantage.
