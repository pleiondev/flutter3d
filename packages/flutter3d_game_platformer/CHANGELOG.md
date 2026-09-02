## 0.4.1

* **`Hunter`**, an enemy that comes after the player across the gaps: it
  follows the level's flow field and jumps where the field says the next
  step is a jump, on a grid baked with the enemies' `JumpReach`. `kind:
  hunter` in a level's `enemy` entity, with `sight` and `patience`; it
  needs no route.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* A second genre, and the instrument that tested the first: a runner who jumps
  twice and dashes, coins, hazards, moving platforms, gates and a summit.
* Acceptance was "no edit to the engine" and it took five, all in input, each
  of which generalised the engine rather than accommodating a game.
