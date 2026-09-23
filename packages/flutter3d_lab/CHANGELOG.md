## 0.7.1

**`firstLabDivergence`: the step a student's run left the assignment.** It
compares the recorded parameters step by step and answers the first that
differs, which is the step the student acted on rather than the later one
where the simulation state caught up.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

## 0.7.0

- **The first publication, and the number skips from 0.1.0.** That number was
  carried inside the workspace and never reached pub.dev, so nobody outside
  saw the ones passed over. The shelf goes out on one number so that one number
  names one tree, and `^0.7.0` on any `flutter3d_*` package resolves against
  every other; `doc/boundary-0.7.0.md` lists the thirteen that begin here.
- **What is in it, since the entry below is one sentence.**
  `PendulumSimulation` is a damped pendulum stepped with `flutter3d_sim`'s
  `Portable` functions, whose `lengthMeters` can be set between steps.
  `PendulumLabRun` runs one for a fixed number of steps at `labFixedDt`, a
  sixtieth of a second, and records a `DigestTrace` every 25 steps by default,
  a `DataSourceTrace` of the length a student's panel set, and the exact state
  after every step. `stateAt` reads one back, `branchAt(atStep, throughStep,
  lengthAt)` starts a new run from precisely that state with a different
  length and leaves the original untouched, and `toDemo` wraps the run as a
  `.f3drun`.
- **`PendulumLabRun.divergenceFrom(assignment)` says which step, and why.** It
  compares a student's checkpoints with an assignment's and, at the first that
  disagrees, reads both runs' length at that step. The answer is a
  `PendulumDivergence`: the `Divergence` and the two lengths, either of them
  null when that run's trace does not reach the step. A timeline to show it on
  is not part of this package.
- Plain Dart. The one dependency is `flutter3d_sim` `^0.7.0`.

## 0.1.0

- **The pendulum, `edu-04`'s own acceptance.** A virtual laboratory built on
  `flutter3d_sim`'s stepping and recording primitives, replayable with no
  Flutter SDK in the container that verifies a student's run.
