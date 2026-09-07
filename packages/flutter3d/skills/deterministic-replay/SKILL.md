---
name: deterministic-replay
description: Use when touching a simulation step, a save, a random draw or anything a run has to reproduce — the same tape must produce the same run on another machine and in a browser, and there is machinery here that measures it.
---

# The same tape, the same run, everywhere

A run is submitted to a verifying server as the inputs that produced it, and the
server does not believe the score it was sent: it replays the tape and works the
score out itself. That proof is worth nothing unless the server's replay is the
same run as the player's, to the last bit, on a different processor and — for a
game published to the web — in a browser rather than in the VM at all.

Everything below exists to keep that true, and to notice the day it stops being.

## The pieces

**`GameRandom`** (`flutter3d_sim/lib/src/save/game_random.dart`) — randomness
with a state you can write down. `math.Random` has no readable state, which
makes it the one thing in a simulation that cannot go in a snapshot: two saves
taken a step apart would restore to worlds that then diverge. Xorshift rather
than a multiplying mixer, because on the web an `int` is a double and a
32-by-32 multiply loses the top bits silently.

**`InputTape`** — what a player did, as data. A bug arrives as a file attached
to a report, and a test can play a whole level.

**`DigestTrace` and `StateDigest`** — a number per checkpoint that says whether
two runs are the same run. Two machines cannot compare their worlds by sending
each other their worlds. It hashes bits and not text, because `jsonEncode` is
stable within a platform and not across one, and `Object.hash` is seeded per
isolate by design.

**`Portable`** (`flutter3d_sim/lib/src/math/portable_math.dart`) — the
transcendentals, routed. Dart pins `sqrt` to the correctly rounded result and
pins nothing about `sin`, `exp` or `atan2`: on the VM they are the host's libm
and in a browser they are whatever that engine ships.

**`dart run flutter3d_sim:headless_run`** — the acceptance test of the package
existing, and a binary rather than a test on purpose. `flutter test` would prove
that the code compiles under a Flutter toolchain, which was never in doubt. What
had to be shown is that a plain `dart run`, in a container with no Flutter SDK,
advances the same step a player's device advances — because that is the process
a verifying server is.

**`flutter3d_sim/test/parity_test.dart`** and its neighbour in
`flutter3d_game_racing` — the measurement, run on the VM and again through
`--platform chrome`. It asks three questions cheapest first: whether the
instrument itself reads the same everywhere, which `dart:math` primitives are
portable, and whether a thousand steps of a body through a room come out the
same.

## What the measurement actually answered

Two `dart:math` functions of twelve are portable — `sqrt` and `pow` — and every
transcendental gives different bits in a browser than in the VM. The step
survives anyway, because the divergences are at the last bit and the quantities
they feed are resolved long before they matter. Both facts are load-bearing:
the first says there is nothing portable to build a substitute out of, the
second says a substitute is not needed yet. Neither is safe to assume, which is
why the test measures rather than asserts.

## The habits that keep it

- A step reaches for no clock and no loose dice. A structure rule holds this.
- Nothing orders work by `Object.hashCode` — it is an address. Monster thinking
  was staggered that way once and two runs of the same save diverged.
- Anything packing two numbers into one integer stops at bit 31. Three places
  shifted past it and were right on the VM and wrong in a browser: a collision
  pair key dropped a pair, a broadphase cell key collapsed a Z row into one
  bucket, and an entity handle aliased after 256 recycles.
- A simulation package that runs on a server names no Flutter, in `lib/`, in
  `test/` and in `bin/` alike — a suite that needs `flutter_test` makes the
  claim true of the library and false of the thing anybody executes.
