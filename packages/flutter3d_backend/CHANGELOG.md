## 0.5.1

* **The floors move to the 0.5.1 backends, and the reason is a coupling the
  version graph could not otherwise state.** `flutter3d` 0.5.1 changed what the
  surface buffer's alpha means and added a member to the `FogInfo` uniform
  block, so an engine at 0.5.1 and a backend at 0.5.0 disagree about the shape
  of a block and about the units of a depth. Nothing forced them to move
  together: the engine names no backend — that is a structure rule — so this
  package is the only edge in the graph where the requirement can be written
  down, and it said `^0.5.0`.
* What that mismatch actually does, since a floor is worth what it prevents:
  Impeller throws a `StateError` naming the block and the member, which is the
  failure this package's floor now makes unreachable; the software backend is
  quieter and merely goes on drawing the old picture, which is the case that
  wanted the floor most.
* **One direction only.** This package does not depend on `flutter3d`, so it
  cannot say "an engine at least as new as these backends". A project that
  pins the engine down while letting the backends float is still able to
  assemble a pair that disagrees.

## 0.5.0

* No API change. Its floors move to the 0.5.0 backends.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* Picks the graphics backend a build draws through, with a conditional import
  rather than a runtime branch: the two pull in worlds that do not compile for
  each other's platform.
* `openDevice` was three files in each of three games and byte-identical in two
  of them.
* Deliberately does not decide resolution or shadow budget. Those are a game's
  trade against its own scene, and a shared constant would be wrong for two of
  the three.
