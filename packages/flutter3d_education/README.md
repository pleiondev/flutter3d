# flutter3d_education

Education on flutter3d, in plain Dart: lab simulations a server replays to check a student's run, the experiment document a lesson is written in, and a lesson's steps read out of a level. The chemistry bench in `example/` is the Flutter half: it draws, so it is an application of its own rather than a library here.

The LTI 1.3 and xAPI side a learning platform talks to is [`flutter3d_education_lti`](https://pub.dev/packages/flutter3d_education_lti), a package of its own: its cryptography and HTTP client are a service's, and an editor or a lesson that reads an experiment does not carry them.

| Library | Was | What it is |
| --- | --- | --- |
| `lab.dart` | `flutter3d_lab` | Virtual laboratory simulations built on `flutter3d_sim`'s stepping and recording primitives |

## `lab.dart`

*Until 1.0.0-rc.1, `flutter3d_lab`.*

Virtual laboratory simulations built on `flutter3d_sim`'s stepping and
recording primitives. The first is the pendulum from `edu-04`.

Plain Dart, no Flutter SDK. A server verifies a student's submitted lab run
the same way it verifies a game run: it replays the run in a container that
has no Flutter SDK in it.
