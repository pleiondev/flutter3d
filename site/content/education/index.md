---
description: What flutter3d offers for teaching: labs that step deterministically so a run can be checked, an LTI 1.3 bridge to a learning platform, and a chemistry bench to start from.
---

# Education

Three pieces of flutter3d exist for teaching, and they fit together.

**A lab that can be checked.** [`flutter3d_education`](https://pub.dev/packages/flutter3d_education)'s `lab.dart` runs experiments on `flutter3d_sim`'s fixed step, which reads no clock and rolls no loose dice. A student's run is recorded as its inputs, and a server checks it by replaying those inputs in a container with no Flutter SDK, the same way a game run is verified. It is plain Dart. The first lab is a pendulum.

**Two profiles, for two jobs.** A laboratory that a server verifies by replay stays on `SimulationProfile.deterministic`, because only that profile promises the same bits on every platform, and a replay is a check only if it lands where the student's run did. `SimulationProfile.accurate` is for demonstration and ships poses to an observer rather than inputs to replay: it steps in doubles with adaptive integrators inside the fixed step, and promises nothing across platforms. There is a number for it. Released at 0.1 rad, a pendulum under it keeps the period its series gives to within 1e-4 over 100 periods, and its energy to within 1e-6 of the swing's (`pendulum_period_test.dart` in `flutter3d_physics` holds both numbers; it measures 1.7e-9 and 4.7e-8). The deterministic step at its default eight substeps misses the same period by 4.6e-4 and loses nearly all of the swing's energy over those 100 periods, which is why a demonstration of the physics wants the other one.

**A way into a course.** Its `lti.dart` handles an LTI 1.3 launch from a learning platform and files results back as xAPI statements. It is plain Dart as well, without a web framework, so a service that only verifies a launch or posts a grade carries nothing else.

**Something to look at.** The [chemistry bench](/education/chemlab/) is a small Flutter application on the engine: glassware turned from profiles, labels typeset in TeX and wrapped on without a decal, and liquid you can pour. It runs in this site, and its source is `packages/flutter3d_education/example` in the repository, the package's example. It is a scene, not yet a lab: nothing reacts, and nothing is recorded.

## Where this is going

The pendulum and the bench are two halves of what a chemistry lab needs: a step that can be replayed and checked, and a bench that looks like one. Joining them, so that a titration on the bench is a recorded run a server can mark, is the next piece.
