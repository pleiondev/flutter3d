# flutter3d_boundaries

The repository's package rules, as tests a package runs against itself.

```dart
void main() => expectPackageBoundaries();
```

Two rules today:

* **No genre.** Nothing in the engine half may import a genre package, depend on
  an application, or *say* a genre word — no `ammo`, no `lapTime`, no
  `doubleJump`. The word scan is the half that matters: `CollisionLayers.monster`
  imports nothing.
* **No shared mutable value pretending to be a constant.** A `static final
  Vector3` is a global variable in a constant's clothes, and the first caller to
  scale it in place changes it for the whole process.

Each rule ships the test that proves it fires, on input that breaks it and on
input that only looks like it — because a scan nobody can see fail is a rule
nobody is keeping.

**Pure Dart, deliberately.** The strictest boundary in the repository is
`flutter3d_physics`, which has no Flutter in it at all; a rule package that
dragged in `flutter_test` could not be used by the package that needs it most.
