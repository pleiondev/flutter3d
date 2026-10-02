---
description: What flutter3d offers for teaching: labs that step deterministically so a run can be checked, an LTI 1.3 bridge to a learning platform, and a chemistry bench to start from.
---

# Education

Three pieces of flutter3d exist for teaching, and they fit together.

**A lab that can be checked.** [`flutter3d_lab`](https://pub.dev/packages/flutter3d_lab) runs experiments on `flutter3d_sim`'s fixed step, which reads no clock and rolls no loose dice. A student's run is recorded as its inputs, and a server checks it by replaying those inputs in a container with no Flutter SDK, the same way a game run is verified. It is plain Dart. The first lab is a pendulum.

**A way into a course.** [`flutter3d_lti`](https://pub.dev/packages/flutter3d_lti) handles an LTI 1.3 launch from a learning platform and files results back as xAPI statements. It is plain Dart as well, without a web framework, so a service that only verifies a launch or posts a grade carries nothing else.

**Something to look at.** The [chemistry bench](/education/chemlab/) is a small Flutter application on the engine: glassware turned from profiles, labels typeset in TeX and wrapped on without a decal, and liquid you can pour. It runs in this site, and its source is `packages/education/chemlab` in the repository. It is a scene, not yet a lab: nothing reacts, and nothing is recorded.

## Where this is going

The pendulum and the bench are two halves of what a chemistry lab needs: a step that can be replayed and checked, and a bench that looks like one. Joining them, so that a titration on the bench is a recorded run a server can mark, is the next piece.
