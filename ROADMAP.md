# Roadmap

Revised 2026-10-15, for the 1.0.0-rc.1+2 tree.

This file is rewritten at every candidate and at every release, and a
structure rule fails when the version it names is not the one the packages
carry. What has already shipped is not here: it is in each package's
`CHANGELOG.md`, beside the version that carries it. This file is the part
that has not happened yet, and one paragraph on where the tree stands.

The working plan behind it is
[`tasks/1.0-rc1-plan.md`](tasks/1.0-rc1-plan.md), and the seams 1.x is
built on are [`tasks/1.0-seams.md`](tasks/1.0-seams.md). If this file and
the plan disagree, the plan was revised later and this file is wrong.

## Where it stands

61 packages are to be published. In the tree, all 61 are at
`1.0.0-rc.1`, the two platform plugins `pad_input` and
`flutter3d_pointer_lock` included. pub.dev still has 0.8.x as the newest, and nothing of the candidate
is published yet. The API shape,
the materials catalog, the hot-path work, the seams for 1.x and the
contracts rc.2 fills are in. What is left for rc.1 is release work: every
suite green on a clean checkout, the proof on hardware, the publishing, the
documents, and the adoption work that has to be there on the day people
first try it.

## 1.0.0-rc.1: reliability and the shape of the API

Everything a user can write against rc.1 is the 1.0 contract. Between the
candidates a break is still allowed, with its migration; at 1.0.0 the
contract freezes.

The tag waits for:

- **Green.** `tool/ci.sh` green on a clean checkout of the tag, and the
  Windows job.
- **Proof on hardware, each with a number.** Frame pacing for three demos
  on a Galaxy A55 and a mid-range iPhone (p50 at most 16.7 ms, p99 at most
  33.3 ms); the C physics core bitwise equal across six compilers and
  targets on two recorded tapes; the APK, IPA and web sizes of the example
  app under their limits; and the nightly run on the A55 green seven nights
  in a row. A two-hour soak and rollback between eight phones join these
  if their tools are ready in time, and move to rc.2 if not.
- **One proof per audience.** A game is the pacing above. A twin reads one
  real source, keeps its history on a tape and scrubs it. A laboratory has
  a named analytic test with a number (a pendulum's period within 1e-4 of
  the series over 100 periods).
- **Published.** All 61 packages on pub.dev in the layer order, the five
  names they replaced marked discontinued, and a fresh `flutter create`
  project reaching a first frame on macOS and in Chrome with
  `^1.0.0-rc.1`.
- **Ready for the first visitor.** The quickstart from the pub user's side,
  a cookbook of 20 short recipes that builds in CI, a release page for the
  tag, the migration guide live, and a place to ask questions.

## 1.0.0-rc.2: breadth

Every item is additive under the rc.1 contract, and rc.2 is not optional:
1.0.0 follows rc.2, never rc.1, so no type that rc.1 lands as an empty
contract reaches 1.0.0 empty.

- The demos and the examples on the new entry points.
- The viewer widget and its kit, text and sprites, video, reverb, point
  clouds, the three lighting models, assessment and rules for lessons,
  terrain and grass.
- WebXR in the browser and OpenXR on a native headset.
- The editor inside the plugin contract, and the Wasm render ABI.
- The model hub's client and `vendor`, with the cookbook moved onto hub
  references.
- Proofs that need more than rc.1 had: the conformance scenes through GLES
  and Vulkan on an Android emulator and through ANGLE on Windows, a GLES
  phone in the pacing set, and the soak and the eight phones if they were
  not done for rc.1.

## 1.0.0

rc.2 green, and the model hub's server ready, because the cookbook and the
site load models from it and a 1.0.0 with the hub "coming soon" is worse
than one without it. The server's list: immutable versions, a public mirror
whose address is in the 1.0 client, `Cache-Control: immutable`, CORS and a
rate limit, a quota, sign-in to upload, a report button, terms of use and a
DMCA procedure, and a licence field on publishing. If the list is not done,
the tag waits.

From 1.0.0 the packages follow strict semver, and [SUPPORT.md](SUPPORT.md)
says which releases get fixes and for how long. They share a major.minor:
a minor or a major moves all of them, and a patch goes only to the package
that needs it, so a repair for a new `flutter_gpu` is `flutter3d_impeller`
1.0.1 beside the rest at 1.0.0.

## 1.x

Each minor moves the whole shelf, adds and breaks nothing: its API diff has additions only, the
default `SimulationVersion` stays, goldens stay or the old look sits behind
a setting, conformance passes on four backends, and the outside sample
plugin builds.

- **1.1**: adoption. The cookbook grows, the time to a first scene goes
  down, and projects we did not write are the measure.
- **1.2**: living materials, where wetting and heat change a surface's look
  and mass; and physics-driven audio as an outside package, which proves
  the engine needs no change for it.
- **1.3**: volumetrics fed by simulation fields, and a heat, steam and light
  laboratory in `flutter3d_education`.
- **1.4 and later**: probe GI, a streaming scheduler and character
  animation, when people ask for them.

Trace export in the Chrome and Perfetto format is additive and lands in
whichever minor is ready for it. New world properties (humidity, ozone,
salinity) arrive one at a time, each with the code that reads it.

## Not in 1.x

- **A `vector_math_64` scene layer**, for scenes that need doubles. Decided
  for 2.0, because it changes types every application touches.
- **A digital-twin package of our own.** A twin is built outside the engine
  against its hooks; the example in this repository shows how.
- **Research without a date**, kept in 0.x packages so it cannot break the
  1.x contract: granular media, coupled heat, fluid and structure, reaction
  kinetics, inverse physics, Gaussian-splat hybrids. Virtualized geometry
  waits until `flutter_gpu` has compute and indirect draws.

## How this file changes

It is rewritten when a candidate or a release is tagged, and when a
decision moves an item between the sections above. Every item is then in
one of four places: shipped and gone to a changelog, still planned, moved
to a later release, or moved to *Not in 1.x* with the sentence that says
why. I would rather say an item slipped than let it disappear without a
word.
